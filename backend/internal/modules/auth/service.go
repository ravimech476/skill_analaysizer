package auth

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"skills-analyzer/internal/config"
	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/rbac"
	"skills-analyzer/internal/sms"
)

const (
	purposeLogin = "login"
	purposeReset = "reset_password"
	otpDigits    = 6
)

type ClientInfo struct {
	Device string
	IP     string
}

type Service struct {
	repo   *Repository
	cfg    *config.Config
	tokens *security.TokenManager
	perms  *rbac.Cache
	sms    sms.Sender
	// dummyHash is compared against when the username doesn't exist, so response
	// timing doesn't reveal which usernames are real.
	dummyHash string
	// failures locks an account name for the rest of a 15-minute window after too many wrong passwords.
	failures *middleware.Limiter
}

const maxPasswordFailures = 10

func NewService(repo *Repository, cfg *config.Config, tokens *security.TokenManager, perms *rbac.Cache, sender sms.Sender) (*Service, error) {
	dummy, err := security.HashPassword("timing-equaliser")
	if err != nil {
		return nil, err
	}
	return &Service{repo: repo, cfg: cfg, tokens: tokens, perms: perms, sms: sender, dummyHash: dummy,
		failures: middleware.NewLimiter(maxPasswordFailures, 15*time.Minute)}, nil
}

var errBadCredentials = response.Unauthorized("Invalid username or password")

// ---- password login ----

func (s *Service) Login(ctx context.Context, req LoginRequest, client ClientInfo) (*TokenResponse, error) {
	key := strings.ToLower(strings.TrimSpace(req.Username))
	if ok, wait := s.failures.Peek(key, time.Now()); !ok {
		return nil, response.TooManyRequests(fmt.Sprintf("Too many wrong passwords for this account. Try again in %d minutes, or sign in with OTP.", wait/60+1))
	}
	fail := func() (*TokenResponse, error) {
		s.failures.Allow(key, time.Now())
		return nil, errBadCredentials
	}
	u, err := s.repo.FindByUsernameOrEmail(ctx, strings.TrimSpace(req.Username))
	if dbutil.IsNoRows(err) {
		security.CheckPassword(s.dummyHash, req.Password)
		return fail()
	}
	if err != nil {
		return nil, err
	}
	if u.PasswordHash == nil || !security.CheckPassword(*u.PasswordHash, req.Password) {
		return fail()
	}
	return s.startSession(ctx, u, "password", client)
}

// ---- OTP login ----

func (s *Service) RequestLoginOTP(ctx context.Context, identifier string) (*OTPSentResponse, error) {
	return s.sendOTP(ctx, identifier, purposeLogin)
}

func (s *Service) VerifyLoginOTP(ctx context.Context, req OTPVerifyRequest, client ClientInfo) (*TokenResponse, error) {
	u, err := s.verifyOTP(ctx, req.Identifier, req.OTP, purposeLogin)
	if err != nil {
		return nil, err
	}
	return s.startSession(ctx, u, "otp", client)
}

// ---- forgot / reset password (OTP) ----

func (s *Service) RequestResetOTP(ctx context.Context, identifier string) (*OTPSentResponse, error) {
	return s.sendOTP(ctx, identifier, purposeReset)
}

func (s *Service) ResetPassword(ctx context.Context, req ResetPasswordRequest) error {
	u, err := s.verifyOTP(ctx, req.Identifier, req.OTP, purposeReset)
	if err != nil {
		return err
	}
	hash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}
	if err := s.repo.UpdatePassword(ctx, u.ID, hash); err != nil {
		return err
	}
	return s.repo.RevokeAllSessions(ctx, u.ID) // sign out every device
}

func (s *Service) ChangePassword(ctx context.Context, userID int64, req ChangePasswordRequest) error {
	u, err := s.repo.FindActiveByID(ctx, userID)
	if err != nil {
		return err
	}
	// Users who only ever logged in by OTP have no password yet and may set one directly.
	if u.PasswordHash != nil && !security.CheckPassword(*u.PasswordHash, req.CurrentPassword) {
		return response.BadRequest("Current password is incorrect")
	}
	hash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}
	return s.repo.UpdatePassword(ctx, userID, hash)
}

// ---- tokens ----

