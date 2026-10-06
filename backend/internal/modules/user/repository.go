package user

import (
	"context"
	"fmt"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
)

type RoleRef struct {
	ID   int64  `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type User struct {
	ID              int64       `json:"id"`
	ReferenceNumber *string     `json:"reference_number"`
	Name            string      `json:"name"`
	Mobile          *string     `json:"mobile"`
	Email           *string     `json:"email"`
	Username        string      `json:"username"`
	DepartmentID    *int64      `json:"department_id"`
	DepartmentName  *string     `json:"department_name"`
	Gender          *string     `json:"gender"`
	DOB             *string     `json:"dob"`
	Photo           *files.Link `json:"photo"`
	HasPassword     bool        `json:"has_password"`
	IsActive        bool        `json:"is_active"`
	LastLoginAt     *time.Time  `json:"last_login_at"`
	CreatedAt       time.Time   `json:"created_at"`
	UpdatedAt       time.Time   `json:"updated_at"`
	Roles           []RoleRef   `json:"roles"`
}

type Filter struct {
	Search       string
	Role         string
	DepartmentID *int64
	Status       string // active (default) | inactive | all
}

// fields shared by create and update
type fields struct {
	ReferenceNumber *string
	Name            string
	Mobile          *string
	Email           *string
	Username        string
	DepartmentID    *int64
	Gender          *string
	DOB             *time.Time
}

type Repository struct{ db *pgxpool.Pool }

func NewRepository(db *pgxpool.Pool) *Repository { return &Repository{db: db} }

const selectUser = `
	SELECT u.id, u.reference_number, u.name, u.mobile, u.email::text, u.username::text,
	       u.department_id, d.name, u.gender, to_char(u.dob, 'YYYY-MM-DD'), file_json(u.photo_file_id),
	       u.password_hash IS NOT NULL, u.is_active, u.last_login_at, u.created_at, u.updated_at
	FROM users u
	LEFT JOIN departments d ON d.id = u.department_id`

func scanUser(row pgx.Row) (*User, error) {
	u := &User{Roles: []RoleRef{}}
	err := row.Scan(&u.ID, &u.ReferenceNumber, &u.Name, &u.Mobile, &u.Email, &u.Username,
		&u.DepartmentID, &u.DepartmentName, &u.Gender, &u.DOB, &u.Photo,
		&u.HasPassword, &u.IsActive, &u.LastLoginAt, &u.CreatedAt, &u.UpdatedAt)
	return u, err
}

func (r *Repository) List(ctx context.Context, f Filter, p pagination.Params) ([]*User, int64, error) {
	where := []string{"true"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }

	switch f.Status {
	case "inactive":
		where = append(where, "NOT u.is_active")
	case "all":
	default:
		where = append(where, "u.is_active")
	}
	if s := strings.TrimSpace(f.Search); s != "" {
		ph := arg("%" + s + "%")
		where = append(where, fmt.Sprintf(`(u.name ILIKE %[1]s OR u.username ILIKE %[1]s OR u.email ILIKE %[1]s
			OR u.mobile ILIKE %[1]s OR u.reference_number ILIKE %[1]s)`, ph))
	}
	if f.DepartmentID != nil {
		where = append(where, "u.department_id = "+arg(*f.DepartmentID))
	}
	if f.Role != "" {
		where = append(where, `EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
			WHERE ur.user_id = u.id AND ur.is_active AND r.slug = `+arg(f.Role)+`)`)
	}
	cond := " WHERE " + strings.Join(where, " AND ")

	var total int64
	if err := r.db.QueryRow(ctx, `SELECT count(*) FROM users u`+cond, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	q := selectUser + cond + fmt.Sprintf(" ORDER BY u.id DESC LIMIT %s OFFSET %s", arg(p.PageSize), arg(p.Offset()))
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	users := []*User{}
	byID := map[int64]*User{}
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, 0, err
		}
		users = append(users, u)
		byID[u.ID] = u
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return users, total, r.attachRoles(ctx, byID)
}

func (r *Repository) Get(ctx context.Context, id int64) (*User, error) {
	u, err := scanUser(r.db.QueryRow(ctx, selectUser+` WHERE u.id = $1`, id))
	if err != nil {
		return nil, err
	}
	return u, r.attachRoles(ctx, map[int64]*User{id: u})
}

// attachRoles loads roles for a page of users in one query (no N+1).
func (r *Repository) attachRoles(ctx context.Context, byID map[int64]*User) error {
	if len(byID) == 0 {
		return nil
	}
	ids := make([]int64, 0, len(byID))
	for id := range byID {
		ids = append(ids, id)
	}
	rows, err := r.db.Query(ctx, `
		SELECT ur.user_id, r.id, r.slug, r.name FROM user_roles ur
		JOIN roles r ON r.id = ur.role_id AND r.is_active
		WHERE ur.user_id = ANY($1) AND ur.is_active ORDER BY r.id`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var uid int64
		var ref RoleRef
		if err := rows.Scan(&uid, &ref.ID, &ref.Slug, &ref.Name); err != nil {
			return err
		}
		byID[uid].Roles = append(byID[uid].Roles, ref)
	}
	return rows.Err()
}

func (r *Repository) Create(ctx context.Context, f fields, passwordHash *string, roleIDs []int64, actor int64) (int64, error) {
	var id int64
	err := pgx.BeginFunc(ctx, r.db, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			INSERT INTO users (reference_number, name, mobile, email, username, password_hash,
			                   department_id, gender, dob, created_by, updated_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10) RETURNING id`,
			f.ReferenceNumber, f.Name, f.Mobile, f.Email, f.Username, passwordHash,
			f.DepartmentID, f.Gender, f.DOB, actor).Scan(&id); err != nil {
			return err
		}
		return setRoles(ctx, tx, id, roleIDs, actor)
	})
	return id, err
}

