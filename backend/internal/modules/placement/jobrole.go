// Package placement covers student skills, company job roles (with required skills and
// eligibility), the skill analyzer, shortlisting/applications and placement records.
package placement

import (
	"context"
	"fmt"
	"regexp"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	notify   *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, students: students, notify: n}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	j := r.Group("/job-roles")
	j.GET("", can("job_role.view"), h.listRoles)
	j.GET("/:id", can("job_role.view"), h.getRole)
	j.POST("", can("job_role.create"), h.createRole)
	j.PUT("/:id", can("job_role.update"), h.updateRole)
	j.PATCH("/:id/status", can("job_role.update"), h.setRoleStatus)
	j.DELETE("/:id", can("job_role.delete"), h.deleteRole)
	// analyzer + shortlist
	j.POST("/:id/analyze", can("skill_analyzer.create"), h.analyze)
	j.GET("/:id/matches", can("skill_analyzer.view"), h.matches)
	j.GET("/:id/matches.xlsx", can("skill_analyzer.view"), h.rankingXLSX)
	j.POST("/:id/shortlist", can("placement.create"), h.shortlist)
	j.GET("/:id/applications", can("placement.view"), h.listApplications)

	j.PUT("/:id/jd", can("job_role.update"), h.setJobDescription)
	r.PUT("/companies/:id/logo", can("company.update"), h.setCompanyLogo)
	r.PUT("/placements/:id/offer-letter", can("placement.update"), h.setOfferLetter)

	r.PATCH("/applications/:id", can("placement.update"), h.updateApplication)
	r.GET("/placements", can("placement.view"), h.listPlacements)
	r.GET("/placements.xlsx", can("placement.view"), h.placementsXLSX)
	r.GET("/placements/stats", can("placement.view"), h.placementStats)

	// student skills + student-facing placement view
	r.GET("/students/:id/skills", can("student_skill.view"), h.studentSkills)
	r.PUT("/students/:id/skills", can("student_skill.create", "student_skill.update"), h.upsertStudentSkill)
	r.DELETE("/students/:id/skills/:skillId", can("student_skill.delete"), h.deleteStudentSkill)
	r.PUT("/students/:id/skills/:skillId/verify", can("student_skill.update"), h.verifyStudentSkill)
	r.GET("/student-skills/matrix", can("student_skill.view"), h.skillMatrix)
	r.GET("/students/:id/opportunities", can("placement.view", "job_role.view"), h.opportunities)
}

// staffOnly: rankings, applications and placement lists are never shown to students/parents,
// even though they hold some placement view permissions for their own data.
func staffOnly(a actor.Actor) error {
	if a.Has("admin", "placement_officer", "hod", "staff") {
		return nil
	}
	return response.Forbidden("This view is available to staff only")
}

// ---- job roles ----

type RoleSkill struct {
	SkillID       int64   `json:"skill_id"`
	SkillName     string  `json:"skill_name"`
	RequiredLevel int     `json:"required_level"`
	IsMandatory   bool    `json:"is_mandatory"`
	Weight        float64 `json:"weight"`
}

