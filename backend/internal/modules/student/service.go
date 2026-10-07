package student

import (
	"context"
	"fmt"
	"regexp"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
)

// ---- DTOs ----

type ParentInput struct {
	ID        *int64  `json:"id"` // link an existing parent account instead of name/mobile
	Name      string  `json:"name"`
	Mobile    string  `json:"mobile"`
	Email     *string `json:"email"`
	Relation  string  `json:"relation"` // father | mother | guardian
	IsPrimary bool    `json:"is_primary"`
}

type SkillInput struct {
	Name        string `json:"name" binding:"required,max=100"`
	Proficiency int    `json:"proficiency" binding:"required,min=1,max=5"`
}

type Input struct {
	Name          string        `json:"name" binding:"required,max=150"`
	Username      string        `json:"username"` // defaults to the register number
	Password      *string       `json:"password" binding:"omitempty,min=8,max=72"`
	RegisterNo    string        `json:"register_no" binding:"required,max=50"`
	Mobile        *string       `json:"mobile"`
	Email         *string       `json:"email" binding:"omitempty,email"`
	Gender        *string       `json:"gender" binding:"omitempty,oneof=male female other"`
	DOB           *string       `json:"dob"`
	DepartmentID  int64         `json:"department_id" binding:"required"`
	AdmissionYear int           `json:"admission_year" binding:"required"`
	Batch         string        `json:"batch"` // defaults to "<admission>-<admission+4>"
	ClassID       *int64        `json:"class_id"`
	BloodGroup    *string       `json:"blood_group" binding:"omitempty,max=5"`
	Address       *string       `json:"address"`
	Parents       []ParentInput `json:"parents"` // create only; use the parent endpoints afterwards
	Skills        []SkillInput  `json:"skills"`  // optional, added/updated on create and update
}

type ParentRef struct {
	ID        int64   `json:"id"`
	Name      string  `json:"name"`
	Username  string  `json:"username"`
	Mobile    *string `json:"mobile"`
	Email     *string `json:"email"`
	Relation  string  `json:"relation"`
	IsPrimary bool    `json:"is_primary"`
}

type SkillRef struct {
	SkillID     int64  `json:"skill_id"`
	Name        string `json:"name"`
	Proficiency int    `json:"proficiency"`
}

type Student struct {
	ID             int64       `json:"id"` // = users.id
	Name           string      `json:"name"`
	Username       string      `json:"username"`
	RegisterNo     string      `json:"register_no"`
	Mobile         *string     `json:"mobile"`
	Email          *string     `json:"email"`
	Gender         *string     `json:"gender"`
	DOB            *string     `json:"dob"`
	DepartmentID   *int64      `json:"department_id"`
	DepartmentName *string     `json:"department_name"`
	DepartmentCode *string     `json:"department_code"`
	AdmissionYear  int         `json:"admission_year"`
	Batch          string      `json:"batch"`
	ClassID        *int64      `json:"class_id"`
	ClassLabel     *string     `json:"class_label"`
	InchargeName   *string     `json:"class_incharge_name"`
	CGPA           float64     `json:"cgpa"`
	BacklogCount   int         `json:"backlog_count"`
	BloodGroup     *string     `json:"blood_group"`
	Address        *string     `json:"address"`
	HasPassword    bool        `json:"has_password"`
	IsActive       bool        `json:"is_active"`
	ParentCount    int         `json:"parent_count"`
	Lifecycle      string      `json:"lifecycle_status"` // studying | passed_out | discontinued
	PassedOutYear  *int        `json:"passed_out_year"`
	StatusRemarks  *string     `json:"status_remarks"`
	CreatedAt      time.Time   `json:"created_at"`
	Photo          *files.Link `json:"photo"`
	Resume         *files.Link `json:"resume"`
	Parents        []ParentRef `json:"parents,omitempty"`
	Skills         []SkillRef  `json:"skills,omitempty"`
}

type Filter struct {
	Search       string
	DepartmentID *int64
	ClassID      *int64
	Batch        string
	Status       string
	Lifecycle    string // studying | passed_out | discontinued | "" (any)
}

// ---- service ----

type Service struct{ db *pgxpool.Pool }

func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

var (
	mobileRe   = regexp.MustCompile(`^[6-9]\d{9}$`)
	batchRe    = regexp.MustCompile(`^\d{4}-\d{4}$`)
	usernameRe = regexp.MustCompile(`[^a-z0-9._-]+`)
)

