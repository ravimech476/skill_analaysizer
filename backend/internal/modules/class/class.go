// Package class manages classes (department × academic year × year level × section)
// and their class incharge, plus the department curriculum (subjects per semester).
package class

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Class struct {
	ID               int64     `json:"id"`
	Label            string    `json:"label"` // "CSE II-A"
	DepartmentID     int64     `json:"department_id"`
	DepartmentName   string    `json:"department_name"`
	DepartmentCode   string    `json:"department_code"`
	AcademicYearID   int64     `json:"academic_year_id"`
	AcademicYearName string    `json:"academic_year_name"`
	IsCurrentYear    bool      `json:"is_current_year"`
	YearLevelID      int64     `json:"year_level_id"`
	YearLevelName    string    `json:"year_level_name"`
	LevelNo          int       `json:"level_no"`
	Section          string    `json:"section"`
	InchargeID       *int64    `json:"class_incharge_id"`
	InchargeName     *string   `json:"class_incharge_name"`
	SemesterID       *int64    `json:"current_semester_id"`
	SemesterName     *string   `json:"current_semester_name"`
	SemNo            *int      `json:"current_sem_no"`
	StudentCount     int       `json:"student_count"`
	IsActive         bool      `json:"is_active"`
	CreatedAt        time.Time `json:"created_at"`
}

type Input struct {
	DepartmentID   int64  `json:"department_id" binding:"required"`
	AcademicYearID int64  `json:"academic_year_id" binding:"required"`
	YearLevelID    int64  `json:"year_level_id" binding:"required"`
	Section        string `json:"section" binding:"required,max=5"`
	InchargeID     *int64 `json:"class_incharge_id"`
	SemesterID     *int64 `json:"current_semester_id"` // defaults to the odd semester of the year level
}

type Handler struct{ db *pgxpool.Pool }

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache) {
	h := &Handler{db: db}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }
	g := r.Group("/classes")
	g.GET("", can("class.view"), h.list)
	g.GET("/:id", can("class.view"), h.get)
	g.POST("", can("class.create"), h.create)
	g.PUT("/:id", can("class.update"), h.update)
	g.DELETE("/:id", can("class.delete"), h.delete)

	cur := r.Group("/curriculum")
	cur.GET("", can("subject.view"), h.listCurriculum)
	cur.POST("", can("subject.create", "subject.update"), h.addCurriculum)
	cur.DELETE("/:id", can("subject.delete", "subject.update"), h.removeCurriculum)
}

// romans renders year levels the way colleges write classes ("CSE II-A").
var romans = []string{"", "I", "II", "III", "IV", "V", "VI"}

const selectClass = `
	SELECT c.id, d.id, d.name, d.code, ay.id, ay.name, ay.is_current, yl.id, yl.name, yl.level_no, c.section,
	       c.class_incharge_id, inc.name, c.current_semester_id, sem.name, sem.sem_no,
	       (SELECT count(*) FROM student_profiles sp JOIN users su ON su.id = sp.user_id
	        WHERE sp.current_class_id = c.id AND sp.is_active AND su.is_active)::int,
	       c.is_active, c.created_at
	FROM classes c
	JOIN departments d     ON d.id = c.department_id
	JOIN academic_years ay ON ay.id = c.academic_year_id
	JOIN year_levels yl    ON yl.id = c.year_level_id
	LEFT JOIN users inc    ON inc.id = c.class_incharge_id
	LEFT JOIN semesters sem ON sem.id = c.current_semester_id`

