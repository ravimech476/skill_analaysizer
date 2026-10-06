// Package marks handles mark entry (per class × semester × subject × exam × attempt),
// grading, CGPA/backlog recomputation, class result sheets, student mark history and
// subject allocation (which staff teach which subject to which class).
package marks

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	notify   *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, students: students, notify: n}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }
	g := r.Group("/marks")
	g.GET("/my-subjects", can("marks.create", "marks.update"), h.mySubjects)
	g.GET("/entry", can("marks.create", "marks.update"), h.getEntry)
	g.PUT("/entry", can("marks.create", "marks.update"), h.saveEntry)
	g.GET("/entry/template", can("marks.create", "marks.update"), h.entryTemplate)
	g.POST("/entry/upload", can("marks.create", "marks.update"), h.uploadEntry)
	g.GET("/sheet", can("marks.view"), h.sheet)
	g.GET("/sheet.xlsx", can("marks.view"), h.sheetXLSX)
	g.GET("/students/:id", can("marks.view"), h.history)
	g.GET("/students/:id/statement.pdf", can("marks.view"), h.statementPDF)

	a := r.Group("/subject-allocations")
	a.GET("", can("subject_allocation.view"), h.listAllocations)
	a.POST("", can("subject_allocation.create"), h.createAllocation)
	a.DELETE("/:id", can("subject_allocation.delete"), h.deleteAllocation)
}

// labelSQL renders a class label like "CSE II-A" (needs aliases d = department, yl = year level, c = class).
const labelSQL = `d.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section`

// ---- entry context ----

type entryCtx struct {
	ClassID        int64   `json:"class_id"`
	ClassLabel     string  `json:"class_label"`
	DepartmentID   int64   `json:"department_id"`
	AcademicYearID int64   `json:"academic_year_id"`
	InchargeID     *int64  `json:"-"`
	SemesterID     int64   `json:"semester_id"`
	SemNo          int     `json:"sem_no"`
	SubjectID      int64   `json:"subject_id"`
	SubjectCode    string  `json:"subject_code"`
	SubjectName    string  `json:"subject_name"`
	Credits        float64 `json:"credits"`
	ExamTypeID     int64   `json:"exam_type_id"`
	ExamName       string  `json:"exam_name"`
	MaxMarks       float64 `json:"max_marks"`
	IsFinal        bool    `json:"is_final"`
	PassPercent    float64 `json:"pass_percent"`
	AttemptNo      int     `json:"attempt_no"`
}

type entryKey struct {
	ClassID    int64 `form:"class_id" json:"class_id" binding:"required"`
	SemesterID int64 `form:"semester_id" json:"semester_id" binding:"required"`
	SubjectID  int64 `form:"subject_id" json:"subject_id" binding:"required"`
	ExamTypeID int64 `form:"exam_type_id" json:"exam_type_id" binding:"required"`
	AttemptNo  int   `form:"attempt_no" json:"attempt_no"`
}

func (h *Handler) loadCtx(ctx context.Context, k entryKey) (*entryCtx, error) {
	if k.AttemptNo <= 0 {
		k.AttemptNo = 1
	}
	if k.AttemptNo > 10 {
		return nil, response.BadRequest("attempt_no is too large")
	}
	e := &entryCtx{ClassID: k.ClassID, SemesterID: k.SemesterID, SubjectID: k.SubjectID, ExamTypeID: k.ExamTypeID, AttemptNo: k.AttemptNo}
	var classLevel, semLevel int64
	err := h.db.QueryRow(ctx, `SELECT `+labelSQL+`, c.department_id, c.academic_year_id, c.class_incharge_id, c.year_level_id
		FROM classes c JOIN departments d ON d.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id
		WHERE c.id = $1 AND c.is_active`, k.ClassID).Scan(&e.ClassLabel, &e.DepartmentID, &e.AcademicYearID, &e.InchargeID, &classLevel)
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Class not found")
	}
	if err != nil {
		return nil, err
	}
	err = h.db.QueryRow(ctx, `SELECT sem_no, year_level_id FROM semesters WHERE id = $1 AND is_active`, k.SemesterID).Scan(&e.SemNo, &semLevel)
	if dbutil.IsNoRows(err) || semLevel != classLevel {
		return nil, response.BadRequest("The semester does not belong to this class's year of study")
	}
	if err != nil {
		return nil, err
	}
	err = h.db.QueryRow(ctx, `SELECT s.code, s.name, s.credits::float8 FROM subjects s
		JOIN curriculum cu ON cu.subject_id = s.id AND cu.department_id = $2 AND cu.semester_id = $3 AND cu.is_active
		WHERE s.id = $1 AND s.is_active LIMIT 1`, k.SubjectID, e.DepartmentID, k.SemesterID).Scan(&e.SubjectCode, &e.SubjectName, &e.Credits)
	if dbutil.IsNoRows(err) {
		return nil, response.BadRequest("This subject is not in the class's curriculum for the semester")
	}
	if err != nil {
		return nil, err
	}
	err = h.db.QueryRow(ctx, `SELECT name, max_marks::float8, is_final, pass_percent::float8 FROM exam_types WHERE id = $1 AND is_active`,
		k.ExamTypeID).Scan(&e.ExamName, &e.MaxMarks, &e.IsFinal, &e.PassPercent)
	if dbutil.IsNoRows(err) {
		return nil, response.BadRequest("exam_type_id does not exist")
	}
	return e, err
}

