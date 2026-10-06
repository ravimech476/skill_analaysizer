package role

import (
	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup, perms *rbac.Cache) {
	can := func(p string) gin.HandlerFunc { return middleware.RequirePermission(perms, p) }
	r.GET("", can("role.view"), h.list)
	r.GET("/:id", can("role.view"), h.get)
	r.POST("", can("role.create"), h.create)
	r.PUT("/:id", can("role.update"), h.update)
	r.DELETE("/:id", can("role.delete"), h.delete)
	r.PUT("/:id/permissions", can("role.update"), h.setPermissions)
}

func (h *Handler) list(c *gin.Context) {
	res, err := h.svc.List(c.Request.Context(), c.Query("include_inactive") == "true")
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	res, err := h.svc.Get(c.Request.Context(), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) create(c *gin.Context) {
	req, ok := request.Bind[CreateRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.Create(c.Request.Context(), *req, middleware.UserID(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, res)
}

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	req, ok := request.Bind[UpdateRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.Update(c.Request.Context(), id, *req, middleware.UserID(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}

func (h *Handler) delete(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if err := h.svc.Delete(c.Request.Context(), id, middleware.UserID(c)); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Role deleted"})
}

func (h *Handler) setPermissions(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	req, ok := request.Bind[SetPermissionsRequest](c)
	if !ok {
		return
	}
	res, err := h.svc.SetPermissions(c.Request.Context(), id, *req, middleware.UserID(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, res)
}
