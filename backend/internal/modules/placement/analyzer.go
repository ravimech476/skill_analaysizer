package placement

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
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

type SkillGap struct {
	SkillID  int64  `json:"skill_id"`
	Name     string `json:"name"`
	Required int    `json:"required_level"`
	Level    int    `json:"student_level"` // 0 = no evidence at all
	// Score is the blended 0-100 skill score behind Level; RequiredScore is the level asked for
	// on the same scale, so the UI can show how far off a student is without rounding to stars.
	Score         float64 `json:"student_score"`
	RequiredScore float64 `json:"required_score"`
	Mandatory     bool    `json:"is_mandatory"`
	Weight        float64 `json:"weight"`
}

type Match struct {
	StudentID         int64      `json:"student_id"`
	Name              string     `json:"name"`
	RegisterNo        string     `json:"register_no"`
	DepartmentID      *int64     `json:"department_id"`
	DepartmentCode    *string    `json:"department_code"`
	ClassLabel        *string    `json:"class_label"`
	Batch             string     `json:"batch"`
	CGPA              float64    `json:"cgpa"`
	Backlogs          int        `json:"backlog_count"`
	SkillScore        float64    `json:"skill_score"`
	AcademicScore     float64    `json:"academic_score"`
	FinalScore        float64    `json:"final_score"`
	IsEligible        bool       `json:"is_eligible"`
	IneligibleReasons []string   `json:"ineligible_reasons"`
	Matched           []SkillGap `json:"matched_skills"`
	Missing           []SkillGap `json:"missing_skills"`
	ApplicationStatus *string    `json:"application_status"`
	PlacedPackage     *float64   `json:"placed_package"`
	PlacedCompany     *string    `json:"placed_company"`
	// IsStale: this row was computed before the student's skill scores last changed, so the
	// ranking needs re-running. Only ever true on a cached ranking.
	IsStale   bool `json:"is_stale"`
	lifecycle string
}