func (s *Service) Refresh(ctx context.Context, refreshToken string, client ClientInfo) (*TokenResponse, error) {
	sess, err := s.repo.FindSession(ctx, security.SHA256(refreshToken))
	if dbutil.IsNoRows(err) {
		return nil, response.Unauthorized("Invalid refresh token")
	}
	if err != nil {
		return nil, err
	}
	if sess.RevokedAt != nil {
		// A rotated-out token was replayed: assume theft and kill every session of this user.
		slog.Warn("refresh token reuse detected", "user_id", sess.UserID)
		_ = s.repo.RevokeAllSessions(ctx, sess.UserID)
		return nil, response.Unauthorized("Session expired, please log in again")
	}
	if time.Now().After(sess.ExpiresAt) {
		return nil, response.Unauthorized("Session expired, please log in again")
	}
	revoked, err := s.repo.RevokeSession(ctx, sess.ID)
	if err != nil {
		return nil, err
	}
	if !revoked { // lost a race with a concurrent refresh of the same token
		return nil, response.Unauthorized("Session expired, please log in again")
	}
	u, err := s.repo.FindActiveByID(ctx, sess.UserID)
	if dbutil.IsNoRows(err) {
		return nil, response.Unauthorized("Account is inactive")
	}
	if err != nil {
		return nil, err
	}
	return s.issueTokens(ctx, u, sess.LoginMethod, client)
}

func (s *Service) Logout(ctx context.Context, refreshToken string) error {
	sess, err := s.repo.FindSession(ctx, security.SHA256(refreshToken))
	if dbutil.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return err
	}
	_, err = s.repo.RevokeSession(ctx, sess.ID)
	return err
}

func (s *Service) Me(ctx context.Context, userID int64) (*SessionUser, error) {
	u, err := s.repo.FindActiveByID(ctx, userID)
	if dbutil.IsNoRows(err) {
		return nil, response.Unauthorized("Account is inactive")
	}
	if err != nil {
		return nil, err
	}
	return s.sessionUser(ctx, u)
}

// ---- internals ----

func (s *Service) startSession(ctx context.Context, u *authUser, method string, client ClientInfo) (*TokenResponse, error) {
	resp, err := s.issueTokens(ctx, u, method, client)
	if err != nil {
		return nil, err
	}
	if err := s.repo.TouchLastLogin(ctx, u.ID); err != nil {
		slog.Warn("update last_login_at failed", "user_id", u.ID, "err", err)
	}
	return resp, nil
}

func (s *Service) issueTokens(ctx context.Context, u *authUser, method string, client ClientInfo) (*TokenResponse, error) {
	su, err := s.sessionUser(ctx, u)
	if err != nil {
		return nil, err
	}
	if len(su.Roles) == 0 {
		return nil, response.Forbidden("No role is assigned to this account. Contact the administrator.")
	}
	access, exp, err := s.tokens.Issue(u.ID, u.Name, su.Roles)
	if err != nil {
		return nil, err
	}
	refresh, err := security.RandomToken(32)
	if err != nil {
		return nil, err
	}
	if err := s.repo.CreateSession(ctx, u.ID, security.SHA256(refresh), client.Device, client.IP, method,
		time.Now().Add(s.cfg.RefreshTokenTTL)); err != nil {
		return nil, err
	}
	return &TokenResponse{
		TokenType:            "Bearer",
		AccessToken:          access,
		AccessTokenExpiresAt: exp,
		RefreshToken:         refresh,
		User:                 su,
	}, nil
}

func (s *Service) sessionUser(ctx context.Context, u *authUser) (*SessionUser, error) {
	roles, err := s.repo.RoleSlugs(ctx, u.ID)
	if err != nil {
		return nil, err
	}
	perms, err := s.perms.PermissionsFor(ctx, roles)
	if err != nil {
		return nil, err
	}
	photo, err := s.repo.Photo(ctx, u.ID)
	if err != nil {
		return nil, err
	}
	return &SessionUser{ID: u.ID, Name: u.Name, Username: u.Username, Roles: roles, Permissions: perms, Photo: photo}, nil
}