type DeptRef struct {
	ID   int64  `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}

type JobRole struct {
	ID               int64       `json:"id"`
	CompanyID        int64       `json:"company_id"`
	CompanyName      string      `json:"company_name"`
	Title            string      `json:"title"`
	Description      *string     `json:"description"`
	PackageLPA       float64     `json:"package_lpa"`
	DriveDate        *string     `json:"drive_date"`
	LastApplyDate    *string     `json:"last_apply_date"`
	MinCGPA          float64     `json:"min_cgpa"`
	MaxBacklogs      int         `json:"max_backlogs"`
	EligibleBatch    *string     `json:"eligible_batch"`
	Openings         *int        `json:"openings"`
	Status           string      `json:"status"`
	IsActive         bool        `json:"is_active"`
	CreatedAt        time.Time   `json:"created_at"`
	ApplicationCount int         `json:"application_count"`
	SelectedCount    int         `json:"selected_count"`
	AnalyzedAt       *time.Time  `json:"analyzed_at"`
	Skills           []RoleSkill `json:"skills"`
	Departments      []DeptRef   `json:"departments"`
	CompanyLogo      *files.Link `json:"company_logo"`
	JD               *files.Link `json:"jd"`
}

const selectRole = `
	SELECT j.id, j.company_id, co.name::text, j.title, j.description, j.package_lpa::float8,
	       to_char(j.drive_date, 'YYYY-MM-DD'), to_char(j.last_apply_date, 'YYYY-MM-DD'),
	       j.min_cgpa::float8, j.max_backlogs, j.eligible_batch, j.openings, j.status, j.is_active, j.created_at,
	       (SELECT count(*) FROM placement_applications a WHERE a.job_role_id = j.id AND a.is_active)::int,
	       (SELECT count(*) FROM placement_applications a WHERE a.job_role_id = j.id AND a.is_active AND a.status = 'selected')::int,
	       (SELECT max(computed_at) FROM skill_match_results r WHERE r.job_role_id = j.id AND r.is_active),
	       file_json(co.logo_file_id), file_json(j.jd_file_id)
	FROM company_job_roles j JOIN companies co ON co.id = j.company_id`

func scanRole(row pgx.Row) (*JobRole, error) {
	j := &JobRole{Skills: []RoleSkill{}, Departments: []DeptRef{}}
	err := row.Scan(&j.ID, &j.CompanyID, &j.CompanyName, &j.Title, &j.Description, &j.PackageLPA, &j.DriveDate, &j.LastApplyDate,
		&j.MinCGPA, &j.MaxBacklogs, &j.EligibleBatch, &j.Openings, &j.Status, &j.IsActive, &j.CreatedAt,
		&j.ApplicationCount, &j.SelectedCount, &j.AnalyzedAt, &j.CompanyLogo, &j.JD)
	return j, err
}

// attach loads skills and eligible departments for a set of roles in two queries.
func (h *Handler) attach(ctx context.Context, roles []*JobRole) error {
	if len(roles) == 0 {
		return nil
	}
	byID := map[int64]*JobRole{}
	ids := []int64{}
	for _, r := range roles {
		byID[r.ID] = r
		ids = append(ids, r.ID)
	}
	rows, err := h.db.Query(ctx, `SELECT rs.job_role_id, s.id, s.name::text, rs.required_level, rs.is_mandatory, rs.weight::float8
		FROM job_role_skills rs JOIN skills s ON s.id = rs.skill_id
		WHERE rs.job_role_id = ANY($1) AND rs.is_active ORDER BY rs.is_mandatory DESC, rs.weight DESC, s.name`, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var rid int64
		var s RoleSkill
		if err := rows.Scan(&rid, &s.SkillID, &s.SkillName, &s.RequiredLevel, &s.IsMandatory, &s.Weight); err != nil {
			rows.Close()
			return err
		}
		byID[rid].Skills = append(byID[rid].Skills, s)
	}
	rows.Close()
	rows, err = h.db.Query(ctx, `SELECT jd.job_role_id, d.id, d.code, d.name FROM job_role_departments jd JOIN departments d ON d.id = jd.department_id
		WHERE jd.job_role_id = ANY($1) AND jd.is_active ORDER BY d.code`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var rid int64
		var d DeptRef
		if err := rows.Scan(&rid, &d.ID, &d.Code, &d.Name); err != nil {
			return err
		}
		byID[rid].Departments = append(byID[rid].Departments, d)
	}
	return rows.Err()
}

func (h *Handler) findRole(ctx context.Context, id int64) (*JobRole, error) {
	j, err := scanRole(h.db.QueryRow(ctx, selectRole+" WHERE j.id = $1 AND j.is_active", id))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Job role not found")
	}
	if err != nil {
		return nil, err
	}
	return j, h.attach(ctx, []*JobRole{j})
}

// listRoles: ?search=&company_id=&status=open,upcoming
func (h *Handler) listRoles(c *gin.Context) {
	where := []string{"j.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	if s := strings.TrimSpace(c.Query("search")); s != "" {
		ph := arg("%" + s + "%")
		where = append(where, fmt.Sprintf("(j.title ILIKE %[1]s OR co.name::text ILIKE %[1]s)", ph))
	}
	if v := request.QueryInt64(c, "company_id"); v != nil {
		where = append(where, "j.company_id = "+arg(*v))
	}
	if st := c.Query("status"); st != "" {
		where = append(where, "j.status = ANY("+arg(strings.Split(st, ","))+")")
	}
	rows, err := h.db.Query(c, selectRole+" WHERE "+strings.Join(where, " AND ")+
		" ORDER BY CASE j.status WHEN 'open' THEN 1 WHEN 'upcoming' THEN 2 WHEN 'closed' THEN 3 ELSE 4 END, j.drive_date NULLS LAST, j.id DESC", args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*JobRole{}
	for rows.Next() {
		j, err := scanRole(rows)
		if err != nil {
			response.Error(c, err)
			return
		}
		out = append(out, j)
	}
	rows.Close()
	if err := h.attach(c, out); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, out)
}

func (h *Handler) getRole(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	j, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, j)
}

type roleInput struct {
	CompanyID     int64   `json:"company_id" binding:"required"`
	Title         string  `json:"title" binding:"required,max=150"`
	Description   *string `json:"description"`
	PackageLPA    float64 `json:"package_lpa" binding:"required,gt=0,lte=500"`
	DriveDate     *string `json:"drive_date"`
	LastApplyDate *string `json:"last_apply_date"`
	MinCGPA       float64 `json:"min_cgpa" binding:"gte=0,lte=10"`
	MaxBacklogs   int     `json:"max_backlogs" binding:"gte=0,lte=50"`
	EligibleBatch *string `json:"eligible_batch"`
	Openings      *int    `json:"openings" binding:"omitempty,gte=1"`
	Status        string  `json:"status" binding:"omitempty,oneof=upcoming open closed completed"`
	DepartmentIDs []int64 `json:"department_ids"` // empty = every department
	Skills        []struct {
		SkillID       int64   `json:"skill_id" binding:"required"`
		RequiredLevel int     `json:"required_level" binding:"required,min=1,max=5"`
		IsMandatory   bool    `json:"is_mandatory"`
		Weight        float64 `json:"weight" binding:"omitempty,gt=0,lte=10"`
	} `json:"skills" binding:"dive"`
}

var batchRe = regexp.MustCompile(`^\d{4}-\d{4}$`)

func parseDate(s *string, field string) (*time.Time, error) {
	if s == nil || strings.TrimSpace(*s) == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", strings.TrimSpace(*s))
	if err != nil {
		return nil, response.BadRequest(field + " must be YYYY-MM-DD")
	}
	return &t, nil
}

func (h *Handler) saveRole(c *gin.Context, id int64) {
	in, ok := request.Bind[roleInput](c)
	if !ok {
		return
	}
	a := actor.From(c)
	in.Title = strings.TrimSpace(in.Title)
	if in.Status == "" {
		in.Status = "upcoming"
	}
	if in.EligibleBatch != nil {
		b := strings.TrimSpace(*in.EligibleBatch)
		if b == "" {
			in.EligibleBatch = nil
		} else if !batchRe.MatchString(b) {
			response.Error(c, response.BadRequest("eligible_batch must look like 2023-2027"))
			return
		} else {
			in.EligibleBatch = &b
		}
	}
	drive, err := parseDate(in.DriveDate, "drive_date")
	if err != nil {
		response.Error(c, err)
		return
	}
	last, err := parseDate(in.LastApplyDate, "last_apply_date")
	if err != nil {
		response.Error(c, err)
		return
	}
	if drive != nil && last != nil && last.After(*drive) {
		response.Error(c, response.BadRequest("last_apply_date must be on or before drive_date"))
		return
	}
	skillIDs := []int64{}
	seen := map[int64]bool{}
	for i := range in.Skills {
		if seen[in.Skills[i].SkillID] {
			response.Error(c, response.BadRequest("A skill is listed twice"))
			return
		}
		seen[in.Skills[i].SkillID] = true
		skillIDs = append(skillIDs, in.Skills[i].SkillID)
		if in.Skills[i].Weight == 0 {
			in.Skills[i].Weight = 1
		}
	}
	if in.DepartmentIDs == nil {
		in.DepartmentIDs = []int64{}
	}
	var companyOK bool
	var skillCount, deptCount int
	if err := h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM companies WHERE id = $1 AND is_active),
		(SELECT count(*) FROM skills WHERE id = ANY($2) AND is_active)::int,
		(SELECT count(DISTINCT id) FROM departments WHERE id = ANY($3) AND is_active)::int`,
		in.CompanyID, skillIDs, in.DepartmentIDs).Scan(&companyOK, &skillCount, &deptCount); err != nil {
		response.Error(c, err)
		return
	}
	switch {
	case !companyOK:
		response.Error(c, response.BadRequest("company_id does not exist"))
		return
	case skillCount != len(skillIDs):
		response.Error(c, response.BadRequest("One or more skill_ids are invalid"))
		return
	case deptCount != len(uniq(in.DepartmentIDs)):
		response.Error(c, response.BadRequest("One or more department_ids are invalid"))
		return
	}

	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if id == 0 {
			if err := tx.QueryRow(c, `INSERT INTO company_job_roles (company_id, title, description, package_lpa, drive_date, last_apply_date,
				min_cgpa, max_backlogs, eligible_batch, openings, status, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12) RETURNING id`,
				in.CompanyID, in.Title, in.Description, in.PackageLPA, drive, last, in.MinCGPA, in.MaxBacklogs, in.EligibleBatch,
				in.Openings, in.Status, a.ID).Scan(&id); err != nil {
				return err
			}
		} else {
			if _, err := tx.Exec(c, `UPDATE company_job_roles SET company_id = $2, title = $3, description = $4, package_lpa = $5,
				drive_date = $6, last_apply_date = $7, min_cgpa = $8, max_backlogs = $9, eligible_batch = $10, openings = $11,
				status = $12, updated_by = $13 WHERE id = $1`,
				id, in.CompanyID, in.Title, in.Description, in.PackageLPA, drive, last, in.MinCGPA, in.MaxBacklogs, in.EligibleBatch,
				in.Openings, in.Status, a.ID); err != nil {
				return err
			}
		}
		// Replace required skills and eligible departments.
		if _, err := tx.Exec(c, `UPDATE job_role_skills SET is_active = false, updated_by = $2 WHERE job_role_id = $1 AND is_active`, id, a.ID); err != nil {
			return err
		}
		for _, s := range in.Skills {
			if _, err := tx.Exec(c, `INSERT INTO job_role_skills (job_role_id, skill_id, required_level, is_mandatory, weight, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $6)`, id, s.SkillID, s.RequiredLevel, s.IsMandatory, s.Weight, a.ID); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(c, `UPDATE job_role_departments SET is_active = false, updated_by = $2 WHERE job_role_id = $1 AND is_active`, id, a.ID); err != nil {
			return err
		}
		_, err := tx.Exec(c, `INSERT INTO job_role_departments (job_role_id, department_id, created_by, updated_by)
			SELECT $1, d, $3, $3 FROM unnest($2::bigint[]) AS d`, id, uniq(in.DepartmentIDs), a.ID)
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	j, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.announceIfOpen(c, j, a)
	response.OK(c, j)
}

