package auth

import (
	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// RegisterPublic mounts endpoints that don't need a token.
func (h *Handler) RegisterPublic(r *gin.RouterGroup) {
	r.POST("/login", h.login)
	r.POST("/otp/request", h.requestOTP)
	r.POST("/otp/verify", h.verifyOTP)
	r.POST("/password/forgot", h.forgotPassword)
	r.POST("/password/reset", h.resetPassword)
	r.POST("/refresh", h.refresh)
	r.POST("/logout", h.logout)
}

// RegisterPrivate mounts endpoints that need a valid access token.
func (h *Handler) RegisterPrivate(r *gin.RouterGroup) {
	r.GET("/me", h.me)
	r.POST("/password/change", h.changePassword)
}

func client(c *gin.Context) ClientInfo {
	return ClientInfo{Device: c.GetHeader("User-Agent"), IP: c.ClientIP()}
}

func (h *Handler) login(c *gin.Context) {
	req, ok := request.Bind[LoginRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.Login(c.Request.Context(), *req, client(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) requestOTP(c *gin.Context) {
	req, ok := request.Bind[OTPRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.RequestLoginOTP(c.Request.Context(), req.Identifier)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) verifyOTP(c *gin.Context) {
	req, ok := request.Bind[OTPVerifyRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.VerifyLoginOTP(c.Request.Context(), *req, client(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) forgotPassword(c *gin.Context) {
	req, ok := request.Bind[OTPRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.RequestResetOTP(c.Request.Context(), req.Identifier)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) resetPassword(c *gin.Context) {
	req, ok := request.Bind[ResetPasswordRequest](c)
	if !ok {
		return
	}
	if err := h.svc.ResetPassword(c.Request.Context(), *req); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Password reset. Please log in with your new password."})
}

func (h *Handler) refresh(c *gin.Context) {
	req, ok := request.Bind[RefreshRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.Refresh(c.Request.Context(), req.RefreshToken, client(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) logout(c *gin.Context) {
	req, ok := request.Bind[RefreshRequest](c)
	if !ok {
		return
	}
	if err := h.svc.Logout(c.Request.Context(), req.RefreshToken); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Logged out"})
}

func (h *Handler) me(c *gin.Context) {
	res, err := h.svc.Me(c.Request.Context(), middleware.UserID(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) changePassword(c *gin.Context) {
	req, ok := request.Bind[ChangePasswordRequest](c)
	if !ok {
		return
	}
	if err := h.svc.ChangePassword(c.Request.Context(), middleware.UserID(c), *req); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Password changed"})
}
