package skillscore

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service) {
	h := &Handler{db: db, students: students}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	r.GET("/config/scoring", can("config.view"), h.getScoring)
	r.PUT("/config/scoring", can("config.update"), h.setScoring)

	r.GET("/config/threshold", can("config.view"), h.getThreshold)
	r.PUT("/config/threshold", can("config.update"), h.setThreshold)

	r.GET("/students/:id/skill-scores", can("student_skill.view"), h.studentScores)
	// Anyone who may record a skill may also refresh the scores built from it.
	r.POST("/skill-scores/recompute", can("skill_analyzer.create", "student_skill.update"), h.recompute)

	r.GET("/subject-skills", can("subject.view"), h.listSubjectSkills)
	r.GET("/subjects/:id/skills", can("subject.view"), h.subjectSkills)
	r.PUT("/subjects/:id/skills", can("subject.update"), h.setSubjectSkills)
}

// ---- settings ----

// getScoring returns the weights behind blended skill scores and match scores.
func (h *Handler) getScoring(c *gin.Context) {
	rows, err := h.db.Query(c, `SELECT a.key, a.value, a.description, a.updated_at, u.name
		FROM app_config a LEFT JOIN users u ON u.id = a.updated_by
		WHERE a.key = ANY($1) ORDER BY a.key`, []string{ConfigWeights, ConfigMatch})
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Setting])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"settings": list, "skill_sources": Sources})
}

// setScoring saves new weights. Changing them changes every blended score, so the
// recompute runs in the background and the response says so.
func (h *Handler) setScoring(c *gin.Context) {
	var body struct {
		SkillScoreWeights map[string]float64 `json:"skill_score_weights"`
		MatchWeights      map[string]float64 `json:"match_weights"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Send skill_score_weights and/or match_weights as maps of numbers", err.Error()))
		return
	}
	if body.SkillScoreWeights == nil && body.MatchWeights == nil {
		response.Error(c, response.BadRequest("Nothing to change"))
		return
	}
	a := actor.From(c)
	rebuild := false
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if body.SkillScoreWeights != nil {
			if err := validWeights(body.SkillScoreWeights, Sources); err != nil {
				return err
			}
			if err := save(c, tx, ConfigWeights, body.SkillScoreWeights, a.ID); err != nil {
				return err
			}
			rebuild = true
		}
		if body.MatchWeights != nil {
			if err := validWeights(body.MatchWeights, []string{"skill", "academic"}); err != nil {
				return err
			}
			return save(c, tx, ConfigMatch, body.MatchWeights, a.ID)
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	if rebuild {
		h.rebuildAll(a.ID, nil)
	}
	h.getScoring(c)
}

func save(ctx context.Context, q dbutil.DBTX, key string, v map[string]float64, actorID int64) error {
	raw, err := json.Marshal(v)
	if err != nil {
		return err
	}
	tag, err := q.Exec(ctx, `UPDATE app_config SET value = $2, updated_at = now(), updated_by = $3 WHERE key = $1`, key, raw, actorID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return response.NotFound("Setting " + key + " does not exist")
	}
	return nil
}

// getThreshold returns the global mark threshold and per-skill overrides.
func (h *Handler) getThreshold(c *gin.Context) {
	raw, err := configValue(c, h.db, ConfigThreshold)
	if err != nil {
		response.Error(c, err)
		return
	}
	matchRaw, err := configValue(c, h.db, ConfigMatch)
	if err != nil {
		response.Error(c, err)
		return
	}
	var threshold struct {
		Default        int                `json:"default"`
		SkillOverrides map[string]float64 `json:"skill_overrides"`
	}
	if err := json.Unmarshal(raw, &threshold); err != nil {
		threshold.Default = 75
		threshold.SkillOverrides = map[string]float64{}
	}
	if threshold.SkillOverrides == nil {
		threshold.SkillOverrides = map[string]float64{}
	}
	var match map[string]float64
	if err := json.Unmarshal(matchRaw, &match); err != nil {
		match = map[string]float64{"skill": 70, "academic": 30}
	}
	response.OK(c, gin.H{
		"global_threshold": threshold.Default,
		"skill_overrides":  threshold.SkillOverrides,
		"match_weights":    match,
	})
}

// setThreshold saves the global mark threshold, per-skill overrides, and match weights.
func (h *Handler) setThreshold(c *gin.Context) {
	var body struct {
		GlobalThreshold int                `json:"global_threshold"`
		SkillOverrides  map[string]float64 `json:"skill_overrides"`
		MatchWeights    map[string]float64 `json:"match_weights"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Invalid request body", err.Error()))
		return
	}
	if body.GlobalThreshold < 0 || body.GlobalThreshold > 100 {
		response.Error(c, response.BadRequest("global_threshold must be between 0 and 100"))
		return
	}
	for name, val := range body.SkillOverrides {
		if val < 0 || val > 100 {
			response.Error(c, response.BadRequest(name+" override must be between 0 and 100"))
			return
		}
	}
	a := actor.From(c)
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		thresholdVal := map[string]any{
			"default":         body.GlobalThreshold,
			"skill_overrides": body.SkillOverrides,
		}
		if body.SkillOverrides == nil {
			thresholdVal["skill_overrides"] = map[string]float64{}
		}
		raw, err := json.Marshal(thresholdVal)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(c, `INSERT INTO app_config (key, value, updated_by) VALUES ($1, $2, $3)
			ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = now(), updated_by = $3`,
			ConfigThreshold, raw, a.ID); err != nil {
			return err
		}
		if body.MatchWeights != nil {
			if err := validWeights(body.MatchWeights, []string{"skill", "academic"}); err != nil {
				return err
			}
			return save(c, tx, ConfigMatch, body.MatchWeights, a.ID)
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	h.getThreshold(c)
}

// rebuildAll recomputes scores away from the request, so a weight change or a bulk
// recompute never blocks the caller. ids == nil means every active student.
func (h *Handler) rebuildAll(actorID int64, ids []int64) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
		defer cancel()
		if ids == nil {
			rows, err := h.db.Query(ctx, `SELECT sp.user_id FROM student_profiles sp
				JOIN users u ON u.id = sp.user_id AND u.is_active WHERE sp.is_active`)
			if err != nil {
				slog.Error("skill score rebuild: could not list students", "err", err)
				return
			}
			if ids, err = pgx.CollectRows(rows, pgx.RowTo[int64]); err != nil {
				slog.Error("skill score rebuild: could not list students", "err", err)
				return
			}
		}
		started := time.Now()
		if err := InBatches(ctx, h.db, actorID, ids); err != nil {
			slog.Error("skill score rebuild failed", "students", len(ids), "err", err)
			return
		}
		slog.Info("skill scores rebuilt", "students", len(ids), "took", time.Since(started).Round(time.Millisecond))
	}()
}

