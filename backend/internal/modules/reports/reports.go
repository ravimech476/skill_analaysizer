// Package reports serves the analytics dashboard: pass percentages, CGPA spread,
// skill gaps against current drives, and the placement trend. HOD/staff see their
// own department; admins and placement officers see the whole college.
package reports

import (
	"context"
	"math"
	"sort"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct{ db *pgxpool.Pool }

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache) {
	h := &Handler{db: db}
	r.GET("/reports/dashboard", middleware.RequirePermission(perms, "report.view"), h.dashboard)
}

type Headline struct {
	Students      int      `json:"students"`
	Staff         int      `json:"staff"`
	Classes       int      `json:"classes"`
	AvgCGPA       *float64 `json:"avg_cgpa"`
	WithBacklogs  int      `json:"with_backlogs"`
	Placed        int      `json:"placed"`
	PlacedPercent float64  `json:"placed_percent"`
	OpenDrives    int      `json:"open_drives"`
}

type ExamRef struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type ClassPass struct {
	ClassID     int64   `json:"class_id"`
	ClassLabel  string  `json:"class_label"`
	Department  string  `json:"department_code"`
	Students    int     `json:"students"`     // students with at least one mark in this exam
	AllClear    int     `json:"all_clear"`    // passed every subject
	Appeared    int     `json:"appeared"`     // subject entries
	Passed      int     `json:"passed"`       // subject entries passed
	PassPercent float64 `json:"pass_percent"` // Passed / Appeared
	ClearPct    float64 `json:"all_clear_percent"`
}

type CGPABucket struct {
	Label string         `json:"label"`
	Min   float64        `json:"min"`
	Total int            `json:"total"`
	ByDep map[string]int `json:"by_department"`
}

type SkillGap struct {
	SkillID      int64   `json:"skill_id"`
	Name         string  `json:"name"`
	Roles        int     `json:"roles"`          // current drives needing it
	Mandatory    int     `json:"mandatory_in"`   // drives where it is mandatory
	Required     int     `json:"required_level"` // highest level any drive asks for
	Meeting      int     `json:"students_meeting"`
	Recorded     int     `json:"students_recorded"` // students with any level recorded
	Coverage     float64 `json:"coverage_percent"`
	AvgLevel     float64 `json:"avg_level"`
	StudentsBase int     `json:"students_base"`
}

type BatchTrend struct {
	Batch       string   `json:"batch"`
	Students    int      `json:"students"`
	Placed      int      `json:"placed"`
	Percent     float64  `json:"placed_percent"`
	Offers      int      `json:"offers"`
	Highest     *float64 `json:"highest_package"`
	Average     *float64 `json:"average_package"`
	MedianOffer *float64 `json:"median_package"`
}

type MonthTrend struct {
	Month   string   `json:"month"` // YYYY-MM
	Offers  int      `json:"offers"`
	Average *float64 `json:"average_package"`
}

type Dashboard struct {
	Scope          *string      `json:"scope_department"` // nil = whole college
	Headline       Headline     `json:"headline"`
	Exams          []ExamRef    `json:"exams"` // exams with marks this academic year (for the pass % selector)
	Exam           *ExamRef     `json:"exam"`
	PassByClass    []ClassPass  `json:"pass_by_class"`
	CGPA           []CGPABucket `json:"cgpa_distribution"`
	NotGraded      int          `json:"cgpa_not_graded"`
	Departments    []string     `json:"departments"`
	SkillGaps      []SkillGap   `json:"skill_gaps"`
	SkillGapSource string       `json:"skill_gap_source"` // "current drives" or "all drives"
	PlacementBatch []BatchTrend `json:"placement_by_batch"`
	PlacementMonth []MonthTrend `json:"placement_by_month"`
}

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return math.Round(float64(a)/float64(b)*10000) / 100
}