const selectStudent = `
	SELECT u.id, u.name, u.username::text, sp.register_no, u.mobile, u.email::text, u.gender, to_char(u.dob, 'YYYY-MM-DD'),
	       u.department_id, d.name, d.code, sp.admission_year, sp.batch,
	       sp.current_class_id,
	       CASE WHEN c.id IS NULL THEN NULL
	            ELSE cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section END,
	       inc.name,
	       sp.cgpa::float8, sp.backlog_count, sp.blood_group, sp.address,
	       u.password_hash IS NOT NULL, u.is_active,
	       (SELECT count(*) FROM student_parents x WHERE x.student_id = u.id AND x.is_active)::int,
	       sp.lifecycle_status, sp.passed_out_year, sp.status_remarks,
	       sp.created_at, file_json(u.photo_file_id), file_json(sp.resume_file_id)
	FROM student_profiles sp
	JOIN users u              ON u.id = sp.user_id
	LEFT JOIN departments d   ON d.id = u.department_id
	LEFT JOIN classes c       ON c.id = sp.current_class_id
	LEFT JOIN departments cd  ON cd.id = c.department_id
	LEFT JOIN year_levels yl  ON yl.id = c.year_level_id
	LEFT JOIN users inc       ON inc.id = c.class_incharge_id`

func scanStudent(row pgx.Row) (*Student, error) {
	s := &Student{}
	err := row.Scan(&s.ID, &s.Name, &s.Username, &s.RegisterNo, &s.Mobile, &s.Email, &s.Gender, &s.DOB,
		&s.DepartmentID, &s.DepartmentName, &s.DepartmentCode, &s.AdmissionYear, &s.Batch,
		&s.ClassID, &s.ClassLabel, &s.InchargeName, &s.CGPA, &s.BacklogCount, &s.BloodGroup, &s.Address,
		&s.HasPassword, &s.IsActive, &s.ParentCount, &s.Lifecycle, &s.PassedOutYear, &s.StatusRemarks, &s.CreatedAt, &s.Photo, &s.Resume)
	return s, err
}

// scope limits which students an actor may see:
// admin / placement officer → all; HOD / staff → own department (all if none set);
// anyone else (student, parent) → themselves and their linked children.
func (s *Service) scope(ctx context.Context, a actor.Actor, arg func(any) string) (string, error) {
	if a.Has("admin", "placement_officer") {
		return "", nil
	}
	if a.Has("hod", "staff") {
		var dept *int64
		if err := s.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&dept); err != nil {
			return "", err
		}
		if dept == nil {
			return "", nil
		}
		return "u.department_id = " + arg(*dept), nil
	}
	ph := arg(a.ID)
	return fmt.Sprintf("(u.id = %[1]s OR u.id IN (SELECT student_id FROM student_parents WHERE parent_id = %[1]s AND is_active))", ph), nil
}

