package skillsuggest

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/chat"
	"skills-analyzer/internal/modules/skillscore"
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
	llm      model
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, llm *chat.Ollama) {
	h := &Handler{db: db, students: students, llm: llm}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	r.GET("/students/:id/skill-suggestions", can("student_skill.view"), h.list)
	r.POST("/students/:id/skill-suggestions/generate", can("student_skill.update"), h.generate)
	r.POST("/skill-suggestions/:id/accept", can("student_skill.update"), h.accept)
	r.POST("/skill-suggestions/:id/dismiss", can("student_skill.update"), h.dismiss)

	r.POST("/subjects/:id/skill-mapping/suggest", can("subject.update"), h.suggestMapping)
}

// ---- subject → skills (model) ----

func (h *Handler) suggestMapping(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	var code, name, typ string
	if err := h.db.QueryRow(ctx, `SELECT code, name, subject_type FROM subjects WHERE id = $1 AND is_active`, id).Scan(&code, &name, &typ); err != nil {
		if dbutil.IsNoRows(err) {
			response.Error(c, response.NotFound("Subject not found"))
			return
		}
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(ctx, `SELECT id, name::text FROM skills WHERE is_active ORDER BY name`)
	if err != nil {
		response.Error(c, err)
		return
	}
	options, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (SkillOption, error) {
		var o SkillOption
		return o, r.Scan(&o.ID, &o.Name)
	})
	if err != nil {
		response.Error(c, err)
		return
	}

	// Uploaded documents about this subject tell the model what it really covers: those tagged with the
	// subject, or whose text mentions its code. Anything else would describe a different subject.
	syllabus, err := h.subjectDocuments(ctx, id, code)
	if err != nil {
		slog.Warn("skillsuggest: reading subject documents failed", "subject", id, "err", err)
	}

	out, err := SuggestMapping(ctx, h.llm, code, name, typ, syllabus, options)
	if err != nil {
		slog.Error("skillsuggest: mapping failed", "subject", id, "err", err)
		response.Error(c, response.ServiceUnavailable("Could not suggest skills for this subject right now."))
		return
	}
	if out == nil {
		out = []MappingSuggestion{}
	}
	response.OK(c, gin.H{"subject_id": id, "used_syllabus": len(syllabus) > 0, "skills": out})
}

func truncate(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n]) + "…"
	}
	return s
}

// ---- student → skill levels (marks) ----

// Suggestion is a stored suggestion as shown to staff.
type Suggestion struct {
	ID             int64      `json:"id"`
	StudentID      int64      `json:"student_id"`
	SkillID        int64      `json:"skill_id"`
	Skill          string     `json:"skill"`
	SuggestedLevel int        `json:"suggested_level"`
	CurrentLevel   *int       `json:"current_level"`
	Percent        float64    `json:"percent"`
	Evidence       []Evidence `json:"evidence"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"created_at"`
}

const selectSuggestions = `
	SELECT x.id, x.student_id, x.skill_id, k.name::text, x.suggested_level::int, x.current_level::int, x.percent::float8,
	       x.evidence, x.status, x.created_at
	FROM skill_suggestions x JOIN skills k ON k.id = x.skill_id`

func scanSuggestion(r pgx.Row) (*Suggestion, error) {
	s := &Suggestion{}
	var ev []byte
	if err := r.Scan(&s.ID, &s.StudentID, &s.SkillID, &s.Skill, &s.SuggestedLevel, &s.CurrentLevel, &s.Percent, &ev, &s.Status, &s.CreatedAt); err != nil {
		return nil, err
	}
	_ = json.Unmarshal(ev, &s.Evidence)
	return s, nil
}