// canEnter: admin; HOD of the class's department; the class incharge; or staff allocated to the subject.
func (h *Handler) canEnter(ctx context.Context, a actor.Actor, e *entryCtx) (bool, error) {
	if a.IsAdmin() {
		return true, nil
	}
	if e.InchargeID != nil && *e.InchargeID == a.ID {
		return true, nil
	}
	var ok bool
	err := h.db.QueryRow(ctx, `SELECT
		($5 AND EXISTS (SELECT 1 FROM users WHERE id = $1 AND department_id = $2))
		OR EXISTS (SELECT 1 FROM staff_assignments WHERE staff_id = $1 AND class_id = $3 AND subject_id = $4 AND semester_id = $6 AND is_active)`,
		a.ID, e.DepartmentID, e.ClassID, e.SubjectID, a.Has("hod"), e.SemesterID).Scan(&ok)
	return ok, err
}

// ---- entry grid ----

type EntryRow struct {
	StudentID     int64      `json:"student_id"`
	RegisterNo    string     `json:"register_no"`
	Name          string     `json:"name"`
	MarksObtained *float64   `json:"marks_obtained"`
	IsAbsent      bool       `json:"is_absent"`
	Grade         *string    `json:"grade"`
	Result        *string    `json:"result"`
	UpdatedAt     *time.Time `json:"updated_at"`
	InClass       bool       `json:"in_class"` // false = moved to another class since the marks were entered
}

type Stats struct {
	Entered int     `json:"entered"`
	Absent  int     `json:"absent"`
	Passed  int     `json:"passed"`
	Failed  int     `json:"failed"`
	Average float64 `json:"average"`
	Highest float64 `json:"highest"`
	PassPct float64 `json:"pass_percent"`
}

type EntrySheet struct {
	*entryCtx
	CanEdit bool       `json:"can_edit"`
	Rows    []EntryRow `json:"rows"`
	Stats   Stats      `json:"stats"`
}

// rosterSQL: attempt 1 → the class's current students + anyone already marked for this class;
// attempt N>1 (arrear) → students who failed/were absent in attempt N-1 + anyone already marked in attempt N.
const rosterSQL = `
	WITH roster AS (
		SELECT sp.user_id AS id FROM student_profiles sp JOIN users u ON u.id = sp.user_id
		 WHERE $5::int = 1 AND sp.current_class_id = $1 AND sp.is_active AND u.is_active
		UNION
		SELECT m.student_id FROM student_marks m
		 WHERE $5::int > 1 AND m.class_id = $1 AND m.semester_id = $2 AND m.subject_id = $3 AND m.exam_type_id = $4
		   AND m.attempt_no = $5::int - 1 AND m.result IN ('fail', 'absent') AND m.is_active
		UNION
		SELECT m.student_id FROM student_marks m
		 WHERE m.class_id = $1 AND m.semester_id = $2 AND m.subject_id = $3 AND m.exam_type_id = $4 AND m.attempt_no = $5::int AND m.is_active
	)
	SELECT u.id, sp.register_no, u.name, m.marks_obtained::float8, m.result = 'absent', m.grade, m.result, m.updated_at,
	       COALESCE(sp.current_class_id = $1, false)
	FROM roster r
	JOIN users u ON u.id = r.id
	JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
	LEFT JOIN student_marks m ON m.student_id = u.id AND m.semester_id = $2 AND m.subject_id = $3
	      AND m.exam_type_id = $4 AND m.attempt_no = $5::int AND m.is_active
	ORDER BY sp.register_no`