// announceIfOpen tells every eligible student about a drive the first time it is open.
func (h *Handler) announceIfOpen(ctx context.Context, j *JobRole, a actor.Actor) {
	if j.Status != "open" || h.notify.AlreadySent(ctx, "job_role_open", j.ID) {
		return
	}
	matches, err := h.evaluate(ctx, j, candidateFilter{})
	if err != nil {
		return
	}
	ids := []int64{}
	for _, m := range matches {
		if m.IsEligible && m.ApplicationStatus == nil {
			ids = append(ids, m.StudentID)
		}
	}
	body := fmt.Sprintf("%s is hiring for %s at %.2f LPA.", j.CompanyName, j.Title, j.PackageLPA)
	if j.LastApplyDate != nil {
		if t, err := time.Parse("2006-01-02", *j.LastApplyDate); err == nil {
			body += " Apply by " + t.Format("02 Jan 2006") + "."
		}
	}
	body += " You are eligible. Open Placement Drives for details."
	rt, rid := notify.Ref("job_role_open", j.ID)
	h.notify.SendSafe(ctx, notify.Notice{Title: "New drive: " + j.CompanyName + " - " + j.Title, Body: body, Type: notify.TypePlacement,
		TargetType: "user", RefType: rt, RefID: rid, CreatedBy: a.ID}, ids)
}

func (h *Handler) createRole(c *gin.Context) { h.saveRole(c, 0) }

func (h *Handler) updateRole(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.findRole(c, id); err != nil {
		response.Error(c, err)
		return
	}
	h.saveRole(c, id)
}

func (h *Handler) setRoleStatus(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Status string `json:"status" binding:"required,oneof=upcoming open closed completed"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("status must be upcoming, open, closed or completed"))
		return
	}
	tag, err := h.db.Exec(c, `UPDATE company_job_roles SET status = $2, updated_by = $3 WHERE id = $1 AND is_active`, id, body.Status, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if tag.RowsAffected() == 0 {
		response.Error(c, response.NotFound("Job role not found"))
		return
	}
	j, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	h.announceIfOpen(c, j, actor.From(c))
	response.OK(c, j)
}

func (h *Handler) deleteRole(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	j, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if j.ApplicationCount > 0 {
		response.Error(c, response.Conflict("This job role has applications; close it instead of deleting"))
		return
	}
	if _, err := h.db.Exec(c, `UPDATE company_job_roles SET is_active = false, updated_by = $2 WHERE id = $1`, id, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Job role deleted"})
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
