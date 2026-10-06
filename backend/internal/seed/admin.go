package seed

import (
	"context"
	"errors"
	"log/slog"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/config"
	"skills-analyzer/internal/pkg/security"
)

// EnsureAdmin creates the first admin from ADMIN_* env vars when no active admin exists. Idempotent.
func EnsureAdmin(ctx context.Context, db *pgxpool.Pool, cfg *config.Config) error {
	var exists bool
	if err := db.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM user_roles ur
		JOIN roles r ON r.id = ur.role_id AND r.slug = 'admin'
		JOIN users u ON u.id = ur.user_id AND u.is_active
		WHERE ur.is_active)`).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return nil
	}
	if len(cfg.AdminPassword) < 8 {
		return errors.New("no admin exists yet: set ADMIN_PASSWORD (min 8 chars) to create one")
	}
	hash, err := security.HashPassword(cfg.AdminPassword)
	if err != nil {
		return err
	}
	var mobile *string
	if cfg.AdminMobile != "" {
		mobile = &cfg.AdminMobile
	}
	return pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		var id int64
		if err := tx.QueryRow(ctx, `INSERT INTO users (name, username, password_hash, mobile)
			VALUES ($1, $2, $3, $4) RETURNING id`, cfg.AdminName, cfg.AdminUsername, hash, mobile).Scan(&id); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_id, created_by)
			SELECT $1, id, $1 FROM roles WHERE slug = 'admin' AND is_active`, id); err != nil {
			return err
		}
		slog.Info("admin user created", "username", cfg.AdminUsername, "id", id)
		return nil
	})
}
