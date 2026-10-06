package bulkupload

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/modules/staff"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/upload"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// ---- staff ----

var staffColumns = []column{
	{"employee_code*", "Unique employee code. Also becomes the login username.", "EMP101"},
	{"name*", "Full name", "Lakshmi N"},
	{"department_code", "Department code, see the Departments sheet (blank for non-departmental staff)", "CSE"},
	{"designation", "e.g. Assistant Professor", "Assistant Professor"},
	{"qualification", "e.g. M.E., Ph.D.", "M.E."},
	{"roles", "Comma separated: staff, hod, placement_officer (default staff)", "staff"},
	{"mobile", "Mobile (10 digits); needed for OTP login", "9000000501"},
	{"email", "Email", "lakshmi@example.com"},
	{"gender", "male / female / other", "female"},
	{"dob", "Date of birth (YYYY-MM-DD or DD-MM-YYYY)", "1988-04-02"},
	{"joined_on", "Joining date (YYYY-MM-DD or DD-MM-YYYY)", "2020-06-01"},
}

func (h *Handler) staffTemplate(c *gin.Context) {
	writeTemplate(c, "staff_upload_template.xlsx", "Staff", staffColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Departments", nil, []string{"department_code", "Department"}, h.lookup(c, `SELECT code, name FROM departments WHERE is_active ORDER BY code`))
	})
}

func (h *Handler) uploadStaff(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	hash, err := defaultPassword(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.run(c, "staff", required(staffColumns), dryRun, func(t *upload.Table) importResult {
		return h.importStaff(c, a, t, hash, dryRun)
	})
}

func (h *Handler) importStaff(ctx context.Context, a actor.Actor, t *upload.Table, hash *string, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	depts := h.codeMap(ctx, `SELECT upper(code), id FROM departments WHERE is_active`)
	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code, name := t.Get(r, "employee_code"), t.Get(r, "name")
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: name, Message: msg})
		}

		in := staff.Input{
			Name: name, EmployeeCode: code,
			Mobile: opt(t.Get(r, "mobile")), Email: opt(t.Get(r, "email")),
			Gender:      opt(strings.ToLower(t.Get(r, "gender"))),
			Designation: opt(t.Get(r, "designation")), Qualification: opt(t.Get(r, "qualification")),
		}
		if dc := strings.ToUpper(t.Get(r, "department_code")); dc != "" {
			id, ok := depts[dc]
			if !ok {
				fail(fmt.Sprintf("Unknown department_code %q", dc))
				continue
			}
			in.DepartmentID = &id
		}
		if in.Gender != nil && *in.Gender != "male" && *in.Gender != "female" && *in.Gender != "other" {
			fail("gender must be male, female or other")
			continue
		}
		var err error
		if in.DOB, err = upload.ExcelDate(t.Get(r, "dob"), "dob"); err != nil {
			fail(err.Error())
			continue
		}
		if in.JoinedOn, err = upload.ExcelDate(t.Get(r, "joined_on"), "joined_on"); err != nil {
			fail(err.Error())
			continue
		}
		for _, role := range strings.Split(t.Get(r, "roles"), ",") {
			if role = strings.ToLower(strings.TrimSpace(role)); role != "" {
				in.Roles = append(in.Roles, role)
			}
		}
		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			_, err := h.staff.CreateInTx(ctx, tx, a, in, hash)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// inTx runs one row in its own transaction; a dry run rolls back after the row validated.
func (h *Handler) inTx(ctx context.Context, dryRun bool, fn func(tx pgx.Tx) error) error {
	err := pgx.BeginFunc(ctx, h.db, func(tx pgx.Tx) error {
		if err := fn(tx); err != nil {
			return err
		}
		if dryRun {
			return errDryRun
		}
		return nil
	})
	if errors.Is(err, errDryRun) {
		return nil
	}
	return err
}

// codeMap loads a (key, id) lookup such as department code → id.
func (h *Handler) codeMap(ctx context.Context, q string, args ...any) map[string]int64 {
	out := map[string]int64{}
	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var k string
		var id int64
		if rows.Scan(&k, &id) == nil {
			out[k] = id
		}
	}
	return out
}

// ---- student skills ----

var skillColumns = []column{
	{"register_no*", "Student register number", "25CS001"},
	{"name", "Student name (for your reference; not imported)", "Arun Kumar"},
	{"skill*", "Skill name exactly as in the Skill list sheet", "Python"},
	{"level*", "1 Beginner, 2 Basic, 3 Intermediate, 4 Advanced, 5 Expert. Leave blank to skip the row.", "3"},
	{"source", "assessment / certification / project / internship / course (default assessment)", "assessment"},
	{"remarks", "Optional note", ""},
}

var skillSources = map[string]bool{"assessment": true, "certification": true, "project": true, "internship": true, "course": true}

// skillsTemplate: ?class_id= pre-fills one row per student of the class (and ?skill_id= the skill column).
func (h *Handler) skillsTemplate(c *gin.Context) {
	var rows [][]any
	if classID := request.QueryInt64(c, "class_id"); classID != nil {
		skill := ""
		if sid := request.QueryInt64(c, "skill_id"); sid != nil {
			_ = h.db.QueryRow(c, `SELECT name::text FROM skills WHERE id = $1 AND is_active`, *sid).Scan(&skill)
		}
		rows = [][]any{}
		for _, st := range h.lookup(c, `SELECT sp.register_no, u.name FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.current_class_id = $1 AND sp.is_active ORDER BY sp.register_no`, *classID) {
			rows = append(rows, []any{st[0], st[1], skill, nil, "assessment", nil})
		}
	}
	writeTemplate(c, "student_skills_template.xlsx", "Skills", skillColumns, rows, func(b *xlsxutil.Book) {
		b.Sheet("Skill list", nil, []string{"skill", "category"}, h.lookup(c, `SELECT name::text, category FROM skills WHERE is_active ORDER BY category, name`))
	})
}