func (h *Handler) buildSheet(ctx context.Context, a actor.Actor, e *entryCtx) (*EntrySheet, error) {
	canEdit, err := h.canEnter(ctx, a, e)
	if err != nil {
		return nil, err
	}
	rows, err := h.db.Query(ctx, rosterSQL, e.ClassID, e.SemesterID, e.SubjectID, e.ExamTypeID, e.AttemptNo)
	if err != nil {
		return nil, err
	}
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (EntryRow, error) {
		var r EntryRow
		var absent *bool
		err := row.Scan(&r.StudentID, &r.RegisterNo, &r.Name, &r.MarksObtained, &absent, &r.Grade, &r.Result, &r.UpdatedAt, &r.InClass)
		r.IsAbsent = absent != nil && *absent
		return r, err
	})
	if err != nil {
		return nil, err
	}
	return &EntrySheet{entryCtx: e, CanEdit: canEdit, Rows: list, Stats: computeStats(list)}, nil
}

func computeStats(rows []EntryRow) Stats {
	s := Stats{}
	sum := 0.0
	for _, r := range rows {
		switch {
		case r.IsAbsent:
			s.Absent++
		case r.MarksObtained != nil:
			s.Entered++
			sum += *r.MarksObtained
			s.Highest = math.Max(s.Highest, *r.MarksObtained)
			if r.Result != nil && *r.Result == "pass" {
				s.Passed++
			} else {
				s.Failed++
			}
		}
	}
	if s.Entered > 0 {
		s.Average = math.Round(sum/float64(s.Entered)*100) / 100
	}
	if appeared := s.Entered + s.Absent; appeared > 0 {
		s.PassPct = math.Round(float64(s.Passed)/float64(appeared)*10000) / 100
	}
	return s
}

func (h *Handler) getEntry(c *gin.Context) {
	var k entryKey
	if err := c.ShouldBindQuery(&k); err != nil {
		response.Error(c, response.BadRequest("class_id, semester_id, subject_id and exam_type_id are required"))
		return
	}
	e, err := h.loadCtx(c, k)
	if err != nil {
		response.Error(c, err)
		return
	}
	sheet, err := h.buildSheet(c, actor.From(c), e)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, sheet)
}

type EntryInput struct {
	StudentID     int64    `json:"student_id" binding:"required"`
	MarksObtained *float64 `json:"marks_obtained"`
	IsAbsent      bool     `json:"is_absent"`
}

type saveBody struct {
	entryKey
	Entries []EntryInput `json:"entries" binding:"required"`
}

type grade struct {
	Grade  string
	Min    float64
	Points float64
	Pass   bool
}

func (h *Handler) gradeScale(ctx context.Context) ([]grade, error) {
	rows, err := h.db.Query(ctx, `SELECT grade, min_percent::float8, grade_point::float8, is_pass FROM grade_scales WHERE is_active ORDER BY min_percent DESC`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[grade])
}

// saveEntry upserts a whole grid. marks_obtained=null and is_absent=false clears a student's entry.
func (h *Handler) saveEntry(c *gin.Context) {
	body, ok := request.Bind[saveBody](c)
	if !ok {
		return
	}
	e, err := h.loadCtx(c, body.entryKey)
	if err != nil {
		response.Error(c, err)
		return
	}
	sheet, err := h.applyEntries(c, actor.From(c), e, body.Entries)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, sheet)
}