// dashboard: GET /reports/dashboard?department_id=&exam_type_id=
func (h *Handler) dashboard(c *gin.Context) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("The dashboard is available to staff only"))
		return
	}
	dept := request.QueryInt64(c, "department_id")
	if !a.Has("admin", "placement_officer") {
		var own *int64
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&own); err != nil {
			response.Error(c, err)
			return
		}
		if own != nil {
			dept = own // HOD/staff: always their own department
		}
	}
	d := &Dashboard{}
	if dept != nil {
		var code string
		if err := h.db.QueryRow(c, `SELECT code FROM departments WHERE id = $1`, *dept).Scan(&code); err != nil {
			response.Error(c, response.BadRequest("department_id does not exist"))
			return
		}
		d.Scope = &code
	}
	steps := []func(context.Context, *Dashboard, *int64) error{h.headline, h.cgpa, h.skillGaps, h.placement}
	for _, step := range steps {
		if err := step(c, d, dept); err != nil {
			response.Error(c, err)
			return
		}
	}
	if err := h.passByClass(c, d, dept, request.QueryInt64(c, "exam_type_id")); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, d)
}

// openToDept: drive j is open to department $1 (drives without a department list are open to all).
const openToDept = `$1::bigint IS NULL
	OR NOT EXISTS (SELECT 1 FROM job_role_departments jd WHERE jd.job_role_id = j.id AND jd.is_active)
	OR EXISTS (SELECT 1 FROM job_role_departments jd WHERE jd.job_role_id = j.id AND jd.department_id = $1 AND jd.is_active)`

// studying students in scope
const studentsCTE = `WITH st AS (
	SELECT u.id, u.department_id, sp.cgpa, sp.backlog_count, sp.batch
	FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
	WHERE sp.is_active AND sp.lifecycle_status = 'studying' AND ($1::bigint IS NULL OR u.department_id = $1))`

func (h *Handler) headline(ctx context.Context, d *Dashboard, dept *int64) error {
	x := &d.Headline
	err := h.db.QueryRow(ctx, studentsCTE+`
		SELECT (SELECT count(*) FROM st)::int,
		       (SELECT round(avg(cgpa) FILTER (WHERE cgpa > 0), 2)::float8 FROM st),
		       (SELECT count(*) FROM st WHERE backlog_count > 0)::int,
		       (SELECT count(DISTINCT pr.student_id) FROM placement_records pr JOIN st ON st.id = pr.student_id WHERE pr.is_active)::int,
		       (SELECT count(DISTINCT u.id) FROM users u JOIN user_roles ur ON ur.user_id = u.id AND ur.is_active
		          JOIN roles r ON r.id = ur.role_id AND r.slug IN ('staff', 'hod', 'placement_officer')
		         WHERE u.is_active AND ($1::bigint IS NULL OR u.department_id = $1))::int,
		       (SELECT count(*) FROM classes c JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
		         WHERE c.is_active AND ($1::bigint IS NULL OR c.department_id = $1))::int,
		       (SELECT count(*) FROM company_job_roles j WHERE j.is_active AND j.status IN ('upcoming', 'open') AND (`+openToDept+`))::int`,
		dept).Scan(&x.Students, &x.AvgCGPA, &x.WithBacklogs, &x.Placed, &x.Staff, &x.Classes, &x.OpenDrives)
	x.PlacedPercent = pct(x.Placed, x.Students)
	return err
}

