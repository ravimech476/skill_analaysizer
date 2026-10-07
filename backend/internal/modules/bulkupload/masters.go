package bulkupload

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/upload"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// ==================== Departments ====================

var departmentColumns = []column{
	{"code*", "Unique department code (uppercased automatically)", "CSE"},
	{"name*", "Department name", "Computer Science and Engineering"},
	{"hod_employee_code", "Employee code of the Head of Department (optional)", "EMP101"},
}

func (h *Handler) departmentsTemplate(c *gin.Context) {
	writeTemplate(c, "departments_upload_template.xlsx", "Departments", departmentColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Staff", nil, []string{"employee_code", "Name"}, h.lookup(c,
			`SELECT sp.employee_code, u.name FROM staff_profiles sp
			 JOIN users u ON u.id = sp.user_id AND u.is_active
			 WHERE sp.is_active ORDER BY sp.employee_code`))
	})
}

func (h *Handler) uploadDepartments(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "departments", required(departmentColumns), dryRun, func(t *upload.Table) importResult {
		return h.importDepartments(c, a, t, dryRun)
	})
}

func (h *Handler) importDepartments(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	// Pre-load staff employee_code -> user_id for HOD lookup.
	staffByCode := h.codeMap(ctx, `SELECT upper(sp.employee_code), sp.user_id FROM staff_profiles sp WHERE sp.is_active`)

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code := strings.ToUpper(strings.TrimSpace(t.Get(r, "code")))
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: name, Message: msg})
		}

		if code == "" {
			fail("code is required")
			continue
		}
		if name == "" {
			fail("name is required")
			continue
		}

		// Resolve optional HOD.
		var hodID *int64
		if hodCode := strings.ToUpper(strings.TrimSpace(t.Get(r, "hod_employee_code"))); hodCode != "" {
			uid, ok := staffByCode[hodCode]
			if !ok {
				fail(fmt.Sprintf("Unknown hod_employee_code %q (not found in staff profiles)", hodCode))
				continue
			}
			hodID = &uid
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM departments WHERE upper(code) = $1 AND is_active`, code).Scan(&existingID)
			if err == nil {
				// Already exists -> update.
				_, err = tx.Exec(ctx,
					`UPDATE departments SET name = $1, hod_id = $2, updated_by = $3, updated_at = now() WHERE id = $4`,
					name, hodID, a.ID, existingID)
				return err
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			// Insert new department.
			_, err = tx.Exec(ctx,
				`INSERT INTO departments (code, name, hod_id, created_by, updated_by) VALUES ($1, $2, $3, $4, $4)`,
				code, name, hodID, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Subjects ====================

var subjectColumns = []column{
	{"code*", "Unique subject code (uppercased automatically)", "CS3401"},
	{"name*", "Subject name", "Database Management Systems"},
	{"credits", "Credits (default 0)", "4"},
	{"subject_type", "theory / lab / elective / project (default theory)", "theory"},
}

var validSubjectTypes = map[string]bool{
	"theory": true, "lab": true, "elective": true, "project": true,
}

func (h *Handler) subjectsTemplate(c *gin.Context) {
	writeTemplate(c, "subjects_upload_template.xlsx", "Subjects", subjectColumns, nil, nil)
}

func (h *Handler) uploadSubjects(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "subjects", required(subjectColumns), dryRun, func(t *upload.Table) importResult {
		return h.importSubjects(c, a, t, dryRun)
	})
}

func (h *Handler) importSubjects(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code := strings.ToUpper(strings.TrimSpace(t.Get(r, "code")))
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: name, Message: msg})
		}

		if code == "" {
			fail("code is required")
			continue
		}
		if name == "" {
			fail("name is required")
			continue
		}

		// Parse credits (default 0).
		var credits float64
		if raw := strings.TrimSpace(t.Get(r, "credits")); raw != "" {
			var err error
			credits, err = strconv.ParseFloat(raw, 64)
			if err != nil || credits < 0 {
				fail("credits must be a non-negative number")
				continue
			}
		}

		// Validate subject_type (default "theory").
		subjectType := strings.ToLower(strings.TrimSpace(t.Get(r, "subject_type")))
		if subjectType == "" {
			subjectType = "theory"
		}
		if !validSubjectTypes[subjectType] {
			fail(fmt.Sprintf("subject_type must be one of: theory, lab, elective, project; got %q", subjectType))
			continue
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM subjects WHERE upper(code) = $1 AND is_active`, code).Scan(&existingID)
			if err == nil {
				return fmt.Errorf("subject with code %q already exists, skipping", code)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			_, err = tx.Exec(ctx,
				`INSERT INTO subjects (code, name, credits, subject_type, created_by, updated_by) VALUES ($1, $2, $3, $4, $5, $5)`,
				code, name, credits, subjectType, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Companies ====================

var companyColumns = []column{
	{"name*", "Company name", "Infosys Limited"},
	{"industry", "Industry or sector", "IT Services"},
	{"location", "City or location", "Chennai"},
	{"website", "Website URL", "https://www.infosys.com"},
	{"contact_person", "Contact person name", "Ravi Kumar"},
	{"contact_email", "Contact email", "ravi@infosys.com"},
	{"contact_mobile", "Contact mobile", "9000000301"},
	{"description", "Short description", "Global IT services company"},
}

func (h *Handler) companiesTemplate(c *gin.Context) {
	writeTemplate(c, "companies_upload_template.xlsx", "Companies", companyColumns, nil, nil)
}

func (h *Handler) uploadCompanies(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "companies", required(companyColumns), dryRun, func(t *upload.Table) importResult {
		return h.importCompanies(c, a, t, dryRun)
	})
}

func (h *Handler) importCompanies(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: "", Name: name, Message: msg})
		}

		if name == "" {
			fail("name is required")
			continue
		}

		industry := opt(strings.TrimSpace(t.Get(r, "industry")))
		location := opt(strings.TrimSpace(t.Get(r, "location")))
		website := opt(strings.TrimSpace(t.Get(r, "website")))
		contactPerson := opt(strings.TrimSpace(t.Get(r, "contact_person")))
		contactEmail := opt(strings.TrimSpace(t.Get(r, "contact_email")))
		contactMobile := opt(strings.TrimSpace(t.Get(r, "contact_mobile")))
		description := opt(strings.TrimSpace(t.Get(r, "description")))

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM companies WHERE lower(name) = lower($1) AND is_active`, name).Scan(&existingID)
			if err == nil {
				return fmt.Errorf("company %q already exists, skipping", name)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			_, err = tx.Exec(ctx,
				`INSERT INTO companies (name, industry, website, location, contact_person, contact_email, contact_mobile, description, created_by, updated_by)
				 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)`,
				name, industry, website, location, contactPerson, contactEmail, contactMobile, description, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Exam Types ====================

var examTypeColumns = []column{
	{"code*", "Exam type code (uppercased automatically)", "CAT1"},
	{"name*", "Exam type name", "Continuous Assessment Test 1"},
	{"max_marks*", "Maximum marks (must be > 0)", "50"},
	{"pass_percent", "Pass percentage 0-100 (default 50)", "50"},
	{"is_final", "true / false (default false)", "false"},
	{"sort_order", "Display order (default 0)", "1"},
}

func (h *Handler) examTypesTemplate(c *gin.Context) {
	writeTemplate(c, "exam_types_upload_template.xlsx", "ExamTypes", examTypeColumns, nil, nil)
}

func (h *Handler) uploadExamTypes(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "exam_types", required(examTypeColumns), dryRun, func(t *upload.Table) importResult {
		return h.importExamTypes(c, a, t, dryRun)
	})
}

func (h *Handler) importExamTypes(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code := strings.ToUpper(strings.TrimSpace(t.Get(r, "code")))
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: name, Message: msg})
		}

		if code == "" {
			fail("code is required")
			continue
		}
		if name == "" {
			fail("name is required")
			continue
		}

		// Parse max_marks (required, > 0).
		maxMarksRaw := strings.TrimSpace(t.Get(r, "max_marks"))
		if maxMarksRaw == "" {
			fail("max_marks is required")
			continue
		}
		maxMarks, err := strconv.ParseFloat(maxMarksRaw, 64)
		if err != nil || maxMarks <= 0 {
			fail("max_marks must be a number greater than 0")
			continue
		}

		// Parse pass_percent (default 50, range 0-100).
		passPercent := 50.0
		if raw := strings.TrimSpace(t.Get(r, "pass_percent")); raw != "" {
			passPercent, err = strconv.ParseFloat(raw, 64)
			if err != nil || passPercent < 0 || passPercent > 100 {
				fail("pass_percent must be a number between 0 and 100")
				continue
			}
		}

		// Parse is_final (default false).
		isFinal := false
		if raw := strings.ToLower(strings.TrimSpace(t.Get(r, "is_final"))); raw != "" {
			if raw == "true" || raw == "yes" || raw == "1" {
				isFinal = true
			} else if raw != "false" && raw != "no" && raw != "0" {
				fail("is_final must be true or false")
				continue
			}
		}

		// Parse sort_order (default 0).
		sortOrder := 0
		if raw := strings.TrimSpace(t.Get(r, "sort_order")); raw != "" {
			sortOrder, err = strconv.Atoi(raw)
			if err != nil {
				fail("sort_order must be a whole number")
				continue
			}
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM exam_types WHERE upper(code) = $1 AND is_active`, code).Scan(&existingID)
			if err == nil {
				return fmt.Errorf("exam type with code %q already exists, skipping", code)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			_, err = tx.Exec(ctx,
				`INSERT INTO exam_types (code, name, max_marks, pass_percent, is_final, sort_order, created_by, updated_by)
				 VALUES ($1, $2, $3, $4, $5, $6, $7, $7)`,
				code, name, maxMarks, passPercent, isFinal, sortOrder, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Skill Master ====================

var skillMasterColumns = []column{
	{"name*", "Skill name (must be unique, case-insensitive)", "Python"},
	{"category", "programming / framework / database / tool / technical / soft_skill / domain (default technical)", "programming"},
}

var validSkillCategories = map[string]bool{
	"programming": true, "framework": true, "database": true, "tool": true,
	"technical": true, "soft_skill": true, "domain": true,
}

func (h *Handler) skillMasterTemplate(c *gin.Context) {
	writeTemplate(c, "skill_master_upload_template.xlsx", "Skills", skillMasterColumns, nil, nil)
}

func (h *Handler) uploadSkillMaster(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "skill_master", required(skillMasterColumns), dryRun, func(t *upload.Table) importResult {
		return h.importSkillMaster(c, a, t, dryRun)
	})
}

func (h *Handler) importSkillMaster(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: "", Name: name, Message: msg})
		}

		if name == "" {
			fail("name is required")
			continue
		}

		// Validate category (default "technical").
		category := strings.ToLower(strings.TrimSpace(t.Get(r, "category")))
		if category == "" {
			category = "technical"
		}
		if !validSkillCategories[category] {
			fail(fmt.Sprintf("category must be one of: programming, framework, database, tool, technical, soft_skill, domain; got %q", category))
			continue
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM skills WHERE lower(name) = lower($1) AND is_active`, name).Scan(&existingID)
			if err == nil {
				return fmt.Errorf("skill %q already exists, skipping", name)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			_, err = tx.Exec(ctx,
				`INSERT INTO skills (name, category, created_by, updated_by) VALUES ($1, $2, $3, $3)`,
				name, category, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Academic Years ====================

var academicYearColumns = []column{
	{"name*", "Academic year name, e.g. 2026-27", "2026-27"},
	{"start_date*", "Start date (YYYY-MM-DD)", "2026-06-01"},
	{"end_date*", "End date (YYYY-MM-DD)", "2027-05-31"},
	{"is_current", "true / false (default false). If true, other current years are unmarked.", "false"},
}

func (h *Handler) academicYearsTemplate(c *gin.Context) {
	writeTemplate(c, "academic_years_upload_template.xlsx", "AcademicYears", academicYearColumns, nil, nil)
}

func (h *Handler) uploadAcademicYears(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "academic_years", required(academicYearColumns), dryRun, func(t *upload.Table) importResult {
		return h.importAcademicYears(c, a, t, dryRun)
	})
}

func (h *Handler) importAcademicYears(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		name := strings.TrimSpace(t.Get(r, "name"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: "", Name: name, Message: msg})
		}

		if name == "" {
			fail("name is required")
			continue
		}

		// Parse start_date (required).
		startDateStr, err := upload.ExcelDate(strings.TrimSpace(t.Get(r, "start_date")), "start_date")
		if err != nil {
			fail(err.Error())
			continue
		}
		if startDateStr == nil {
			fail("start_date is required")
			continue
		}

		// Parse end_date (required).
		endDateStr, err := upload.ExcelDate(strings.TrimSpace(t.Get(r, "end_date")), "end_date")
		if err != nil {
			fail(err.Error())
			continue
		}
		if endDateStr == nil {
			fail("end_date is required")
			continue
		}

		// Validate end_date > start_date.
		startDate, _ := time.Parse("2006-01-02", *startDateStr)
		endDate, _ := time.Parse("2006-01-02", *endDateStr)
		if !endDate.After(startDate) {
			fail("end_date must be after start_date")
			continue
		}

		// Parse is_current (default false).
		isCurrent := false
		if raw := strings.ToLower(strings.TrimSpace(t.Get(r, "is_current"))); raw != "" {
			if raw == "true" || raw == "yes" || raw == "1" {
				isCurrent = true
			} else if raw != "false" && raw != "no" && raw != "0" {
				fail("is_current must be true or false")
				continue
			}
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var existingID int64
			err := tx.QueryRow(ctx, `SELECT id FROM academic_years WHERE lower(name) = lower($1) AND is_active`, name).Scan(&existingID)
			if err == nil {
				return fmt.Errorf("academic year %q already exists, skipping", name)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			// If is_current, unmark any other current year.
			if isCurrent {
				_, err = tx.Exec(ctx, `UPDATE academic_years SET is_current = false, updated_by = $1, updated_at = now() WHERE is_current AND is_active`, a.ID)
				if err != nil {
					return err
				}
			}
			_, err = tx.Exec(ctx,
				`INSERT INTO academic_years (name, start_date, end_date, is_current, created_by, updated_by)
				 VALUES ($1, $2, $3, $4, $5, $5)`,
				name, *startDateStr, *endDateStr, isCurrent, a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Placement Drives ====================

var placementDriveColumns = []column{
	{"company_name*", "Company name (must match an existing company, case-insensitive)", "Infosys Limited"},
	{"title*", "Job role title", "Software Developer"},
	{"package_lpa*", "Package in LPA (must be > 0)", "6.5"},
	{"drive_date", "Drive date (YYYY-MM-DD or DD-MM-YYYY)", "2026-03-15"},
	{"last_apply_date", "Last date to apply (YYYY-MM-DD or DD-MM-YYYY)", "2026-03-10"},
	{"min_cgpa", "Minimum CGPA required (default 0)", "7.0"},
	{"max_backlogs", "Maximum allowed backlogs (default 0)", "0"},
	{"eligible_batch", "Eligible batch, e.g. 2023-2027", "2023-2027"},
	{"openings", "Number of positions", "10"},
	{"status", "upcoming / open / closed / completed (default upcoming)", "upcoming"},
	{"skills", "Comma-separated skill:level pairs, e.g. Programming:3,SQL:2,Communication:3", "Programming:3,SQL:2"},
}

var validDriveStatuses = map[string]bool{
	"upcoming": true, "open": true, "closed": true, "completed": true,
}

func (h *Handler) placementDrivesTemplate(c *gin.Context) {
	writeTemplate(c, "placement_drives_upload_template.xlsx", "PlacementDrives", placementDriveColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Companies", nil, []string{"company_name"}, h.lookup(c,
			`SELECT name, name FROM companies WHERE is_active ORDER BY name`))
		b.Sheet("Skills", nil, []string{"skill_name"}, h.lookup(c,
			`SELECT name, name FROM skills WHERE is_active ORDER BY name`))
	})
}

func (h *Handler) uploadPlacementDrives(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "placement_drives", required(placementDriveColumns), dryRun, func(t *upload.Table) importResult {
		return h.importPlacementDrives(c, a, t, dryRun)
	})
}

func (h *Handler) importPlacementDrives(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}

	// Pre-load company name (lower) -> id.
	companyByName := h.codeMap(ctx, `SELECT lower(name), id FROM companies WHERE is_active`)

	// Pre-load skill name (lower) -> id.
	skillByName := h.codeMap(ctx, `SELECT lower(name), id FROM skills WHERE is_active`)

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		companyName := strings.TrimSpace(t.Get(r, "company_name"))
		title := strings.TrimSpace(t.Get(r, "title"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: "", Name: title, Message: msg})
		}

		if companyName == "" {
			fail("company_name is required")
			continue
		}
		if title == "" {
			fail("title is required")
			continue
		}

		// Look up company by name (case-insensitive).
		companyID, ok := companyByName[strings.ToLower(companyName)]
		if !ok {
			fail(fmt.Sprintf("Unknown company %q (not found in companies list)", companyName))
			continue
		}

		// Parse package_lpa (required, > 0).
		packageRaw := strings.TrimSpace(t.Get(r, "package_lpa"))
		if packageRaw == "" {
			fail("package_lpa is required")
			continue
		}
		packageLPA, err := strconv.ParseFloat(packageRaw, 64)
		if err != nil || packageLPA <= 0 {
			fail("package_lpa must be a number greater than 0")
			continue
		}

		// Parse drive_date (optional).
		driveDateStr, err := upload.ExcelDate(strings.TrimSpace(t.Get(r, "drive_date")), "drive_date")
		if err != nil {
			fail(err.Error())
			continue
		}

		// Parse last_apply_date (optional).
		lastApplyStr, err := upload.ExcelDate(strings.TrimSpace(t.Get(r, "last_apply_date")), "last_apply_date")
		if err != nil {
			fail(err.Error())
			continue
		}

		// Validate last_apply_date <= drive_date when both are given.
		if driveDateStr != nil && lastApplyStr != nil {
			driveDate, _ := time.Parse("2006-01-02", *driveDateStr)
			lastApply, _ := time.Parse("2006-01-02", *lastApplyStr)
			if lastApply.After(driveDate) {
				fail("last_apply_date must be on or before drive_date")
				continue
			}
		}

		// Parse min_cgpa (default 0).
		var minCGPA float64
		if raw := strings.TrimSpace(t.Get(r, "min_cgpa")); raw != "" {
			minCGPA, err = strconv.ParseFloat(raw, 64)
			if err != nil || minCGPA < 0 || minCGPA > 10 {
				fail("min_cgpa must be a number between 0 and 10")
				continue
			}
		}

		// Parse max_backlogs (default 0).
		maxBacklogs := 0
		if raw := strings.TrimSpace(t.Get(r, "max_backlogs")); raw != "" {
			maxBacklogs, err = strconv.Atoi(raw)
			if err != nil || maxBacklogs < 0 {
				fail("max_backlogs must be a non-negative whole number")
				continue
			}
		}

		// Parse eligible_batch.
		var eligibleBatch *string
		if raw := strings.TrimSpace(t.Get(r, "eligible_batch")); raw != "" {
			eligibleBatch = &raw
		}

		// Parse openings.
		var openings *int
		if raw := strings.TrimSpace(t.Get(r, "openings")); raw != "" {
			v, err := strconv.Atoi(raw)
			if err != nil || v < 1 {
				fail("openings must be a positive whole number")
				continue
			}
			openings = &v
		}

		// Validate status (default "upcoming").
		status := strings.ToLower(strings.TrimSpace(t.Get(r, "status")))
		if status == "" {
			status = "upcoming"
		}
		if !validDriveStatuses[status] {
			fail(fmt.Sprintf("status must be one of: upcoming, open, closed, completed; got %q", status))
			continue
		}

		// Parse skills column: comma-separated "skill_name:level" pairs.
		type skillReq struct {
			skillID int64
			level   int
		}
		var skillReqs []skillReq
		if raw := strings.TrimSpace(t.Get(r, "skills")); raw != "" {
			parts := strings.Split(raw, ",")
			seen := map[int64]bool{}
			parseErr := false
			for _, p := range parts {
				p = strings.TrimSpace(p)
				if p == "" {
					continue
				}
				colonIdx := strings.LastIndex(p, ":")
				if colonIdx < 0 {
					fail(fmt.Sprintf("skill entry %q must be in the format skill_name:level", p))
					parseErr = true
					break
				}
				sName := strings.TrimSpace(p[:colonIdx])
				sLevelStr := strings.TrimSpace(p[colonIdx+1:])
				if sName == "" {
					fail(fmt.Sprintf("skill entry %q has an empty skill name", p))
					parseErr = true
					break
				}
				sLevel, err := strconv.Atoi(sLevelStr)
				if err != nil || sLevel < 1 || sLevel > 5 {
					fail(fmt.Sprintf("skill %q level must be 1-5; got %q", sName, sLevelStr))
					parseErr = true
					break
				}
				sid, ok := skillByName[strings.ToLower(sName)]
				if !ok {
					fail(fmt.Sprintf("Unknown skill %q (not found in skills list)", sName))
					parseErr = true
					break
				}
				if seen[sid] {
					fail(fmt.Sprintf("skill %q is listed more than once", sName))
					parseErr = true
					break
				}
				seen[sid] = true
				skillReqs = append(skillReqs, skillReq{skillID: sid, level: sLevel})
			}
			if parseErr {
				continue
			}
		}

		// Truncate package_lpa to two decimal places to match numeric(6,2).
		packageLPA = math.Round(packageLPA*100) / 100

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var roleID int64
			if err := tx.QueryRow(ctx,
				`INSERT INTO company_job_roles (company_id, title, package_lpa, drive_date, last_apply_date,
				 min_cgpa, max_backlogs, eligible_batch, openings, status, created_by, updated_by)
				 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11) RETURNING id`,
				companyID, title, packageLPA, driveDateStr, lastApplyStr,
				minCGPA, maxBacklogs, eligibleBatch, openings, status, a.ID).Scan(&roleID); err != nil {
				return err
			}
			for _, s := range skillReqs {
				if _, err := tx.Exec(ctx,
					`INSERT INTO job_role_skills (job_role_id, skill_id, required_level, is_mandatory, weight, created_by, updated_by)
					 VALUES ($1, $2, $3, true, 1, $4, $4)`,
					roleID, s.skillID, s.level, a.ID); err != nil {
					return err
				}
			}
			return nil
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}
