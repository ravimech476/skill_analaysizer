package auth

import (
	"time"

	"skills-analyzer/internal/files"
)

type LoginRequest struct {
	Username string `json:"username" binding:"required"` // username or email
	Password string `json:"password" binding:"required"`
}

type OTPRequest struct {
	Identifier string `json:"identifier" binding:"required"` // username or mobile number
}

type OTPVerifyRequest struct {
	Identifier string `json:"identifier" binding:"required"`
	OTP        string `json:"otp" binding:"required,len=6,numeric"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password" binding:"required,min=8,max=72"`
}

type ResetPasswordRequest struct {
	Identifier  string `json:"identifier" binding:"required"`
	OTP         string `json:"otp" binding:"required,len=6,numeric"`
	NewPassword string `json:"new_password" binding:"required,min=8,max=72"`
}

type SessionUser struct {
	ID          int64       `json:"id"`
	Name        string      `json:"name"`
	Username    string      `json:"username"`
	Roles       []string    `json:"roles"`
	Permissions []string    `json:"permissions"`
	Photo       *files.Link `json:"photo"`
}

type TokenResponse struct {
	TokenType            string       `json:"token_type"`
	AccessToken          string       `json:"access_token"`
	AccessTokenExpiresAt time.Time    `json:"access_token_expires_at"`
	RefreshToken         string       `json:"refresh_token"`
	User                 *SessionUser `json:"user"`
}

type OTPSentResponse struct {
	Message      string `json:"message"`
	MaskedMobile string `json:"masked_mobile,omitempty"`
	ExpiresIn    int    `json:"expires_in_seconds"`
	DebugOTP     string `json:"debug_otp,omitempty"` // only when OTP_DEBUG=true
}