// applyEntries checks entry rights, grades and saves entries, recomputes CGPA and notifies
// students whose marks changed. Shared by the grid and the Excel upload.
func (h *Handler) applyEntries(c *gin.Context, a actor.Actor, e *entryCtx, entries []EntryInput) (*EntrySheet, error) {
	allowed, err := h.canEnter(c, a, e)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, response.Forbidden("Only the subject's staff, the class incharge, the HOD or an admin can enter these marks")
	}
	current, err := h.buildSheet(c, a, e)
	if err != nil {
		return nil, err
	}
	onRoster := map[int64]bool{}
	before := map[int64]EntryRow{}
	for _, r := range current.Rows {
		onRoster[r.StudentID] = true
		before[r.StudentID] = r
	}
	scale, err := h.gradeScale(c)
	if err != nil {
		return nil, err
	}
	if e.IsFinal && len(scale) == 0 {
		return nil, response.BadRequest("No grade scale is configured")
	}

	touched := []int64{}
	published := []int64{} // students whose marks were added or changed (not cleared)
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		for _, en := range entries {
			if !onRoster[en.StudentID] {
				return response.BadRequest(fmt.Sprintf("Student %d is not on this class's list for this exam", en.StudentID))
			}
			if !en.IsAbsent && en.MarksObtained == nil {
				if _, err := tx.Exec(c, `UPDATE student_marks SET is_active = false, updated_by = $6
					WHERE student_id = $1 AND semester_id = $2 AND subject_id = $3 AND exam_type_id = $4 AND attempt_no = $5 AND is_active`,
					en.StudentID, e.SemesterID, e.SubjectID, e.ExamTypeID, e.AttemptNo, a.ID); err != nil {
					return err
				}
				touched = append(touched, en.StudentID)
				continue
			}
			var marks *float64
			var gradeTxt *string
			var points *float64
			result := "absent"
			if en.IsAbsent {
				if e.IsFinal {
					ab, zero := "AB", 0.0
					gradeTxt, points = &ab, &zero
				}
			} else {
				m := *en.MarksObtained
				if m < 0 || m > e.MaxMarks {
					return response.BadRequest(fmt.Sprintf("Marks must be between 0 and %v", e.MaxMarks))
				}
				m = math.Round(m*100) / 100
				marks = &m
				pct := m / e.MaxMarks * 100
				if e.IsFinal {
					g := scale[len(scale)-1]
					for _, s := range scale {
						if pct >= s.Min {
							g = s
							break
						}
					}
					gradeTxt, points = &g.Grade, &g.Points
					result = map[bool]string{true: "pass", false: "fail"}[g.Pass]
				} else {
					result = map[bool]string{true: "pass", false: "fail"}[pct >= e.PassPercent]
				}
			}
			if _, err := tx.Exec(c, `
				INSERT INTO student_marks (student_id, academic_year_id, semester_id, subject_id, exam_type_id, attempt_no,
				                           marks_obtained, max_marks, grade, grade_point, result, class_id, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13)
				ON CONFLICT (student_id, semester_id, subject_id, exam_type_id, attempt_no) WHERE is_active
				DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained, max_marks = EXCLUDED.max_marks, grade = EXCLUDED.grade,
				              grade_point = EXCLUDED.grade_point, result = EXCLUDED.result, class_id = EXCLUDED.class_id,
				              academic_year_id = EXCLUDED.academic_year_id, updated_by = EXCLUDED.updated_by`,
				en.StudentID, e.AcademicYearID, e.SemesterID, e.SubjectID, e.ExamTypeID, e.AttemptNo,
				marks, e.MaxMarks, gradeTxt, points, result, e.ClassID, a.ID); err != nil {
				return err
			}
			// Record where the student studied this semester (student history).
			if _, err := tx.Exec(c, `
				INSERT INTO student_enrollments (student_id, class_id, academic_year_id, semester_id, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $5)
				ON CONFLICT (student_id, academic_year_id, semester_id) WHERE is_active DO NOTHING`,
				en.StudentID, e.ClassID, e.AcademicYearID, e.SemesterID, a.ID); err != nil {
				return err
			}
			touched = append(touched, en.StudentID)
			if old := before[en.StudentID]; old.IsAbsent != en.IsAbsent || !sameMarks(old.MarksObtained, marks) {
				published = append(published, en.StudentID)
			}
		}
		if len(touched) == 0 {
			return nil
		}
		if e.IsFinal {
			if err := Recompute(c, tx, touched); err != nil {
				return err
			}
		}
		// Marks reach a student's skill scores through the subject's skill mapping,
		// so every saved exam — not only the final one — refreshes them.
		return skillscore.Recompute(c, tx, a.ID, touched)
	})
	if err != nil {
		return nil, err
	}
	if len(published) > 0 {
		rt, rid := notify.Ref("marks", e.SubjectID)
		h.notify.SendSafe(c, notify.Notice{Title: fmt.Sprintf("%s marks: %s", e.ExamName, e.SubjectCode),
			Body: fmt.Sprintf("%s marks for %s %s (Semester %d) are available. Open Marks to view them.", e.ExamName, e.SubjectCode, e.SubjectName, e.SemNo),
			Type: notify.TypeMarks, RefType: rt, RefID: rid, CreatedBy: a.ID}, h.notify.WithParents(c, published))
	}
	return h.buildSheet(c, a, e)
}