func (h *Handler) passByClass(ctx context.Context, d *Dashboard, dept, examID *int64) error {
	rows, err := h.db.Query(ctx, `
		SELECT et.id, et.name FROM exam_types et
		WHERE et.is_active AND EXISTS (
			SELECT 1 FROM student_marks m JOIN classes c ON c.id = m.class_id
			JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
			WHERE m.exam_type_id = et.id AND m.is_active AND ($1::bigint IS NULL OR c.department_id = $1))
		ORDER BY et.sort_order, et.id`, dept)
	if err != nil {
		return err
	}
	d.Exams, err = pgx.CollectRows(rows, pgx.RowToStructByPos[ExamRef])
	if err != nil {
		return err
	}
	d.PassByClass = []ClassPass{}
	if len(d.Exams) == 0 {
		return nil
	}
	d.Exam = &d.Exams[len(d.Exams)-1] // default: the latest exam in the calendar
	if examID != nil {
		for i := range d.Exams {
			if d.Exams[i].ID == *examID {
				d.Exam = &d.Exams[i]
			}
		}
	}
	rows, err = h.db.Query(ctx, `
		WITH m AS (
			SELECT m.class_id, m.student_id, m.result FROM student_marks m
			WHERE m.exam_type_id = $2 AND m.attempt_no = 1 AND m.is_active
		)
		SELECT c.id, dp.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section, dp.code,
		       count(DISTINCT m.student_id)::int,
		       (count(DISTINCT m.student_id) - count(DISTINCT m.student_id) FILTER (WHERE m.result IN ('fail', 'absent')))::int,
		       count(*)::int, count(*) FILTER (WHERE m.result = 'pass')::int
		FROM classes c
		JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
		JOIN departments dp ON dp.id = c.department_id
		JOIN year_levels yl ON yl.id = c.year_level_id
		JOIN m ON m.class_id = c.id
		WHERE c.is_active AND ($1::bigint IS NULL OR c.department_id = $1)
		GROUP BY c.id, dp.code, yl.level_no, c.section
		ORDER BY dp.code, yl.level_no, c.section`, dept, d.Exam.ID)
	if err != nil {
		return err
	}
	d.PassByClass, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (ClassPass, error) {
		var p ClassPass
		err := r.Scan(&p.ClassID, &p.ClassLabel, &p.Department, &p.Students, &p.AllClear, &p.Appeared, &p.Passed)
		p.PassPercent, p.ClearPct = pct(p.Passed, p.Appeared), pct(p.AllClear, p.Students)
		return p, err
	})
	return err
}

var cgpaBuckets = []struct {
	label    string
	min, max float64
}{
	{"Below 5", 0.01, 5}, {"5 – 6", 5, 6}, {"6 – 7", 6, 7}, {"7 – 8", 7, 8}, {"8 – 9", 8, 9}, {"9 – 10", 9, 10.01},
}

func (h *Handler) cgpa(ctx context.Context, d *Dashboard, dept *int64) error {
	d.CGPA = make([]CGPABucket, len(cgpaBuckets))
	for i, b := range cgpaBuckets {
		d.CGPA[i] = CGPABucket{Label: b.label, Min: b.min, ByDep: map[string]int{}}
	}
	rows, err := h.db.Query(ctx, studentsCTE+`
		SELECT COALESCE(dp.code, '-'), st.cgpa::float8 FROM st LEFT JOIN departments dp ON dp.id = st.department_id`, dept)
	if err != nil {
		return err
	}
	defer rows.Close()
	seen := map[string]bool{}
	for rows.Next() {
		var code string
		var v float64
		if err := rows.Scan(&code, &v); err != nil {
			return err
		}
		if !seen[code] {
			seen[code] = true
			d.Departments = append(d.Departments, code)
		}
		if v <= 0 {
			d.NotGraded++
			continue
		}
		for i, b := range cgpaBuckets {
			if v >= b.min && v < b.max {
				d.CGPA[i].Total++
				d.CGPA[i].ByDep[code]++
				break
			}
		}
	}
	if d.Departments == nil {
		d.Departments = []string{}
	}
	return rows.Err()
}