func (h *Handler) uploadSkills(c *gin.Context) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("Only staff can record student skills"))
		return
	}
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "skills", required(skillColumns), dryRun, func(t *upload.Table) importResult {
		return h.importSkills(c, a, t, dryRun)
	})
}

type skillStudent struct {
	id   int64
	dept *int64
}

func (h *Handler) importSkills(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	skills := h.codeMap(ctx, `SELECT lower(name::text), id FROM skills WHERE is_active`)
	skillNames := map[int64]string{} // master spelling for notices
	for _, row := range h.lookup(ctx, `SELECT id::text, name::text FROM skills WHERE is_active`) {
		if id, err := strconv.ParseInt(row[0].(string), 10, 64); err == nil {
			skillNames[id] = row[1].(string)
		}
	}

	// HOD/staff may only record skills for their own department (same rule as the skill screen).
	var scope *int64
	if !a.Has("admin", "placement_officer") {
		_ = h.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&scope)
	}
	students := map[string]skillStudent{}
	if rows, err := h.db.Query(ctx, `SELECT upper(sp.register_no), u.id, u.department_id FROM student_profiles sp
		JOIN users u ON u.id = sp.user_id AND u.is_active WHERE sp.is_active`); err == nil {
		for rows.Next() {
			var reg string
			var st skillStudent
			if rows.Scan(&reg, &st.id, &st.dept) == nil {
				students[reg] = st
			}
		}
		rows.Close()
	}

	type change struct {
		student, skill int64
		name           string
		level          int
	}
	changed := []change{}
	seen := map[[2]int64]int{}
	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		reg, name := t.Get(r, "register_no"), t.Get(r, "name")
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: reg, Name: name, Message: msg})
		}
		levelTxt := t.Get(r, "level")
		if levelTxt == "" {
			continue // pre-filled roster rows without a level are skipped
		}
		st, ok := students[strings.ToUpper(reg)]
		if !ok {
			fail(fmt.Sprintf("No student with register number %q", reg))
			continue
		}
		if scope != nil && (st.dept == nil || *st.dept != *scope) {
			fail("This student belongs to another department")
			continue
		}
		skillName := t.Get(r, "skill")
		skillID, ok := skills[strings.ToLower(skillName)]
		if !ok {
			fail(fmt.Sprintf("Unknown skill %q (see the Skill list sheet)", skillName))
			continue
		}
		level, err := strconv.Atoi(levelTxt)
		if err != nil || level < 1 || level > 5 {
			fail("level must be a whole number from 1 to 5")
			continue
		}
		source := strings.ToLower(t.Get(r, "source"))
		if source == "" {
			source = "assessment"
		}
		if !skillSources[source] {
			fail("source must be assessment, certification, project, internship or course")
			continue
		}
		key := [2]int64{st.id, skillID}
		if prev, dup := seen[key]; dup {
			fail(fmt.Sprintf("Duplicate of row %d (same student and skill)", prev))
			continue
		}
		seen[key] = rowNo

		var prev *int
		err = h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			if err := tx.QueryRow(ctx, `SELECT proficiency FROM student_skills WHERE student_id = $1 AND skill_id = $2 AND is_active`, st.id, skillID).Scan(&prev); err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			_, err := tx.Exec(ctx, `
				INSERT INTO student_skills (student_id, skill_id, proficiency, source, remarks, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $6)
				ON CONFLICT (student_id, skill_id) WHERE is_active
				DO UPDATE SET proficiency = EXCLUDED.proficiency, source = EXCLUDED.source,
				              remarks = COALESCE(EXCLUDED.remarks, student_skills.remarks), updated_by = EXCLUDED.updated_by`,
				st.id, skillID, level, source, opt(t.Get(r, "remarks")), a.ID)
			return err
		})
		if err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
		if !dryRun && (prev == nil || *prev != level) {
			changed = append(changed, change{st.id, skillID, skillNames[skillID], level})
		}
	}

	// Every student whose levels moved needs their blended scores rebuilt.
	touched := []int64{}

	// One notice per student listing what changed, instead of one per row.
	byStudent := map[int64][]string{}
	order := []int64{}
	for _, ch := range changed {
		if _, ok := byStudent[ch.student]; !ok {
			order = append(order, ch.student)
			touched = append(touched, ch.student)
		}
		byStudent[ch.student] = append(byStudent[ch.student], fmt.Sprintf("%s: level %d", ch.name, ch.level))
	}
	for _, sid := range order {
		items := byStudent[sid]
		title := "Skills updated"
		if len(items) == 1 {
			title = "Skill recorded: " + strings.SplitN(items[0], ":", 2)[0]
		}
		h.notify.SendSafe(ctx, notify.Notice{Title: title,
			Body: strings.Join(items, ", ") + " (out of 5). Higher levels improve your placement match.",
			Type: notify.TypeSkill, CreatedBy: a.ID}, []int64{sid})
	}
	if len(touched) > 0 {
		if err := skillscore.InBatches(ctx, h.db, a.ID, touched); err != nil {
			slog.Error("skill score recompute after skills import failed", "students", len(touched), "err", err)
		}
	}
	return res
}
