package placement

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// placementsXLSX: GET /placements.xlsx — placement records with the list filters, plus a per-company summary.
func (h *Handler) placementsXLSX(c *gin.Context) {
	list, err := h.queryPlacements(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	rows := make([][]any, 0, len(list))
	type agg struct {
		offers   int
		students map[int64]bool
		highest  float64
		sum      float64
	}
	byCompany := map[string]*agg{}
	order := []string{}
	for _, p := range list {
		rows = append(rows, []any{p.RegisterNo, p.StudentName, deref(p.DepartmentCode), p.Batch, p.CompanyName, p.JobTitle, p.PackageLPA, deref(p.OfferDate)})
		a, ok := byCompany[p.CompanyName]
		if !ok {
			a = &agg{students: map[int64]bool{}}
			byCompany[p.CompanyName] = a
			order = append(order, p.CompanyName)
		}
		a.offers++
		a.students[p.StudentID] = true
		a.sum += p.PackageLPA
		a.highest = max(a.highest, p.PackageLPA)
	}
	title := []string{"Placement report"}
	if b := c.Query("batch"); b != "" {
		title = append(title, "Batch "+b)
	}
	b := xlsxutil.New()
	b.Sheet("Placements", title, []string{"Register no", "Student", "Department", "Batch", "Company", "Role", "Package (LPA)", "Offer date"}, rows)
	summary := make([][]any, 0, len(order))
	for _, name := range order {
		a := byCompany[name]
		summary = append(summary, []any{name, a.offers, len(a.students), a.highest, round2(a.sum / float64(a.offers))})
	}
	b.Sheet("By company", title, []string{"Company", "Offers", "Students", "Highest (LPA)", "Average (LPA)"}, summary)
	b.Send(c, "placements.xlsx")
}

// rankingXLSX: GET /job-roles/:id/matches.xlsx — the analyzer ranking from the last run.
func (h *Handler) rankingXLSX(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	role, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	at, matches, err := h.cachedMatches(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	eligibleOnly := c.Query("eligible_only") == "true"
	gaps := func(list []SkillGap) string {
		parts := make([]string, len(list))
		for i, g := range list {
			parts[i] = fmt.Sprintf("%s %d/%d", g.Name, g.Level, g.Required)
		}
		return strings.Join(parts, ", ")
	}
	rows := [][]any{}
	rank := 0
	for _, m := range matches {
		if eligibleOnly && !m.IsEligible {
			continue
		}
		var r any
		if m.IsEligible {
			rank++
			r = rank
		}
		rows = append(rows, []any{r, m.RegisterNo, m.Name, deref(m.DepartmentCode), deref(m.ClassLabel), m.Batch, m.CGPA, m.Backlogs,
			m.SkillScore, m.AcademicScore, m.FinalScore, map[bool]string{true: "Yes", false: "No"}[m.IsEligible],
			strings.Join(m.IneligibleReasons, "; "), gaps(m.Matched), gaps(m.Missing), deref(m.ApplicationStatus)})
	}
	title := []string{fmt.Sprintf("Skill match ranking: %s · %s (%.2f LPA)", role.CompanyName, role.Title, role.PackageLPA)}
	if at != nil {
		title = append(title, "Analyzed "+at.Format("02 Jan 2006 15:04"))
	} else {
		title = append(title, "Not analyzed yet: run the analyzer first")
	}
	b := xlsxutil.New()
	b.Sheet("Ranking", title, []string{"Rank", "Register no", "Name", "Department", "Class", "Batch", "CGPA", "Backlogs",
		"Skill score", "Academic score", "Final score", "Eligible", "Why not eligible", "Skills met (level/required)", "Skill gaps (level/required)", "Application"}, rows)
	req := make([][]any, len(role.Skills))
	for i, s := range role.Skills {
		req[i] = []any{s.SkillName, s.RequiredLevel, map[bool]string{true: "Yes", false: "No"}[s.IsMandatory], s.Weight}
	}
	b.Sheet("Required skills", title[:1], []string{"Skill", "Required level", "Mandatory", "Weight"}, req)
	b.Send(c, fmt.Sprintf("ranking_%s_%s.xlsx", role.CompanyName, role.Title))
}
