// Package staff manages staff members: a user with staff-type roles (staff, hod,
// placement_officer) plus a staff_profiles row (employee code, designation…).
package staff

import (
	"context"
	"fmt"
	"regexp"
	"skills-analyzer/internal/files"
	"slices"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/rbac"
)

// StaffRoles are the roles this module may assign.
var StaffRoles = []string{"staff", "hod", "placement_officer"}

type Input struct {
	Name          string   `json:"name" binding:"required,max=150"`
	Username      string   `json:"username"` // defaults to the employee code
	Password      *string  `json:"password" binding:"omitempty,min=8,max=72"`
	EmployeeCode  string   `json:"employee_code" binding:"required,max=50"`
	Mobile        *string  `json:"mobile"`
	Email         *string  `json:"email" binding:"omitempty,email"`
	Gender        *string  `json:"gender" binding:"omitempty,oneof=male female other"`
	DOB           *string  `json:"dob"`
	DepartmentID  *int64   `json:"department_id"`
	Designation   *string  `json:"designation" binding:"omitempty,max=100"`
	Qualification *string  `json:"qualification" binding:"omitempty,max=200"`
	JoinedOn      *string  `json:"joined_on"`
	Roles         []string `json:"roles"` // subset of StaffRoles; default ["staff"]
}

type Staff struct {
	ID             int64       `json:"id"`
	Name           string      `json:"name"`
	Username       string      `json:"username"`
	EmployeeCode   *string     `json:"employee_code"`
	Mobile         *string     `json:"mobile"`
	Email          *string     `json:"email"`
	Gender         *string     `json:"gender"`
	DOB            *string     `json:"dob"`
	DepartmentID   *int64      `json:"department_id"`
	DepartmentName *string     `json:"department_name"`
	Designation    *string     `json:"designation"`
	Qualification  *string     `json:"qualification"`
	JoinedOn       *string     `json:"joined_on"`
	Roles          []string    `json:"roles"`
	InchargeOf     *string     `json:"incharge_of"` // class label in the current academic year
	IsActive       bool        `json:"is_active"`
	CreatedAt      time.Time   `json:"created_at"`
	Photo          *files.Link `json:"photo"`
}

type Handler struct{ db *pgxpool.Pool }

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache) {
	h := &Handler{db: db}
	can := func(p string) gin.HandlerFunc { return middleware.RequirePermission(perms, p) }
	g := r.Group("/staff")
	g.GET("", can("staff.view"), h.list)
	g.GET("/:id", can("staff.view"), h.get)
	g.POST("", can("staff.create"), h.create)
	g.PUT("/:id", can("staff.update"), h.update)
	g.PATCH("/:id/status", can("staff.delete"), h.setStatus)
}

const selectStaff = `
	SELECT u.id, u.name, u.username::text, sp.employee_code, u.mobile, u.email::text, u.gender, to_char(u.dob, 'YYYY-MM-DD'),
	       u.department_id, d.name, sp.designation, sp.qualification, to_char(sp.joined_on, 'YYYY-MM-DD'),
	       COALESCE((SELECT array_agg(r.slug ORDER BY r.id) FROM user_roles ur JOIN roles r ON r.id = ur.role_id AND r.is_active
	                 WHERE ur.user_id = u.id AND ur.is_active), '{}'),
	       (SELECT cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section
	          FROM classes c JOIN academic_years ay ON ay.id = c.academic_year_id AND ay.is_current
	          JOIN departments cd ON cd.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id
	         WHERE c.class_incharge_id = u.id AND c.is_active LIMIT 1),
	       u.is_active, u.created_at, file_json(u.photo_file_id)
	FROM users u
	LEFT JOIN staff_profiles sp ON sp.user_id = u.id AND sp.is_active
	LEFT JOIN departments d ON d.id = u.department_id`

// Staff = anyone holding a staff-type role.
const isStaff = `EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
	WHERE ur.user_id = u.id AND ur.is_active AND r.slug IN ('staff', 'hod', 'placement_officer'))`

func scan(row pgx.Row) (*Staff, error) {
	s := &Staff{}
	err := row.Scan(&s.ID, &s.Name, &s.Username, &s.EmployeeCode, &s.Mobile, &s.Email, &s.Gender, &s.DOB,
		&s.DepartmentID, &s.DepartmentName, &s.Designation, &s.Qualification, &s.JoinedOn, &s.Roles, &s.InchargeOf,
		&s.IsActive, &s.CreatedAt, &s.Photo)
	return s, err
}

