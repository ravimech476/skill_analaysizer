package user

import (
	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup, perms *rbac.Cache) {
	can := func(p string) gin.HandlerFunc { return middleware.RequirePermission(perms, p) }
	r.GET("", can("user.view"), h.list)
	r.GET("/:id", can("user.view"), h.get)
	r.POST("", can("user.create"), h.create)
	r.PUT("/:id", can("user.update"), h.update)
	r.PATCH("/:id/status", can("user.delete"), h.setStatus)
	r.PUT("/:id/roles", can("user.update"), h.setRoles)
	r.PUT("/:id/password", can("user.update"), h.setPassword)
}

func actor(c *gin.Context) Actor { return Actor{ID: middleware.UserID(c), Roles: middleware.Roles(c)} }

// list: GET /users?search=&role=student&department_id=1&status=active|inactive|all&page=1&page_size=20
func (h *Handler) list(c *gin.Context) {
	p := pagination.FromQuery(c)
	f := Filter{
		Search:       c.Query("search"),
		Role:         c.Query("role"),
		DepartmentID: request.QueryInt64(c, "department_id"),
		Status:       c.Query("status"),
	}
	users, total, err := h.svc.List(c.Request.Context(), f, p)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.List(c, users, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	u, err := h.svc.Get(c.Request.Context(), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, u)
}

func (h *Handler) create(c *gin.Context) {
	req, ok := request.Bind[CreateRequest](c)
	if !ok {
		return
	}
	u, err := h.svc.Create(c.Request.Context(), *req, actor(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, u)
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
	u, err := h.svc.Update(c.Request.Context(), id, *req, actor(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, u)
}

func (h *Handler) setStatus(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	req, ok := request.Bind[SetStatusRequest](c)
	if !ok {
		return
	}
	u, err := h.svc.SetStatus(c.Request.Context(), id, *req.IsActive, actor(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, u)
}

func (h *Handler) setRoles(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	req, ok := request.Bind[SetRolesRequest](c)
	if !ok {
		return
	}
	u, err := h.svc.SetRoles(c.Request.Context(), id, req.RoleIDs, actor(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, u)
}

func (h *Handler) setPassword(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	req, ok := request.Bind[SetPasswordRequest](c)
	if !ok {
		return
	}
	if err := h.svc.SetPassword(c.Request.Context(), id, req.Password, actor(c)); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Password updated"})
}