func (s *Service) List(ctx context.Context, a actor.Actor, f Filter, p pagination.Params) ([]*Student, int64, error) {
	where := []string{"sp.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }

	sc, err := s.scope(ctx, a, arg)
	if err != nil {
		return nil, 0, err
	}
	if sc != "" {
		where = append(where, sc)
	}
	switch f.Status {
	case "inactive":
		where = append(where, "NOT u.is_active")
	case "all":
	default:
		where = append(where, "u.is_active")
	}
	if q := strings.TrimSpace(f.Search); q != "" {
		ph := arg("%" + q + "%")
		where = append(where, fmt.Sprintf("(u.name ILIKE %[1]s OR sp.register_no ILIKE %[1]s OR u.mobile ILIKE %[1]s OR u.username ILIKE %[1]s)", ph))
	}
	if f.DepartmentID != nil {
		where = append(where, "u.department_id = "+arg(*f.DepartmentID))
	}
	if f.ClassID != nil {
		where = append(where, "sp.current_class_id = "+arg(*f.ClassID))
	}
	if f.Batch != "" {
		where = append(where, "sp.batch = "+arg(f.Batch))
	}
	if f.Lifecycle != "" {
		where = append(where, "sp.lifecycle_status = "+arg(f.Lifecycle))
	}
	cond := " WHERE " + strings.Join(where, " AND ")

	var total int64
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM student_profiles sp JOIN users u ON u.id = sp.user_id`+cond, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, selectStudent+cond+fmt.Sprintf(" ORDER BY sp.register_no LIMIT %s OFFSET %s", arg(p.PageSize), arg(p.Offset())), args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []*Student{}
	for rows.Next() {
		st, err := scanStudent(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, st)
	}
	return out, total, rows.Err()
}

// Get returns one student (with parents) if the actor is allowed to see them.
func (s *Service) Get(ctx context.Context, a actor.Actor, id int64) (*Student, error) {
	args := []any{id}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	sc, err := s.scope(ctx, a, arg)
	if err != nil {
		return nil, err
	}
	q := selectStudent + " WHERE sp.is_active AND u.id = $1"
	if sc != "" {
		q += " AND " + sc
	}
	st, err := scanStudent(s.db.QueryRow(ctx, q, args...))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Student not found")
	}
	if err != nil {
		return nil, err
	}
	st.Parents, err = s.parents(ctx, id)
	if err != nil {
		return nil, err
	}
	st.Skills, err = s.skills(ctx, id)
	return st, err
}

func (s *Service) parents(ctx context.Context, studentID int64) ([]ParentRef, error) {
	rows, err := s.db.Query(ctx, `
		SELECT p.id, p.name, p.username::text, p.mobile, p.email::text, x.relation, x.is_primary
		FROM student_parents x JOIN users p ON p.id = x.parent_id
		WHERE x.student_id = $1 AND x.is_active ORDER BY x.is_primary DESC, p.name`, studentID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[ParentRef])
}

func (s *Service) skills(ctx context.Context, studentID int64) ([]SkillRef, error) {
	rows, err := s.db.Query(ctx, `
		SELECT s.id, s.name::text, ss.proficiency
		FROM student_skills ss JOIN skills s ON s.id = ss.skill_id
		WHERE ss.student_id = $1 AND ss.is_active ORDER BY s.name`, studentID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[SkillRef])
}

// ensureSkill finds a skill by name (case-insensitive) or creates it with category "technical".
func ensureSkill(ctx context.Context, tx pgx.Tx, name string, actorID int64) (int64, error) {
	name = strings.TrimSpace(name)
	var id int64
	err := tx.QueryRow(ctx, `SELECT id FROM skills WHERE lower(name::text) = lower($1) AND is_active`, name).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !dbutil.IsNoRows(err) {
		return 0, err
	}
	// Auto-create the skill
	err = tx.QueryRow(ctx, `INSERT INTO skills (name, category, created_by, updated_by) VALUES ($1, 'technical', $2, $2) RETURNING id`,
		name, actorID).Scan(&id)
	return id, err
}

// ---- writes ----

type normalized struct {
	Input
	dob *time.Time
}

func (s *Service) normalize(ctx context.Context, q dbutil.DBTX, in Input) (*normalized, error) {
	n := &normalized{Input: in}
	n.Name = strings.TrimSpace(in.Name)
	n.RegisterNo = strings.ToUpper(strings.TrimSpace(in.RegisterNo))
	n.Mobile = trimPtr(in.Mobile)
	n.Email = trimPtr(in.Email)
	n.BloodGroup = trimPtr(in.BloodGroup)
	n.Address = trimPtr(in.Address)
	if n.Name == "" || n.RegisterNo == "" {
		return nil, response.BadRequest("Name and register number are required")
	}
	if n.Mobile != nil && !mobileRe.MatchString(*n.Mobile) {
		return nil, response.BadRequest("Mobile must be a valid 10-digit number")
	}
	if in.AdmissionYear < 1990 || in.AdmissionYear > time.Now().Year()+1 {
		return nil, response.BadRequest("admission_year is not valid")
	}
	n.Batch = strings.TrimSpace(in.Batch)
	if n.Batch == "" {
		n.Batch = fmt.Sprintf("%d-%d", in.AdmissionYear, in.AdmissionYear+4)
	}
	if !batchRe.MatchString(n.Batch) {
		return nil, response.BadRequest("batch must look like 2023-2027")
	}
	n.Username = strings.ToLower(strings.TrimSpace(in.Username))
	if n.Username == "" {
		n.Username = usernameRe.ReplaceAllString(strings.ToLower(n.RegisterNo), "")
	}
	if len(n.Username) < 3 {
		return nil, response.BadRequest("Username must be at least 3 characters")
	}
	if in.DOB != nil && strings.TrimSpace(*in.DOB) != "" {
		t, err := time.Parse("2006-01-02", strings.TrimSpace(*in.DOB))
		if err != nil || t.After(time.Now()) {
			return nil, response.BadRequest("dob must be a past date in YYYY-MM-DD format")
		}
		n.dob = &t
	}
	var deptOK bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1 AND is_active)`, in.DepartmentID).Scan(&deptOK); err != nil {
		return nil, err
	}
	if !deptOK {
		return nil, response.BadRequest("department_id does not exist")
	}
	if in.ClassID != nil && *in.ClassID == 0 {
		n.ClassID = nil
	}
	if n.ClassID != nil {
		var classDept int64
		err := q.QueryRow(ctx, `SELECT department_id FROM classes WHERE id = $1 AND is_active`, *n.ClassID).Scan(&classDept)
		if dbutil.IsNoRows(err) {
			return nil, response.BadRequest("class_id does not exist")
		}
		if err != nil {
			return nil, err
		}
		if classDept != in.DepartmentID {
			return nil, response.BadRequest("The class belongs to a different department")
		}
	}
	return n, nil
}

