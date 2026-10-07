// Package bulkupload imports students (with their parents), staff and student skill levels
// from Excel sheets. Each row is saved in its own transaction, so one bad row never blocks
// the rest; dry_run validates every row and rolls everything back.
package bulkupload

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/staff"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/pkg/upload"
	"skills-analyzer/internal/pkg/xlsxutil"
	"skills-analyzer/internal/rbac"
)

// Column spec: header → description. Headers are matched case-insensitively; "*" marks required.
var columns = []column{
	{"register_no*", "Unique register number. Also becomes the login username.", "21CS001"},
	{"name*", "Student full name", "Arun Kumar"},
	{"department_code*", "Department code, see the Departments sheet", "CSE"},
	{"admission_year*", "Year of admission, e.g. 2023", "2023"},
	{"year*", "Current year of study: 1, 2, 3 or 4", "2"},
	{"section", "Class section (default A)", "A"},
	{"batch", "e.g. 2023-2027 (default: admission_year to admission_year+4)", "2023-2027"},
	{"gender", "male / female / other", "male"},
	{"dob", "Date of birth (YYYY-MM-DD or DD-MM-YYYY)", "2005-06-15"},
	{"mobile", "Student mobile (10 digits)", "9000000101"},
	{"email", "Student email", "arun@example.com"},
	{"blood_group", "e.g. O+", "O+"},
	{"address", "Address", "Chennai"},
	{"parent_name", "Parent / guardian name", "Kumar R"},
	{"parent_mobile", "Parent mobile (10 digits). Existing parent accounts with this mobile are reused (siblings).", "9000000201"},
	{"parent_relation", "father / mother / guardian", "father"},
	{"parent_email", "Parent email", ""},
}

type column struct{ Header, Help, Sample string }

func required(cols []column) []string {
	out := []string{}
	for _, c := range cols {
		if strings.HasSuffix(c.Header, "*") {
			out = append(out, c.Header)
		}
	}
	return out
}

type (
	RowError = upload.RowError
	Job      = upload.Job
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	staff    *staff.Importer
	notify   *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, students: students, staff: staff.NewImporter(db), notify: n}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }
	g := r.Group("/bulk-upload")
	g.GET("/students/template", can("bulk_upload.create"), h.template)
	g.POST("/students", can("bulk_upload.create"), h.uploadStudents)
	g.GET("/staff/template", can("staff.create"), h.staffTemplate)
	g.POST("/staff", can("staff.create"), h.uploadStaff)
	g.GET("/skills/template", can("student_skill.create"), h.skillsTemplate)
	g.POST("/skills", can("student_skill.create"), h.uploadSkills)
	g.GET("/departments/template", can("department.create"), h.departmentsTemplate)
	g.POST("/departments", can("department.create"), h.uploadDepartments)
	g.GET("/subjects/template", can("subject.create"), h.subjectsTemplate)
	g.POST("/subjects", can("subject.create"), h.uploadSubjects)
	g.GET("/companies/template", can("company.create"), h.companiesTemplate)
	g.POST("/companies", can("company.create"), h.uploadCompanies)
	g.GET("/exam-types/template", can("exam_type.create"), h.examTypesTemplate)
	g.POST("/exam-types", can("exam_type.create"), h.uploadExamTypes)
	g.GET("/academic-years/template", can("academic_year.create"), h.academicYearsTemplate)
	g.POST("/academic-years", can("academic_year.create"), h.uploadAcademicYears)
	g.GET("/skill-master/template", can("skill.create"), h.skillMasterTemplate)
	g.POST("/skill-master", can("skill.create"), h.uploadSkillMaster)
	g.GET("/placement-drives/template", can("job_role.create"), h.placementDrivesTemplate)
	g.POST("/placement-drives", can("job_role.create"), h.uploadPlacementDrives)
	g.GET("/jobs", can("bulk_upload.view"), h.listJobs)
	g.GET("/jobs/:id", can("bulk_upload.view", "staff.create", "student_skill.create", "marks.create", "department.create", "subject.create", "company.create", "exam_type.create", "academic_year.create", "skill.create", "job_role.create"), h.getJob)
	g.GET("/jobs/:id/errors.xlsx", can("bulk_upload.view", "staff.create", "student_skill.create", "marks.create", "department.create", "subject.create", "company.create", "exam_type.create", "academic_year.create", "skill.create", "job_role.create"), h.errorReport)
}

