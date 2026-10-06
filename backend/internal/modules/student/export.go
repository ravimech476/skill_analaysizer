package student

import (
	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/xlsxutil"
)

// exportXLSX: GET /students/export.xlsx — the directory with the same filters as the list (staff only).
func (h *Handler) exportXLSX(c *gin.Context) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("This export is available to staff only"))
		return
	}
	f := Filter{
		Search:       c.Query("search"),
		DepartmentID: request.QueryInt64(c, "department_id"),
		ClassID:      request.QueryInt64(c, "class_id"),
		Batch:        c.Query("batch"),
		Status:       c.Query("status"),
		Lifecycle:    c.Query("lifecycle"),
	}
	list, _, err := h.svc.List(c, a, f, pagination.Params{Page: 1, PageSize: 20000})
	if err != nil {
		response.Error(c, err)
		return
	}
	ids := make([]int64, len(list))
	for i, s := range list {
		ids[i] = s.ID
	}
	type parent struct{ name, relation, mobile string }
	parents := map[int64]parent{}
	rows, err := h.svc.db.Query(c, `
		SELECT DISTINCT ON (x.student_id) x.student_id, u.name, x.relation, COALESCE(u.mobile, '')
		FROM student_parents x JOIN users u ON u.id = x.parent_id
		WHERE x.student_id = ANY($1) AND x.is_active
		ORDER BY x.student_id, x.is_primary DESC, x.id`, ids)
	if err != nil {
		response.Error(c, err)
		return
	}
	for rows.Next() {
		var id int64
		var p parent
		if rows.Scan(&id, &p.name, &p.relation, &p.mobile) == nil {
			parents[id] = p
		}
	}
	rows.Close()

	out := make([][]any, 0, len(list))
	for _, s := range list {
		p := parents[s.ID]
		status := s.Lifecycle
		if !s.IsActive {
			status = "inactive"
		}
		out = append(out, []any{s.RegisterNo, s.Name, str(s.DepartmentCode), str(s.ClassLabel), s.Batch, s.AdmissionYear,
			str(s.Gender), str(s.DOB), str(s.Mobile), str(s.Email), s.CGPA, s.BacklogCount, status,
			p.name, p.relation, p.mobile, str(s.InchargeName)})
	}
	b := xlsxutil.New()
	b.Sheet("Students", nil, []string{"Register no", "Name", "Department", "Class", "Batch", "Admission year", "Gender", "DOB",
		"Mobile", "Email", "CGPA", "Backlogs", "Status", "Parent", "Relation", "Parent mobile", "Class incharge"}, out)
	b.Send(c, "students.xlsx")
}

func str(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