func sameMarks(a, b *float64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return math.Abs(*a-*b) < 0.001
}

// Recompute refreshes cached CGPA and backlog count from each student's latest final-exam attempt per subject.
// CGPA = Σ(credits × grade point) / Σ credits over passed subjects; backlogs = subjects whose latest attempt failed/absent.
func Recompute(ctx context.Context, q dbutil.DBTX, studentIDs []int64) error {
	_, err := q.Exec(ctx, `
		WITH latest AS (
			SELECT DISTINCT ON (m.student_id, m.subject_id) m.student_id, m.result, m.grade_point, s.credits
			FROM student_marks m
			JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
			JOIN subjects s ON s.id = m.subject_id
			WHERE m.is_active AND m.student_id = ANY($1)
			ORDER BY m.student_id, m.subject_id, m.attempt_no DESC
		), agg AS (
			SELECT student_id,
			       ROUND(COALESCE(SUM(credits * grade_point) FILTER (WHERE result = 'pass')
			                      / NULLIF(SUM(credits) FILTER (WHERE result = 'pass'), 0), 0), 2) AS cgpa,
			       COUNT(*) FILTER (WHERE result IN ('fail', 'absent')) AS backlogs
			FROM latest GROUP BY student_id
		)
		UPDATE student_profiles sp SET cgpa = COALESCE(a.cgpa, 0), backlog_count = COALESCE(a.backlogs, 0)
		FROM (SELECT DISTINCT unnest($1::bigint[]) AS sid) ids
		LEFT JOIN agg a ON a.student_id = ids.sid
		WHERE sp.user_id = ids.sid AND sp.is_active`, studentIDs)
	return err
}

// ---- entry targets for the logged-in staff ----

type Target struct {
	ClassID     int64  `json:"class_id"`
	ClassLabel  string `json:"class_label"`
	SemesterID  int64  `json:"semester_id"`
	SemNo       int    `json:"sem_no"`
	SubjectID   int64  `json:"subject_id"`
	SubjectCode string `json:"subject_code"`
	SubjectName string `json:"subject_name"`
	Reason      string `json:"reason"` // admin | hod | incharge | allocated
}

// mySubjects lists (class, semester, subject) combinations the user may enter marks for in the current
// academic year, using each class's current semester (allocations carry their own semester).
func (h *Handler) mySubjects(c *gin.Context) {
	a := actor.From(c)
	rows, err := h.db.Query(c, `
		WITH me AS (SELECT id, department_id FROM users WHERE id = $1),
		class_access AS (
			SELECT c.*, CASE WHEN $2 THEN 'admin' WHEN c.class_incharge_id = $1 THEN 'incharge' ELSE 'hod' END AS reason
			FROM classes c JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
			WHERE c.is_active AND ($2 OR c.class_incharge_id = $1 OR ($3 AND c.department_id = (SELECT department_id FROM me)))
		)
		SELECT * FROM (
			SELECT DISTINCT ON (ca.id, sub.id) ca.id, `+labelFor("ca")+`, se.id, se.sem_no, sub.id, sub.code, sub.name, ca.reason
			FROM class_access ca
			JOIN departments d ON d.id = ca.department_id JOIN year_levels yl ON yl.id = ca.year_level_id
			JOIN semesters se ON se.id = ca.current_semester_id
			JOIN curriculum cu ON cu.department_id = ca.department_id AND cu.semester_id = ca.current_semester_id AND cu.is_active
			JOIN subjects sub ON sub.id = cu.subject_id AND sub.is_active
			UNION
			SELECT c.id, `+labelFor("c")+`, se.id, se.sem_no, sub.id, sub.code, sub.name, 'allocated'
			FROM staff_assignments sa
			JOIN classes c ON c.id = sa.class_id AND c.is_active
			JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
			JOIN departments d ON d.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id
			JOIN semesters se ON se.id = sa.semester_id
			JOIN subjects sub ON sub.id = sa.subject_id
			WHERE sa.staff_id = $1 AND sa.is_active
		) t ORDER BY 2, 5`, a.ID, a.IsAdmin(), a.Has("hod"))
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Target])
	if err != nil {
		response.Error(c, err)
		return
	}
	// A subject can appear twice (e.g. incharge and allocated); keep the first.
	seen := map[string]bool{}
	out := []Target{}
	for _, t := range list {
		k := fmt.Sprintf("%d/%d/%d", t.ClassID, t.SemesterID, t.SubjectID)
		if !seen[k] {
			seen[k] = true
			out = append(out, t)
		}
	}
	response.OK(c, out)
}

