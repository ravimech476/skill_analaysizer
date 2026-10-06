// Package response gives every endpoint the same JSON envelope:
//
//	{ "success": true,  "data": ..., "meta": {...} }
//	{ "success": false, "error": { "code": "...", "message": "...", "details": ... } }
package response

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
)

type AppError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

func (e *AppError) Error() string { return e.Message }

func BadRequest(msg string, details ...any) *AppError {
	e := &AppError{Status: http.StatusBadRequest, Code: "bad_request", Message: msg}
	if len(details) > 0 {
		e.Details = details[0]
	}
	return e
}
func Unauthorized(msg string) *AppError {
	return &AppError{Status: http.StatusUnauthorized, Code: "unauthorized", Message: msg}
}
func Forbidden(msg string) *AppError {
	return &AppError{Status: http.StatusForbidden, Code: "forbidden", Message: msg}
}
func NotFound(msg string) *AppError {
	return &AppError{Status: http.StatusNotFound, Code: "not_found", Message: msg}
}
func Conflict(msg string) *AppError {
	return &AppError{Status: http.StatusConflict, Code: "conflict", Message: msg}
}
func TooManyRequests(msg string) *AppError {
	return &AppError{Status: http.StatusTooManyRequests, Code: "too_many_requests", Message: msg}
}
func ServiceUnavailable(msg string) *AppError {
	return &AppError{Status: http.StatusServiceUnavailable, Code: "service_unavailable", Message: msg}
}
func TooLarge(msg string) *AppError {
	return &AppError{Status: http.StatusRequestEntityTooLarge, Code: "too_large", Message: msg}
}

type Meta struct {
	Page     int   `json:"page"`
	PageSize int   `json:"page_size"`
	Total    int64 `json:"total"`
}

func OK(c *gin.Context, data any) {
	c.JSON(http.StatusOK, gin.H{"success": true, "data": data})
}

func Created(c *gin.Context, data any) {
	c.JSON(http.StatusCreated, gin.H{"success": true, "data": data})
}

func List(c *gin.Context, data any, meta Meta) {
	c.JSON(http.StatusOK, gin.H{"success": true, "data": data, "meta": meta})
}

// Error writes an AppError as-is; anything else is logged and hidden behind a 500.
func Error(c *gin.Context, err error) {
	var appErr *AppError
	if errors.As(err, &appErr) {
		c.AbortWithStatusJSON(appErr.Status, gin.H{"success": false, "error": appErr})
		return
	}
	slog.Error("unhandled error", "path", c.FullPath(), "err", err)
	c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
		"success": false,
		"error":   AppError{Code: "internal_error", Message: "Something went wrong"},
	})
}