func scanClass(row pgx.Row) (*Class, error) {
	c := &Class{}
	err := row.Scan(&c.ID, &c.DepartmentID, &c.DepartmentName, &c.DepartmentCode, &c.AcademicYearID, &c.AcademicYearName,
		&c.IsCurrentYear, &c.YearLevelID, &c.YearLevelName, &c.LevelNo, &c.Section, &c.InchargeID, &c.InchargeName,
		&c.SemesterID, &c.SemesterName, &c.SemNo, &c.StudentCount, &c.IsActive, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	roman := fmt.Sprint(c.LevelNo)
	if c.LevelNo > 0 && c.LevelNo < len(romans) {
		roman = romans[c.LevelNo]
	}
	c.Label = fmt.Sprintf("%s %s-%s", c.DepartmentCode, roman, c.Section)
	return c, nil
}

// list: ?academic_year_id= (default: current year; "all" for every year) &department_id= &year_level_id= &incharge_id= &search=
func (h *Handler) list(c *gin.Context) {
	where := []string{"c.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }

	switch ay := c.Query("academic_year_id"); ay {
	case "all":
	case "":
		where = append(where, "ay.is_current")
	default:
		where = append(where, "c.academic_year_id::text = "+arg(ay))
	}
	for _, f := range []struct{ q, col string }{{"department_id", "c.department_id"}, {"year_level_id", "c.year_level_id"}, {"incharge_id", "c.class_incharge_id"}} {
		if v := c.Query(f.q); v != "" {
			where = append(where, f.col+"::text = "+arg(v))
		}
	}
	if s := strings.TrimSpace(c.Query("search")); s != "" {
		ph := arg("%" + s + "%")
		where = append(where, fmt.Sprintf("(d.name ILIKE %[1]s OR d.code ILIKE %[1]s OR inc.name ILIKE %[1]s)", ph))
	}
	rows, err := h.db.Query(c, selectClass+" WHERE "+strings.Join(where, " AND ")+
		" ORDER BY ay.start_date DESC, d.code, yl.level_no, c.section", args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*Class{}
	for rows.Next() {
		cl, err := scanClass(rows)
		if err != nil {
			response.Error(c, err)
			return
		}
		out = append(out, cl)
	}
	response.OK(c, out)
}

func (h *Handler) find(ctx context.Context, id int64) (*Class, error) {
	cl, err := scanClass(h.db.QueryRow(ctx, selectClass+" WHERE c.id = $1", id))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Class not found")
	}
	return cl, err
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	cl, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, cl)
}

func (h *Handler) validate(ctx context.Context, in *Input, classID int64) error {
	in.Section = strings.ToUpper(strings.TrimSpace(in.Section))
	if in.Section == "" {
		return response.BadRequest("section is required")
	}
	var deptOK, ayOK, ylOK bool
	err := h.db.QueryRow(ctx, `SELECT
		EXISTS (SELECT 1 FROM departments WHERE id = $1 AND is_active),
		EXISTS (SELECT 1 FROM academic_years WHERE id = $2 AND is_active),
		EXISTS (SELECT 1 FROM year_levels WHERE id = $3 AND is_active)`,
		in.DepartmentID, in.AcademicYearID, in.YearLevelID).Scan(&deptOK, &ayOK, &ylOK)
	if err != nil {
		return err
	}
	switch {
	case !deptOK:
		return response.BadRequest("department_id does not exist")
	case !ayOK:
		return response.BadRequest("academic_year_id does not exist")
	case !ylOK:
		return response.BadRequest("year_level_id does not exist")
	}
	if in.SemesterID != nil && *in.SemesterID == 0 {
		in.SemesterID = nil
	}
	if in.SemesterID == nil {
		// Default: the odd (first) semester of the class's year of study.
		if err := h.db.QueryRow(ctx, `SELECT s.id FROM semesters s JOIN year_levels yl ON yl.id = $1
			WHERE s.sem_no = yl.level_no * 2 - 1 AND s.is_active`, in.YearLevelID).Scan(&in.SemesterID); err != nil && !dbutil.IsNoRows(err) {
			return err
		}
	} else {
		var ok bool
		if err := h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM semesters WHERE id = $1 AND year_level_id = $2 AND is_active)`,
			*in.SemesterID, in.YearLevelID).Scan(&ok); err != nil {
			return err
		}
		if !ok {
			return response.BadRequest("current_semester_id must be a semester of the class's year of study")
		}
	}
	if in.InchargeID == nil || *in.InchargeID == 0 {
		in.InchargeID = nil
		return nil
	}
	var isStaff bool
	if err := h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
		JOIN users u ON u.id = ur.user_id AND u.is_active
		WHERE ur.user_id = $1 AND ur.is_active AND r.slug IN ('staff', 'hod'))`, *in.InchargeID).Scan(&isStaff); err != nil {
		return err
	}
	if !isStaff {
		return response.BadRequest("Class incharge must be an active staff member")
	}
	// One class per incharge per academic year.
	var other *string
	err = h.db.QueryRow(ctx, `SELECT d.code || ' ' || c.section FROM classes c JOIN departments d ON d.id = c.department_id
		WHERE c.class_incharge_id = $1 AND c.academic_year_id = $2 AND c.is_active AND c.id <> $3 LIMIT 1`,
		*in.InchargeID, in.AcademicYearID, classID).Scan(&other)
	if err != nil && !dbutil.IsNoRows(err) {
		return err
	}
	if other != nil {
		return response.Conflict("This staff member is already class incharge of another class this academic year")
	}
	return nil
}

func mapErr(err error) error {
	if dbutil.UniqueViolation(err) == "ux_classes" {
		return response.Conflict("This class (department, year, section) already exists for the academic year")
	}
	return err
}

func (h *Handler) create(c *gin.Context) {
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	if err := h.validate(c, in, 0); err != nil {
		response.Error(c, err)
		return
	}
	var id int64
	err := h.db.QueryRow(c, `INSERT INTO classes (department_id, academic_year_id, year_level_id, section, class_incharge_id, current_semester_id, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id`,
		in.DepartmentID, in.AcademicYearID, in.YearLevelID, in.Section, in.InchargeID, in.SemesterID, actor.From(c).ID).Scan(&id)
	if err != nil {
		response.Error(c, mapErr(err))
		return
	}
	cl, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, cl)
}

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	if err := h.validate(c, in, id); err != nil {
		response.Error(c, err)
		return
	}
	_, err := h.db.Exec(c, `UPDATE classes SET department_id = $2, academic_year_id = $3, year_level_id = $4, section = $5,
		class_incharge_id = $6, current_semester_id = $7, updated_by = $8 WHERE id = $1`,
		id, in.DepartmentID, in.AcademicYearID, in.YearLevelID, in.Section, in.InchargeID, in.SemesterID, actor.From(c).ID)
	if err != nil {
		response.Error(c, mapErr(err))
		return
	}
	cl, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, cl)
}