func (r *Repository) Update(ctx context.Context, id int64, f fields, actor int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET reference_number = $2, name = $3, mobile = $4, email = $5, username = $6,
		       department_id = $7, gender = $8, dob = $9, updated_by = $10
		WHERE id = $1`,
		id, f.ReferenceNumber, f.Name, f.Mobile, f.Email, f.Username, f.DepartmentID, f.Gender, f.DOB, actor)
	return err
}

func (r *Repository) SetActive(ctx context.Context, id int64, active bool, actor int64) error {
	return pgx.BeginFunc(ctx, r.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE users SET is_active = $2, updated_by = $3 WHERE id = $1`, id, active, actor); err != nil {
			return err
		}
		if active {
			return nil
		}
		// Deactivated users are signed out everywhere.
		_, err := tx.Exec(ctx, `UPDATE user_sessions SET revoked_at = now(), is_active = false
			WHERE user_id = $1 AND revoked_at IS NULL`, id)
		return err
	})
}

func (r *Repository) SetRoles(ctx context.Context, id int64, roleIDs []int64, actor int64) error {
	return pgx.BeginFunc(ctx, r.db, func(tx pgx.Tx) error { return setRoles(ctx, tx, id, roleIDs, actor) })
}

func (r *Repository) SetPassword(ctx context.Context, id int64, hash string, actor int64) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET password_hash = $2, updated_by = $3 WHERE id = $1`, id, hash, actor)
	return err
}

func (r *Repository) CountActiveRoles(ctx context.Context, ids []int64) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `SELECT count(*) FROM roles WHERE id = ANY($1) AND is_active`, ids).Scan(&n)
	return n, err
}

func (r *Repository) IncludesRole(ctx context.Context, ids []int64, slug string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM roles WHERE id = ANY($1) AND slug = $2)`, ids, slug).Scan(&ok)
	return ok, err
}

func (r *Repository) DepartmentExists(ctx context.Context, id int64) (bool, error) {
	var ok bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1 AND is_active)`, id).Scan(&ok)
	return ok, err
}

// setRoles makes the user's active roles exactly roleIDs.
func setRoles(ctx context.Context, tx dbutil.DBTX, userID int64, roleIDs []int64, actor int64) error {
	if roleIDs == nil {
		roleIDs = []int64{}
	}
	if _, err := tx.Exec(ctx, `UPDATE user_roles SET is_active = false, updated_by = $3
		WHERE user_id = $1 AND is_active AND NOT (role_id = ANY($2))`, userID, roleIDs, actor); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO user_roles (user_id, role_id, created_by, updated_by)
		SELECT $1, r.id, $3, $3 FROM roles r
		WHERE r.id = ANY($2) AND r.is_active
		  AND NOT EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = $1 AND ur.role_id = r.id AND ur.is_active)`,
		userID, roleIDs, actor)
	return err
}
