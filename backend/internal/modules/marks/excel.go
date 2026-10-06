package marks

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/upload"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// ---- mark entry via Excel ----

// entryTemplate: GET /marks/entry/template?class_id=&semester_id=&subject_id=&exam_type_id=&attempt_no=
// The roster is pre-filled with any marks already entered; the Info sheet pins the file to this exam.
func (h *Handler) entryTemplate(c *gin.Context) {
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
	rows := make([][]any, 0, len(sheet.Rows))
	for _, r := range sheet.Rows {
		var v any
		switch {
		case r.IsAbsent:
			v = "AB"
		case r.MarksObtained != nil:
			v = *r.MarksObtained
		}
		rows = append(rows, []any{r.RegisterNo, r.Name, v})
	}
	b := xlsxutil.New()
	b.Sheet("Marks", nil, []string{"register_no*", "name", "marks*"}, rows)
	b.Sheet("Info", nil, []string{"key", "value", "note"}, [][]any{
		{"class_id", e.ClassID, e.ClassLabel},
		{"semester_id", e.SemesterID, fmt.Sprintf("Semester %d", e.SemNo)},
		{"subject_id", e.SubjectID, e.SubjectCode + " " + e.SubjectName},
		{"exam_type_id", e.ExamTypeID, e.ExamName},
		{"attempt_no", e.AttemptNo, map[bool]string{true: "Regular", false: "Arrear attempt"}[e.AttemptNo == 1]},
		{"max_marks", e.MaxMarks, "Marks must be between 0 and this value"},
		{"how_to", "", "Enter a number, or AB for absent. Leave a cell blank to keep it unchanged. Do not edit this sheet."},
	})
	b.Send(c, fmt.Sprintf("marks_%s_%s_%s.xlsx", e.ClassLabel, e.SubjectCode, e.ExamName))
}

type uploadResult struct {
	Job   *upload.Job `json:"job"`
	Saved bool        `json:"saved"`
	Sheet *EntrySheet `json:"sheet,omitempty"`
}

