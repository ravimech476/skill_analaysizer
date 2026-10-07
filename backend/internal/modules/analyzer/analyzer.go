// Package analyzer provides analytics endpoints that combine a student's mark
// history, skills and placement eligibility into dashboard-ready views at the
// student, class and department level.
package analyzer

import (
	"context"
	"math"
	"sort"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

// Handler holds the dependencies shared by all three endpoints.
type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
}

// Register wires the analyzer routes into the private API group.
func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service) {
	h := &Handler{db: db, students: students}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	r.GET("/analyzer/student/:id", can("student.view"), h.studentAnalysis)
	r.GET("/analyzer/class/:id", can("class.view"), h.classAnalysis)
	r.GET("/analyzer/department", can("report.view"), h.departmentAnalysis)
}

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return math.Round(float64(a)/float64(b)*10000) / 100
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// ─────────────────────────────────────────────────────────────────────────────
// 1. GET /analyzer/student/:id
// ─────────────────────────────────────────────────────────────────────────────

type SemesterStat struct {
	SemNo      int     `json:"sem_no"`
	Name       string  `json:"name"`
	SGPA       float64 `json:"sgpa"`
	Subjects   int     `json:"subjects"`
	Passed     int     `json:"passed"`
	Failed     int     `json:"failed"`
	AvgPercent float64 `json:"avg_percent"`
}

type SubjectMark struct {
	SubjectID     int64   `json:"subject_id"`
	Code          string  `json:"code"`
	Name          string  `json:"name"`
	Semester      string  `json:"semester"`
	MarksPercent  float64 `json:"marks_percent"`
	MaxMarks      float64 `json:"max_marks"`
	MarksObtained float64 `json:"marks_obtained"`
	Result        string  `json:"result"`
	Grade         string  `json:"grade"`
}

type SkillEntry struct {
	SkillID     int64  `json:"skill_id"`
	Name        string `json:"name"`
	Proficiency int    `json:"proficiency"`
	Source      string `json:"source"`
}

type EligibleDrive struct {
	ID           int64   `json:"id"`
	Company      string  `json:"company"`
	Title        string  `json:"title"`
	PackageLPA   float64 `json:"package_lpa"`
	MatchPercent float64 `json:"match_percent"`
}

type StudentAnalysis struct {
	StudentID    int64          `json:"student_id"`
	Name         string         `json:"name"`
	RegisterNo   string         `json:"register_no"`
	Department   string         `json:"department"`
	ClassLabel   string         `json:"class_label"`
	CGPA         float64        `json:"cgpa"`
	BacklogCount int            `json:"backlog_count"`
	Semesters    []SemesterStat `json:"semesters"`
	Subjects     []SubjectMark  `json:"subjects"`
	Skills       []SkillEntry   `json:"skills"`
	Strengths    []string       `json:"strengths"`
	Weaknesses   []string       `json:"weaknesses"`
	EligDrives   []EligibleDrive `json:"eligible_drives"`
}