// writeTemplate builds a data sheet (header + sample or prefilled rows) and an Instructions sheet.
func writeTemplate(c *gin.Context, filename, sheet string, cols []column, rows [][]any, extra func(b *xlsxutil.Book)) {
	b := xlsxutil.New()
	headers := make([]string, len(cols))
	for i, col := range cols {
		headers[i] = col.Header
	}
	if rows == nil {
		sample := make([]any, len(cols))
		for i, col := range cols {
			sample[i] = col.Sample
		}
		rows = [][]any{sample}
	}
	b.Sheet(sheet, nil, headers, rows)
	help := make([][]any, len(cols))
	for i, col := range cols {
		help[i] = []any{col.Header, col.Help}
	}
	b.Sheet("Instructions", nil, []string{"Column", "What to enter (* = required)"}, help)
	if extra != nil {
		extra(b)
	}
	b.Send(c, filename)
}

// ---- template ----

func (h *Handler) template(c *gin.Context) {
	writeTemplate(c, "student_upload_template.xlsx", "Students", columns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Departments", nil, []string{"department_code", "Department"}, h.lookup(c, `SELECT code, name FROM departments WHERE is_active ORDER BY code`))
	})
}

// lookup runs a two-column query for the reference sheets in templates.
func (h *Handler) lookup(ctx context.Context, q string, args ...any) [][]any {
	out := [][]any{}
	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var a, b string
		if rows.Scan(&a, &b) == nil {
			out = append(out, []any{a, b})
		}
	}
	return out
}

// ---- upload ----

