package marks

import (
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

// Allocation = staff_assignments row: this staff teaches this subject to this class in this semester.
type Allocation struct {
	ID               int64     `json:"id"`
	StaffID          int64     `json:"staff_id"`
	StaffName        string    `json:"staff_name"`
	ClassID          int64     `json:"class_id"`
	ClassLabel       string    `json:"class_label"`
	AcademicYearName string    `json:"academic_year_name"`
	SemesterID       int64     `json:"semester_id"`
	SemNo            int       `json:"sem_no"`
	SubjectID        int64     `json:"subject_id"`
	SubjectCode      string    `json:"subject_code"`
	SubjectName      string    `json:"subject_name"`
	CreatedAt        time.Time `json:"created_at"`
}

const selectAllocation = `
	SELECT sa.id, u.id, u.name, c.id, ` + labelSQL + `, ay.name, se.id, se.sem_no, s.id, s.code, s.name, sa.created_at
	FROM staff_assignments sa
	JOIN users u ON u.id = sa.staff_id
	JOIN classes c ON c.id = sa.class_id
	JOIN departments d ON d.id = c.department_id
	JOIN year_levels yl ON yl.id = c.year_level_id
	JOIN academic_years ay ON ay.id = sa.academic_year_id
	JOIN semesters se ON se.id = sa.semester_id
	JOIN subjects s ON s.id = sa.subject_id`

// listAllocations: ?class_id=&staff_id=&department_id=&academic_year_id= (default current year; "all")
func (h *Handler) listAllocations(c *gin.Context) {
	where := []string{"sa.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	switch ay := c.Query("academic_year_id"); ay {
	case "all":
	case "":
		where = append(where, "ay.is_current")
	default:
		where = append(where, "sa.academic_year_id::text = "+arg(ay))
	}
	for _, f := range []struct{ q, col string }{{"class_id", "sa.class_id"}, {"staff_id", "sa.staff_id"}, {"department_id", "c.department_id"}, {"semester_id", "sa.semester_id"}} {
		if v := c.Query(f.q); v != "" {
			where = append(where, f.col+"::text = "+arg(v))
		}
	}
	rows, err := h.db.Query(c, selectAllocation+" WHERE "+strings.Join(where, " AND ")+" ORDER BY d.code, yl.level_no, c.section, s.code", args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Allocation])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

type allocInput struct {
	StaffID    int64 `json:"staff_id" binding:"required"`
	ClassID    int64 `json:"class_id" binding:"required"`
	SubjectID  int64 `json:"subject_id" binding:"required"`
	SemesterID int64 `json:"semester_id"` // defaults to the class's current semester
}

func (h *Handler) createAllocation(c *gin.Context) {
	in, ok := request.Bind[allocInput](c)
	if !ok {
		return
	}
	a := actor.From(c)
	var deptID, ayID, levelID int64
	var curSem *int64
	err := h.db.QueryRow(c, `SELECT department_id, academic_year_id, year_level_id, current_semester_id FROM classes WHERE id = $1 AND is_active`,
		in.ClassID).Scan(&deptID, &ayID, &levelID, &curSem)
	if err != nil {
		response.Error(c, notFound(err, "Class not found"))
		return
	}
	if in.SemesterID == 0 {
		if curSem == nil {
			response.Error(c, response.BadRequest("semester_id is required (the class has no current semester)"))
			return
		}
		in.SemesterID = *curSem
	}
	if err := h.checkDept(c, a, deptID); err != nil {
		response.Error(c, err)
		return
	}
	var semOK, subjOK, staffOK bool
	if err := h.db.QueryRow(c, `SELECT
		EXISTS (SELECT 1 FROM semesters WHERE id = $1 AND year_level_id = $2 AND is_active),
		EXISTS (SELECT 1 FROM curriculum WHERE department_id = $3 AND semester_id = $1 AND subject_id = $4 AND is_active),
		EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id JOIN users u ON u.id = ur.user_id AND u.is_active
		        WHERE ur.user_id = $5 AND ur.is_active AND r.slug IN ('staff', 'hod'))`,
		in.SemesterID, levelID, deptID, in.SubjectID, in.StaffID).Scan(&semOK, &subjOK, &staffOK); err != nil {
		response.Error(c, err)
		return
	}
	switch {
	case !semOK:
		response.Error(c, response.BadRequest("The semester does not belong to this class's year of study"))
		return
	case !subjOK:
		response.Error(c, response.BadRequest("This subject is not in the class's curriculum for the semester"))
		return
	case !staffOK:
		response.Error(c, response.BadRequest("Only active staff can be allocated a subject"))
		return
	}
	var id int64
	err = h.db.QueryRow(c, `INSERT INTO staff_assignments (staff_id, academic_year_id, semester_id, department_id, class_id, subject_id, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id`, in.StaffID, ayID, in.SemesterID, deptID, in.ClassID, in.SubjectID, a.ID).Scan(&id)
	if dbutil.UniqueViolation(err) != "" {
		response.Error(c, response.Conflict("This staff member is already allocated this subject for the class"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	var out Allocation
	row := h.db.QueryRow(c, selectAllocation+" WHERE sa.id = $1", id)
	if err := row.Scan(&out.ID, &out.StaffID, &out.StaffName, &out.ClassID, &out.ClassLabel, &out.AcademicYearName, &out.SemesterID,
		&out.SemNo, &out.SubjectID, &out.SubjectCode, &out.SubjectName, &out.CreatedAt); err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, out)
}

func (h *Handler) deleteAllocation(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	var deptID int64
	if err := h.db.QueryRow(c, `SELECT department_id FROM staff_assignments WHERE id = $1 AND is_active`, id).Scan(&deptID); err != nil {
		response.Error(c, notFound(err, "Allocation not found"))
		return
	}
	if err := h.checkDept(c, a, deptID); err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.db.Exec(c, `UPDATE staff_assignments SET is_active = false, updated_by = $2 WHERE id = $1`, id, a.ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Allocation removed"})
}

// checkDept: non-admins (HODs) may only manage allocations in their own department.
func (h *Handler) checkDept(c *gin.Context, a actor.Actor, deptID int64) error {
	if a.IsAdmin() {
		return nil
	}
	var mine bool
	if err := h.db.QueryRow(c, `SELECT department_id = $2 FROM users WHERE id = $1`, a.ID, deptID).Scan(&mine); err != nil {
		return err
	}
	if !mine {
		return response.Forbidden("You can only manage subject allocation for your own department")
	}
	return nil
}