func labelFor(alias string) string {
	return `d.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || ` + alias + `.section`
}

// ---- class result sheet ----

type SheetSubject struct {
	ID      int64   `json:"id"`
	Code    string  `json:"code"`
	Name    string  `json:"name"`
	Credits float64 `json:"credits"`
	Stats   Stats   `json:"stats"`
}

type SheetCell struct {
	Marks  *float64 `json:"marks"`
	Result *string  `json:"result"`
	Grade  *string  `json:"grade"`
}

type SheetRow struct {
	StudentID  int64                `json:"student_id"`
	RegisterNo string               `json:"register_no"`
	Name       string               `json:"name"`
	Marks      map[string]SheetCell `json:"marks"` // subject id → cell
	Failed     int                  `json:"failed"`
}

type ResultSheet struct {
	ClassID    int64          `json:"class_id"`
	ClassLabel string         `json:"class_label"`
	SemesterID int64          `json:"semester_id"`
	ExamTypeID int64          `json:"exam_type_id"`
	ExamName   string         `json:"exam_name"`
	MaxMarks   float64        `json:"max_marks"`
	AttemptNo  int            `json:"attempt_no"`
	Subjects   []SheetSubject `json:"subjects"`
	Rows       []*SheetRow    `json:"rows"`
}

// sheetParams reads ?class_id=&semester_id=&exam_type_id=&attempt_no= (staff only).
func sheetParams(c *gin.Context) (a actor.Actor, classID, semID, examID int64, attempt int, err error) {
	a = actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		return a, 0, 0, 0, 0, response.Forbidden("Use the student mark history instead")
	}
	cl, se, ex := request.QueryInt64(c, "class_id"), request.QueryInt64(c, "semester_id"), request.QueryInt64(c, "exam_type_id")
	if cl == nil || se == nil || ex == nil {
		return a, 0, 0, 0, 0, response.BadRequest("class_id, semester_id and exam_type_id are required")
	}
	attempt = 1
	if v := request.QueryInt64(c, "attempt_no"); v != nil && *v > 0 {
		attempt = int(*v)
	}
	return a, *cl, *se, *ex, attempt, nil
}

