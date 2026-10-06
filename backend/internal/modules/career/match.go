package career

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

// Readiness buckets. A student is only "ready" once every core skill is met.
const (
	Ready   = "ready"
	Close   = "close"
	Explore = "explore"
)

type CourseRef struct {
	ID       int64   `json:"id"`
	Title    string  `json:"title"`
	Provider *string `json:"provider"`
	URL      *string `json:"url"`
	Level    int     `json:"level"`
	Hours    *int    `json:"duration_hours"`
	IsFree   bool    `json:"is_free"`
}

// SkillStanding is one required skill measured against what the student has.
// It is used for both the strengths and the gaps list.
type SkillStanding struct {
	SkillID       int64       `json:"skill_id"`
	Name          string      `json:"name"`
	Category      string      `json:"category"`
	Score         float64     `json:"score"` // blended 0-100
	Level         int         `json:"level"`
	RequiredLevel int         `json:"required_level"`
	RequiredScore float64     `json:"required_score"`
	Gap           float64     `json:"gap"` // points still needed, 0 when met
	IsCore        bool        `json:"is_core"`
	Weight        float64     `json:"weight"`
	Courses       []CourseRef `json:"courses,omitempty"`
}

type Match struct {
	CareerID      int64           `json:"career_id"`
	Code          string          `json:"code"`
	Name          string          `json:"name"`
	Domain        *string         `json:"domain"`
	Description   *string         `json:"description"`
	AvgPackage    *float64        `json:"avg_package"`
	MinCGPA       float64         `json:"min_cgpa"`
	Rank          int             `json:"rank"`
	SkillScore    float64         `json:"skill_score"`
	AcademicScore float64         `json:"academic_score"`
	FinalScore    float64         `json:"final_score"`
	Readiness     string          `json:"readiness"`
	Strengths     []SkillStanding `json:"strengths"`
	Gaps          []SkillStanding `json:"gaps"`
	Explanation   string          `json:"explanation"`
	ComputedAt    time.Time       `json:"computed_at"`
	IsStale       bool            `json:"is_stale"`
	Feedback      *Feedback       `json:"feedback"`
}

