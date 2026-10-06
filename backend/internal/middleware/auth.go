package middleware

import (
	"slices"
	"strings"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/rbac"
)

const (
	ctxUserID = actor.CtxUserID
	ctxRoles  = actor.CtxRoles
)

// Auth requires a valid "Authorization: Bearer <access token>".
func Auth(tokens *security.TokenManager) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		raw, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || raw == "" {
			response.Error(c, response.Unauthorized("Missing bearer token"))
			return
		}
		claims, err := tokens.Parse(raw)
		if err != nil {
			response.Error(c, response.Unauthorized("Invalid or expired token"))
			return
		}
		c.Set(ctxUserID, claims.UserID)
		c.Set(ctxRoles, claims.Roles)
		c.Next()
	}
}

// RequirePermission passes if the user's roles grant ANY of the given permission slugs.
func RequirePermission(cache *rbac.Cache, perms ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		ok, err := cache.HasAny(c.Request.Context(), Roles(c), perms...)
		if err != nil {
			response.Error(c, err)
			return
		}
		if !ok {
			response.Error(c, response.Forbidden("You do not have permission to perform this action"))
			return
		}
		c.Next()
	}
}

func UserID(c *gin.Context) int64 {
	id, _ := c.Get(ctxUserID)
	v, _ := id.(int64)
	return v
}

func Roles(c *gin.Context) []string {
	r, _ := c.Get(ctxRoles)
	v, _ := r.([]string)
	return v
}

func HasRole(c *gin.Context, role string) bool { return slices.Contains(Roles(c), role) }
