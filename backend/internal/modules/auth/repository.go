package auth

import (
	"context"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/pkg/dbutil"
)

type authUser struct {
	ID           int64
	Name         string
	Username     string
	Mobile       *string
	PasswordHash *string
}

type session struct {
	ID          int64
	UserID      int64
	LoginMethod string
	ExpiresAt   time.Time
	RevokedAt   *time.Time
}

type otpRow struct {
	ID        int64
	OTPHash   string
	Attempts  int
	ExpiresAt time.Time
	CreatedAt time.Time
}

type Repository struct{ db *pgxpool.Pool }

func NewRepository(db *pgxpool.Pool) *Repository { return &Repository{db: db} }

const userCols = `id, name, username::text, mobile, password_hash`

func scanUser(row pgx.Row) (*authUser, error) {
	u := &authUser{}
	if err := row.Scan(&u.ID, &u.Name, &u.Username, &u.Mobile, &u.PasswordHash); err != nil {
		return nil, err
	}
	return u, nil
}

// Photo returns the user's profile photo link, if any.
func (r *Repository) Photo(ctx context.Context, userID int64) (*files.Link, error) {
	var l *files.Link
	err := r.db.QueryRow(ctx, `SELECT file_json(photo_file_id) FROM users WHERE id = $1`, userID).Scan(&l)
	return l, err
}

// FindByUsernameOrEmail is used for password login.
func (r *Repository) FindByUsernameOrEmail(ctx context.Context, identifier string) (*authUser, error) {
	return scanUser(r.db.QueryRow(ctx, `SELECT `+userCols+` FROM users
		WHERE is_active AND (username = $1::citext OR email = $1::citext) LIMIT 1`, identifier))
}

// FindByUsernameOrMobile is used for OTP flows; may return several users when a mobile is shared.
func (r *Repository) FindByUsernameOrMobile(ctx context.Context, identifier string) ([]*authUser, error) {
	rows, err := r.db.Query(ctx, `SELECT `+userCols+` FROM users
		WHERE is_active AND (username = $1::citext OR mobile = $1)
		ORDER BY (username = $1::citext) DESC, id`, identifier)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*authUser
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
		if strings.EqualFold(u.Username, identifier) { // a username hit is unambiguous
			return out[:1], nil
		}
	}
	return out, rows.Err()
}

func (r *Repository) FindActiveByID(ctx context.Context, id int64) (*authUser, error) {
	return scanUser(r.db.QueryRow(ctx, `SELECT `+userCols+` FROM users WHERE id = $1 AND is_active`, id))
}

func (r *Repository) RoleSlugs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT r.slug FROM user_roles ur JOIN roles r ON r.id = ur.role_id AND r.is_active
		WHERE ur.user_id = $1 AND ur.is_active ORDER BY r.id`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

func (r *Repository) TouchLastLogin(ctx context.Context, userID int64) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET last_login_at = now() WHERE id = $1`, userID)
	return err
}

func (r *Repository) UpdatePassword(ctx context.Context, userID int64, hash string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET password_hash = $2, updated_by = $1 WHERE id = $1`, userID, hash)
	return err
}

// ---- sessions ----

func (r *Repository) CreateSession(ctx context.Context, userID int64, tokenHash, device, ip, method string, expires time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO user_sessions (user_id, refresh_token_hash, device_info, ip_address, login_method, expires_at, created_by)
		VALUES ($1, $2, $3, $4, $5, $6, $1)`, userID, tokenHash, device, ip, method, expires)
	return err
}

func (r *Repository) FindSession(ctx context.Context, tokenHash string) (*session, error) {
	s := &session{}
	err := r.db.QueryRow(ctx, `SELECT id, user_id, login_method, expires_at, revoked_at FROM user_sessions
		WHERE refresh_token_hash = $1`, tokenHash).Scan(&s.ID, &s.UserID, &s.LoginMethod, &s.ExpiresAt, &s.RevokedAt)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// RevokeSession returns false if it was already revoked (lets refresh detect token reuse).
func (r *Repository) RevokeSession(ctx context.Context, id int64) (bool, error) {
	tag, err := r.db.Exec(ctx, `UPDATE user_sessions SET revoked_at = now(), is_active = false
		WHERE id = $1 AND revoked_at IS NULL`, id)
	return tag.RowsAffected() == 1, err
}

func (r *Repository) RevokeAllSessions(ctx context.Context, userID int64) error {
	_, err := r.db.Exec(ctx, `UPDATE user_sessions SET revoked_at = now(), is_active = false
		WHERE user_id = $1 AND revoked_at IS NULL`, userID)
	return err
}

// ---- OTPs ----

func (r *Repository) LatestOTPCreatedAt(ctx context.Context, userID int64, purpose string) (*time.Time, error) {
	var t time.Time
	err := r.db.QueryRow(ctx, `SELECT created_at FROM user_otps WHERE user_id = $1 AND purpose = $2
		ORDER BY created_at DESC LIMIT 1`, userID, purpose).Scan(&t)
	if dbutil.IsNoRows(err) {
		return nil, nil
	}
	return &t, err
}

// CreateOTP retires any still-open OTP for the same purpose, so only the newest code works.
func (r *Repository) CreateOTP(ctx context.Context, userID int64, mobile, hash, purpose string, expires time.Time) error {
	return pgx.BeginFunc(ctx, r.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE user_otps SET is_active = false
			WHERE user_id = $1 AND purpose = $2 AND consumed_at IS NULL AND is_active`, userID, purpose); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO user_otps (user_id, mobile, otp_hash, purpose, expires_at, created_by)
			VALUES ($1, $2, $3, $4, $5, $1)`, userID, mobile, hash, purpose, expires)
		return err
	})
}

func (r *Repository) ActiveOTP(ctx context.Context, userID int64, purpose string) (*otpRow, error) {
	o := &otpRow{}
	err := r.db.QueryRow(ctx, `SELECT id, otp_hash, attempts, expires_at, created_at FROM user_otps
		WHERE user_id = $1 AND purpose = $2 AND is_active AND consumed_at IS NULL
		ORDER BY created_at DESC LIMIT 1`, userID, purpose).
		Scan(&o.ID, &o.OTPHash, &o.Attempts, &o.ExpiresAt, &o.CreatedAt)
	if err != nil {
		return nil, err
	}
	return o, nil
}

func (r *Repository) IncrementOTPAttempts(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, `UPDATE user_otps SET attempts = attempts + 1 WHERE id = $1`, id)
	return err
}

// ConsumeOTP is atomic: returns false if another request consumed it first.
func (r *Repository) ConsumeOTP(ctx context.Context, id int64) (bool, error) {
	tag, err := r.db.Exec(ctx, `UPDATE user_otps SET consumed_at = now(), is_active = false
		WHERE id = $1 AND consumed_at IS NULL`, id)
	return tag.RowsAffected() == 1, err
}