func (h *Handler) pending(ctx context.Context, studentID int64) ([]*Suggestion, error) {
	rows, err := h.db.Query(ctx, selectSuggestions+` WHERE x.student_id = $1 AND x.status = 'pending' ORDER BY x.suggested_level DESC, k.name`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Suggestion{}
	for rows.Next() {
		s, err := scanSuggestion(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (h *Handler) list(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil { // access check
		response.Error(c, err)
		return
	}
	out, err := h.pending(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, out)
}

// inputs loads what Candidates needs for one student.
func (h *Handler) inputs(ctx context.Context, studentID int64) (marks []SubjectMark, links map[int64][]SkillLink, current map[int64]int, err error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT ON (m.subject_id) m.subject_id, s.name,
		       LEAST(100, GREATEST(0, m.marks_obtained / NULLIF(m.max_marks, 0) * 100))::float8
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id
		WHERE m.student_id = $1 AND m.is_active AND m.marks_obtained IS NOT NULL AND m.max_marks > 0
		ORDER BY m.subject_id, et.is_final DESC, m.attempt_no DESC`, studentID)
	if err != nil {
		return nil, nil, nil, err
	}
	marks, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (SubjectMark, error) {
		var m SubjectMark
		return m, r.Scan(&m.SubjectID, &m.Subject, &m.Percent)
	})
	if err != nil {
		return nil, nil, nil, err
	}

	links = map[int64][]SkillLink{}
	lrows, err := h.db.Query(ctx, `
		SELECT ss.subject_id, ss.skill_id, k.name::text, ss.weight::float8
		FROM subject_skills ss JOIN skills k ON k.id = ss.skill_id AND k.is_active
		WHERE ss.is_active AND ss.subject_id = ANY($1)`, subjectIDs(marks))
	if err != nil {
		return nil, nil, nil, err
	}
	defer lrows.Close()
	for lrows.Next() {
		var sid int64
		var l SkillLink
		if err := lrows.Scan(&sid, &l.SkillID, &l.Skill, &l.Weight); err != nil {
			return nil, nil, nil, err
		}
		links[sid] = append(links[sid], l)
	}
	if err := lrows.Err(); err != nil {
		return nil, nil, nil, err
	}

	current = map[int64]int{}
	crows, err := h.db.Query(ctx, `SELECT skill_id, proficiency::int FROM student_skills WHERE student_id = $1 AND is_active`, studentID)
	if err != nil {
		return nil, nil, nil, err
	}
	defer crows.Close()
	for crows.Next() {
		var sk, lvl int
		if err := crows.Scan(&sk, &lvl); err != nil {
			return nil, nil, nil, err
		}
		current[int64(sk)] = lvl
	}
	return marks, links, current, crows.Err()
}

func subjectIDs(marks []SubjectMark) []int64 {
	ids := make([]int64, len(marks))
	for i, m := range marks {
		ids[i] = m.SubjectID
	}
	return ids
}

type generateResult struct {
	Suggestions []*Suggestion `json:"suggestions"`
	// Summary is a short plain-language reading of the marks, built from the numbers.
	Summary string `json:"summary"`
	// UnmappedSubjects are subjects with marks but no skill mapping: their marks cannot produce suggestions yet.
	UnmappedSubjects []string `json:"unmapped_subjects"`
}

func (h *Handler) generate(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	a := actor.From(c)
	st, err := h.students.Get(ctx, a, id)
	if err != nil {
		response.Error(c, err)
		return
	}

	marks, links, current, err := h.inputs(ctx, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	cands := Candidates(marks, links, current)

	var unmapped []string
	for _, m := range marks {
		if len(links[m.SubjectID]) == 0 {
			unmapped = append(unmapped, m.Subject)
		}
	}

	// Replace the open suggestions with the fresh ones. A skill staff already dismissed at this level or
	// higher is not suggested again, so the same suggestion does not keep coming back.
	err = pgx.BeginFunc(ctx, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `DELETE FROM skill_suggestions WHERE student_id = $1 AND status = 'pending'`, id); err != nil {
			return err
		}
		for _, cd := range cands {
			var dismissed bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM skill_suggestions
				WHERE student_id = $1 AND skill_id = $2 AND status = 'dismissed' AND suggested_level >= $3)`,
				id, cd.SkillID, cd.Level).Scan(&dismissed); err != nil {
				return err
			}
			if dismissed {
				continue
			}
			ev, _ := json.Marshal(cd.Evidence)
			var cur *int
			if cd.Current > 0 {
				cur = &cd.Current
			}
			if _, err := tx.Exec(ctx, `
				INSERT INTO skill_suggestions (student_id, skill_id, suggested_level, current_level, percent, evidence, created_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7)`, id, cd.SkillID, cd.Level, cur, cd.Percent, ev, a.ID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}

	list, err := h.pending(ctx, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if unmapped == nil {
		unmapped = []string{}
	}
	response.OK(c, generateResult{Suggestions: list, Summary: Summarize(st.Name, marks, cands, unmapped), UnmappedSubjects: unmapped})
}

// ---- accept / dismiss ----

func (h *Handler) load(c *gin.Context) (*Suggestion, bool) {
	id, ok := request.ID(c, "id")
	if !ok {
		return nil, false
	}
	s, err := scanSuggestion(h.db.QueryRow(c, selectSuggestions+` WHERE x.id = $1`, id))
	if dbutil.IsNoRows(err) {
		response.Error(c, response.NotFound("Suggestion not found"))
		return nil, false
	}
	if err != nil {
		response.Error(c, err)
		return nil, false
	}
	if _, err := h.students.Get(c, actor.From(c), s.StudentID); err != nil { // same access rules as the student
		response.Error(c, err)
		return nil, false
	}
	if s.Status != "pending" {
		response.Error(c, response.Conflict("This suggestion has already been "+s.Status))
		return nil, false
	}
	return s, true
}

func (h *Handler) dismiss(c *gin.Context) {
	s, ok := h.load(c)
	if !ok {
		return
	}
	if _, err := h.db.Exec(c, `UPDATE skill_suggestions SET status = 'dismissed', decided_at = now(), decided_by = $2 WHERE id = $1 AND status = 'pending'`,
		s.ID, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Dismissed"})
}

// accept records the skill level for the student (never lowering one that is already higher) and rebuilds
// that student's skill scores, so the analyzer and career matching see it.
func (h *Handler) accept(c *gin.Context) {
	s, ok := h.load(c)
	if !ok {
		return
	}
	a := actor.From(c)
	remark := fmt.Sprintf("Suggested from marks (%.0f%%) and accepted by staff", s.Percent)

	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		tag, err := tx.Exec(c, `UPDATE skill_suggestions SET status = 'accepted', decided_at = now(), decided_by = $2 WHERE id = $1 AND status = 'pending'`, s.ID, a.ID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return response.Conflict("This suggestion has already been decided")
		}
		upd, err := tx.Exec(c, `
			UPDATE student_skills SET proficiency = GREATEST(proficiency, $3), remarks = $4, updated_by = $5
			WHERE student_id = $1 AND skill_id = $2 AND is_active`, s.StudentID, s.SkillID, s.SuggestedLevel, remark, a.ID)
		if err != nil {
			return err
		}
		if upd.RowsAffected() == 0 {
			if _, err := tx.Exec(c, `
				INSERT INTO student_skills (student_id, skill_id, proficiency, source, remarks, created_by, updated_by)
				VALUES ($1, $2, $3, 'assessment', $4, $5, $5)`, s.StudentID, s.SkillID, s.SuggestedLevel, remark, a.ID); err != nil {
				return err
			}
		}
		return skillscore.Recompute(c, tx, a.ID, []int64{s.StudentID})
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Skill recorded", "skill_id": s.SkillID, "level": s.SuggestedLevel})
}

// subjectDocuments returns up to three passages from knowledge-base documents that belong to the subject.
func (h *Handler) subjectDocuments(ctx context.Context, subjectID int64, code string) ([]string, error) {
	rows, err := h.db.Query(ctx, `
		SELECT c.content
		FROM kb_chunks c JOIN kb_documents d ON d.id = c.document_id
		WHERE d.is_active AND (d.subject_id = $1 OR c.content ILIKE '%' || $2 || '%')
		ORDER BY (d.subject_id = $1) DESC, d.doc_type = 'syllabus' DESC, d.id, c.position
		LIMIT 3`, subjectID, code)
	if err != nil {
		return nil, err
	}
	passages, err := pgx.CollectRows(rows, pgx.RowTo[string])
	for i := range passages {
		passages[i] = truncate(passages[i], 900)
	}
	return passages, err
}
