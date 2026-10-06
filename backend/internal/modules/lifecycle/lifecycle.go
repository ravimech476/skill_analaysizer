// Package lifecycle moves students through their course: semester change, year promotion
// (with detention and pass-out), discontinuation and re-admission. Every move keeps
// student_enrollments as the per-semester history.
package lifecycle

import (
	"context"
	"encoding/json"
	"fmt"
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
	g := r.Group("/lifecycle")
	g.POST("/semester-change", can("promotion.create", "class.update"), h.semesterChange)
	g.POST("/promotion/preview", can("promotion.view"), h.preview)
	g.POST("/promotion", can("promotion.create"), h.promote)
	g.GET("/promotions", can("promotion.view"), h.runs)
	r.POST("/students/:id/lifecycle", can("promotion.create"), h.studentAction)
	r.GET("/students/:id/history", can("student.view"), h.history)
}

type Enrollment struct {
	AcademicYear string    `json:"academic_year"`
	SemNo        int       `json:"sem_no"`
	Semester     string    `json:"semester"`
	ClassLabel   string    `json:"class_label"`
	Status       string    `json:"status"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// history lists a student's semester-by-semester enrollments (scoped like the student profile).
func (h *Handler) history(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, `SELECT ay.name, se.sem_no, se.name, `+labelSQL+`, e.status, e.updated_at
		FROM student_enrollments e
		JOIN academic_years ay ON ay.id = e.academic_year_id
		JOIN semesters se ON se.id = e.semester_id
		JOIN classes c ON c.id = e.class_id
		JOIN departments d ON d.id = c.department_id
		JOIN year_levels yl ON yl.id = c.year_level_id
		WHERE e.student_id = $1 AND e.is_active ORDER BY ay.start_date, se.sem_no`, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Enrollment])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

const labelSQL = `d.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section`

// ---- semester change ----

type semesterBody struct {
	ClassIDs  []int64 `json:"class_ids" binding:"required,min=1"`
	Direction string  `json:"direction" binding:"omitempty,oneof=next previous"`
}

type classResult struct {
	ClassID int64  `json:"class_id"`
	Label   string `json:"label"`
	From    string `json:"from,omitempty"`
	To      string `json:"to,omitempty"`
	Reason  string `json:"reason,omitempty"`
}

// semesterChange moves classes to the other semester of their year (Sem 3 → 4, or back) and
// enrols their current students in the new semester. HODs are limited to their department.
func (h *Handler) semesterChange(c *gin.Context) {
	b, ok := request.Bind[semesterBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	step := 1
	if b.Direction == "previous" {
		step = -1
	}
	var deptScope *int64
	if !a.IsAdmin() {
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&deptScope); err != nil {
			response.Error(c, err)
			return
		}
		if deptScope == nil {
			response.Error(c, response.Forbidden("Your account has no department"))
			return
		}
	}
	changed, skipped := []classResult{}, []classResult{}
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		rows, err := tx.Query(c, `SELECT c.id, `+labelSQL+`, c.department_id, c.academic_year_id, c.year_level_id, se.id, se.name, se.sem_no
			FROM classes c JOIN departments d ON d.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id
			LEFT JOIN semesters se ON se.id = c.current_semester_id
			WHERE c.id = ANY($1) AND c.is_active ORDER BY 2`, b.ClassIDs)
		if err != nil {
			return err
		}
		type cls struct {
			id, dept, year, level int64
			label                 string
			semID                 *int64
			semName               *string
			semNo                 *int
		}
		list := []cls{}
		for rows.Next() {
			var x cls
			if err := rows.Scan(&x.id, &x.label, &x.dept, &x.year, &x.level, &x.semID, &x.semName, &x.semNo); err != nil {
				rows.Close()
				return err
			}
			list = append(list, x)
		}
		rows.Close()
		for _, x := range list {
			if deptScope != nil && *deptScope != x.dept {
				skipped = append(skipped, classResult{ClassID: x.id, Label: x.label, Reason: "Belongs to another department"})
				continue
			}
			if x.semNo == nil {
				skipped = append(skipped, classResult{ClassID: x.id, Label: x.label, Reason: "Class has no current semester"})
				continue
			}
			var nextID int64
			var nextName string
			err := tx.QueryRow(c, `SELECT id, name FROM semesters WHERE sem_no = $1 AND year_level_id = $2 AND is_active`,
				*x.semNo+step, x.level).Scan(&nextID, &nextName)
			if dbutil.IsNoRows(err) {
				reason := "Already in the last semester of the year; use year promotion"
				if step < 0 {
					reason = "Already in the first semester of the year"
				}
				skipped = append(skipped, classResult{ClassID: x.id, Label: x.label, Reason: reason})
				continue
			}
			if err != nil {
				return err
			}
			if _, err := tx.Exec(c, `UPDATE classes SET current_semester_id = $2, updated_by = $3 WHERE id = $1`, x.id, nextID, a.ID); err != nil {
				return err
			}
			if err := enrolClass(c, tx, x.id, a.ID); err != nil {
				return err
			}
			changed = append(changed, classResult{ClassID: x.id, Label: x.label, From: deref(x.semName), To: nextName})
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"changed": changed, "skipped": skipped})
}

// enrolClass records every current student of the class in the class's current semester.
func enrolClass(ctx context.Context, tx pgx.Tx, classID, actorID int64) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO student_enrollments (student_id, class_id, academic_year_id, semester_id, status, created_by, updated_by)
		SELECT sp.user_id, c.id, c.academic_year_id, c.current_semester_id, 'studying', $2, $2
		FROM student_profiles sp JOIN classes c ON c.id = sp.current_class_id
		WHERE c.id = $1 AND sp.is_active AND sp.lifecycle_status = 'studying' AND c.current_semester_id IS NOT NULL
		ON CONFLICT (student_id, academic_year_id, semester_id) WHERE is_active
		DO UPDATE SET class_id = EXCLUDED.class_id, status = 'studying', updated_by = EXCLUDED.updated_by`, classID, actorID)
	return err
}

