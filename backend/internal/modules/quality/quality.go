package quality

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct{ db *pgxpool.Pool }

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache) {
	h := &Handler{db: db}
	r.GET("/reports/data-quality", middleware.RequirePermission(perms, "report.view"), h.report)
}

// report: GET /reports/data-quality?department_id=
// HOD and staff are limited to their own department, like the dashboard.
func (h *Handler) report(c *gin.Context) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("The data quality report is available to staff only"))
		return
	}
	dept := request.QueryInt64(c, "department_id")
	if !a.Has("admin", "placement_officer") {
		var own *int64
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&own); err != nil {
			response.Error(c, err)
			return
		}
		if own != nil {
			dept = own
		}
	}
	var scope *string
	if dept != nil {
		var code string
		if err := h.db.QueryRow(c, `SELECT code FROM departments WHERE id = $1`, *dept).Scan(&code); err != nil {
			response.Error(c, response.BadRequest("department_id does not exist"))
			return
		}
		scope = &code
	}

	total, hits, err := h.run(c, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	rep := Aggregate(total, Checks, hits)
	response.OK(c, gin.H{"scope_department": scope, "generated_at": time.Now(), "report": rep})
}

func (h *Handler) run(ctx context.Context, dept *int64) (int, map[string][]Person, error) {
	var total int
	if err := h.db.QueryRow(ctx, StudentsCTE+` SELECT count(*)::int FROM st`, dept).Scan(&total); err != nil {
		return 0, nil, err
	}
	hits := map[string][]Person{}
	for _, ch := range Checks {
		rows, err := h.db.Query(ctx, StudentsCTE+` SELECT st.id, st.name, st.register_no FROM st WHERE `+ch.Where+` ORDER BY st.register_no`, dept)
		if err != nil {
			return 0, nil, err
		}
		for rows.Next() {
			var p Person
			if err := rows.Scan(&p.ID, &p.Name, &p.RegisterNo); err != nil {
				rows.Close()
				return 0, nil, err
			}
			hits[ch.Key] = append(hits[ch.Key], p)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return 0, nil, err
		}
	}
	return total, hits, nil
}
