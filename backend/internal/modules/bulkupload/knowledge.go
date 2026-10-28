package bulkupload

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/modules/blooms"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/upload"
	"skills-analyzer/internal/pkg/xlsxutil"
)

var (
	interviewCategories = []string{"technical", "aptitude", "hr", "coding", "group_discussion", "case_study"}
	difficulties        = []string{"easy", "medium", "hard"}
	materialTypes       = []string{"notes", "question_paper", "slides", "reference", "video", "link"}
)

func oneOf(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// cell returns a trimmed cell, or an error when it is longer than max characters.
func cell(t *upload.Table, r []string, col string, max int) (string, error) {
	v := strings.TrimSpace(t.Get(r, col))
	if len([]rune(v)) > max {
		return "", fmt.Errorf("%s is longer than %d characters", col, max)
	}
	return v, nil
}

func clipText(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n]) + "…"
	}
	return s
}

// ==================== Interview questions ====================

var interviewColumns = []column{
	{"company", "Company name from the Companies sheet. Leave empty for a general question.", "TCS"},
	{"category*", strings.Join(interviewCategories, " / "), "technical"},
	{"question*", "The interview question", "What is the difference between an array and a linked list?"},
	{"answer", "Model answer or hint", "Arrays are contiguous with O(1) access; linked lists use pointers."},
	{"difficulty", "easy / medium / hard (default medium)", "easy"},
	{"tags", "Comma-separated tags", "dsa,array"},
}

func (h *Handler) interviewTemplate(c *gin.Context) {
	writeTemplate(c, "interview_questions_upload_template.xlsx", "Interview questions", interviewColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Companies", nil, []string{"company"}, h.lookupOne(c, `SELECT name::text FROM companies WHERE is_active ORDER BY name`))
	})
}

// lookupOne runs a one-column query for the reference sheets in templates.
func (h *Handler) lookupOne(ctx context.Context, q string) [][]any {
	out := [][]any{}
	rows, err := h.db.Query(ctx, q)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var s string
		if rows.Scan(&s) == nil {
			out = append(out, []any{s})
		}
	}
	return out
}

func (h *Handler) uploadInterview(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "interview_questions", required(interviewColumns), dryRun, func(t *upload.Table) importResult {
		return h.importInterview(c, a, t, dryRun)
	})
}