// Create adds a student in its own transaction.
func (s *Service) Create(ctx context.Context, a actor.Actor, in Input) (*Student, error) {
	var hash *string
	if in.Password != nil && *in.Password != "" {
		h, err := security.HashPassword(*in.Password)
		if err != nil {
			return nil, err
		}
		hash = &h
	}
	var id int64
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var err error
		id, err = s.CreateInTx(ctx, tx, a.ID, in, hash)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, actor.Actor{ID: a.ID, Roles: []string{"admin"}}, id)
}

// CreateInTx creates user + student role + profile + parent links inside tx.
// passwordHash is pre-computed so bulk upload hashes a shared default password once.
func (s *Service) CreateInTx(ctx context.Context, tx pgx.Tx, actorID int64, in Input, passwordHash *string) (int64, error) {
	n, err := s.normalize(ctx, tx, in)
	if err != nil {
		return 0, err
	}
	// Checked up front: the username defaults to the register number, so the unique-username
	// violation would otherwise surface first with a confusing message.
	var dup bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM student_profiles WHERE register_no = $1 AND is_active)
		OR EXISTS (SELECT 1 FROM users WHERE reference_number = $1 AND is_active)`, n.RegisterNo).Scan(&dup); err != nil {
		return 0, err
	}
	if dup {
		return 0, response.Conflict(fmt.Sprintf("A student with register number %s already exists", n.RegisterNo))
	}
	var id int64
	err = tx.QueryRow(ctx, `
		INSERT INTO users (reference_number, name, mobile, email, username, password_hash, department_id, gender, dob, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10) RETURNING id`,
		n.RegisterNo, n.Name, n.Mobile, n.Email, n.Username, passwordHash, n.DepartmentID, n.Gender, n.dob, actorID).Scan(&id)
	if err != nil {
		return 0, mapWriteErr(err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_id, created_by, updated_by)
		SELECT $1, id, $2, $2 FROM roles WHERE slug = 'student' AND is_active`, id, actorID); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO student_profiles (user_id, register_no, admission_year, batch, current_class_id, blood_group, address, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)`,
		id, n.RegisterNo, n.AdmissionYear, n.Batch, n.ClassID, n.BloodGroup, n.Address, actorID); err != nil {
		return 0, mapWriteErr(err)
	}
	for i, p := range in.Parents {
		if p.ID == nil && strings.TrimSpace(p.Name) == "" && strings.TrimSpace(p.Mobile) == "" {
			continue // blank parent row from a form
		}
		if err := linkParent(ctx, tx, actorID, id, p); err != nil {
			return 0, prefixErr(fmt.Sprintf("Parent %d: ", i+1), err)
		}
	}
	for _, sk := range in.Skills {
		if strings.TrimSpace(sk.Name) == "" {
			continue
		}
		skillID, err := ensureSkill(ctx, tx, sk.Name, actorID)
		if err != nil {
			return 0, err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO student_skills (student_id, skill_id, proficiency, source, created_by, updated_by)
			VALUES ($1, $2, $3, 'manual', $4, $4)
			ON CONFLICT (student_id, skill_id) WHERE is_active DO UPDATE SET proficiency = $3, updated_by = $4`,
			id, skillID, sk.Proficiency, actorID); err != nil {
			return 0, err
		}
	}
	return id, nil
}