// ---- year promotion ----

type yearInfo struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	StartDate time.Time `json:"-"`
	EndDate   time.Time `json:"-"`
	IsCurrent bool      `json:"is_current"`
}

type studentRef struct {
	ID           int64   `json:"id"`
	Name         string  `json:"name"`
	RegisterNo   string  `json:"register_no"`
	CGPA         float64 `json:"cgpa"`
	BacklogCount int     `json:"backlog_count"`
}

type classPlan struct {
	ClassID      int64        `json:"class_id"`
	Label        string       `json:"label"`
	DepartmentID int64        `json:"-"`
	LevelID      int64        `json:"-"`
	LevelNo      int          `json:"level_no"`
	Section      string       `json:"-"`
	InchargeID   *int64       `json:"-"`
	InchargeName *string      `json:"incharge_name"`
	Action       string       `json:"action"` // promote | pass_out
	TargetLabel  *string      `json:"target_label"`
	TargetExists bool         `json:"target_exists"`
	Students     []studentRef `json:"students"`
}

type promoteBody struct {
	FromYearID         int64   `json:"from_year_id" binding:"required"`
	ToYearID           int64   `json:"to_year_id" binding:"required"`
	DetainedStudentIDs []int64 `json:"detained_student_ids"`
	CarryIncharge      bool    `json:"carry_incharge"`
	SetCurrent         bool    `json:"set_current"`
}

func (h *Handler) year(ctx context.Context, q dbutil.DBTX, id int64) (*yearInfo, error) {
	y := &yearInfo{ID: id}
	err := q.QueryRow(ctx, `SELECT name, start_date, end_date, is_current FROM academic_years WHERE id = $1 AND is_active`, id).
		Scan(&y.Name, &y.StartDate, &y.EndDate, &y.IsCurrent)
	if dbutil.IsNoRows(err) {
		return nil, response.BadRequest("Academic year not found")
	}
	return y, err
}

