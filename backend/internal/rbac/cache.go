// Package rbac resolves role slugs → permission slugs, cached in memory.
// Roles travel in the JWT; permissions are looked up here so edits to a role's
// permissions take effect immediately (Invalidate) instead of at token expiry.
package rbac

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const AdminRole = "admin"

type Cache struct {
	db       *pgxpool.Pool
	ttl      time.Duration
	mu       sync.RWMutex
	byRole   map[string]map[string]struct{}
	loadedAt time.Time
}

func NewCache(db *pgxpool.Pool) *Cache {
	return &Cache{db: db, ttl: 5 * time.Minute}
}

// Invalidate forces a reload on next lookup; call after any role/permission change.
func (c *Cache) Invalidate() {
	c.mu.Lock()
	c.loadedAt = time.Time{}
	c.mu.Unlock()
}

func (c *Cache) load(ctx context.Context) (map[string]map[string]struct{}, error) {
	c.mu.RLock()
	if time.Since(c.loadedAt) < c.ttl {
		m := c.byRole
		c.mu.RUnlock()
		return m, nil
	}
	c.mu.RUnlock()

	rows, err := c.db.Query(ctx, `
		SELECT r.slug, p.slug
		FROM role_permissions rp
		JOIN roles r       ON r.id = rp.role_id       AND r.is_active
		JOIN permissions p ON p.id = rp.permission_id AND p.is_active
		WHERE rp.is_active`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	m := map[string]map[string]struct{}{}
	for rows.Next() {
		var role, perm string
		if err := rows.Scan(&role, &perm); err != nil {
			return nil, err
		}
		if m[role] == nil {
			m[role] = map[string]struct{}{}
		}
		m[role][perm] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	c.mu.Lock()
	c.byRole, c.loadedAt = m, time.Now()
	c.mu.Unlock()
	return m, nil
}

// HasAny reports whether any of the roles grants any of the permissions. Admin always passes.
func (c *Cache) HasAny(ctx context.Context, roles []string, perms ...string) (bool, error) {
	for _, r := range roles {
		if r == AdminRole {
			return true, nil
		}
	}
	m, err := c.load(ctx)
	if err != nil {
		return false, err
	}
	for _, r := range roles {
		for _, p := range perms {
			if _, ok := m[r][p]; ok {
				return true, nil
			}
		}
	}
	return false, nil
}

// PermissionsFor returns the union of permission slugs granted to the roles.
func (c *Cache) PermissionsFor(ctx context.Context, roles []string) ([]string, error) {
	m, err := c.load(ctx)
	if err != nil {
		return nil, err
	}
	set := map[string]struct{}{}
	for _, r := range roles {
		for p := range m[r] {
			set[p] = struct{}{}
		}
	}
	out := make([]string, 0, len(set))
	for p := range set {
		out = append(out, p)
	}
	return out, nil
}
