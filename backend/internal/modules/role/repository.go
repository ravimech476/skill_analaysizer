package role

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Role struct {
	ID              int64     `json:"id"`
	Name            string    `json:"name"`
	Slug            string    `json:"slug"`
	Description     *string   `json:"description"`
	IsSystem        bool      `json:"is_system"`
	IsActive        bool      `json:"is_active"`
	UserCount       int       `json:"user_count"`
	PermissionCount int       `json:"permission_count"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	PermissionIDs   []int64   `json:"permission_ids,omitempty"`
}

type Repository struct{ db *pgxpool.Pool }

func NewRepository(db *pgxpool.Pool) *Repository { return &Repository{db: db} }

const selectRole = `
	SELECT r.id, r.name, r.slug, r.description, r.is_system, r.is_active,
	       (SELECT count(*) FROM user_roles ur WHERE ur.role_id = r.id AND ur.is_active)::int,
	       (SELECT count(*) FROM role_permissions rp WHERE rp.role_id = r.id AND rp.is_active)::int,
	       r.created_at, r.updated_at
	FROM roles r`

func scanRole(row pgx.Row) (*Role, error) {
	r := &Role{}
	err := row.Scan(&r.ID, &r.Name, &r.Slug, &r.Description, &r.IsSystem, &r.IsActive,
		&r.UserCount, &r.PermissionCount, &r.CreatedAt, &r.UpdatedAt)
	return r, err
}

func (r *Repository) List(ctx context.Context, includeInactive bool) ([]*Role, error) {
	rows, err := r.db.Query(ctx, selectRole+` WHERE r.is_active OR $1 ORDER BY r.id`, includeInactive)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Role{}
	for rows.Next() {
		role, err := scanRole(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, role)
	}
	return out, rows.Err()
}

func (r *Repository) Get(ctx context.Context, id int64) (*Role, error) {
	role, err := scanRole(r.db.QueryRow(ctx, selectRole+` WHERE r.id = $1`, id))
	if err != nil {
		return nil, err
	}
	rows, err := r.db.Query(ctx, `SELECT permission_id FROM role_permissions
		WHERE role_id = $1 AND is_active ORDER BY permission_id`, id)
	if err != nil {
		return nil, err
	}
	role.PermissionIDs, err = pgx.CollectRows(rows, pgx.RowTo[int64])
	return role, err
}

func (r *Repository) Create(ctx context.Context, name, slug string, desc *string, actor int64) (int64, error) {
	var id int64
	err := r.db.QueryRow(ctx, `INSERT INTO roles (name, slug, description, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $4) RETURNING id`, name, slug, desc, actor).Scan(&id)
	return id, err
}

func (r *Repository) Update(ctx context.Context, id int64, name string, desc *string, actor int64) error {
	_, err := r.db.Exec(ctx, `UPDATE roles SET name = $2, description = $3, updated_by = $4 WHERE id = $1`,
		id, name, desc, actor)
	return err
}

func (r *Repository) Deactivate(ctx context.Context, id int64, actor int64) error {
	_, err := r.db.Exec(ctx, `UPDATE roles SET is_active = false, updated_by = $2 WHERE id = $1`, id, actor)
	return err
}

// SetPermissions makes the role's active grants exactly permissionIDs.
func (r *Repository) SetPermissions(ctx context.Context, roleID int64, permissionIDs []int64, actor int64) error {
	if permissionIDs == nil {
		permissionIDs = []int64{} // nil would bind as NULL and "= ANY(NULL)" matches nothing
	}
	return pgx.BeginFunc(ctx, r.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE role_permissions SET is_active = false, updated_by = $3
			WHERE role_id = $1 AND is_active AND NOT (permission_id = ANY($2))`, roleID, permissionIDs, actor); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
			SELECT $1, p.id, $3, $3 FROM permissions p
			WHERE p.id = ANY($2) AND p.is_active
			  AND NOT EXISTS (SELECT 1 FROM role_permissions rp
			                  WHERE rp.role_id = $1 AND rp.permission_id = p.id AND rp.is_active)`,
			roleID, permissionIDs, actor)
		return err
	})
}

func (r *Repository) CountActivePermissions(ctx context.Context, ids []int64) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `SELECT count(*) FROM permissions WHERE id = ANY($1) AND is_active`, ids).Scan(&n)
	return n, err
}