func (h *Handler) importInterview(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	companies := h.codeMap(ctx, `SELECT lower(name::text), id FROM companies WHERE is_active`)

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		question := strings.TrimSpace(t.Get(r, "question"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, Name: clipText(question, 60), Message: msg})
		}
		if question == "" || len([]rune(question)) > 2000 {
			fail("question is required and at most 2000 characters")
			continue
		}
		category := strings.ToLower(strings.TrimSpace(t.Get(r, "category")))
		if !oneOf(interviewCategories, category) {
			fail("category must be one of: " + strings.Join(interviewCategories, ", "))
			continue
		}
		difficulty := strings.ToLower(strings.TrimSpace(t.Get(r, "difficulty")))
		if difficulty == "" {
			difficulty = "medium"
		}
		if !oneOf(difficulties, difficulty) {
			fail("difficulty must be one of: " + strings.Join(difficulties, ", "))
			continue
		}
		answer, err := cell(t, r, "answer", 5000)
		if err != nil {
			fail(err.Error())
			continue
		}
		tags, err := cell(t, r, "tags", 500)
		if err != nil {
			fail(err.Error())
			continue
		}
		var companyID *int64
		if name := strings.TrimSpace(t.Get(r, "company")); name != "" {
			id, ok := companies[strings.ToLower(name)]
			if !ok {
				fail(fmt.Sprintf("company %q was not found; add it under Companies first", name))
				continue
			}
			companyID = &id
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM interview_questions
				WHERE is_active AND lower(question) = lower($1) AND company_id IS NOT DISTINCT FROM $2)`, question, companyID).Scan(&exists); err != nil {
				return err
			}
			if exists {
				return response.Conflict("This question already exists, skipping")
			}
			_, err := tx.Exec(ctx, `INSERT INTO interview_questions (company_id, category, question, answer, difficulty, tags, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $7)`, companyID, category, question, opt(answer), difficulty, opt(tags), a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Study materials ====================

var materialColumns = []column{
	{"subject_code*", "Subject code from the Subjects sheet", "CS3301"},
	{"title*", "Title of the material", "Unit 1 notes: arrays and linked lists"},
	{"material_type", strings.Join(materialTypes, " / ") + " (default notes)", "notes"},
	{"description", "Short description", "Handwritten notes with worked examples"},
	{"url", "Link to the material (http:// or https://). Files are attached later on the Study Materials page.", "https://example.com/unit1.pdf"},
}

func (h *Handler) materialsTemplate(c *gin.Context) {
	writeTemplate(c, "study_materials_upload_template.xlsx", "Study materials", materialColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Subjects", nil, []string{"subject_code", "Subject"}, h.lookup(c, `SELECT code, name FROM subjects WHERE is_active ORDER BY code`))
	})
}

func (h *Handler) uploadMaterials(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "study_materials", required(materialColumns), dryRun, func(t *upload.Table) importResult {
		return h.importMaterials(c, a, t, dryRun)
	})
}

func (h *Handler) importMaterials(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	subjects := h.codeMap(ctx, `SELECT upper(code), id FROM subjects WHERE is_active`)

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code := strings.ToUpper(strings.TrimSpace(t.Get(r, "subject_code")))
		title := strings.TrimSpace(t.Get(r, "title"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: clipText(title, 60), Message: msg})
		}
		subjectID, ok := subjects[code]
		if !ok {
			fail(fmt.Sprintf("subject_code %q was not found; add it under Subjects first", code))
			continue
		}
		if title == "" || len([]rune(title)) > 200 {
			fail("title is required and at most 200 characters")
			continue
		}
		mtype := strings.ToLower(strings.TrimSpace(t.Get(r, "material_type")))
		if mtype == "" {
			mtype = "notes"
		}
		if !oneOf(materialTypes, mtype) {
			fail("material_type must be one of: " + strings.Join(materialTypes, ", "))
			continue
		}
		description, err := cell(t, r, "description", 1000)
		if err != nil {
			fail(err.Error())
			continue
		}
		url, err := cell(t, r, "url", 500)
		if err != nil {
			fail(err.Error())
			continue
		}
		if lower := strings.ToLower(url); url != "" && !strings.HasPrefix(lower, "http://") && !strings.HasPrefix(lower, "https://") {
			fail("url must start with http:// or https://")
			continue
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM study_materials
				WHERE is_active AND subject_id = $1 AND lower(title) = lower($2))`, subjectID, title).Scan(&exists); err != nil {
				return err
			}
			if exists {
				return response.Conflict("This material already exists for the subject, skipping")
			}
			_, err := tx.Exec(ctx, `INSERT INTO study_materials (subject_id, title, material_type, description, url, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $6)`, subjectID, title, mtype, opt(description), opt(url), a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}

// ==================== Question bank ====================

var questionColumns = []column{
	{"subject_code*", "Subject code from the Subjects sheet", "CS3301"},
	{"question*", "The question text", "Define a stack and list its applications."},
	{"marks", "Marks, 0 to 100 (default 0)", "2"},
	{"year", "Year of the paper, e.g. 2024", "2024"},
	{"exam_type", "Exam type code or name from the Exam types sheet", "End Semester"},
	{"unit", "Unit, e.g. Unit 1", "Unit 1"},
	{"blooms_level", "remember / understand / apply / analyze / evaluate / create. Leave empty to set it automatically from the question's action verb.", ""},
}

func (h *Handler) questionsTemplate(c *gin.Context) {
	writeTemplate(c, "question_bank_upload_template.xlsx", "Questions", questionColumns, nil, func(b *xlsxutil.Book) {
		b.Sheet("Subjects", nil, []string{"subject_code", "Subject"}, h.lookup(c, `SELECT code, name FROM subjects WHERE is_active ORDER BY code`))
		b.Sheet("Exam types", nil, []string{"code", "Name"}, h.lookup(c, `SELECT code, name FROM exam_types WHERE is_active ORDER BY name`))
	})
}