// uploadEntry: POST /marks/entry/upload (multipart: file + the entry key + dry_run).
// All-or-nothing: any bad row means nothing is saved.
func (h *Handler) uploadEntry(c *gin.Context) {
	a := actor.From(c)
	var k entryKey
	if err := c.ShouldBind(&k); err != nil {
		response.Error(c, response.BadRequest("class_id, semester_id, subject_id and exam_type_id are required"))
		return
	}
	dryRun := c.PostForm("dry_run") == "true"
	e, err := h.loadCtx(c, k)
	if err != nil {
		response.Error(c, err)
		return
	}
	current, err := h.buildSheet(c, a, e)
	if err != nil {
		response.Error(c, err)
		return
	}
	if !current.CanEdit {
		response.Error(c, response.Forbidden("Only the subject's staff, the class incharge, the HOD or an admin can enter these marks"))
		return
	}
	name, data, err := upload.File(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	t, err := upload.Parse(data, []string{"register_no", "marks"})
	if err != nil {
		response.Error(c, err)
		return
	}
	// A template downloaded for another subject/exam must not be uploaded here by mistake.
	for key, want := range map[string]int64{"class_id": e.ClassID, "semester_id": e.SemesterID, "subject_id": e.SubjectID,
		"exam_type_id": e.ExamTypeID, "attempt_no": int64(e.AttemptNo)} {
		if got, ok := t.Info[key]; ok && got != strconv.FormatInt(want, 10) {
			response.Error(c, response.BadRequest(fmt.Sprintf("This file was downloaded for a different class, subject or exam (%s does not match). Download the template for %s %s %s.",
				key, e.ClassLabel, e.SubjectCode, e.ExamName)))
			return
		}
	}

	roster := map[string]EntryRow{}
	for _, r := range current.Rows {
		roster[strings.ToUpper(r.RegisterNo)] = r
	}
	errs := []upload.RowError{}
	entries := []EntryInput{}
	seen := map[int64]int{}
	for i, r := range t.Data {
		rowNo := t.First + i
		if upload.IsBlank(r) {
			continue
		}
		reg, nm, val := t.Get(r, "register_no"), t.Get(r, "name"), strings.ToUpper(t.Get(r, "marks"))
		fail := func(msg string) {
			errs = append(errs, upload.RowError{Row: rowNo, RegisterNo: reg, Name: nm, Message: msg})
		}
		if val == "" {
			continue // blank = leave unchanged
		}
		st, ok := roster[strings.ToUpper(reg)]
		if !ok {
			fail(fmt.Sprintf("%s is not on %s's list for this exam", reg, e.ClassLabel))
			continue
		}
		if prev, dup := seen[st.StudentID]; dup {
			fail(fmt.Sprintf("Duplicate of row %d", prev))
			continue
		}
		seen[st.StudentID] = rowNo
		in := EntryInput{StudentID: st.StudentID}
		if val == "AB" || val == "A" || val == "ABSENT" {
			in.IsAbsent = true
		} else {
			m, err := strconv.ParseFloat(val, 64)
			if err != nil {
				fail(fmt.Sprintf("marks %q is not a number (use AB for absent)", val))
				continue
			}
			if m < 0 || m > e.MaxMarks {
				fail(fmt.Sprintf("marks must be between 0 and %v", e.MaxMarks))
				continue
			}
			in.MarksObtained = &m
		}
		entries = append(entries, in)
	}

	jobID, err := upload.Start(c, h.db, "marks", name, len(t.Data), dryRun, a.ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	res := uploadResult{}
	if len(errs) == 0 && len(entries) == 0 {
		errs = append(errs, upload.RowError{Message: "No marks found in the file"})
	}
	if len(errs) == 0 && !dryRun {
		res.Sheet, err = h.applyEntries(c, a, e, entries)
		if err != nil {
			errs = append(errs, upload.RowError{Message: upload.RowMessage(err)})
		} else {
			res.Saved = true
		}
	}
	success := len(entries)
	if len(errs) > 0 {
		success = 0 // all-or-nothing
	}
	if res.Job, err = upload.Finish(c, h.db, jobID, success, errs, a.ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

// ---- class result sheet export ----

// sheetXLSX: GET /marks/sheet.xlsx — the class result sheet plus a per-subject summary.
func (h *Handler) sheetXLSX(c *gin.Context) {
	a, classID, semID, examID, attempt, err := sheetParams(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	rs, err := h.buildResultSheet(c, a, classID, semID, examID, attempt)
	if err != nil {
		response.Error(c, err)
		return
	}
	var semName, year string
	_ = h.db.QueryRow(c, `SELECT se.name, ay.name FROM semesters se, classes c JOIN academic_years ay ON ay.id = c.academic_year_id
		WHERE se.id = $1 AND c.id = $2`, semID, classID).Scan(&semName, &year)

	headers := []string{"Register no", "Name"}
	for _, s := range rs.Subjects {
		headers = append(headers, s.Code)
	}
	headers = append(headers, "Total", "Failed / absent", "Result")
	rows := make([][]any, 0, len(rs.Rows))
	for _, r := range rs.Rows {
		row := []any{r.RegisterNo, r.Name}
		total, entered := 0.0, 0
		for _, s := range rs.Subjects {
			cell, ok := r.Marks[strconv.FormatInt(s.ID, 10)]
			switch {
			case !ok || cell.Result == nil:
				row = append(row, nil)
			case *cell.Result == "absent":
				row = append(row, "AB")
			case cell.Marks != nil:
				total += *cell.Marks
				entered++
				if cell.Grade != nil {
					row = append(row, fmt.Sprintf("%g (%s)", *cell.Marks, *cell.Grade))
				} else {
					row = append(row, *cell.Marks)
				}
			default:
				row = append(row, nil)
			}
		}
		result := "Pass"
		switch {
		case entered == 0 && r.Failed == 0:
			result = "-"
		case r.Failed > 0:
			result = fmt.Sprintf("Fail (%d)", r.Failed)
		}
		row = append(row, total, r.Failed, result)
		rows = append(rows, row)
	}
	title := []string{
		fmt.Sprintf("Class result sheet: %s", rs.ClassLabel),
		fmt.Sprintf("%s · %s · %s (max %g)%s", year, semName, rs.ExamName, rs.MaxMarks, map[bool]string{true: "", false: fmt.Sprintf(" · attempt %d", rs.AttemptNo)}[rs.AttemptNo == 1]),
	}
	b := xlsxutil.New()
	b.Sheet("Results", title, headers, rows)

	summary := make([][]any, 0, len(rs.Subjects))
	for _, s := range rs.Subjects {
		st := s.Stats
		summary = append(summary, []any{s.Code, s.Name, s.Credits, st.Entered + st.Absent, st.Passed, st.Failed, st.Absent, st.Average, st.Highest, st.PassPct})
	}
	b.Sheet("Subject summary", title, []string{"Code", "Subject", "Credits", "Appeared", "Passed", "Failed", "Absent", "Average", "Highest", "Pass %"}, summary)
	b.Send(c, fmt.Sprintf("results_%s_%s.xlsx", rs.ClassLabel, rs.ExamName))
}