// ---- scores ----

func (h *Handler) studentScores(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil { // self / parent / staff in scope
		response.Error(c, err)
		return
	}
	list, err := Of(c, h.db, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	at, err := ComputedAt(c, h.db, []int64{id})
	if err != nil {
		response.Error(c, err)
		return
	}
	weights, err := Weights(c, h.db, ConfigWeights)
	if err != nil {
		response.Error(c, err)
		return
	}
	var computed *time.Time
	if t, ok := at[id]; ok {
		computed = &t
	}
	response.OK(c, gin.H{"student_id": id, "computed_at": computed, "weights": weights, "scores": list})
}

// recompute rebuilds scores for a chosen set of students: explicit ids, a class, a
// department, or everyone. Staff outside their department are rejected by the scope check.
func (h *Handler) recompute(c *gin.Context) {
	var body struct {
		StudentIDs   []int64 `json:"student_ids"`
		ClassID      *int64  `json:"class_id"`
		DepartmentID *int64  `json:"department_id"`
		All          bool    `json:"all"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Send student_ids, class_id, department_id or all"))
		return
	}
	a := actor.From(c)
	if body.All && !a.Has("admin", "placement_officer") {
		response.Error(c, response.Forbidden("Only an admin or placement officer can recompute every student"))
		return
	}
	var ids []int64
	switch {
	case len(body.StudentIDs) > 0:
		for _, id := range distinct(body.StudentIDs) {
			if _, err := h.students.Get(c, a, id); err != nil { // keeps HOD/staff inside their department
				response.Error(c, err)
				return
			}
			ids = append(ids, id)
		}
	case body.ClassID != nil, body.DepartmentID != nil:
		rows, err := h.db.Query(c, `SELECT sp.user_id FROM student_profiles sp
			JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.is_active AND ($1::bigint IS NULL OR sp.current_class_id = $1)
			  AND ($2::bigint IS NULL OR u.department_id = $2)`, body.ClassID, body.DepartmentID)
		if err != nil {
			response.Error(c, err)
			return
		}
		if ids, err = pgx.CollectRows(rows, pgx.RowTo[int64]); err != nil {
			response.Error(c, err)
			return
		}
		for _, id := range ids {
			if _, err := h.students.Get(c, a, id); err != nil {
				response.Error(c, err)
				return
			}
		}
	case body.All:
		h.rebuildAll(a.ID, nil)
		response.OK(c, gin.H{"message": "Recomputing skill scores for every student in the background"})
		return
	default:
		response.Error(c, response.BadRequest("Send student_ids, class_id, department_id or all"))
		return
	}
	if len(ids) == 0 {
		response.OK(c, gin.H{"message": "No students matched", "students": 0})
		return
	}
	if err := InBatches(c, h.db, a.ID, ids); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Skill scores recomputed", "students": len(ids)})
}

// ---- subject → skill mapping ----

type SubjectSkill struct {
	SkillID  int64   `json:"skill_id"`
	Name     string  `json:"name"`
	Category string  `json:"category"`
	Weight   float64 `json:"weight"`
}

type SubjectMapping struct {
	SubjectID   int64          `json:"subject_id"`
	SubjectCode string         `json:"subject_code"`
	SubjectName string         `json:"subject_name"`
	Skills      []SubjectSkill `json:"skills"`
}

func (h *Handler) mappings(ctx context.Context, where string, args ...any) ([]*SubjectMapping, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.code, s.name, sk.id, sk.name::text, sk.category, ms.weight::float8
		FROM subjects s
		LEFT JOIN subject_skills ms ON ms.subject_id = s.id AND ms.is_active
		LEFT JOIN skills sk ON sk.id = ms.skill_id AND sk.is_active
		WHERE s.is_active AND `+where+`
		ORDER BY s.code, ms.weight DESC, sk.name`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*SubjectMapping{}
	byID := map[int64]*SubjectMapping{}
	for rows.Next() {
		var m SubjectMapping
		// A subject with no mapping still returns one row, with the skill columns NULL.
		var skillID *int64
		var name, category *string
		var weight *float64
		if err := rows.Scan(&m.SubjectID, &m.SubjectCode, &m.SubjectName, &skillID, &name, &category, &weight); err != nil {
			return nil, err
		}
		cur, ok := byID[m.SubjectID]
		if !ok {
			m.Skills = []SubjectSkill{}
			cur = &m
			byID[m.SubjectID] = cur
			out = append(out, cur)
		}
		if skillID != nil {
			cur.Skills = append(cur.Skills, SubjectSkill{SkillID: *skillID, Name: str(name), Category: str(category), Weight: f(weight)})
		}
	}
	return out, rows.Err()
}

func str(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func f(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

// listSubjectSkills: GET /subject-skills?search=&mapped=true|false — the setup screen for
// "which skills does this subject teach", which is what makes marks feed skill scores.
func (h *Handler) listSubjectSkills(c *gin.Context) {
	where := []string{"true"}
	args := []any{}
	if s := strings.TrimSpace(c.Query("search")); s != "" {
		args = append(args, "%"+s+"%")
		where = append(where, "(s.code ILIKE $1 OR s.name ILIKE $1)")
	}
	switch c.Query("mapped") {
	case "true":
		where = append(where, "EXISTS (SELECT 1 FROM subject_skills x WHERE x.subject_id = s.id AND x.is_active)")
	case "false":
		where = append(where, "NOT EXISTS (SELECT 1 FROM subject_skills x WHERE x.subject_id = s.id AND x.is_active)")
	}
	list, err := h.mappings(c, strings.Join(where, " AND "), args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	mapped := 0
	for _, m := range list {
		if len(m.Skills) > 0 {
			mapped++
		}
	}
	response.OK(c, gin.H{"subjects": list, "total": len(list), "mapped": mapped})
}

func (h *Handler) subjectSkills(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	list, err := h.mappings(c, "s.id = $1", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if len(list) == 0 {
		response.Error(c, response.NotFound("Subject not found"))
		return
	}
	response.OK(c, list[0])
}

// setSubjectSkills replaces a subject's skill mapping, then recomputes the academic score
// of every student with marks in that subject.
func (h *Handler) setSubjectSkills(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Skills []struct {
			SkillID int64   `json:"skill_id" binding:"required"`
			Weight  float64 `json:"weight" binding:"omitempty,gt=0,lte=10"`
		} `json:"skills" binding:"dive"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Send skills as a list of {skill_id, weight}", err.Error()))
		return
	}
	seen := map[int64]bool{}
	skillIDs := []int64{}
	for i := range body.Skills {
		if seen[body.Skills[i].SkillID] {
			response.Error(c, response.BadRequest("A skill is listed twice"))
			return
		}
		seen[body.Skills[i].SkillID] = true
		skillIDs = append(skillIDs, body.Skills[i].SkillID)
		if body.Skills[i].Weight == 0 {
			body.Skills[i].Weight = 1
		}
	}
	var subjectOK bool
	var skillCount int
	if err := h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM subjects WHERE id = $1 AND is_active),
		(SELECT count(*) FROM skills WHERE id = ANY($2) AND is_active)::int`, id, skillIDs).Scan(&subjectOK, &skillCount); err != nil {
		response.Error(c, err)
		return
	}
	if !subjectOK {
		response.Error(c, response.NotFound("Subject not found"))
		return
	}
	if skillCount != len(skillIDs) {
		response.Error(c, response.BadRequest("One or more skill_ids are invalid"))
		return
	}
	a := actor.From(c)
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(c, `UPDATE subject_skills SET is_active = false, updated_by = $2
			WHERE subject_id = $1 AND is_active`, id, a.ID); err != nil {
			return err
		}
		for _, s := range body.Skills {
			if _, err := tx.Exec(c, `INSERT INTO subject_skills (subject_id, skill_id, weight, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $4)`, id, s.SkillID, s.Weight, a.ID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	if err := ForSubject(c, h.db, a.ID, id); err != nil {
		slog.Error("recompute after subject mapping change failed", "subject", id, "err", err)
	}
	h.subjectSkills(c)
}