// plan builds the per-class promotion plan for from → to (used by preview and execute).
func (h *Handler) plan(ctx context.Context, q dbutil.DBTX, from, to *yearInfo) ([]*classPlan, error) {
	var maxLevel int
	if err := q.QueryRow(ctx, `SELECT COALESCE(max(level_no), 4) FROM year_levels WHERE is_active`).Scan(&maxLevel); err != nil {
		return nil, err
	}
	rows, err := q.Query(ctx, `
		SELECT c.id, `+labelSQL+`, d.code, c.department_id, c.year_level_id, yl.level_no, c.section, c.class_incharge_id, inc.name,
		       nyl.id, nyl.level_no,
		       EXISTS (SELECT 1 FROM classes t WHERE t.is_active AND t.academic_year_id = $2 AND t.department_id = c.department_id
		               AND t.section = c.section AND t.year_level_id = nyl.id)
		FROM classes c
		JOIN departments d ON d.id = c.department_id
		JOIN year_levels yl ON yl.id = c.year_level_id
		LEFT JOIN year_levels nyl ON nyl.level_no = yl.level_no + 1 AND nyl.is_active
		LEFT JOIN users inc ON inc.id = c.class_incharge_id
		WHERE c.academic_year_id = $1 AND c.is_active
		ORDER BY yl.level_no DESC, d.code, c.section`, from.ID, to.ID)
	if err != nil {
		return nil, err
	}
	plans := []*classPlan{}
	for rows.Next() {
		p := &classPlan{Students: []studentRef{}}
		var nextLevelID *int64
		var nextLevelNo *int
		var deptCode string
		if err := rows.Scan(&p.ClassID, &p.Label, &deptCode, &p.DepartmentID, &p.LevelID, &p.LevelNo, &p.Section, &p.InchargeID, &p.InchargeName,
			&nextLevelID, &nextLevelNo, &p.TargetExists); err != nil {
			rows.Close()
			return nil, err
		}
		if nextLevelNo == nil || p.LevelNo >= maxLevel {
			p.Action = "pass_out"
		} else {
			p.Action = "promote"
			lbl := fmt.Sprintf("%s %s-%s", deptCode, roman(*nextLevelNo), p.Section)
			p.TargetLabel = &lbl
		}
		plans = append(plans, p)
	}
	rows.Close()
	for _, p := range plans {
		srows, err := q.Query(ctx, `SELECT u.id, u.name, sp.register_no, sp.cgpa::float8, sp.backlog_count
			FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.current_class_id = $1 AND sp.is_active AND sp.lifecycle_status = 'studying' ORDER BY sp.register_no`, p.ClassID)
		if err != nil {
			return nil, err
		}
		p.Students, err = pgx.CollectRows(srows, pgx.RowToStructByPos[studentRef])
		if err != nil {
			return nil, err
		}
	}
	return plans, nil
}