func (h *Handler) studentAnalysis(c *gin.Context) {
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

	out := StudentAnalysis{
		StudentID:    st.ID,
		Name:         st.Name,
		RegisterNo:   st.RegisterNo,
		Department:   strVal(st.DepartmentCode),
		ClassLabel:   strVal(st.ClassLabel),
		CGPA:         st.CGPA,
		BacklogCount: st.BacklogCount,
	}

	// ── semesters ──
	sems, err := h.semesterStats(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Semesters = sems

	// ── subjects (latest final-exam marks per subject) ──
	subjects, err := h.subjectMarks(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Subjects = subjects

	// ── strengths / weaknesses ──
	out.Strengths, out.Weaknesses = []string{}, []string{}
	for _, s := range subjects {
		if s.MarksPercent >= 75 {
			out.Strengths = append(out.Strengths, s.Name)
		} else if s.MarksPercent > 0 && s.MarksPercent < 60 {
			out.Weaknesses = append(out.Weaknesses, s.Name)
		}
	}

	// ── skills ──
	skills, err := h.studentSkills(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Skills = skills

	// ── eligible drives ──
	drives, err := h.eligibleDrives(c, id, st.CGPA, st.BacklogCount, st.DepartmentID, st.Batch)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.EligDrives = drives

	response.OK(c, out)
}

// semesterStats groups final-exam marks by semester and computes per-semester stats.
func (h *Handler) semesterStats(ctx context.Context, studentID int64) ([]SemesterStat, error) {
	rows, err := h.db.Query(ctx, `
		SELECT se.sem_no, se.name,
		       s.credits::float8, m.marks_obtained::float8, m.max_marks::float8, m.result, m.grade_point::float8
		FROM student_marks m
		JOIN semesters se ON se.id = m.semester_id
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		WHERE m.student_id = $1 AND m.is_active
		  AND m.attempt_no = (SELECT max(m2.attempt_no) FROM student_marks m2
		      WHERE m2.student_id = m.student_id AND m2.subject_id = m.subject_id
		        AND m2.exam_type_id = m.exam_type_id AND m2.semester_id = m.semester_id AND m2.is_active)
		ORDER BY se.sem_no`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type semAcc struct {
		name       string
		pts, creds float64
		subjects   int
		passed     int
		failed     int
		pctSum     float64
	}
	acc := map[int]*semAcc{}
	order := []int{}

	for rows.Next() {
		var semNo int
		var name string
		var credits, marks, maxMarks float64
		var result *string
		var gp *float64
		if err := rows.Scan(&semNo, &name, &credits, &marks, &maxMarks, &result, &gp); err != nil {
			return nil, err
		}
		s, ok := acc[semNo]
		if !ok {
			s = &semAcc{name: name}
			acc[semNo] = s
			order = append(order, semNo)
		}
		s.subjects++
		if maxMarks > 0 {
			s.pctSum += marks / maxMarks * 100
		}
		if result != nil && *result == "pass" {
			s.passed++
			if gp != nil {
				s.pts += credits * *gp
				s.creds += credits
			}
		} else {
			s.failed++
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := make([]SemesterStat, 0, len(order))
	for _, semNo := range order {
		s := acc[semNo]
		sgpa := 0.0
		if s.creds > 0 {
			sgpa = round2(s.pts / s.creds)
		}
		out = append(out, SemesterStat{
			SemNo:      semNo,
			Name:       s.name,
			SGPA:       sgpa,
			Subjects:   s.subjects,
			Passed:     s.passed,
			Failed:     s.failed,
			AvgPercent: round2(s.pctSum / float64(s.subjects)),
		})
	}
	return out, nil
}

// subjectMarks returns the latest final-exam marks per subject for a student.
func (h *Handler) subjectMarks(ctx context.Context, studentID int64) ([]SubjectMark, error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT ON (m.subject_id)
		       s.id, s.code, s.name, 'Sem ' || se.sem_no,
		       m.marks_obtained::float8, m.max_marks::float8,
		       COALESCE(m.result, 'pending'), COALESCE(m.grade, '-')
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN semesters se ON se.id = m.semester_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		WHERE m.student_id = $1 AND m.is_active
		ORDER BY m.subject_id, m.attempt_no DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []SubjectMark{}
	for rows.Next() {
		var sm SubjectMark
		if err := rows.Scan(&sm.SubjectID, &sm.Code, &sm.Name, &sm.Semester,
			&sm.MarksObtained, &sm.MaxMarks, &sm.Result, &sm.Grade); err != nil {
			return nil, err
		}
		if sm.MaxMarks > 0 {
			sm.MarksPercent = round2(sm.MarksObtained / sm.MaxMarks * 100)
		}
		out = append(out, sm)
	}
	return out, rows.Err()
}

// studentSkills returns the manual skills recorded for a student.
func (h *Handler) studentSkills(ctx context.Context, studentID int64) ([]SkillEntry, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.name::text, ss.proficiency, ss.source
		FROM student_skills ss JOIN skills s ON s.id = ss.skill_id
		WHERE ss.student_id = $1 AND ss.is_active
		ORDER BY s.name`, studentID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[SkillEntry])
}

// eligibleDrives returns open/upcoming drives the student may be eligible for, with a
// basic match percentage computed from skill overlap.
func (h *Handler) eligibleDrives(ctx context.Context, studentID int64, cgpa float64, backlogs int, deptID *int64, batch string) ([]EligibleDrive, error) {
	rows, err := h.db.Query(ctx, `
		WITH student_sk AS (
			SELECT skill_id FROM student_skills WHERE student_id = $1 AND is_active
		)
		SELECT j.id, co.name, j.title, j.package_lpa::float8,
		       (SELECT count(*) FROM job_role_skills rs WHERE rs.job_role_id = j.id AND rs.is_active AND rs.skill_id IN (SELECT skill_id FROM student_sk))::int,
		       (SELECT count(*) FROM job_role_skills rs WHERE rs.job_role_id = j.id AND rs.is_active)::int
		FROM company_job_roles j
		JOIN companies co ON co.id = j.company_id
		WHERE j.is_active AND j.status IN ('open', 'upcoming')
		  AND j.min_cgpa <= $2
		  AND j.max_backlogs >= $3
		  AND (j.eligible_batch IS NULL OR j.eligible_batch = $5)
		  AND ($4::bigint IS NULL
		       OR NOT EXISTS (SELECT 1 FROM job_role_departments jd WHERE jd.job_role_id = j.id AND jd.is_active)
		       OR EXISTS (SELECT 1 FROM job_role_departments jd WHERE jd.job_role_id = j.id AND jd.department_id = $4 AND jd.is_active))
		ORDER BY j.package_lpa DESC`, studentID, cgpa, backlogs, deptID, batch)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []EligibleDrive{}
	for rows.Next() {
		var d EligibleDrive
		var matched, total int
		if err := rows.Scan(&d.ID, &d.Company, &d.Title, &d.PackageLPA, &matched, &total); err != nil {
			return nil, err
		}
		d.MatchPercent = pct(matched, total)
		out = append(out, d)
	}
	return out, rows.Err()
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. GET /analyzer/class/:id
// ─────────────────────────────────────────────────────────────────────────────

type ClassSubjectStat struct {
	SubjectID  int64   `json:"subject_id"`
	Code       string  `json:"code"`
	Name       string  `json:"name"`
	AvgPercent float64 `json:"avg_percent"`
	PassPct    float64 `json:"pass_percent"`
	Failed     int     `json:"failed"`
	Highest    float64 `json:"highest"`
}

type ClassSkillSummary struct {
	SkillID        int64   `json:"skill_id"`
	Name           string  `json:"name"`
	StudentsWithSk int     `json:"students_with_skill"`
	TotalStudents  int     `json:"total_students"`
	CoveragePct    float64 `json:"coverage_percent"`
}

type StudentRank struct {
	StudentID  int64   `json:"student_id"`
	Name       string  `json:"name"`
	RegisterNo string  `json:"register_no"`
	CGPA       float64 `json:"cgpa"`
	SkillCount int     `json:"skill_count"`
	Placed     bool    `json:"placed"`
}

type ClassAnalysis struct {
	ClassID     int64              `json:"class_id"`
	ClassLabel  string             `json:"class_label"`
	Department  string             `json:"department"`
	Students    int                `json:"students"`
	AvgCGPA     float64            `json:"avg_cgpa"`
	PassPercent float64            `json:"pass_percent"`
	TopCGPA     float64            `json:"top_cgpa"`
	Subjects    []ClassSubjectStat `json:"subjects"`
	SkillSum    []ClassSkillSummary `json:"skill_summary"`
	Ranking     []StudentRank      `json:"student_ranking"`
}

func (h *Handler) classAnalysis(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)

	// Load class info and verify access: admin=any, staff=own department.
	var out ClassAnalysis
	var classDeptID int64
	err := h.db.QueryRow(c, `
		SELECT c.id, d.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section,
		       d.code, c.department_id
		FROM classes c
		JOIN departments d ON d.id = c.department_id
		JOIN year_levels yl ON yl.id = c.year_level_id
		WHERE c.id = $1 AND c.is_active`, id).Scan(&out.ClassID, &out.ClassLabel, &out.Department, &classDeptID)
	if err != nil {
		if err == pgx.ErrNoRows {
			response.Error(c, response.NotFound("Class not found"))
		} else {
			response.Error(c, err)
		}
		return
	}

	// Staff / HOD: must belong to this class's department.
	if !a.Has("admin", "placement_officer") {
		var actorDept *int64
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&actorDept); err != nil {
			response.Error(c, err)
			return
		}
		if actorDept != nil && *actorDept != classDeptID {
			response.Error(c, response.Forbidden("You can only view classes in your department"))
			return
		}
	}

	// ── student count, avg/top CGPA ──
	err = h.db.QueryRow(c, `
		SELECT count(*)::int,
		       COALESCE(round((avg(sp.cgpa) FILTER (WHERE sp.cgpa > 0))::numeric, 2), 0)::float8,
		       COALESCE(max(sp.cgpa), 0)::float8
		FROM student_profiles sp
		JOIN users u ON u.id = sp.user_id AND u.is_active
		WHERE sp.is_active AND sp.current_class_id = $1`, id).Scan(&out.Students, &out.AvgCGPA, &out.TopCGPA)
	if err != nil {
		response.Error(c, err)
		return
	}

	// ── pass percent (all-clear students / total) ──
	if out.Students > 0 {
		var allClear int
		err = h.db.QueryRow(c, `
			SELECT count(*)::int
			FROM student_profiles sp
			JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.is_active AND sp.current_class_id = $1 AND sp.backlog_count = 0`, id).Scan(&allClear)
		if err != nil {
			response.Error(c, err)
			return
		}
		out.PassPercent = pct(allClear, out.Students)
	}

	// ── subject-wise stats ──
	subjects, err := h.classSubjects(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Subjects = subjects

	// ── skill summary ──
	skills, err := h.classSkills(c, id, out.Students)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.SkillSum = skills

	// ── student ranking ──
	ranking, err := h.classRanking(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Ranking = ranking

	response.OK(c, out)
}

// classSubjects returns per-subject mark statistics for a class.
func (h *Handler) classSubjects(ctx context.Context, classID int64) ([]ClassSubjectStat, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.code, s.name,
		       round(avg(m.marks_obtained / NULLIF(m.max_marks, 0) * 100)::numeric, 2)::float8,
		       (count(*) FILTER (WHERE m.result = 'pass'))::int,
		       count(*)::int,
		       max(m.marks_obtained)::float8
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		WHERE m.class_id = $1 AND m.is_active
		  AND m.attempt_no = 1
		GROUP BY s.id, s.code, s.name
		ORDER BY s.code`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ClassSubjectStat{}
	for rows.Next() {
		var cs ClassSubjectStat
		var passed, total int
		if err := rows.Scan(&cs.SubjectID, &cs.Code, &cs.Name, &cs.AvgPercent, &passed, &total, &cs.Highest); err != nil {
			return nil, err
		}
		cs.PassPct = pct(passed, total)
		cs.Failed = total - passed
		out = append(out, cs)
	}
	return out, rows.Err()
}

// classSkills counts how many students in the class have each skill.
func (h *Handler) classSkills(ctx context.Context, classID int64, totalStudents int) ([]ClassSkillSummary, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.name::text, count(DISTINCT ss.student_id)::int
		FROM student_skills ss
		JOIN skills s ON s.id = ss.skill_id
		JOIN student_profiles sp ON sp.user_id = ss.student_id AND sp.is_active AND sp.current_class_id = $1
		JOIN users u ON u.id = ss.student_id AND u.is_active
		WHERE ss.is_active
		GROUP BY s.id, s.name
		ORDER BY count(DISTINCT ss.student_id) DESC, s.name`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ClassSkillSummary{}
	for rows.Next() {
		var cs ClassSkillSummary
		if err := rows.Scan(&cs.SkillID, &cs.Name, &cs.StudentsWithSk); err != nil {
			return nil, err
		}
		cs.TotalStudents = totalStudents
		cs.CoveragePct = pct(cs.StudentsWithSk, totalStudents)
		out = append(out, cs)
	}
	return out, rows.Err()
}

// classRanking returns students in the class ranked by CGPA descending.
func (h *Handler) classRanking(ctx context.Context, classID int64) ([]StudentRank, error) {
	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.name, sp.register_no, sp.cgpa::float8,
		       (SELECT count(*) FROM student_skills ss WHERE ss.student_id = u.id AND ss.is_active)::int,
		       EXISTS (SELECT 1 FROM placement_records pr WHERE pr.student_id = u.id AND pr.is_active)
		FROM student_profiles sp
		JOIN users u ON u.id = sp.user_id AND u.is_active
		WHERE sp.is_active AND sp.current_class_id = $1
		ORDER BY sp.cgpa DESC, u.name`, classID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[StudentRank])
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. GET /analyzer/department?department_id=
// ─────────────────────────────────────────────────────────────────────────────

type DepartmentEntry struct {
	ID            int64    `json:"id"`
	Code          string   `json:"code"`
	Name          string   `json:"name"`
	Students      int      `json:"students"`
	AvgCGPA       float64  `json:"avg_cgpa"`
	PassPercent   float64  `json:"pass_percent"`
	PlacedCount   int      `json:"placed_count"`
	PlacedPercent float64  `json:"placed_percent"`
	TopSkills     []string `json:"top_skills"`
}

type SkillDistribution struct {
	SkillID      int64          `json:"skill_id"`
	Name         string         `json:"name"`
	ByDepartment map[string]int `json:"by_department"`
}

type SemTrend struct {
	Semester   string  `json:"semester"`
	AvgPercent float64 `json:"avg_percent"`
}

type WeakSubject struct {
	SubjectID  int64   `json:"subject_id"`
	Code       string  `json:"code"`
	Name       string  `json:"name"`
	Department string  `json:"department"`
	PassPct    float64 `json:"pass_percent"`
}

type DepartmentAnalysis struct {
	Scope     string              `json:"scope"` // "all" or department code
	Depts     []DepartmentEntry   `json:"departments"`
	SkillDist []SkillDistribution `json:"skill_distribution"`
	SemTrend  []SemTrend          `json:"semester_trend"`
	WeakSubjs []WeakSubject       `json:"weak_subjects"`
}

func (h *Handler) departmentAnalysis(c *gin.Context) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("This view is available to staff only"))
		return
	}

	dept := request.QueryInt64(c, "department_id")

	// Staff / HOD: force-scope to own department.
	if !a.Has("admin", "placement_officer") {
		var own *int64
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&own); err != nil {
			response.Error(c, err)
			return
		}
		if own != nil {
			dept = own
		}
	}

	out := DepartmentAnalysis{Scope: "all"}
	if dept != nil {
		var code string
		err := h.db.QueryRow(c, `SELECT code FROM departments WHERE id = $1 AND is_active`, *dept).Scan(&code)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.Error(c, response.BadRequest("department_id does not exist"))
			} else {
				response.Error(c, err)
			}
			return
		}
		out.Scope = code
	}

	// ── per-department stats ──
	depts, err := h.deptEntries(c, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.Depts = depts

	// ── skill distribution ──
	dist, err := h.skillDistribution(c, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.SkillDist = dist

	// ── semester trend ──
	trend, err := h.semesterTrend(c, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.SemTrend = trend

	// ── weak subjects ──
	weak, err := h.weakSubjects(c, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	out.WeakSubjs = weak

	response.OK(c, out)
}

// deptEntries returns per-department headline stats: student count, CGPA, pass %, placement, top skills.
func (h *Handler) deptEntries(ctx context.Context, dept *int64) ([]DepartmentEntry, error) {
	rows, err := h.db.Query(ctx, `
		SELECT d.id, d.code, d.name,
		       count(u.id)::int,
		       COALESCE(round((avg(sp.cgpa) FILTER (WHERE sp.cgpa > 0))::numeric, 2), 0)::float8,
		       count(*) FILTER (WHERE sp.backlog_count = 0)::int,
		       count(DISTINCT pr.student_id)::int
		FROM departments d
		LEFT JOIN users u ON u.department_id = d.id AND u.is_active
		LEFT JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active AND sp.lifecycle_status = 'studying'
		LEFT JOIN placement_records pr ON pr.student_id = u.id AND pr.is_active
		WHERE d.is_active AND ($1::bigint IS NULL OR d.id = $1)
		GROUP BY d.id, d.code, d.name
		HAVING count(u.id) > 0
		ORDER BY d.code`, dept)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []DepartmentEntry{}
	deptIDs := []int64{}
	for rows.Next() {
		var de DepartmentEntry
		var noBL int
		if err := rows.Scan(&de.ID, &de.Code, &de.Name, &de.Students, &de.AvgCGPA, &noBL, &de.PlacedCount); err != nil {
			return nil, err
		}
		de.PassPercent = pct(noBL, de.Students)
		de.PlacedPercent = pct(de.PlacedCount, de.Students)
		de.TopSkills = []string{}
		out = append(out, de)
		deptIDs = append(deptIDs, de.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Top 3 skills per department.
	if len(deptIDs) > 0 {
		skillRows, err := h.db.Query(ctx, `
			SELECT u.department_id, s.name::text, count(*)::int AS cnt
			FROM student_skills ss
			JOIN skills s ON s.id = ss.skill_id
			JOIN users u ON u.id = ss.student_id AND u.is_active
			WHERE ss.is_active AND u.department_id = ANY($1)
			GROUP BY u.department_id, s.name
			ORDER BY u.department_id, cnt DESC, s.name`, deptIDs)
		if err != nil {
			return nil, err
		}
		defer skillRows.Close()

		topByDept := map[int64][]string{}
		for skillRows.Next() {
			var dID int64
			var name string
			var cnt int
			if err := skillRows.Scan(&dID, &name, &cnt); err != nil {
				return nil, err
			}
			if len(topByDept[dID]) < 3 {
				topByDept[dID] = append(topByDept[dID], name)
			}
		}
		if err := skillRows.Err(); err != nil {
			return nil, err
		}
		for i := range out {
			if ts, ok := topByDept[out[i].ID]; ok {
				out[i].TopSkills = ts
			}
		}
	}

	return out, nil
}

// skillDistribution counts students with each skill broken down by department.
func (h *Handler) skillDistribution(ctx context.Context, dept *int64) ([]SkillDistribution, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.name::text, d.code, count(DISTINCT ss.student_id)::int
		FROM student_skills ss
		JOIN skills s ON s.id = ss.skill_id
		JOIN users u ON u.id = ss.student_id AND u.is_active
		JOIN departments d ON d.id = u.department_id
		WHERE ss.is_active AND ($1::bigint IS NULL OR u.department_id = $1)
		GROUP BY s.id, s.name, d.code
		ORDER BY s.name, d.code`, dept)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	bySkill := map[int64]*SkillDistribution{}
	order := []int64{}
	for rows.Next() {
		var skillID int64
		var name, deptCode string
		var cnt int
		if err := rows.Scan(&skillID, &name, &deptCode, &cnt); err != nil {
			return nil, err
		}
		sd, ok := bySkill[skillID]
		if !ok {
			sd = &SkillDistribution{SkillID: skillID, Name: name, ByDepartment: map[string]int{}}
			bySkill[skillID] = sd
			order = append(order, skillID)
		}
		sd.ByDepartment[deptCode] = cnt
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := make([]SkillDistribution, 0, len(order))
	for _, id := range order {
		out = append(out, *bySkill[id])
	}
	// Sort by total student count descending so the most popular skills appear first.
	sort.Slice(out, func(i, j int) bool {
		ti, tj := 0, 0
		for _, v := range out[i].ByDepartment {
			ti += v
		}
		for _, v := range out[j].ByDepartment {
			tj += v
		}
		if ti != tj {
			return ti > tj
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}

// semesterTrend returns the average marks percentage by semester across all students in scope.
func (h *Handler) semesterTrend(ctx context.Context, dept *int64) ([]SemTrend, error) {
	rows, err := h.db.Query(ctx, `
		SELECT 'Sem ' || se.sem_no, round(avg(m.marks_obtained / NULLIF(m.max_marks, 0) * 100)::numeric, 2)::float8
		FROM student_marks m
		JOIN semesters se ON se.id = m.semester_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		JOIN users u ON u.id = m.student_id AND u.is_active
		WHERE m.is_active AND ($1::bigint IS NULL OR u.department_id = $1)
		GROUP BY se.sem_no
		ORDER BY se.sem_no`, dept)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[SemTrend])
}

// weakSubjects returns subjects with a first-attempt pass rate below 70%.
func (h *Handler) weakSubjects(ctx context.Context, dept *int64) ([]WeakSubject, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.code, s.name, d.code,
		       count(*) FILTER (WHERE m.result = 'pass')::int,
		       count(*)::int
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		JOIN users u ON u.id = m.student_id AND u.is_active
		JOIN departments d ON d.id = u.department_id
		WHERE m.is_active AND m.attempt_no = 1 AND ($1::bigint IS NULL OR u.department_id = $1)
		GROUP BY s.id, s.code, s.name, d.code
		HAVING count(*) >= 10
		ORDER BY (count(*) FILTER (WHERE m.result = 'pass'))::float8 / count(*), s.code`, dept)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []WeakSubject{}
	for rows.Next() {
		var ws WeakSubject
		var passed, total int
		if err := rows.Scan(&ws.SubjectID, &ws.Code, &ws.Name, &ws.Department, &passed, &total); err != nil {
			return nil, err
		}
		ws.PassPct = pct(passed, total)
		if ws.PassPct < 70 {
			out = append(out, ws)
		}
	}
	return out, rows.Err()
}

// ── helpers ──

func strVal(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