// skillGaps: for every skill the current drives ask for, how many in-scope students already meet the level.
func (h *Handler) skillGaps(ctx context.Context, d *Dashboard, dept *int64) error {
	d.SkillGapSource = "current drives"
	var current int
	if err := h.db.QueryRow(ctx, `SELECT count(*) FROM company_job_roles WHERE is_active AND status IN ('upcoming', 'open')`).Scan(&current); err != nil {
		return err
	}
	statuses := []string{"upcoming", "open"}
	if current == 0 {
		d.SkillGapSource = "all drives"
		statuses = []string{"upcoming", "open", "closed", "completed"}
	}
	rows, err := h.db.Query(ctx, studentsCTE+`,
		req AS (
			SELECT rs.skill_id, count(DISTINCT j.id)::int AS roles, count(DISTINCT j.id) FILTER (WHERE rs.is_mandatory)::int AS mandatory,
			       max(rs.required_level) AS lvl
			FROM job_role_skills rs JOIN company_job_roles j ON j.id = rs.job_role_id AND j.is_active AND j.status = ANY($2)
			WHERE rs.is_active AND (`+openToDept+`)
			GROUP BY rs.skill_id
		)
		SELECT s.id, s.name::text, req.roles, req.mandatory, req.lvl,
		       count(x.student_id) FILTER (WHERE x.proficiency >= req.lvl)::int,
		       count(x.student_id)::int,
		       COALESCE(round(avg(x.proficiency), 2), 0)::float8,
		       (SELECT count(*) FROM st)::int
		FROM req JOIN skills s ON s.id = req.skill_id
		LEFT JOIN student_skills x ON x.skill_id = req.skill_id AND x.is_active AND x.student_id IN (SELECT id FROM st)
		GROUP BY s.id, s.name, req.roles, req.mandatory, req.lvl`, dept, statuses)
	if err != nil {
		return err
	}
	d.SkillGaps, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (SkillGap, error) {
		var g SkillGap
		err := r.Scan(&g.SkillID, &g.Name, &g.Roles, &g.Mandatory, &g.Required, &g.Meeting, &g.Recorded, &g.AvgLevel, &g.StudentsBase)
		g.Coverage = pct(g.Meeting, g.StudentsBase)
		return g, err
	})
	if err != nil {
		return err
	}
	// Biggest gaps first: in-demand skills that few students meet.
	g := d.SkillGaps
	sort.Slice(g, func(i, j int) bool {
		if g[i].Coverage != g[j].Coverage {
			return g[i].Coverage < g[j].Coverage
		}
		if g[i].Roles != g[j].Roles {
			return g[i].Roles > g[j].Roles
		}
		return g[i].Name < g[j].Name
	})
	return nil
}

// placement: per batch (all students of the batch, including alumni) and offers per month over the last year.
func (h *Handler) placement(ctx context.Context, d *Dashboard, dept *int64) error {
	rows, err := h.db.Query(ctx, `
		WITH st AS (
			SELECT u.id, sp.batch FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.is_active AND sp.lifecycle_status <> 'discontinued' AND ($1::bigint IS NULL OR u.department_id = $1)
		), best AS (
			SELECT pr.student_id, max(pr.package_lpa) AS pkg, count(*) AS n
			FROM placement_records pr WHERE pr.is_active GROUP BY pr.student_id
		)
		SELECT st.batch, count(*)::int, count(best.student_id)::int, COALESCE(sum(best.n), 0)::int,
		       max(best.pkg)::float8, round(avg(best.pkg), 2)::float8,
		       (percentile_cont(0.5) WITHIN GROUP (ORDER BY best.pkg))::float8
		FROM st LEFT JOIN best ON best.student_id = st.id
		GROUP BY st.batch ORDER BY st.batch`, dept)
	if err != nil {
		return err
	}
	d.PlacementBatch, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (BatchTrend, error) {
		var b BatchTrend
		err := r.Scan(&b.Batch, &b.Students, &b.Placed, &b.Offers, &b.Highest, &b.Average, &b.MedianOffer)
		b.Percent = pct(b.Placed, b.Students)
		return b, err
	})
	if err != nil {
		return err
	}
	rows, err = h.db.Query(ctx, `
		WITH months AS (
			SELECT to_char(g, 'YYYY-MM') AS m FROM generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') g
		)
		SELECT months.m, count(pr.id)::int, round(avg(pr.package_lpa), 2)::float8
		FROM months
		LEFT JOIN (placement_records pr JOIN users u ON u.id = pr.student_id AND ($1::bigint IS NULL OR u.department_id = $1))
		       ON pr.is_active AND to_char(COALESCE(pr.offer_date, pr.created_at::date), 'YYYY-MM') = months.m
		GROUP BY months.m ORDER BY months.m`, dept)
	if err != nil {
		return err
	}
	d.PlacementMonth, err = pgx.CollectRows(rows, pgx.RowToStructByPos[MonthTrend])
	return err
}