type Feedback struct {
	Rating    int       `json:"rating"`
	IsUseful  bool      `json:"is_useful"`
	Comment   *string   `json:"comment"`
	CreatedAt time.Time `json:"created_at"`
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// ---- the matcher ----

// evaluate ranks every career for one student from their blended skill scores and CGPA.
// Authorisation is the caller's job; this only reads.
func (h *Handler) evaluate(ctx context.Context, studentID int64) ([]*Match, error) {
	var cgpa float64
	if err := h.db.QueryRow(ctx, `SELECT sp.cgpa::float8 FROM student_profiles sp
		WHERE sp.user_id = $1 AND sp.is_active`, studentID).Scan(&cgpa); err != nil {
		if dbutil.IsNoRows(err) {
			return nil, response.NotFound("Student not found")
		}
		return nil, err
	}
	blended, err := skillscore.Blended(ctx, h.db, []int64{studentID})
	if err != nil {
		return nil, err
	}
	scores := blended[studentID]

	rows, err := h.db.Query(ctx, selectCareer+` WHERE c.is_active`)
	if err != nil {
		return nil, err
	}
	careers := []*Career{}
	for rows.Next() {
		ca, err := scanCareer(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		careers = append(careers, ca)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := h.attach(ctx, careers); err != nil {
		return nil, err
	}
	skillW, academicW, err := skillscore.MatchWeights(ctx, h.db)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	out := make([]*Match, 0, len(careers))
	gapSkills := map[int64]bool{}
	for _, ca := range careers {
		m := &Match{CareerID: ca.ID, Code: ca.Code, Name: ca.Name, Domain: ca.Domain, Description: ca.Description,
			AvgPackage: ca.AvgPackage, MinCGPA: ca.MinCGPA, ComputedAt: now,
			Strengths: []SkillStanding{}, Gaps: []SkillStanding{}}
		coreMet := true
		var got, total float64
		for _, rs := range ca.Skills {
			required := float64(rs.RequiredLevel) * skillscore.LevelStep
			score := scores[rs.SkillID]
			total += rs.Weight
			got += rs.Weight * math.Min(score/required, 1)
			st := SkillStanding{SkillID: rs.SkillID, Name: rs.SkillName, Category: rs.Category, Score: round2(score),
				Level: skillscore.Level(score), RequiredLevel: rs.RequiredLevel, RequiredScore: required,
				IsCore: rs.IsCore, Weight: rs.Weight}
			if score >= required {
				m.Strengths = append(m.Strengths, st)
				continue
			}
			st.Gap = round2(required - score)
			m.Gaps = append(m.Gaps, st)
			gapSkills[rs.SkillID] = true
			if rs.IsCore {
				coreMet = false
			}
		}
		// A career with no requirements recorded yet should not rank first on an empty profile.
		m.SkillScore = 0
		if total > 0 {
			m.SkillScore = round2(got / total * 100)
		}
		m.AcademicScore = round2(math.Min(cgpa*10, 100))
		m.FinalScore = round2(skillW*m.SkillScore + academicW*m.AcademicScore)
		// Biggest gap first, core requirements ahead of optional ones.
		sort.SliceStable(m.Gaps, func(i, j int) bool {
			if m.Gaps[i].IsCore != m.Gaps[j].IsCore {
				return m.Gaps[i].IsCore
			}
			return m.Gaps[i].Gap > m.Gaps[j].Gap
		})
		switch {
		case coreMet && len(ca.Skills) > 0 && cgpa >= ca.MinCGPA:
			m.Readiness = Ready
		case m.SkillScore >= 50:
			m.Readiness = Close
		default:
			m.Readiness = Explore
		}
		m.Explanation = explain(m, cgpa)
		out = append(out, m)
	}
	if err := h.attachCourses(ctx, out, gapSkills); err != nil {
		return nil, err
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].FinalScore != out[j].FinalScore {
			return out[i].FinalScore > out[j].FinalScore
		}
		// Equal scores: the more reachable career first, so a student with nothing on
		// record yet is pointed at the entry routes rather than at the hardest role.
		if out[i].MinCGPA != out[j].MinCGPA {
			return out[i].MinCGPA < out[j].MinCGPA
		}
		return out[i].Name < out[j].Name
	})
	for i, m := range out {
		m.Rank = i + 1
	}
	return out, nil
}

// attachCourses hangs up to three courses off each gap, so every gap comes with a next step.
func (h *Handler) attachCourses(ctx context.Context, list []*Match, skillIDs map[int64]bool) error {
	if len(skillIDs) == 0 {
		return nil
	}
	ids := make([]int64, 0, len(skillIDs))
	for id := range skillIDs {
		ids = append(ids, id)
	}
	rows, err := h.db.Query(ctx, `SELECT skill_id, id, title, provider, url, level, duration_hours, is_free
		FROM courses WHERE skill_id = ANY($1) AND is_active ORDER BY skill_id, level, is_free DESC, title`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	bySkill := map[int64][]CourseRef{}
	for rows.Next() {
		var sid int64
		var co CourseRef
		if err := rows.Scan(&sid, &co.ID, &co.Title, &co.Provider, &co.URL, &co.Level, &co.Hours, &co.IsFree); err != nil {
			return err
		}
		bySkill[sid] = append(bySkill[sid], co)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, m := range list {
		for i := range m.Gaps {
			all := bySkill[m.Gaps[i].SkillID]
			// Prefer a course at or just above the level the student still needs.
			pick := []CourseRef{}
			for _, co := range all {
				if co.Level >= m.Gaps[i].Level && len(pick) < 3 {
					pick = append(pick, co)
				}
			}
			if len(pick) == 0 && len(all) > 0 {
				pick = all[:min(3, len(all))]
			}
			m.Gaps[i].Courses = pick
		}
	}
	return nil
}

// explain writes the one-line reason shown under a match. Rule-based and deterministic,
// so the same profile always reads the same way.
func explain(m *Match, cgpa float64) string {
	parts := []string{}
	switch m.Readiness {
	case Ready:
		parts = append(parts, fmt.Sprintf("You meet every core requirement for %s", m.Name))
	case Close:
		parts = append(parts, fmt.Sprintf("You are close to %s at a %.0f%% skill match", m.Name, m.SkillScore))
	default:
		parts = append(parts, fmt.Sprintf("%s is a stretch right now at a %.0f%% skill match", m.Name, m.SkillScore))
	}
	if n := names(m.Strengths, 2); n != "" {
		parts = append(parts, "your strongest fit here is "+n)
	}
	if len(m.Gaps) > 0 {
		g := m.Gaps[0]
		if g.Level == 0 {
			parts = append(parts, fmt.Sprintf("the biggest gap is %s, which is not recorded yet (needs level %d)", g.Name, g.RequiredLevel))
		} else {
			parts = append(parts, fmt.Sprintf("the biggest gap is %s at level %d of the %d needed", g.Name, g.Level, g.RequiredLevel))
		}
		if len(g.Courses) > 0 {
			parts = append(parts, "start with \""+g.Courses[0].Title+"\"")
		}
	}
	if cgpa < m.MinCGPA {
		parts = append(parts, fmt.Sprintf("CGPA %.2f is below the %.2f usually expected", cgpa, m.MinCGPA))
	}
	return capitalise(strings.Join(parts, "; ")) + "."
}

func names(list []SkillStanding, n int) string {
	picked := []string{}
	for _, s := range list {
		if len(picked) >= n {
			break
		}
		picked = append(picked, s.Name)
	}
	switch len(picked) {
	case 0:
		return ""
	case 1:
		return picked[0]
	default:
		return strings.Join(picked[:len(picked)-1], ", ") + " and " + picked[len(picked)-1]
	}
}

func capitalise(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// ---- storing and reading matches ----

// store replaces a student's career_matches rows. They are a derived cache, like
// skill_match_results, so they are rewritten rather than soft-deleted.
func (h *Handler) store(ctx context.Context, studentID, actorID int64, list []*Match) error {
	return pgx.BeginFunc(ctx, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `DELETE FROM career_matches WHERE student_id = $1`, studentID); err != nil {
			return err
		}
		batch := &pgx.Batch{}
		for _, m := range list {
			gaps, _ := json.Marshal(m.Gaps)
			strengths, _ := json.Marshal(m.Strengths)
			batch.Queue(`INSERT INTO career_matches (student_id, career_id, rank, skill_score, academic_score, final_score,
				readiness, gaps, strengths, explanation, computed_at, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12)`,
				studentID, m.CareerID, m.Rank, m.SkillScore, m.AcademicScore, m.FinalScore, m.Readiness,
				gaps, strengths, m.Explanation, m.ComputedAt, actorID)
		}
		return tx.SendBatch(ctx, batch).Close()
	})
}

// cached reads the stored matches, newest skill-score timestamp deciding is_stale.
func (h *Handler) cached(ctx context.Context, studentID int64) ([]*Match, error) {
	rows, err := h.db.Query(ctx, `
		SELECT m.career_id, c.code, c.name, c.domain, c.description, c.avg_package::float8, c.min_cgpa::float8,
		       m.rank, m.skill_score::float8, m.academic_score::float8, m.final_score::float8, m.readiness,
		       m.strengths, m.gaps, m.explanation, m.computed_at,
		       f.rating, f.is_useful, f.comment, f.created_at
		FROM career_matches m
		JOIN careers c ON c.id = m.career_id AND c.is_active
		LEFT JOIN career_feedback f ON f.student_id = m.student_id AND f.career_id = m.career_id AND f.is_active
		WHERE m.student_id = $1 AND m.is_active
		ORDER BY m.rank`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Match{}
	for rows.Next() {
		m := &Match{}
		var strengths, gaps []byte
		var rating *int
		var useful *bool
		var comment *string
		var fbAt *time.Time
		if err := rows.Scan(&m.CareerID, &m.Code, &m.Name, &m.Domain, &m.Description, &m.AvgPackage, &m.MinCGPA,
			&m.Rank, &m.SkillScore, &m.AcademicScore, &m.FinalScore, &m.Readiness,
			&strengths, &gaps, &m.Explanation, &m.ComputedAt, &rating, &useful, &comment, &fbAt); err != nil {
			return nil, err
		}
		m.Strengths, m.Gaps = []SkillStanding{}, []SkillStanding{}
		_ = json.Unmarshal(strengths, &m.Strengths)
		_ = json.Unmarshal(gaps, &m.Gaps)
		if rating != nil && fbAt != nil {
			m.Feedback = &Feedback{Rating: *rating, IsUseful: useful != nil && *useful, Comment: comment, CreatedAt: *fbAt}
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// markStale flags matches computed before the student's skill scores last changed.
func (h *Handler) markStale(ctx context.Context, studentID int64, list []*Match) error {
	at, err := skillscore.ComputedAt(ctx, h.db, []int64{studentID})
	if err != nil {
		return err
	}
	scored, ok := at[studentID]
	if !ok {
		return nil
	}
	for _, m := range list {
		m.IsStale = scored.After(m.ComputedAt)
	}
	return nil
}

func (h *Handler) writeMatches(c *gin.Context, studentID int64, list []*Match) {
	if err := h.markStale(c, studentID, list); err != nil {
		response.Error(c, err)
		return
	}
	filter := c.Query("readiness")
	top := request.QueryInt64(c, "limit")
	stale := false
	counts := map[string]int{Ready: 0, Close: 0, Explore: 0}
	out := []*Match{}
	for _, m := range list {
		counts[m.Readiness]++
		if m.IsStale {
			stale = true
		}
		if filter != "" && m.Readiness != filter {
			continue
		}
		if top != nil && *top > 0 && int64(len(out)) >= *top {
			continue
		}
		out = append(out, m)
	}
	var at *time.Time
	if len(list) > 0 {
		at = &list[0].ComputedAt
	}
	response.OK(c, gin.H{"student_id": studentID, "computed_at": at, "is_stale": stale,
		"counts": counts, "total": len(list), "matches": out})
}

// studentMatches returns the stored ranking. The first time a student opens the screen
// there is nothing stored yet, so it is computed and saved on the spot.
func (h *Handler) studentMatches(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if _, err := h.students.Get(c, a, id); err != nil { // self / parent / staff in scope
		response.Error(c, err)
		return
	}
	list, err := h.cached(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if len(list) == 0 || c.Query("refresh") == "true" {
		if list, err = h.evaluate(c, id); err != nil {
			response.Error(c, err)
			return
		}
		if err := h.store(c, id, a.ID, list); err != nil {
			response.Error(c, err)
			return
		}
	}
	h.writeMatches(c, id, list)
}

// runStudentMatches recomputes and stores the ranking, and tells the student it changed.
func (h *Handler) runStudentMatches(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	st, err := h.students.Get(c, a, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.evaluate(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if err := h.store(c, id, a.ID, list); err != nil {
		response.Error(c, err)
		return
	}
	if a.ID != id && len(list) > 0 {
		rt, rid := notify.Ref("career", list[0].CareerID)
		h.notify.SendSafe(c, notify.Notice{Title: "Your career suggestions were updated",
			Body: fmt.Sprintf("%s is your closest fit right now. Open Careers to see what is missing and what to study next.", list[0].Name),
			Type: notify.TypeSkill, RefType: rt, RefID: rid, CreatedBy: a.ID}, []int64{st.ID})
	}
	h.writeMatches(c, id, list)
}

// feedback records what the student thought of a suggestion. Besides being useful to the
// placement cell, these are the labels a trained model would later learn from.
func (h *Handler) feedback(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	careerID, ok := request.ID(c, "careerId")
	if !ok {
		return
	}
	var body struct {
		Rating   int     `json:"rating" binding:"required,min=1,max=5"`
		IsUseful *bool   `json:"is_useful"`
		Comment  *string `json:"comment" binding:"omitempty,max=1000"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("rating (1-5) is required", err.Error()))
		return
	}
	a := actor.From(c)
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.find(c, careerID); err != nil {
		response.Error(c, err)
		return
	}
	useful := body.Rating >= 3
	if body.IsUseful != nil {
		useful = *body.IsUseful
	}
	if _, err := h.db.Exec(c, `
		INSERT INTO career_feedback (student_id, career_id, rating, is_useful, comment, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $6)
		ON CONFLICT (student_id, career_id) WHERE is_active
		DO UPDATE SET rating = EXCLUDED.rating, is_useful = EXCLUDED.is_useful, comment = EXCLUDED.comment,
		              updated_by = EXCLUDED.updated_by`,
		id, careerID, body.Rating, useful, body.Comment, a.ID); err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.cached(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.writeMatches(c, id, list)
}
