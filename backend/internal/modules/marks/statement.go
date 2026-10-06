package marks

import (
	"bytes"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-pdf/fpdf"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// statementPDF: GET /marks/students/:id/statement.pdf — a printable mark statement.
// Scoped like the mark history: students get their own, parents their children's, staff their department's.
func (h *Handler) statementPDF(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	hist, err := h.buildHistory(c, actor.From(c), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	pdf := renderStatement(hist)
	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		response.Error(c, err)
		return
	}
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, xlsxutil.SafeName("mark_statement_"+hist.RegisterNo+".pdf")))
	c.Data(http.StatusOK, "application/pdf", buf.Bytes())
}

func renderStatement(hist *History) *fpdf.Fpdf {
	college := os.Getenv("COLLEGE_NAME")
	if college == "" {
		college = "Skills Analyzer College"
	}
	pdf := fpdf.New("P", "mm", "A4", "")
	tr := pdf.UnicodeTranslatorFromDescriptor("") // core fonts are cp1252
	pdf.SetMargins(12, 12, 12)
	pdf.SetAutoPageBreak(true, 16)
	generated := time.Now().Format("02 Jan 2006")
	pdf.SetFooterFunc(func() {
		pdf.SetY(-12)
		pdf.SetFont("Helvetica", "", 8)
		pdf.SetTextColor(120, 120, 120)
		pdf.CellFormat(0, 5, tr(fmt.Sprintf("%s · %s · generated %s · page %d", hist.RegisterNo, hist.Name, generated, pdf.PageNo())), "", 0, "C", false, 0, "")
	})
	pdf.AddPage()

	pdf.SetFont("Helvetica", "B", 15)
	pdf.CellFormat(0, 8, tr(college), "", 1, "C", false, 0, "")
	pdf.SetFont("Helvetica", "", 11)
	pdf.CellFormat(0, 6, "Statement of Marks", "", 1, "C", false, 0, "")
	pdf.Ln(3)

	// Student block
	pdf.SetFillColor(240, 244, 250)
	pdf.SetFont("Helvetica", "", 9.5)
	field := func(label, value string, w float64, ln int) {
		pdf.SetFont("Helvetica", "B", 9.5)
		pdf.CellFormat(28, 6.5, tr(label), "", 0, "L", true, 0, "")
		pdf.SetFont("Helvetica", "", 9.5)
		pdf.CellFormat(w, 6.5, tr(value), "", ln, "L", true, 0, "")
	}
	field("Name", hist.Name, 65, 0)
	field("Register no", hist.RegisterNo, 0, 1)
	field("Department", deref(hist.DepartmentName), 65, 0)
	field("Batch", hist.Batch, 0, 1)
	field("Class", deref(hist.ClassLabel), 65, 0)
	field("CGPA", fmt.Sprintf("%.2f   (backlogs: %d)", hist.CGPA, hist.BacklogCount), 0, 1)
	pdf.Ln(4)

	if len(hist.Semesters) == 0 {
		pdf.SetFont("Helvetica", "I", 10)
		pdf.CellFormat(0, 8, "No marks have been recorded yet.", "", 1, "C", false, 0, "")
		return pdf
	}

	widths := []float64{20, 62, 14, 50, 18, 22}
	heads := []string{"Code", "Subject", "Credits", "Internal assessments", "Grade", "Result"}
	for _, sem := range hist.Semesters {
		// Keep the semester heading with at least a few rows.
		if pdf.GetY() > 250 {
			pdf.AddPage()
		}
		pdf.SetFont("Helvetica", "B", 10.5)
		title := fmt.Sprintf("%s · %s", sem.Name, sem.AcademicYear)
		if sem.ClassLabel != nil {
			title += " · " + *sem.ClassLabel
		}
		pdf.CellFormat(0, 7, tr(title), "", 1, "L", false, 0, "")

		pdf.SetFont("Helvetica", "B", 8.5)
		pdf.SetFillColor(225, 232, 245)
		for i, hd := range heads {
			pdf.CellFormat(widths[i], 6, hd, "1", 0, "C", true, 0, "")
		}
		pdf.Ln(-1)
		pdf.SetFont("Helvetica", "", 8.5)
		for _, sub := range sem.Subjects {
			internals := []string{}
			for _, ex := range sub.Exams {
				if ex.IsFinal {
					continue
				}
				v := "AB"
				if ex.Result != nil && *ex.Result != "absent" && ex.Marks != nil {
					v = fmt.Sprintf("%g/%g", *ex.Marks, ex.MaxMarks)
				}
				internals = append(internals, ex.ExamCode+" "+v)
			}
			grade, result := "-", "-"
			if sub.FinalGrade != nil {
				grade = *sub.FinalGrade
			}
			if sub.FinalResult != nil {
				result = strings.ToUpper((*sub.FinalResult)[:1]) + (*sub.FinalResult)[1:]
			}
			name := sub.Name
			if pdf.GetStringWidth(name) > widths[1]-2 {
				for len(name) > 3 && pdf.GetStringWidth(name+"...") > widths[1]-2 {
					name = name[:len(name)-1]
				}
				name += "..."
			}
			intTxt := strings.Join(internals, ", ")
			for len(intTxt) > 3 && pdf.GetStringWidth(intTxt) > widths[3]-2 {
				intTxt = intTxt[:len(intTxt)-1]
			}
			cells := []string{sub.Code, name, fmt.Sprintf("%g", sub.Credits), intTxt, grade, result}
			aligns := []string{"L", "L", "C", "L", "C", "C"}
			for i, v := range cells {
				if i == 5 && sub.FinalResult != nil && *sub.FinalResult != "pass" {
					pdf.SetTextColor(190, 30, 30)
				}
				pdf.CellFormat(widths[i], 6, tr(v), "1", 0, aligns[i], false, 0, "")
				pdf.SetTextColor(0, 0, 0)
			}
			pdf.Ln(-1)
		}
		pdf.SetFont("Helvetica", "B", 8.5)
		sgpa := "-"
		if sem.SGPA != nil {
			sgpa = fmt.Sprintf("%.2f", *sem.SGPA)
		}
		pdf.CellFormat(0, 6.5, fmt.Sprintf("SGPA %s    Credits earned %g    Backlogs %d", sgpa, sem.Credits, sem.Backlogs), "", 1, "R", false, 0, "")
		pdf.Ln(2)
	}

	pdf.Ln(2)
	pdf.SetFont("Helvetica", "B", 10)
	pdf.CellFormat(0, 7, fmt.Sprintf("Cumulative GPA: %.2f     Standing backlogs: %d", hist.CGPA, hist.BacklogCount), "T", 1, "L", false, 0, "")
	pdf.SetFont("Helvetica", "I", 8)
	pdf.SetTextColor(110, 110, 110)
	pdf.MultiCell(0, 4.5, "Grades and results are from final examinations; internal assessments are shown for reference. This is a computer-generated statement.", "", "L", false)
	return pdf
}

func deref(s *string) string {
	if s == nil {
		return "-"
	}
	return *s
}