func (h *Handler) uploadStudents(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	createClasses := c.PostForm("create_missing_classes") == "true"
	hash, err := defaultPassword(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.run(c, "students", required(columns), dryRun, func(t *upload.Table) importResult {
		return h.importStudents(c, a, t, hash, createClasses, dryRun)
	})
}

// defaultPassword hashes the optional default_password form field once, shared by every row.
func defaultPassword(c *gin.Context) (*string, error) {
	p := strings.TrimSpace(c.PostForm("default_password"))
	if p == "" {
		return nil, nil
	}
	if len(p) < 8 {
		return nil, response.BadRequest("default_password must be at least 8 characters")
	}
	hs, err := security.HashPassword(p)
	return &hs, err
}

// run reads the posted file, records the job and stores the import outcome.
func (h *Handler) run(c *gin.Context, uploadType string, requiredCols []string, dryRun bool, do func(t *upload.Table) importResult) {
	a := actor.From(c)
	name, data, err := upload.File(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	t, err := upload.Parse(data, requiredCols)
	if err != nil {
		response.Error(c, err)
		return
	}
	jobID, err := upload.Start(c, h.db, uploadType, name, len(t.Data), dryRun, a.ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	res := do(t)
	job, err := upload.Finish(c, h.db, jobID, res.success, res.errors, a.ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, job)
}

type importResult struct {
	success int
	errors  []RowError
}

type classKey struct {
	dept    int64
	level   int
	section string
}

func (h *Handler) importStudents(ctx context.Context, a actor.Actor, rows *upload.Table, hash *string, createClasses, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	fail := func(rowNo int, reg, name, msg string) {
		res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: reg, Name: name, Message: msg})
	}

	depts := map[string]int64{}
	if dr, err := h.db.Query(ctx, `SELECT code, id FROM departments WHERE is_active`); err == nil {
		for dr.Next() {
			var code string
			var id int64
			if dr.Scan(&code, &id) == nil {
				depts[strings.ToUpper(code)] = id
			}
		}
		dr.Close()
	}
	levels := map[int]int64{}
	if lr, err := h.db.Query(ctx, `SELECT level_no, id FROM year_levels WHERE is_active`); err == nil {
		for lr.Next() {
			var no int
			var id int64
			if lr.Scan(&no, &id) == nil {
				levels[no] = id
			}
		}
		lr.Close()
	}
	var currentYear *int64
	_ = h.db.QueryRow(ctx, `SELECT id FROM academic_years WHERE is_current AND is_active`).Scan(&currentYear)

	for i, r := range rows.Data {
		rowNo := rows.First + i
		if upload.IsBlank(r) {
			continue
		}
		reg, name := rows.Get(r, "register_no"), rows.Get(r, "name")

		deptCode := strings.ToUpper(rows.Get(r, "department_code"))
		deptID, ok := depts[deptCode]
		if !ok {
			fail(rowNo, reg, name, fmt.Sprintf("Unknown department_code %q", deptCode))
			continue
		}
		admission, err := strconv.Atoi(rows.Get(r, "admission_year"))
		if err != nil {
			fail(rowNo, reg, name, "admission_year must be a year like 2023")
			continue
		}
		level, err := strconv.Atoi(rows.Get(r, "year"))
		levelID, okLevel := levels[level]
		if err != nil || !okLevel {
			fail(rowNo, reg, name, "year must be 1, 2, 3 or 4")
			continue
		}
		if currentYear == nil {
			fail(rowNo, reg, name, "No current academic year is set; set one under Academic Setup first")
			continue
		}
		section := strings.ToUpper(rows.Get(r, "section"))
		if section == "" {
			section = "A"
		}
		dob, err := upload.ExcelDate(rows.Get(r, "dob"), "dob")
		if err != nil {
			fail(rowNo, reg, name, err.Error())
			continue
		}

		in := student.Input{
			Name:          name,
			RegisterNo:    reg,
			DepartmentID:  deptID,
			AdmissionYear: admission,
			Batch:         rows.Get(r, "batch"),
			Mobile:        opt(rows.Get(r, "mobile")),
			Email:         opt(rows.Get(r, "email")),
			Gender:        opt(strings.ToLower(rows.Get(r, "gender"))),
			DOB:           dob,
			BloodGroup:    opt(strings.ToUpper(rows.Get(r, "blood_group"))),
			Address:       opt(rows.Get(r, "address")),
		}
		if in.Gender != nil && *in.Gender != "male" && *in.Gender != "female" && *in.Gender != "other" {
			fail(rowNo, reg, name, "gender must be male, female or other")
			continue
		}
		if pn, pm := rows.Get(r, "parent_name"), rows.Get(r, "parent_mobile"); pn != "" || pm != "" {
			in.Parents = []student.ParentInput{{
				Name: pn, Mobile: pm, Email: opt(rows.Get(r, "parent_email")),
				Relation: rows.Get(r, "parent_relation"), IsPrimary: true,
			}}
		}

		err = h.importRow(ctx, a.ID, in, hash, classKey{deptID, level, section}, levelID, *currentYear, createClasses, dryRun)
		if err != nil {
			fail(rowNo, reg, name, upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

var errDryRun = errors.New("dry run")

func (h *Handler) importRow(ctx context.Context, actorID int64, in student.Input, hash *string, key classKey, levelID, yearID int64, createClasses, dryRun bool) error {
	err := pgx.BeginFunc(ctx, h.db, func(tx pgx.Tx) error {
		var classID int64
		err := tx.QueryRow(ctx, `SELECT id FROM classes WHERE department_id = $1 AND academic_year_id = $2 AND year_level_id = $3
			AND section = $4 AND is_active`, key.dept, yearID, levelID, key.section).Scan(&classID)
		if dbutil.IsNoRows(err) {
			if !createClasses {
				return response.BadRequest(fmt.Sprintf("Class (year %d, section %s) does not exist for the current academic year; create it or tick 'create missing classes'", key.level, key.section))
			}
			err = tx.QueryRow(ctx, `INSERT INTO classes (department_id, academic_year_id, year_level_id, section, current_semester_id, created_by, updated_by)
				VALUES ($1, $2, $3, $4, (SELECT id FROM semesters WHERE sem_no = $6 * 2 - 1 AND is_active), $5, $5) RETURNING id`,
				key.dept, yearID, levelID, key.section, actorID, key.level).Scan(&classID)
		}
		if err != nil {
			return err
		}
		in.ClassID = &classID
		if _, err := h.students.CreateInTx(ctx, tx, actorID, in, hash); err != nil {
			return err
		}
		if dryRun {
			return errDryRun // roll back, but the row validated fine
		}
		return nil
	})
	if errors.Is(err, errDryRun) {
		return nil
	}
	return err
}

func opt(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// ---- jobs ----

func (h *Handler) listJobs(c *gin.Context) {
	p := pagination.FromQuery(c)
	kind := c.Query("upload_type")
	var total int64
	if err := h.db.QueryRow(c, `SELECT count(*) FROM bulk_upload_jobs WHERE is_active AND ($1 = '' OR upload_type = $1)`, kind).Scan(&total); err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, upload.SelectJob+" WHERE j.is_active AND ($3 = '' OR j.upload_type = $3) ORDER BY j.created_at DESC LIMIT $1 OFFSET $2", p.PageSize, p.Offset(), kind)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*Job{}
	for rows.Next() {
		j, err := upload.ScanJob(rows)
		if err != nil {
			response.Error(c, err)
			return
		}
		j.Errors = nil // list view: counts only
		out = append(out, j)
	}
	response.List(c, out, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}

func (h *Handler) getJob(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	j, err := upload.Find(c, h.db, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, j)
}

// errorReport downloads the failed rows as an Excel sheet.
func (h *Handler) errorReport(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	j, err := upload.Find(c, h.db, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	rows := make([][]any, len(j.Errors))
	for i, e := range j.Errors {
		rows[i] = []any{e.Row, e.RegisterNo, e.Name, e.Message}
	}
	b := xlsxutil.New()
	b.Sheet("Errors", []string{fmt.Sprintf("%s upload #%d: %s", j.UploadType, j.ID, j.FileName)}, []string{"Row", "Code", "Name", "Error"}, rows)
	b.Send(c, fmt.Sprintf("upload_%d_errors.xlsx", id))
}