// list: ?search=&department_id=&role=&status=&page=&page_size=
func (h *Handler) list(c *gin.Context) {
	where := []string{isStaff}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	switch c.Query("status") {
	case "inactive":
		where = append(where, "NOT u.is_active")
	case "all":
	default:
		where = append(where, "u.is_active")
	}
	if q := strings.TrimSpace(c.Query("search")); q != "" {
		ph := arg("%" + q + "%")
		where = append(where, fmt.Sprintf("(u.name ILIKE %[1]s OR sp.employee_code ILIKE %[1]s OR u.mobile ILIKE %[1]s OR u.username ILIKE %[1]s)", ph))
	}
	if d := request.QueryInt64(c, "department_id"); d != nil {
		where = append(where, "u.department_id = "+arg(*d))
	}
	if role := c.Query("role"); role != "" {
		where = append(where, `EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
			WHERE ur.user_id = u.id AND ur.is_active AND r.slug = `+arg(role)+`)`)
	}
	cond := " WHERE " + strings.Join(where, " AND ")
	p := pagination.FromQuery(c)
	if c.Query("all") == "true" {
		p = pagination.Params{Page: 1, PageSize: 1000}
	}
	var total int64
	if err := h.db.QueryRow(c, `SELECT count(*) FROM users u LEFT JOIN staff_profiles sp ON sp.user_id = u.id AND sp.is_active`+cond, args...).Scan(&total); err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, selectStaff+cond+fmt.Sprintf(" ORDER BY u.name LIMIT %s OFFSET %s", arg(p.PageSize), arg(p.Offset())), args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*Staff{}
	for rows.Next() {
		s, err := scan(rows)
		if err != nil {
			response.Error(c, err)
			return
		}
		out = append(out, s)
	}
	response.List(c, out, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}

func (h *Handler) find(ctx context.Context, id int64) (*Staff, error) {
	s, err := scan(h.db.QueryRow(ctx, selectStaff+" WHERE u.id = $1 AND "+isStaff, id))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Staff member not found")
	}
	return s, err
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	s, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, s)
}

var (
	mobileRe   = regexp.MustCompile(`^[6-9]\d{9}$`)
	usernameRe = regexp.MustCompile(`[^a-z0-9._-]+`)
)

type norm struct {
	Input
	dob, joined *time.Time
}

func (h *Handler) normalize(ctx context.Context, in Input, a actor.Actor) (*norm, error) {
	n := &norm{Input: in}
	n.Name = strings.TrimSpace(in.Name)
	n.EmployeeCode = strings.ToUpper(strings.TrimSpace(in.EmployeeCode))
	n.Mobile, n.Email = trim(in.Mobile), trim(in.Email)
	n.Designation, n.Qualification = trim(in.Designation), trim(in.Qualification)
	if n.Name == "" || n.EmployeeCode == "" {
		return nil, response.BadRequest("Name and employee code are required")
	}
	if n.Mobile != nil && !mobileRe.MatchString(*n.Mobile) {
		return nil, response.BadRequest("Mobile must be a valid 10-digit number")
	}
	n.Username = strings.ToLower(strings.TrimSpace(in.Username))
	if n.Username == "" {
		n.Username = usernameRe.ReplaceAllString(strings.ToLower(n.EmployeeCode), "")
	}
	if len(n.Username) < 3 {
		return nil, response.BadRequest("Username must be at least 3 characters")
	}
	var err error
	if n.dob, err = parseDate(in.DOB, "dob"); err != nil {
		return nil, err
	}
	if n.joined, err = parseDate(in.JoinedOn, "joined_on"); err != nil {
		return nil, err
	}
	if in.DepartmentID != nil && *in.DepartmentID == 0 {
		n.DepartmentID = nil
	}
	if n.DepartmentID != nil {
		var ok bool
		if err := h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1 AND is_active)`, *n.DepartmentID).Scan(&ok); err != nil {
			return nil, err
		}
		if !ok {
			return nil, response.BadRequest("department_id does not exist")
		}
	}
	if len(in.Roles) == 0 {
		n.Roles = []string{"staff"}
	}
	for _, r := range n.Roles {
		if !slices.Contains(StaffRoles, r) {
			return nil, response.BadRequest("roles may only contain staff, hod, placement_officer")
		}
	}
	return n, nil
}

func parseDate(s *string, field string) (*time.Time, error) {
	if s == nil || strings.TrimSpace(*s) == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", strings.TrimSpace(*s))
	if err != nil || t.After(time.Now()) {
		return nil, response.BadRequest(field + " must be a past date in YYYY-MM-DD format")
	}
	return &t, nil
}

// setStaffRoles replaces the user's staff-type roles, leaving non-staff roles (e.g. parent) untouched.
func setStaffRoles(ctx context.Context, tx pgx.Tx, userID int64, roles []string, actorID int64) error {
	if _, err := tx.Exec(ctx, `UPDATE user_roles ur SET is_active = false, updated_by = $3 FROM roles r
		WHERE r.id = ur.role_id AND ur.user_id = $1 AND ur.is_active
		  AND r.slug IN ('staff', 'hod', 'placement_officer') AND NOT (r.slug = ANY($2))`, userID, roles, actorID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_id, created_by, updated_by)
		SELECT $1, r.id, $3, $3 FROM roles r WHERE r.slug = ANY($2) AND r.is_active
		  AND NOT EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = $1 AND ur.role_id = r.id AND ur.is_active)`,
		userID, roles, actorID)
	return err
}