func (s *Service) Update(ctx context.Context, a actor.Actor, id int64, in Input) (*Student, error) {
	if _, err := s.Get(ctx, a, id); err != nil {
		return nil, err
	}
	n, err := s.normalize(ctx, s.db, in)
	if err != nil {
		return nil, err
	}
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE users SET reference_number = $2, name = $3, mobile = $4, email = $5, username = $6,
			       department_id = $7, gender = $8, dob = $9, updated_by = $10 WHERE id = $1`,
			id, n.RegisterNo, n.Name, n.Mobile, n.Email, n.Username, n.DepartmentID, n.Gender, n.dob, a.ID); err != nil {
			return mapWriteErr(err)
		}
		if _, err := tx.Exec(ctx, `
			UPDATE student_profiles SET register_no = $2, admission_year = $3, batch = $4, current_class_id = $5,
			       blood_group = $6, address = $7, updated_by = $8 WHERE user_id = $1 AND is_active`,
			id, n.RegisterNo, n.AdmissionYear, n.Batch, n.ClassID, n.BloodGroup, n.Address, a.ID); err != nil {
			return mapWriteErr(err)
		}
		// Replace manual skills: deactivate old ones, insert new ones
		if in.Skills != nil {
			if _, err := tx.Exec(ctx, `UPDATE student_skills SET is_active = false, updated_by = $2 WHERE student_id = $1 AND is_active AND source = 'manual'`, id, a.ID); err != nil {
				return err
			}
			for _, sk := range in.Skills {
				if strings.TrimSpace(sk.Name) == "" {
					continue
				}
				skillID, err := ensureSkill(ctx, tx, sk.Name, a.ID)
				if err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `INSERT INTO student_skills (student_id, skill_id, proficiency, source, created_by, updated_by)
					VALUES ($1, $2, $3, 'manual', $4, $4)
					ON CONFLICT (student_id, skill_id) WHERE is_active DO UPDATE SET proficiency = $3, updated_by = $4`,
					id, skillID, sk.Proficiency, a.ID); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, a, id)
}

func (s *Service) SetStatus(ctx context.Context, a actor.Actor, id int64, active bool) (*Student, error) {
	if _, err := s.Get(ctx, a, id); err != nil {
		return nil, err
	}
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE users SET is_active = $2, updated_by = $3 WHERE id = $1`, id, active, a.ID); err != nil {
			return mapWriteErr(err)
		}
		if !active {
			_, err := tx.Exec(ctx, `UPDATE user_sessions SET revoked_at = now(), is_active = false WHERE user_id = $1 AND revoked_at IS NULL`, id)
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, a, id)
}

func (s *Service) AddParent(ctx context.Context, a actor.Actor, studentID int64, p ParentInput) (*Student, error) {
	if _, err := s.Get(ctx, a, studentID); err != nil {
		return nil, err
	}
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error { return linkParent(ctx, tx, a.ID, studentID, p) })
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, a, studentID)
}

func (s *Service) RemoveParent(ctx context.Context, a actor.Actor, studentID, parentID int64) (*Student, error) {
	if _, err := s.Get(ctx, a, studentID); err != nil {
		return nil, err
	}
	tag, err := s.db.Exec(ctx, `UPDATE student_parents SET is_active = false, updated_by = $3
		WHERE student_id = $1 AND parent_id = $2 AND is_active`, studentID, parentID, a.ID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, response.NotFound("This parent is not linked to the student")
	}
	return s.Get(ctx, a, studentID)
}