// resolveOTPUser maps a username or mobile to exactly one active account.
func (s *Service) resolveOTPUser(ctx context.Context, identifier string) (*authUser, error) {
	users, err := s.repo.FindByUsernameOrMobile(ctx, strings.TrimSpace(identifier))
	if err != nil {
		return nil, err
	}
	switch len(users) {
	case 0:
		return nil, nil
	case 1:
		return users[0], nil
	default:
		return nil, response.Conflict("This mobile number is linked to more than one account. Enter your username instead.")
	}
}

func (s *Service) sendOTP(ctx context.Context, identifier, purpose string) (*OTPSentResponse, error) {
	generic := &OTPSentResponse{
		Message:   "If an account exists, an OTP has been sent to its registered mobile number",
		ExpiresIn: int(s.cfg.OTPTTL.Seconds()),
	}
	u, err := s.resolveOTPUser(ctx, identifier)
	if err != nil {
		return nil, err
	}
	if u == nil {
		return generic, nil // don't reveal whether the account exists
	}
	if u.Mobile == nil || *u.Mobile == "" {
		return nil, response.BadRequest("No mobile number is registered for this account. Use password login or contact the administrator.")
	}

	last, err := s.repo.LatestOTPCreatedAt(ctx, u.ID, purpose)
	if err != nil {
		return nil, err
	}
	if last != nil {
		if wait := s.cfg.OTPResendAfter - time.Since(*last); wait > 0 {
			return nil, response.TooManyRequests(fmt.Sprintf("Please wait %d seconds before requesting another OTP", int(wait.Seconds())+1))
		}
	}

	code, err := security.NumericOTP(otpDigits)
	if err != nil {
		return nil, err
	}
	if err := s.repo.CreateOTP(ctx, u.ID, *u.Mobile, s.otpHash(u.ID, purpose, code), purpose,
		time.Now().Add(s.cfg.OTPTTL)); err != nil {
		return nil, err
	}
	msg := fmt.Sprintf("%s is your Skills Analyzer OTP. Valid for %d minutes. Do not share it.", code, int(s.cfg.OTPTTL.Minutes()))
	if err := s.sms.Send(ctx, sms.Message{To: *u.Mobile, Text: msg, OTP: code, Minutes: int(s.cfg.OTPTTL.Minutes())}); err != nil {
		slog.Error("otp sms failed", "user_id", u.ID, "err", err)
		return nil, response.ServiceUnavailable("We could not send the OTP right now. Please try again in a minute or sign in with your password.")
	}

	resp := *generic
	resp.Message = "OTP sent to your registered mobile number"
	resp.MaskedMobile = maskMobile(*u.Mobile)
	if s.cfg.OTPDebug {
		resp.DebugOTP = code
	}
	return &resp, nil
}

func (s *Service) verifyOTP(ctx context.Context, identifier, code, purpose string) (*authUser, error) {
	invalid := response.Unauthorized("Invalid or expired OTP")
	u, err := s.resolveOTPUser(ctx, identifier)
	if err != nil {
		return nil, err
	}
	if u == nil {
		return nil, invalid
	}
	otp, err := s.repo.ActiveOTP(ctx, u.ID, purpose)
	if dbutil.IsNoRows(err) {
		return nil, invalid
	}
	if err != nil {
		return nil, err
	}
	if time.Now().After(otp.ExpiresAt) {
		return nil, invalid
	}
	if otp.Attempts >= s.cfg.OTPMaxAttempts {
		return nil, response.TooManyRequests("Too many wrong attempts. Request a new OTP.")
	}
	if !security.EqualHash(otp.OTPHash, s.otpHash(u.ID, purpose, code)) {
		if err := s.repo.IncrementOTPAttempts(ctx, otp.ID); err != nil {
			return nil, err
		}
		return nil, invalid
	}
	ok, err := s.repo.ConsumeOTP(ctx, otp.ID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, invalid
	}
	return u, nil
}

// otpHash binds the code to user + purpose so a login OTP can't be used to reset a password.
func (s *Service) otpHash(userID int64, purpose, code string) string {
	return security.HMAC(s.cfg.JWTSecret, fmt.Sprintf("%d:%s:%s", userID, purpose, code))
}

func maskMobile(m string) string {
	if len(m) <= 4 {
		return m
	}
	return strings.Repeat("*", len(m)-4) + m[len(m)-4:]
}
