// Package permission exposes the permission catalogue. Permissions are defined in
// migrations (middleware checks their slugs in code), so the API is read-only.
package permission

import (
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Permission struct {
	ID          int64   `json:"id"`
	Module      string  `json:"module"`
	Action      string  `json:"action"`
	Slug        string  `json:"slug"`
	Description *string `json:"description"`
}

type Group struct {
	Module      string        `json:"module"`
	Permissions []*Permission `json:"permissions"`
}

type Handler struct{ db *pgxpool.Pool }

func NewHandler(db *pgxpool.Pool) *Handler { return &Handler{db: db} }

func (h *Handler) Register(r *gin.RouterGroup, perms *rbac.Cache) {
	r.GET("", middleware.RequirePermission(perms, "permission.view", "role.view"), h.list)
}

// list returns permissions grouped by module (?flat=true for a plain array), ready for a role-matrix UI.
func (h *Handler) list(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT id, module, action, slug, description FROM permissions WHERE is_active
		ORDER BY module, CASE action WHEN 'view' THEN 1 WHEN 'create' THEN 2 WHEN 'update' THEN 3 WHEN 'delete' THEN 4 ELSE 5 END`)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByPos[Permission])
	if err != nil {
		response.Error(c, err)
		return
	}
	if c.Query("flat") == "true" {
		response.OK(c, list)
		return
	}
	groups := []*Group{}
	for _, p := range list {
		if len(groups) == 0 || groups[len(groups)-1].Module != p.Module {
			groups = append(groups, &Group{Module: p.Module})
		}
		g := groups[len(groups)-1]
		g.Permissions = append(g.Permissions, p)
	}
	response.OK(c, groups)
}