// linkParent finds or creates the parent account and links it to the student.
// Matching is by mobile among existing parent accounts, so siblings share one parent login.
func linkParent(ctx context.Context, tx pgx.Tx, actorID, studentID int64, p ParentInput) error {
	rel := strings.ToLower(strings.TrimSpace(p.Relation))
	if rel == "" {
		rel = "guardian"
	}
	if rel != "father" && rel != "mother" && rel != "guardian" {
		return response.BadRequest("relation must be father, mother or guardian")
	}
	parentID, err := upsertParent(ctx, tx, actorID, p)
	if err != nil {
		return err
	}
	if parentID == studentID {
		return response.BadRequest("A student cannot be their own parent")
	}
	var linked bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM student_parents WHERE student_id = $1 AND parent_id = $2 AND is_active)`,
		studentID, parentID).Scan(&linked); err != nil {
		return err
	}
	if linked {
		return response.Conflict("This parent is already linked to the student")
	}
	var hasPrimary bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM student_parents WHERE student_id = $1 AND is_primary AND is_active)`,
		studentID).Scan(&hasPrimary); err != nil {
		return err
	}
	primary := p.IsPrimary || !hasPrimary // first parent becomes primary contact
	if p.IsPrimary && hasPrimary {
		if _, err := tx.Exec(ctx, `UPDATE student_parents SET is_primary = false WHERE student_id = $1 AND is_active`, studentID); err != nil {
			return err
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO student_parents (student_id, parent_id, relation, is_primary, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $5)`, studentID, parentID, rel, primary, actorID)
	return err
}

func upsertParent(ctx context.Context, tx pgx.Tx, actorID int64, p ParentInput) (int64, error) {
	if p.ID != nil {
		var ok bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id AND ur.is_active
			JOIN roles r ON r.id = ur.role_id AND r.slug = 'parent' WHERE u.id = $1 AND u.is_active)`, *p.ID).Scan(&ok); err != nil {
			return 0, err
		}
		if !ok {
			return 0, response.BadRequest("Selected parent account does not exist")
		}
		return *p.ID, nil
	}
	name, mobile := strings.TrimSpace(p.Name), strings.TrimSpace(p.Mobile)
	if name == "" || !mobileRe.MatchString(mobile) {
		return 0, response.BadRequest("Parent name and a valid 10-digit mobile are required")
	}
	rows, err := tx.Query(ctx, `SELECT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id AND ur.is_active
		JOIN roles r ON r.id = ur.role_id AND r.slug = 'parent' WHERE u.mobile = $1 AND u.is_active`, mobile)
	if err != nil {
		return 0, err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[int64])
	if err != nil {
		return 0, err
	}
	switch len(ids) {
	case 1:
		return ids[0], nil // existing parent (e.g. a sibling's) — reuse the account
	case 0:
	default:
		return 0, response.Conflict(fmt.Sprintf("More than one parent account uses mobile %s; pick the parent explicitly", mobile))
	}

	// New parent account: username p<mobile>, suffixed if taken.
	username := "p" + mobile
	for i := 2; ; i++ {
		var taken bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE username = $1::citext AND is_active)`, username).Scan(&taken); err != nil {
			return 0, err
		}
		if !taken {
			break
		}
		username = fmt.Sprintf("p%s_%d", mobile, i)
	}
	var id int64
	if err := tx.QueryRow(ctx, `INSERT INTO users (name, mobile, email, username, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $5) RETURNING id`, name, mobile, trimPtr(p.Email), username, actorID).Scan(&id); err != nil {
		return 0, mapWriteErr(err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_id, created_by, updated_by)
		SELECT $1, id, $2, $2 FROM roles WHERE slug = 'parent' AND is_active`, id, actorID); err != nil {
		return 0, err
	}
	return id, nil
}

// ---- parent directory (for "link existing parent" pickers) ----

type ParentListItem struct {
	ID       int64    `json:"id"`
	Name     string   `json:"name"`
	Username string   `json:"username"`
	Mobile   *string  `json:"mobile"`
	Email    *string  `json:"email"`
	Children []string `json:"children"`
}

func (s *Service) ListParents(ctx context.Context, search string, p pagination.Params) ([]ParentListItem, error) {
	rows, err := s.db.Query(ctx, `
		SELECT u.id, u.name, u.username::text, u.mobile, u.email::text,
		       COALESCE(array_agg(c.name ORDER BY c.name) FILTER (WHERE c.id IS NOT NULL), '{}')
		FROM users u
		JOIN user_roles ur ON ur.user_id = u.id AND ur.is_active
		JOIN roles r ON r.id = ur.role_id AND r.slug = 'parent'
		LEFT JOIN student_parents x ON x.parent_id = u.id AND x.is_active
		LEFT JOIN users c ON c.id = x.student_id AND c.is_active
		WHERE u.is_active AND ($1 = '' OR u.name ILIKE '%' || $1 || '%' OR u.mobile ILIKE '%' || $1 || '%' OR u.username ILIKE '%' || $1 || '%')
		GROUP BY u.id ORDER BY u.name LIMIT $2 OFFSET $3`, strings.TrimSpace(search), p.PageSize, p.Offset())
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[ParentListItem])
}

// ---- helpers ----

func mapWriteErr(err error) error {
	switch dbutil.UniqueViolation(err) {
	case "":
		return err
	case "ux_users_username":
		return response.Conflict("Username is already taken")
	case "ux_users_reference_number", "ux_student_profiles_register":
		return response.Conflict("A user with this register number already exists")
	case "ux_users_email":
		return response.Conflict("Email is already in use")
	default:
		return response.Conflict("A record with the same unique value already exists")
	}
}

func prefixErr(prefix string, err error) error {
	if ae, ok := err.(*response.AppError); ok {
		cp := *ae
		cp.Message = prefix + cp.Message
		return &cp
	}
	return err
}

func trimPtr(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