type candidateFilter struct {
	StudentIDs []int64 // nil = everyone
	DeptScope  *int64  // HOD/staff: own department only
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// evaluate scores students against a job role. Eligibility is checked in this order:
// department, batch, CGPA, backlogs, placement rule (only higher packages), mandatory skills.
func (h *Handler) evaluate(ctx context.Context, role *JobRole, f candidateFilter) ([]*Match, error) {
	var deptList []int64
	if len(role.Departments) > 0 && f.StudentIDs == nil {
		// When ranking everyone, only candidates from eligible departments are relevant.
		for _, d := range role.Departments {
			deptList = append(deptList, d.ID)
		}
	}
	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.name, sp.register_no, u.department_id, d.code,
		       CASE WHEN c.id IS NULL THEN NULL
		            ELSE cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section END,
		       sp.batch, sp.cgpa::float8, sp.backlog_count,
		       best.package, best.company,
		       (SELECT a.status FROM placement_applications a WHERE a.student_id = u.id AND a.job_role_id = $1 AND a.is_active),
		       sp.lifecycle_status
		FROM student_profiles sp
		JOIN users u ON u.id = sp.user_id AND u.is_active
		LEFT JOIN departments d ON d.id = u.department_id
		LEFT JOIN classes c ON c.id = sp.current_class_id
		LEFT JOIN departments cd ON cd.id = c.department_id
		LEFT JOIN year_levels yl ON yl.id = c.year_level_id
		LEFT JOIN LATERAL (
			SELECT pr.package_lpa::float8 AS package, co.name::text AS company
			FROM placement_records pr JOIN companies co ON co.id = pr.company_id
			WHERE pr.student_id = u.id AND pr.is_active AND pr.job_role_id <> $1
			ORDER BY pr.package_lpa DESC LIMIT 1
		) best ON true
		WHERE sp.is_active
		  AND ($2::bigint[] IS NOT NULL OR sp.lifecycle_status = 'studying')
		  AND ($2::bigint[] IS NULL OR u.id = ANY($2))
		  AND ($3::bigint IS NULL OR u.department_id = $3)
		  AND ($4::bigint[] IS NULL OR u.department_id = ANY($4))`,
		role.ID, f.StudentIDs, f.DeptScope, deptList)
	if err != nil {
		return nil, err
	}
	matches := []*Match{}
	ids := []int64{}
	for rows.Next() {
		m := &Match{}
		if err := rows.Scan(&m.StudentID, &m.Name, &m.RegisterNo, &m.DepartmentID, &m.DepartmentCode, &m.ClassLabel, &m.Batch,
			&m.CGPA, &m.Backlogs, &m.PlacedPackage, &m.PlacedCompany, &m.ApplicationStatus, &m.lifecycle); err != nil {
			rows.Close()
			return nil, err
		}
		matches = append(matches, m)
		ids = append(ids, m.StudentID)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Blended scores, not the raw level staff typed: a certificate, an assessment and
	// subject marks all move this number (see internal/modules/skillscore).
	scores, err := skillscore.Blended(ctx, h.db, ids)
	if err != nil {
		return nil, err
	}
	skillWeight, academicWeight, err := skillscore.MatchWeights(ctx, h.db)
	if err != nil {
		return nil, err
	}

	eligibleDept := map[int64]bool{}
	for _, d := range role.Departments {
		eligibleDept[d.ID] = true
	}
	for _, m := range matches {
		m.IneligibleReasons = []string{}
		m.Matched, m.Missing = []SkillGap{}, []SkillGap{}
		if m.lifecycle != "studying" {
			m.IneligibleReasons = append(m.IneligibleReasons, "Not a current student ("+strings.ReplaceAll(m.lifecycle, "_", " ")+")")
		}
		if len(eligibleDept) > 0 && (m.DepartmentID == nil || !eligibleDept[*m.DepartmentID]) {
			m.IneligibleReasons = append(m.IneligibleReasons, "Department not eligible")
		}
		if role.EligibleBatch != nil && *role.EligibleBatch != m.Batch {
			m.IneligibleReasons = append(m.IneligibleReasons, fmt.Sprintf("Only batch %s is eligible", *role.EligibleBatch))
		}
		if m.CGPA < role.MinCGPA {
			m.IneligibleReasons = append(m.IneligibleReasons, fmt.Sprintf("CGPA %.2f is below %.2f", m.CGPA, role.MinCGPA))
		}
		if m.Backlogs > role.MaxBacklogs {
			m.IneligibleReasons = append(m.IneligibleReasons, fmt.Sprintf("%d backlog(s), at most %d allowed", m.Backlogs, role.MaxBacklogs))
		}
		if m.PlacedPackage != nil && *m.PlacedPackage >= role.PackageLPA {
			m.IneligibleReasons = append(m.IneligibleReasons,
				fmt.Sprintf("Already placed at %.2f LPA (%s), only higher packages allowed", *m.PlacedPackage, deref(m.PlacedCompany)))
		}

		// Skill score = Σ weight × min(score / required score, 1) / Σ weight.
		var got, total float64
		for _, rs := range role.Skills {
			score := scores[m.StudentID][rs.SkillID]
			required := float64(rs.RequiredLevel) * skillscore.LevelStep
			lvl := skillscore.Level(score)
			gap := SkillGap{SkillID: rs.SkillID, Name: rs.SkillName, Required: rs.RequiredLevel, Level: lvl,
				Score: round2(score), RequiredScore: required, Mandatory: rs.IsMandatory, Weight: rs.Weight}
			total += rs.Weight
			got += rs.Weight * math.Min(score/required, 1)
			if score >= required {
				m.Matched = append(m.Matched, gap)
			} else {
				m.Missing = append(m.Missing, gap)
				if rs.IsMandatory {
					m.IneligibleReasons = append(m.IneligibleReasons, fmt.Sprintf("Needs %s at level %d (has %d)", rs.SkillName, rs.RequiredLevel, lvl))
				}
			}
		}
		m.SkillScore = 100
		if total > 0 {
			m.SkillScore = round2(got / total * 100)
		}
		m.AcademicScore = round2(m.CGPA * 10)
		m.FinalScore = round2(skillWeight*m.SkillScore + academicWeight*m.AcademicScore)
		m.IsEligible = len(m.IneligibleReasons) == 0
	}
	sort.SliceStable(matches, func(i, j int) bool {
		if matches[i].IsEligible != matches[j].IsEligible {
			return matches[i].IsEligible
		}
		if matches[i].FinalScore != matches[j].FinalScore {
			return matches[i].FinalScore > matches[j].FinalScore
		}
		return matches[i].Name < matches[j].Name
	})
	return matches, nil
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// scopeFor limits HOD/staff to their own department; admin and placement officers see everyone.
func (h *Handler) scopeFor(ctx context.Context, a actor.Actor) (*int64, error) {
	if a.Has("admin", "placement_officer") {
		return nil, nil
	}
	var dept *int64
	if err := h.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&dept); err != nil {
		return nil, err
	}
	return dept, nil
}

type rankResponse struct {
	AnalyzedAt *time.Time `json:"analyzed_at"`
	Total      int        `json:"total"`
	Eligible   int        `json:"eligible"`
	Stale      int        `json:"stale"` // students whose skill scores changed since this ranking
	Matches    []*Match   `json:"matches"`
}

// analyze ranks every candidate for the role and caches the result in skill_match_results.
func (h *Handler) analyze(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	role, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	matches, err := h.evaluate(c, role, candidateFilter{DeptScope: scope})
	if err != nil {
		response.Error(c, err)
		return
	}
	now := time.Now()
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		// skill_match_results is a derived cache: replace this role's rows (only the analyzer's department for HODs).
		if _, err := tx.Exec(c, `DELETE FROM skill_match_results r USING users u
			WHERE r.job_role_id = $1 AND u.id = r.student_id AND ($2::bigint IS NULL OR u.department_id = $2)`, id, scope); err != nil {
			return err
		}
		batch := &pgx.Batch{}
		for _, m := range matches {
			matched, _ := json.Marshal(m.Matched)
			missing, _ := json.Marshal(m.Missing)
			var reason *string
			if len(m.IneligibleReasons) > 0 {
				r := strings.Join(m.IneligibleReasons, "\n") // reasons never contain newlines
				reason = &r
			}
			batch.Queue(`INSERT INTO skill_match_results (job_role_id, student_id, skill_score, academic_score, final_score,
				matched_skills, missing_skills, is_eligible, ineligible_reason, computed_at, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)`,
				id, m.StudentID, m.SkillScore, m.AcademicScore, m.FinalScore, matched, missing, m.IsEligible, reason, now, a.ID)
		}
		return tx.SendBatch(c, batch).Close()
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	h.writeRanking(c, &now, matches)
}

func (h *Handler) writeRanking(c *gin.Context, at *time.Time, matches []*Match) {
	eligibleOnly := c.Query("eligible_only") == "true"
	limit := 500
	if v := request.QueryInt64(c, "limit"); v != nil && *v > 0 && *v < 5000 {
		limit = int(*v)
	}
	res := rankResponse{AnalyzedAt: at, Total: len(matches), Matches: []*Match{}}
	for _, m := range matches {
		if m.IsEligible {
			res.Eligible++
		}
		if m.IsStale {
			res.Stale++
		}
		if (!eligibleOnly || m.IsEligible) && len(res.Matches) < limit {
			res.Matches = append(res.Matches, m)
		}
	}
	response.OK(c, res)
}

// matches returns the cached ranking from the last analyze run, with live application/placement status.
func (h *Handler) matches(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if err := staffOnly(actor.From(c)); err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.findRole(c, id); err != nil {
		response.Error(c, err)
		return
	}
	at, out, err := h.cachedMatches(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.writeRanking(c, at, out)
}

// cachedMatches reads skill_match_results for a role (HOD/staff: own department only).
func (h *Handler) cachedMatches(c *gin.Context, id int64) (*time.Time, []*Match, error) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		return nil, nil, err
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		return nil, nil, err
	}
	rows, err := h.db.Query(c, `
		SELECT u.id, u.name, sp.register_no, u.department_id, d.code,
		       CASE WHEN c.id IS NULL THEN NULL
		            ELSE cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section END,
		       sp.batch, sp.cgpa::float8, sp.backlog_count,
		       r.skill_score::float8, r.academic_score::float8, r.final_score::float8, r.is_eligible, r.ineligible_reason,
		       r.matched_skills, r.missing_skills, r.computed_at,
		       (SELECT a.status FROM placement_applications a WHERE a.student_id = u.id AND a.job_role_id = $1 AND a.is_active)
		FROM skill_match_results r
		JOIN users u ON u.id = r.student_id
		JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
		LEFT JOIN departments d ON d.id = u.department_id
		LEFT JOIN classes c ON c.id = sp.current_class_id
		LEFT JOIN departments cd ON cd.id = c.department_id
		LEFT JOIN year_levels yl ON yl.id = c.year_level_id
		WHERE r.job_role_id = $1 AND r.is_active AND ($2::bigint IS NULL OR u.department_id = $2)
		ORDER BY r.is_eligible DESC, r.final_score DESC, u.name`, id, scope)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var at *time.Time
	out := []*Match{}
	computedFor := map[int64]time.Time{}
	ids := []int64{}
	for rows.Next() {
		m := &Match{}
		var reason *string
		var matched, missing []byte
		var computed time.Time
		if err := rows.Scan(&m.StudentID, &m.Name, &m.RegisterNo, &m.DepartmentID, &m.DepartmentCode, &m.ClassLabel, &m.Batch,
			&m.CGPA, &m.Backlogs, &m.SkillScore, &m.AcademicScore, &m.FinalScore, &m.IsEligible, &reason,
			&matched, &missing, &computed, &m.ApplicationStatus); err != nil {
			return nil, nil, err
		}
		if at == nil || computed.After(*at) {
			t := computed
			at = &t
		}
		computedFor[m.StudentID] = computed
		ids = append(ids, m.StudentID)
		m.IneligibleReasons = []string{}
		if reason != nil {
			m.IneligibleReasons = strings.Split(*reason, "\n")
		}
		_ = json.Unmarshal(matched, &m.Matched)
		_ = json.Unmarshal(missing, &m.Missing)
		out = append(out, m)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	rows.Close()
	// A ranking is only as fresh as the skill scores it was built from.
	scored, err := skillscore.ComputedAt(c, h.db, ids)
	if err != nil {
		return nil, nil, err
	}
	for _, m := range out {
		if t, ok := scored[m.StudentID]; ok {
			m.IsStale = t.After(computedFor[m.StudentID])
		}
	}
	return at, out, nil
}

// ---- student-facing: opportunities & skill gap ----

type Opportunity struct {
	Role              *JobRole   `json:"job_role"`
	IsEligible        bool       `json:"is_eligible"`
	IneligibleReasons []string   `json:"ineligible_reasons"`
	SkillScore        float64    `json:"skill_score"`
	FinalScore        float64    `json:"final_score"`
	Matched           []SkillGap `json:"matched_skills"`
	Missing           []SkillGap `json:"missing_skills"`
	ApplicationStatus *string    `json:"application_status"`
}

// opportunities: open/upcoming drives for one student with eligibility, match and missing skills,
// plus their applications and offers. Scoped like the student profile (self / parent / staff).
func (h *Handler) opportunities(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	st, err := h.students.Get(c, actor.From(c), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, selectRole+` WHERE j.is_active AND j.status IN ('open', 'upcoming')
		ORDER BY CASE j.status WHEN 'open' THEN 1 ELSE 2 END, j.drive_date NULLS LAST`)
	if err != nil {
		response.Error(c, err)
		return
	}
	roles := []*JobRole{}
	for rows.Next() {
		j, err := scanRole(rows)
		if err != nil {
			rows.Close()
			response.Error(c, err)
			return
		}
		roles = append(roles, j)
	}
	rows.Close()
	if err := h.attach(c, roles); err != nil {
		response.Error(c, err)
		return
	}
	ops := []Opportunity{}
	for _, role := range roles {
		ms, err := h.evaluate(c, role, candidateFilter{StudentIDs: []int64{id}})
		if err != nil {
			response.Error(c, err)
			return
		}
		if len(ms) == 0 {
			continue
		}
		m := ms[0]
		ops = append(ops, Opportunity{Role: role, IsEligible: m.IsEligible, IneligibleReasons: m.IneligibleReasons, SkillScore: m.SkillScore,
			FinalScore: m.FinalScore, Matched: m.Matched, Missing: m.Missing, ApplicationStatus: m.ApplicationStatus})
	}
	skills, err := h.skillsOf(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	apps, err := h.applicationsWhere(c, "a.student_id = $1", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{
		"student_id": st.ID, "name": st.Name, "cgpa": st.CGPA, "backlog_count": st.BacklogCount,
		"skills": skills, "applications": apps, "opportunities": ops,
	})
}