func (h *Handler) create(c *gin.Context) {
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	a := actor.From(c)
	n, err := h.normalize(c, *in, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	var hash *string
	if in.Password != nil && *in.Password != "" {
		hs, err := security.HashPassword(*in.Password)
		if err != nil {
			response.Error(c, err)
			return
		}
		hash = &hs
	}
	var id int64
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		id, err = insertStaff(c, tx, n, hash, a.ID)
		return err
	})
	if err != nil {
		response.Error(c, mapErr(err))
		return
	}
	s, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, s)
}

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	a := actor.From(c)
	n, err := h.normalize(c, *in, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(c, `UPDATE users SET reference_number = $2, name = $3, mobile = $4, email = $5, username = $6,
			department_id = $7, gender = $8, dob = $9, updated_by = $10 WHERE id = $1`,
			id, n.EmployeeCode, n.Name, n.Mobile, n.Email, n.Username, n.DepartmentID, n.Gender, n.dob, a.ID); err != nil {
			return err
		}
		// Upsert the profile: users made via /users may not have one yet.
		tag, err := tx.Exec(c, `UPDATE staff_profiles SET employee_code = $2, designation = $3, qualification = $4, joined_on = $5, updated_by = $6
			WHERE user_id = $1 AND is_active`, id, n.EmployeeCode, n.Designation, n.Qualification, n.joined, a.ID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			if _, err := tx.Exec(c, `INSERT INTO staff_profiles (user_id, employee_code, designation, qualification, joined_on, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $6)`, id, n.EmployeeCode, n.Designation, n.Qualification, n.joined, a.ID); err != nil {
				return err
			}
		}
		if len(in.Roles) > 0 {
			return setStaffRoles(c, tx, id, n.Roles, a.ID)
		}
		return nil
	})
	if err != nil {
		response.Error(c, mapErr(err))
		return
	}
	s, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, s)
}

func (h *Handler) setStatus(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		IsActive *bool `json:"is_active" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("is_active is required"))
		return
	}
	a := actor.From(c)
	if id == a.ID && !*body.IsActive {
		response.Error(c, response.Conflict("You cannot deactivate your own account"))
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	if !*body.IsActive {
		var incharge bool
		if err := h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM classes WHERE class_incharge_id = $1 AND is_active)`, id).Scan(&incharge); err != nil {
			response.Error(c, err)
			return
		}
		if incharge {
			response.Error(c, response.Conflict("This staff member is a class incharge; assign another incharge first"))
			return
		}
	}
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(c, `UPDATE users SET is_active = $2, updated_by = $3 WHERE id = $1`, id, *body.IsActive, a.ID); err != nil {
			return err
		}
		if !*body.IsActive {
			_, err := tx.Exec(c, `UPDATE user_sessions SET revoked_at = now(), is_active = false WHERE user_id = $1 AND revoked_at IS NULL`, id)
			return err
		}
		return nil
	})
	if err != nil {
		response.Error(c, mapErr(err))
		return
	}
	s, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, s)
}

func insertStaff(ctx context.Context, tx pgx.Tx, n *norm, hash *string, actorID int64) (int64, error) {
	var id int64
	if err := tx.QueryRow(ctx, `INSERT INTO users (reference_number, name, mobile, email, username, password_hash, department_id, gender, dob, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10) RETURNING id`,
		n.EmployeeCode, n.Name, n.Mobile, n.Email, n.Username, hash, n.DepartmentID, n.Gender, n.dob, actorID).Scan(&id); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO staff_profiles (user_id, employee_code, designation, qualification, joined_on, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $6)`, id, n.EmployeeCode, n.Designation, n.Qualification, n.joined, actorID); err != nil {
		return 0, err
	}
	return id, setStaffRoles(ctx, tx, id, n.Roles, actorID)
}

// Importer creates staff for the Excel upload with the same rules as the staff form.
type Importer struct{ h *Handler }

func NewImporter(db *pgxpool.Pool) *Importer { return &Importer{h: &Handler{db: db}} }

// CreateInTx validates and inserts one staff member inside the caller's transaction.
func (i *Importer) CreateInTx(ctx context.Context, tx pgx.Tx, a actor.Actor, in Input, hash *string) (int64, error) {
	n, err := i.h.normalize(ctx, in, a)
	if err != nil {
		return 0, err
	}
	id, err := insertStaff(ctx, tx, n, hash, a.ID)
	return id, mapErr(err)
}

func mapErr(err error) error {
	switch dbutil.UniqueViolation(err) {
	case "":
		return err
	case "ux_users_username":
		return response.Conflict("Username is already taken")
	case "ux_users_reference_number", "ux_staff_profiles_code":
		return response.Conflict("A user with this employee code already exists")
	case "ux_users_email":
		return response.Conflict("Email is already in use")
	default:
		return response.Conflict("A record with the same unique value already exists")
	}
}

func trim(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