func roman(n int) string {
	r := []string{"", "I", "II", "III", "IV", "V", "VI"}
	if n > 0 && n < len(r) {
		return r[n]
	}
	return fmt.Sprint(n)
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func (h *Handler) checkYears(ctx context.Context, q dbutil.DBTX, fromID, toID int64) (*yearInfo, *yearInfo, error) {
	if fromID == toID {
		return nil, nil, response.BadRequest("Pick two different academic years")
	}
	from, err := h.year(ctx, q, fromID)
	if err != nil {
		return nil, nil, err
	}
	to, err := h.year(ctx, q, toID)
	if err != nil {
		return nil, nil, err
	}
	if !to.StartDate.After(from.StartDate) {
		return nil, nil, response.BadRequest("Students can only be promoted into a later academic year")
	}
	return from, to, nil
}

func (h *Handler) preview(c *gin.Context) {
	var b struct {
		FromYearID int64 `json:"from_year_id" binding:"required"`
		ToYearID   int64 `json:"to_year_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("from_year_id and to_year_id are required"))
		return
	}
	from, to, err := h.checkYears(c, h.db, b.FromYearID, b.ToYearID)
	if err != nil {
		response.Error(c, err)
		return
	}
	plans, err := h.plan(c, h.db, from, to)
	if err != nil {
		response.Error(c, err)
		return
	}
	var alreadyRun bool
	if err := h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM promotion_runs WHERE from_year_id = $1 AND to_year_id = $2 AND is_active)`, from.ID, to.ID).Scan(&alreadyRun); err != nil {
		response.Error(c, err)
		return
	}
	promote, passOut := 0, 0
	for _, p := range plans {
		if p.Action == "promote" {
			promote += len(p.Students)
		} else {
			passOut += len(p.Students)
		}
	}
	response.OK(c, gin.H{"from": from, "to": to, "already_run": alreadyRun, "classes": plans,
		"totals": gin.H{"classes": len(plans), "to_promote": promote, "to_pass_out": passOut}})
}

// promote runs the whole year promotion in one transaction.
func (h *Handler) promote(c *gin.Context) {
	b, ok := request.Bind[promoteBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	var runID int64
	var promoted, detained, passedOut, created int
	summary := []gin.H{}
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		from, to, err := h.checkYears(c, tx, b.FromYearID, b.ToYearID)
		if err != nil {
			return err
		}
		// Reserve the run first: the unique index makes a concurrent or repeated promotion fail here.
		if err := tx.QueryRow(c, `INSERT INTO promotion_runs (from_year_id, to_year_id, created_by, updated_by) VALUES ($1, $2, $3, $3) RETURNING id`,
			from.ID, to.ID, a.ID).Scan(&runID); err != nil {
			if dbutil.UniqueViolation(err) != "" {
				return response.Conflict(fmt.Sprintf("Students were already promoted from %s to %s", from.Name, to.Name))
			}
			return err
		}
		plans, err := h.plan(c, tx, from, to)
		if err != nil {
			return err
		}
		detainedSet := map[int64]bool{}
		for _, id := range b.DetainedStudentIDs {
			detainedSet[id] = true
		}
		// target finds or creates the class for (dept, level, section) in the new year.
		target := func(p *classPlan, levelID int64, carry bool) (int64, error) {
			var id int64
			err := tx.QueryRow(c, `SELECT id FROM classes WHERE is_active AND academic_year_id = $1 AND department_id = $2
				AND year_level_id = $3 AND section = $4`, to.ID, p.DepartmentID, levelID, p.Section).Scan(&id)
			if err == nil {
				return id, nil
			}
			if !dbutil.IsNoRows(err) {
				return 0, err
			}
			var incharge *int64
			if carry && p.InchargeID != nil {
				var busy bool
				if err := tx.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM classes WHERE class_incharge_id = $1 AND academic_year_id = $2 AND is_active)`,
					*p.InchargeID, to.ID).Scan(&busy); err != nil {
					return 0, err
				}
				if !busy {
					incharge = p.InchargeID
				}
			}
			err = tx.QueryRow(c, `INSERT INTO classes (department_id, academic_year_id, year_level_id, section, class_incharge_id, current_semester_id, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5,
				        (SELECT s.id FROM semesters s JOIN year_levels yl ON yl.id = $3 WHERE s.sem_no = yl.level_no * 2 - 1 AND s.is_active), $6, $6)
				RETURNING id`, p.DepartmentID, to.ID, levelID, p.Section, incharge, a.ID).Scan(&id)
			if err == nil {
				created++
			}
			return id, err
		}
		move := func(studentID, fromClass, toClass int64, oldStatus string) error {
			if _, err := tx.Exec(c, `UPDATE student_enrollments SET status = $3, updated_by = $4
				WHERE student_id = $1 AND academic_year_id = $2 AND is_active`, studentID, from.ID, oldStatus, a.ID); err != nil {
				return err
			}
			if _, err := tx.Exec(c, `UPDATE student_profiles SET current_class_id = $2, updated_by = $3 WHERE user_id = $1 AND is_active`,
				studentID, toClass, a.ID); err != nil {
				return err
			}
			_, err := tx.Exec(c, `INSERT INTO student_enrollments (student_id, class_id, academic_year_id, semester_id, status, created_by, updated_by)
				SELECT $1, c.id, c.academic_year_id, c.current_semester_id, 'studying', $3, $3 FROM classes c WHERE c.id = $2 AND c.current_semester_id IS NOT NULL
				ON CONFLICT (student_id, academic_year_id, semester_id) WHERE is_active DO UPDATE SET class_id = EXCLUDED.class_id, status = 'studying'`,
				studentID, toClass, a.ID)
			return err
		}

		for _, p := range plans {
			row := gin.H{"class": p.Label, "action": p.Action, "promoted": 0, "detained": 0, "passed_out": 0}
			var nextLevelID *int64
			if p.Action == "promote" {
				if err := tx.QueryRow(c, `SELECT id FROM year_levels WHERE level_no = $1 AND is_active`, p.LevelNo+1).Scan(&nextLevelID); err != nil {
					return err
				}
			}
			for _, s := range p.Students {
				switch {
				case detainedSet[s.ID]:
					repeat, err := target(p, p.LevelID, false)
					if err != nil {
						return err
					}
					if err := move(s.ID, p.ClassID, repeat, "detained"); err != nil {
						return err
					}
					detained++
					row["detained"] = row["detained"].(int) + 1
				case p.Action == "pass_out":
					if _, err := tx.Exec(c, `UPDATE student_enrollments SET status = 'passed_out', updated_by = $3
						WHERE student_id = $1 AND academic_year_id = $2 AND is_active`, s.ID, from.ID, a.ID); err != nil {
						return err
					}
					if _, err := tx.Exec(c, `UPDATE student_profiles SET lifecycle_status = 'passed_out', passed_out_year = $2,
						current_class_id = NULL, updated_by = $3 WHERE user_id = $1 AND is_active`, s.ID, from.EndDate.Year(), a.ID); err != nil {
						return err
					}
					passedOut++
					row["passed_out"] = row["passed_out"].(int) + 1
				default:
					next, err := target(p, *nextLevelID, b.CarryIncharge)
					if err != nil {
						return err
					}
					if err := move(s.ID, p.ClassID, next, "promoted"); err != nil {
						return err
					}
					promoted++
					row["promoted"] = row["promoted"].(int) + 1
				}
			}
			// Empty classes still get their next-year class so the structure carries forward.
			if len(p.Students) == 0 && p.Action == "promote" {
				if _, err := target(p, *nextLevelID, b.CarryIncharge); err != nil {
					return err
				}
			}
			summary = append(summary, row)
		}
		if b.SetCurrent {
			if _, err := tx.Exec(c, `UPDATE academic_years SET is_current = false WHERE is_current AND id <> $1`, to.ID); err != nil {
				return err
			}
			if _, err := tx.Exec(c, `UPDATE academic_years SET is_current = true, updated_by = $2 WHERE id = $1`, to.ID, a.ID); err != nil {
				return err
			}
		}
		js, _ := json.Marshal(summary)
		_, err = tx.Exec(c, `UPDATE promotion_runs SET promoted_count = $2, detained_count = $3, passed_out_count = $4, classes_created = $5, summary = $6
			WHERE id = $1`, runID, promoted, detained, passedOut, created, js)
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, gin.H{"run_id": runID, "promoted": promoted, "detained": detained, "passed_out": passedOut,
		"classes_created": created, "classes": summary})
}

type Run struct {
	ID             int64           `json:"id"`
	FromYear       string          `json:"from_year"`
	ToYear         string          `json:"to_year"`
	PromotedCount  int             `json:"promoted_count"`
	DetainedCount  int             `json:"detained_count"`
	PassedOutCount int             `json:"passed_out_count"`
	ClassesCreated int             `json:"classes_created"`
	Summary        json.RawMessage `json:"summary"`
	CreatedBy      *string         `json:"created_by_name"`
	CreatedAt      time.Time       `json:"created_at"`
}

func (h *Handler) runs(c *gin.Context) {
	rows, err := h.db.Query(c, `SELECT r.id, f.name, t.name, r.promoted_count, r.detained_count, r.passed_out_count, r.classes_created,
		r.summary, u.name, r.created_at
		FROM promotion_runs r JOIN academic_years f ON f.id = r.from_year_id JOIN academic_years t ON t.id = r.to_year_id
		LEFT JOIN users u ON u.id = r.created_by WHERE r.is_active ORDER BY r.created_at DESC`)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Run])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// ---- discontinue / re-admit ----

type actionBody struct {
	Action  string  `json:"action" binding:"required,oneof=discontinue readmit"`
	ClassID *int64  `json:"class_id"` // re-admit: the class to join (current academic year)
	Remarks *string `json:"remarks" binding:"omitempty,max=500"`
}

func (h *Handler) studentAction(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	b, ok := request.Bind[actionBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	var status string
	var dept *int64
	err := h.db.QueryRow(c, `SELECT sp.lifecycle_status, u.department_id FROM student_profiles sp JOIN users u ON u.id = sp.user_id
		WHERE sp.user_id = $1 AND sp.is_active`, id).Scan(&status, &dept)
	if dbutil.IsNoRows(err) {
		response.Error(c, response.NotFound("Student not found"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if b.Action == "discontinue" {
			if status != "studying" {
				return response.Conflict("Only a current student can be discontinued")
			}
			if _, err := tx.Exec(c, `UPDATE student_enrollments se SET status = 'discontinued', updated_by = $2
				FROM classes c WHERE c.id = se.class_id AND se.student_id = $1 AND se.is_active
				  AND c.academic_year_id = (SELECT id FROM academic_years WHERE is_current AND is_active LIMIT 1)`, id, a.ID); err != nil {
				return err
			}
			_, err := tx.Exec(c, `UPDATE student_profiles SET lifecycle_status = 'discontinued', current_class_id = NULL, status_remarks = $2, updated_by = $3
				WHERE user_id = $1 AND is_active`, id, b.Remarks, a.ID)
			return err
		}
		// re-admit
		if status == "studying" {
			return response.Conflict("The student is already studying")
		}
		if b.ClassID == nil {
			return response.BadRequest("Pick the class to re-admit the student into")
		}
		var classDept int64
		var current bool
		if err := tx.QueryRow(c, `SELECT c.department_id, ay.is_current FROM classes c JOIN academic_years ay ON ay.id = c.academic_year_id
			WHERE c.id = $1 AND c.is_active`, *b.ClassID).Scan(&classDept, &current); err != nil {
			if dbutil.IsNoRows(err) {
				return response.BadRequest("Class not found")
			}
			return err
		}
		if !current {
			return response.BadRequest("Re-admit into a class of the current academic year")
		}
		if dept != nil && *dept != classDept {
			return response.BadRequest("The class belongs to a different department")
		}
		if _, err := tx.Exec(c, `UPDATE student_profiles SET lifecycle_status = 'studying', passed_out_year = NULL, current_class_id = $2,
			status_remarks = $3, updated_by = $4 WHERE user_id = $1 AND is_active`, id, *b.ClassID, b.Remarks, a.ID); err != nil {
			return err
		}
		_, err := tx.Exec(c, `INSERT INTO student_enrollments (student_id, class_id, academic_year_id, semester_id, status, created_by, updated_by)
			SELECT $1, c.id, c.academic_year_id, c.current_semester_id, 'studying', $3, $3 FROM classes c WHERE c.id = $2 AND c.current_semester_id IS NOT NULL
			ON CONFLICT (student_id, academic_year_id, semester_id) WHERE is_active DO UPDATE SET class_id = EXCLUDED.class_id, status = 'studying'`,
			id, *b.ClassID, a.ID)
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": map[string]string{"discontinue": "Student discontinued", "readmit": "Student re-admitted"}[b.Action]})
}