// sheet: GET /marks/sheet?class_id=&semester_id=&exam_type_id=&attempt_no=
func (h *Handler) sheet(c *gin.Context) {
	a, classID, semID, examID, attempt, err := sheetParams(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	res, err := h.buildResultSheet(c, a, classID, semID, examID, attempt)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

// buildResultSheet: every student of the class × every curriculum subject for one exam (HOD/staff: own department).
func (h *Handler) buildResultSheet(c *gin.Context, a actor.Actor, classID, semID, examID int64, attempt int) (*ResultSheet, error) {
	var deptID int64
	var label, examName string
	var maxMarks float64
	if err := h.db.QueryRow(c, `SELECT c.department_id, `+labelSQL+` FROM classes c JOIN departments d ON d.id = c.department_id
		JOIN year_levels yl ON yl.id = c.year_level_id WHERE c.id = $1 AND c.is_active`, classID).Scan(&deptID, &label); err != nil {
		return nil, notFound(err, "Class not found")
	}
	if err := h.db.QueryRow(c, `SELECT name, max_marks::float8 FROM exam_types WHERE id = $1`, examID).Scan(&examName, &maxMarks); err != nil {
		return nil, notFound(err, "Exam type not found")
	}
	// HOD/staff see their own department's classes (placement officers and admins see all).
	if !a.Has("admin", "placement_officer") {
		var mine bool
		if err := h.db.QueryRow(c, `SELECT department_id IS NULL OR department_id = $2 FROM users WHERE id = $1`, a.ID, deptID).Scan(&mine); err != nil {
			return nil, err
		}
		if !mine {
			return nil, response.Forbidden("This class belongs to another department")
		}
	}

	subRows, err := h.db.Query(c, `SELECT s.id, s.code, s.name, s.credits::float8 FROM curriculum cu JOIN subjects s ON s.id = cu.subject_id
		WHERE cu.department_id = $1 AND cu.semester_id = $2 AND cu.is_active ORDER BY s.code`, deptID, semID)
	if err != nil {
		return nil, err
	}
	subjects, err := pgx.CollectRows(subRows, func(r pgx.CollectableRow) (SheetSubject, error) {
		var s SheetSubject
		return s, r.Scan(&s.ID, &s.Code, &s.Name, &s.Credits)
	})
	if err != nil {
		return nil, err
	}

	rows, err := h.db.Query(c, `
		WITH roster AS (
			SELECT sp.user_id AS id FROM student_profiles sp JOIN users u ON u.id = sp.user_id
			 WHERE sp.current_class_id = $1 AND sp.is_active AND u.is_active
			UNION
			SELECT student_id FROM student_marks WHERE class_id = $1 AND semester_id = $2 AND is_active
		)
		SELECT u.id, sp.register_no, u.name, m.subject_id, m.marks_obtained::float8, m.result, m.grade
		FROM roster r JOIN users u ON u.id = r.id JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
		LEFT JOIN student_marks m ON m.student_id = u.id AND m.semester_id = $2 AND m.exam_type_id = $3 AND m.attempt_no = $4 AND m.is_active
		ORDER BY sp.register_no`, classID, semID, examID, attempt)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	byStudent := map[int64]*SheetRow{}
	order := []int64{}
	perSubject := map[int64][]EntryRow{}
	for rows.Next() {
		var sid int64
		var reg, name string
		var subID *int64
		var cell SheetCell
		if err := rows.Scan(&sid, &reg, &name, &subID, &cell.Marks, &cell.Result, &cell.Grade); err != nil {
			return nil, err
		}
		row, ok := byStudent[sid]
		if !ok {
			row = &SheetRow{StudentID: sid, RegisterNo: reg, Name: name, Marks: map[string]SheetCell{}}
			byStudent[sid] = row
			order = append(order, sid)
		}
		if subID != nil {
			row.Marks[fmt.Sprint(*subID)] = cell
			if cell.Result != nil && (*cell.Result == "fail" || *cell.Result == "absent") {
				row.Failed++
			}
			perSubject[*subID] = append(perSubject[*subID], EntryRow{MarksObtained: cell.Marks, Result: cell.Result, IsAbsent: cell.Result != nil && *cell.Result == "absent"})
		}
	}
	for i := range subjects {
		subjects[i].Stats = computeStats(perSubject[subjects[i].ID])
	}
	out := make([]*SheetRow, 0, len(order))
	for _, id := range order {
		out = append(out, byStudent[id])
	}
	return &ResultSheet{ClassID: classID, ClassLabel: label, SemesterID: semID, ExamTypeID: examID, ExamName: examName,
		MaxMarks: maxMarks, AttemptNo: attempt, Subjects: subjects, Rows: out}, nil
}

// ---- student mark history ----

type ExamMark struct {
	ExamTypeID int64    `json:"exam_type_id"`
	ExamCode   string   `json:"exam_code"`
	ExamName   string   `json:"exam_name"`
	IsFinal    bool     `json:"is_final"`
	AttemptNo  int      `json:"attempt_no"`
	Marks      *float64 `json:"marks"`
	MaxMarks   float64  `json:"max_marks"`
	Result     *string  `json:"result"`
	Grade      *string  `json:"grade"`
}

type SubjectHistory struct {
	SubjectID   int64      `json:"subject_id"`
	Code        string     `json:"code"`
	Name        string     `json:"name"`
	Credits     float64    `json:"credits"`
	Exams       []ExamMark `json:"exams"`
	FinalGrade  *string    `json:"final_grade"`
	FinalResult *string    `json:"final_result"`
	gradePoint  *float64
}

type SemesterHistory struct {
	SemesterID   int64             `json:"semester_id"`
	SemNo        int               `json:"sem_no"`
	Name         string            `json:"name"`
	AcademicYear string            `json:"academic_year"`
	ClassLabel   *string           `json:"class_label"`
	SGPA         *float64          `json:"sgpa"`
	Credits      float64           `json:"credits_earned"`
	Backlogs     int               `json:"backlogs"`
	Subjects     []*SubjectHistory `json:"subjects"`
}

type History struct {
	StudentID      int64              `json:"student_id"`
	Name           string             `json:"name"`
	RegisterNo     string             `json:"register_no"`
	ClassLabel     *string            `json:"class_label"`
	DepartmentName *string            `json:"department_name"`
	Batch          string             `json:"batch"`
	CGPA           float64            `json:"cgpa"`
	BacklogCount   int                `json:"backlog_count"`
	Semesters      []*SemesterHistory `json:"semesters"`
}

func (h *Handler) history(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	res, err := h.buildHistory(c, actor.From(c), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

// buildHistory returns a student's marks by semester (scoped like the student profile).
func (h *Handler) buildHistory(c *gin.Context, a actor.Actor, id int64) (*History, error) {
	st, err := h.students.Get(c, a, id) // enforces who may see this student
	if err != nil {
		return nil, err
	}
	rows, err := h.db.Query(c, `
		SELECT se.id, se.sem_no, se.name, ay.name,
		       (SELECT `+labelSQL+` FROM classes c JOIN departments d ON d.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id WHERE c.id = m.class_id),
		       s.id, s.code, s.name, s.credits::float8,
		       et.id, et.code, et.name, et.is_final, et.sort_order, m.attempt_no, m.marks_obtained::float8, m.max_marks::float8, m.result, m.grade, m.grade_point::float8
		FROM student_marks m
		JOIN semesters se ON se.id = m.semester_id
		JOIN academic_years ay ON ay.id = m.academic_year_id
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id
		WHERE m.student_id = $1 AND m.is_active
		ORDER BY se.sem_no, s.code, et.sort_order, m.attempt_no`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	sems := map[int64]*SemesterHistory{}
	subjIdx := map[string]*SubjectHistory{}
	for rows.Next() {
		var semID, subID int64
		var semNo int
		var semName, ayName, code, name string
		var classLabel *string
		var credits float64
		var em ExamMark
		var sortOrder int
		var gp *float64
		if err := rows.Scan(&semID, &semNo, &semName, &ayName, &classLabel, &subID, &code, &name, &credits,
			&em.ExamTypeID, &em.ExamCode, &em.ExamName, &em.IsFinal, &sortOrder, &em.AttemptNo, &em.Marks, &em.MaxMarks, &em.Result, &em.Grade, &gp); err != nil {
			return nil, err
		}
		sem, ok := sems[semID]
		if !ok {
			sem = &SemesterHistory{SemesterID: semID, SemNo: semNo, Name: semName, AcademicYear: ayName, ClassLabel: classLabel}
			sems[semID] = sem
		}
		key := fmt.Sprintf("%d/%d", semID, subID)
		sub, ok := subjIdx[key]
		if !ok {
			sub = &SubjectHistory{SubjectID: subID, Code: code, Name: name, Credits: credits}
			subjIdx[key] = sub
			sem.Subjects = append(sem.Subjects, sub)
		}
		sub.Exams = append(sub.Exams, em)
		if em.IsFinal { // rows are ordered by attempt, so the last final wins
			sub.FinalGrade, sub.FinalResult, sub.gradePoint = em.Grade, em.Result, gp
		}
	}
	out := make([]*SemesterHistory, 0, len(sems))
	for _, sem := range sems {
		var pts, cr float64
		finals := 0
		for _, sub := range sem.Subjects {
			if sub.FinalResult == nil {
				continue
			}
			finals++
			if *sub.FinalResult == "pass" && sub.gradePoint != nil {
				pts += sub.Credits * *sub.gradePoint
				cr += sub.Credits
			} else {
				sem.Backlogs++
			}
		}
		sem.Credits = cr
		if finals > 0 && cr > 0 {
			v := math.Round(pts/cr*100) / 100
			sem.SGPA = &v
		}
		out = append(out, sem)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SemNo < out[j].SemNo })
	return &History{StudentID: st.ID, Name: st.Name, RegisterNo: st.RegisterNo, ClassLabel: st.ClassLabel, DepartmentName: st.DepartmentName,
		Batch: st.Batch, CGPA: st.CGPA, BacklogCount: st.BacklogCount, Semesters: out}, nil
}

func notFound(err error, msg string) error {
	if dbutil.IsNoRows(err) {
		return response.NotFound(msg)
	}
	return err
}