func (h *Handler) uploadQuestions(c *gin.Context) {
	a := actor.From(c)
	dryRun := c.PostForm("dry_run") == "true"
	h.run(c, "question_bank", required(questionColumns), dryRun, func(t *upload.Table) importResult {
		return h.importQuestions(c, a, t, dryRun)
	})
}

func (h *Handler) importQuestions(ctx context.Context, a actor.Actor, t *upload.Table, dryRun bool) importResult {
	res := importResult{errors: []RowError{}}
	subjects := h.codeMap(ctx, `SELECT upper(code), id FROM subjects WHERE is_active`)
	exams := h.codeMap(ctx, `SELECT lower(code), id FROM exam_types WHERE is_active`)
	for k, v := range h.codeMap(ctx, `SELECT lower(name), id FROM exam_types WHERE is_active`) {
		exams[k] = v
	}

	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		code := strings.ToUpper(strings.TrimSpace(t.Get(r, "subject_code")))
		question := strings.TrimSpace(t.Get(r, "question"))
		fail := func(msg string) {
			res.errors = append(res.errors, RowError{Row: rowNo, RegisterNo: code, Name: clipText(question, 60), Message: msg})
		}
		subjectID, ok := subjects[code]
		if !ok {
			fail(fmt.Sprintf("subject_code %q was not found; add it under Subjects first", code))
			continue
		}
		if question == "" || len([]rune(question)) > 5000 {
			fail("question is required and at most 5000 characters")
			continue
		}
		marks := 0
		if raw := strings.TrimSpace(t.Get(r, "marks")); raw != "" {
			n, err := strconv.ParseFloat(raw, 64)
			if err != nil || n < 0 || n > 100 || n != float64(int(n)) {
				fail("marks must be a whole number from 0 to 100")
				continue
			}
			marks = int(n)
		}
		var year *int
		if raw := strings.TrimSpace(t.Get(r, "year")); raw != "" {
			n, err := strconv.Atoi(strings.TrimSuffix(raw, ".0"))
			if err != nil || n < 2000 || n > 2100 {
				fail("year must be between 2000 and 2100")
				continue
			}
			year = &n
		}
		var examID *int64
		if name := strings.TrimSpace(t.Get(r, "exam_type")); name != "" {
			id, ok := exams[strings.ToLower(name)]
			if !ok {
				fail(fmt.Sprintf("exam_type %q was not found; see the Exam types sheet", name))
				continue
			}
			examID = &id
		}
		unit, err := cell(t, r, "unit", 50)
		if err != nil {
			fail(err.Error())
			continue
		}
		level := strings.ToLower(strings.TrimSpace(t.Get(r, "blooms_level")))
		switch {
		case level == "":
			// No level given: take it from the action verb ("Define" means remember). Without a verb the
			// question bank's own default applies.
			if l, found := blooms.VerbLevel(question); found {
				level = l
			} else {
				level = "understand"
			}
		case !oneOf(blooms.Levels, level):
			fail("blooms_level must be one of: " + strings.Join(blooms.Levels, ", "))
			continue
		}

		if err := h.inTx(ctx, dryRun, func(tx pgx.Tx) error {
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM question_bank
				WHERE is_active AND subject_id = $1 AND lower(question) = lower($2) AND year IS NOT DISTINCT FROM $3)`, subjectID, question, year).Scan(&exists); err != nil {
				return err
			}
			if exists {
				return response.Conflict("This question already exists for the subject and year, skipping")
			}
			_, err := tx.Exec(ctx, `INSERT INTO question_bank (subject_id, exam_type_id, year, question, marks, blooms_level, unit, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)`, subjectID, examID, year, question, marks, level, opt(unit), a.ID)
			return err
		}); err != nil {
			fail(upload.RowMessage(err))
			continue
		}
		res.success++
	}
	return res
}
