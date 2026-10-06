package student

import (
	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup, perms *rbac.Cache) {
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }
	g := r.Group("/students")
	g.GET("", can("student.view"), h.list)
	g.GET("/export.xlsx", can("student.view"), h.exportXLSX)
	g.GET("/:id", can("student.view"), h.get)
	g.POST("", can("student.create"), h.create)
	g.PUT("/:id", can("student.update"), h.update)
	g.PATCH("/:id/status", can("student.delete"), h.setStatus)
	g.POST("/:id/parents", can("student.update", "parent.create"), h.addParent)
	g.DELETE("/:id/parents/:parentId", can("student.update", "parent.delete"), h.removeParent)

	r.GET("/parents", can("parent.view", "student.create", "student.update"), h.listParents)
}

// list: ?search=&department_id=&class_id=&batch=&status=&page=&page_size=
func (h *Handler) list(c *gin.Context) {
	p := pagination.FromQuery(c)
	f := Filter{
		Search:       c.Query("search"),
		DepartmentID: request.QueryInt64(c, "department_id"),
		ClassID:      request.QueryInt64(c, "class_id"),
		Batch:        c.Query("batch"),
		Status:       c.Query("status"),
		Lifecycle:    c.Query("lifecycle"),
	}
	list, total, err := h.svc.List(c, actor.From(c), f, p)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.List(c, list, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	st, err := h.svc.Get(c, actor.From(c), id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, st)
}

func (h *Handler) create(c *gin.Context) {
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	st, err := h.svc.Create(c, actor.From(c), *in)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, st)
}

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	in, ok := request.Bind[Input](c)
	if !ok {
		return
	}
	st, err := h.svc.Update(c, actor.From(c), id, *in)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, st)
}

func (h *Handler) setStatus(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		IsActive *bool `json:"is_active" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("is_active is required"))
		return
	}
	st, err := h.svc.SetStatus(c, actor.From(c), id, *body.IsActive)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, st)
}

func (h *Handler) addParent(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	in, ok := request.Bind[ParentInput](c)
	if !ok {
		return
	}
	st, err := h.svc.AddParent(c, actor.From(c), id, *in)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, st)
}

func (h *Handler) removeParent(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	pid, ok := request.ID(c, "parentId")
	if !ok {
		return
	}
	st, err := h.svc.RemoveParent(c, actor.From(c), id, pid)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, st)
}

func (h *Handler) listParents(c *gin.Context) {
	list, err := h.svc.ListParents(c, c.Query("search"), pagination.FromQuery(c))
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}