func (h *Handler) delete(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	cl, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if cl.StudentCount > 0 {
		response.Error(c, response.Conflict("Class still has students; move them to another class first"))
		return
	}
	if _, err := h.db.Exec(c, `UPDATE classes SET is_active = false, updated_by = $2 WHERE id = $1`, id, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Class deleted"})
}

// ---- curriculum ----

type CurriculumRow struct {
	ID           int64   `json:"id"`
	DepartmentID int64   `json:"department_id"`
	SemesterID   int64   `json:"semester_id"`
	SemNo        int     `json:"sem_no"`
	Regulation   string  `json:"regulation"`
	SubjectID    int64   `json:"subject_id"`
	SubjectCode  string  `json:"subject_code"`
	SubjectName  string  `json:"subject_name"`
	Credits      float64 `json:"credits"`
	SubjectType  string  `json:"subject_type"`
}

// listCurriculum: ?department_id= (required) &semester_id= &regulation=
func (h *Handler) listCurriculum(c *gin.Context) {
	dept := request.QueryInt64(c, "department_id")
	if dept == nil {
		response.Error(c, response.BadRequest("department_id is required"))
		return
	}
	where := []string{"cu.is_active", "cu.department_id = $1"}
	args := []any{*dept}
	if s := request.QueryInt64(c, "semester_id"); s != nil {
		args = append(args, *s)
		where = append(where, fmt.Sprintf("cu.semester_id = $%d", len(args)))
	}
	if reg := c.Query("regulation"); reg != "" {
		args = append(args, reg)
		where = append(where, fmt.Sprintf("cu.regulation = $%d", len(args)))
	}
	rows, err := h.db.Query(c, `
		SELECT cu.id, cu.department_id, cu.semester_id, se.sem_no, cu.regulation, s.id, s.code, s.name, s.credits::float8, s.subject_type
		FROM curriculum cu JOIN subjects s ON s.id = cu.subject_id JOIN semesters se ON se.id = cu.semester_id
		WHERE `+strings.Join(where, " AND ")+` ORDER BY se.sem_no, s.code`, args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	out, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByPos[CurriculumRow])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, out)
}

type AddCurriculumInput struct {
	DepartmentID int64   `json:"department_id" binding:"required"`
	SemesterID   int64   `json:"semester_id" binding:"required"`
	Regulation   string  `json:"regulation"`
	SubjectIDs   []int64 `json:"subject_ids" binding:"required,min=1"`
}

// addCurriculum attaches subjects to a department semester; already-attached ones are skipped.
func (h *Handler) addCurriculum(c *gin.Context) {
	in, ok := request.Bind[AddCurriculumInput](c)
	if !ok {
		return
	}
	in.Regulation = strings.ToUpper(strings.TrimSpace(in.Regulation))
	if in.Regulation == "" {
		in.Regulation = "R2021"
	}
	var deptOK, semOK bool
	var subjCount int
	if err := h.db.QueryRow(c, `SELECT
		EXISTS (SELECT 1 FROM departments WHERE id = $1 AND is_active),
		EXISTS (SELECT 1 FROM semesters WHERE id = $2 AND is_active),
		(SELECT count(DISTINCT id) FROM subjects WHERE id = ANY($3) AND is_active)::int`,
		in.DepartmentID, in.SemesterID, in.SubjectIDs).Scan(&deptOK, &semOK, &subjCount); err != nil {
		response.Error(c, err)
		return
	}
	if !deptOK || !semOK {
		response.Error(c, response.BadRequest("department_id or semester_id does not exist"))
		return
	}
	if subjCount != len(uniq(in.SubjectIDs)) {
		response.Error(c, response.BadRequest("One or more subject_ids are invalid"))
		return
	}
	tag, err := h.db.Exec(c, `
		INSERT INTO curriculum (department_id, semester_id, subject_id, regulation, created_by, updated_by)
		SELECT $1::bigint, $2::bigint, s, $3::varchar, $5::bigint, $5::bigint FROM unnest($4::bigint[]) AS s
		WHERE NOT EXISTS (SELECT 1 FROM curriculum cu WHERE cu.department_id = $1 AND cu.semester_id = $2
		                  AND cu.subject_id = s AND cu.regulation = $3::varchar AND cu.is_active)`,
		in.DepartmentID, in.SemesterID, in.Regulation, uniq(in.SubjectIDs), actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, gin.H{"added": tag.RowsAffected()})
}

func (h *Handler) removeCurriculum(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	tag, err := h.db.Exec(c, `UPDATE curriculum SET is_active = false, updated_by = $2 WHERE id = $1 AND is_active`, id, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if tag.RowsAffected() == 0 {
		response.Error(c, response.NotFound("Curriculum entry not found"))
		return
	}
	response.OK(c, gin.H{"message": "Subject removed from curriculum"})
}

func uniq(ids []int64) []int64 {
	seen := map[int64]bool{}
	out := []int64{}
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}
