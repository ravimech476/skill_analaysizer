// Package career holds the career catalogue — roles a student can aim at whether or not a
// company is hiring right now — and matches each student against it using their blended
// skill scores, reporting what is missing and which course closes the gap.
package career

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	notify   *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, students: students, notify: n}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	g := r.Group("/careers")
	g.GET("", can("career.view"), h.list)
	g.GET("/domains", can("career.view"), h.domains)
	g.GET("/:id", can("career.view"), h.get)
	g.GET("/:id/courses", can("career.view"), h.careerCourses)
	g.POST("", can("career.create"), h.create)
	g.PUT("/:id", can("career.update"), h.update)
	g.DELETE("/:id", can("career.delete"), h.remove)

	r.GET("/students/:id/career-matches", can("career.view"), h.studentMatches)
	r.POST("/students/:id/career-matches", can("career.run"), h.runStudentMatches)
	r.POST("/students/:id/career-matches/:careerId/feedback", can("career.view"), h.feedback)
}

// ---- catalogue ----

type CareerSkill struct {
	SkillID       int64   `json:"skill_id"`
	SkillName     string  `json:"skill_name"`
	Category      string  `json:"category"`
	RequiredLevel int     `json:"required_level"`
	Weight        float64 `json:"weight"`
	IsCore        bool    `json:"is_core"`
}

type Career struct {
	ID          int64         `json:"id"`
	Code        string        `json:"code"`
	Name        string        `json:"name"`
	Domain      *string       `json:"domain"`
	Description *string       `json:"description"`
	AvgPackage  *float64      `json:"avg_package"`
	MinCGPA     float64       `json:"min_cgpa"`
	IsActive    bool          `json:"is_active"`
	CreatedAt   time.Time     `json:"created_at"`
	CourseCount int           `json:"course_count"`
	Skills      []CareerSkill `json:"skills"`
}

const selectCareer = `
	SELECT c.id, c.code, c.name, c.domain, c.description, c.avg_package::float8, c.min_cgpa::float8, c.is_active, c.created_at,
	       (SELECT count(DISTINCT co.id) FROM career_skills cs JOIN courses co ON co.skill_id = cs.skill_id AND co.is_active
	          WHERE cs.career_id = c.id AND cs.is_active)::int
	FROM careers c`

func scanCareer(row pgx.Row) (*Career, error) {
	ca := &Career{Skills: []CareerSkill{}}
	err := row.Scan(&ca.ID, &ca.Code, &ca.Name, &ca.Domain, &ca.Description, &ca.AvgPackage, &ca.MinCGPA,
		&ca.IsActive, &ca.CreatedAt, &ca.CourseCount)
	return ca, err
}

// attach loads required skills for a set of careers in one query.
func (h *Handler) attach(ctx context.Context, list []*Career) error {
	if len(list) == 0 {
		return nil
	}
	byID := map[int64]*Career{}
	ids := []int64{}
	for _, ca := range list {
		byID[ca.ID] = ca
		ids = append(ids, ca.ID)
	}
	rows, err := h.db.Query(ctx, `SELECT cs.career_id, s.id, s.name::text, s.category, cs.required_level, cs.weight::float8, cs.is_core
		FROM career_skills cs JOIN skills s ON s.id = cs.skill_id
		WHERE cs.career_id = ANY($1) AND cs.is_active
		ORDER BY cs.is_core DESC, cs.weight DESC, s.name`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cid int64
		var s CareerSkill
		if err := rows.Scan(&cid, &s.SkillID, &s.SkillName, &s.Category, &s.RequiredLevel, &s.Weight, &s.IsCore); err != nil {
			return err
		}
		byID[cid].Skills = append(byID[cid].Skills, s)
	}
	return rows.Err()
}

func (h *Handler) find(ctx context.Context, id int64) (*Career, error) {
	ca, err := scanCareer(h.db.QueryRow(ctx, selectCareer+` WHERE c.id = $1 AND c.is_active`, id))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Career not found")
	}
	if err != nil {
		return nil, err
	}
	return ca, h.attach(ctx, []*Career{ca})
}

// list: GET /careers?search=&domain=
func (h *Handler) list(c *gin.Context) {
	where := []string{"c.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	if s := strings.TrimSpace(c.Query("search")); s != "" {
		ph := arg("%" + s + "%")
		where = append(where, fmt.Sprintf("(c.name ILIKE %[1]s OR c.code ILIKE %[1]s OR c.domain ILIKE %[1]s)", ph))
	}
	if d := strings.TrimSpace(c.Query("domain")); d != "" {
		where = append(where, "c.domain = "+arg(d))
	}
	rows, err := h.db.Query(c, selectCareer+" WHERE "+strings.Join(where, " AND ")+" ORDER BY c.domain NULLS LAST, c.name", args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*Career{}
	for rows.Next() {
		ca, err := scanCareer(rows)
		if err != nil {
			response.Error(c, err)
			return
		}
		out = append(out, ca)
	}
	rows.Close()
	if err := h.attach(c, out); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, out)
}

func (h *Handler) domains(c *gin.Context) {
	rows, err := h.db.Query(c, `SELECT DISTINCT domain FROM careers WHERE is_active AND domain IS NOT NULL ORDER BY domain`)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	ca, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, ca)
}

type Course struct {
	ID              int64   `json:"id"`
	SkillID         int64   `json:"skill_id"`
	SkillName       string  `json:"skill_name"`
	Title           string  `json:"title"`
	Provider        *string `json:"provider"`
	URL             *string `json:"url"`
	Level           int     `json:"level"`
	DurationHours   *int    `json:"duration_hours"`
	IsCertification bool    `json:"is_certification"`
	IsFree          bool    `json:"is_free"`
}

// careerCourses lists what a student could study for this career, hardest requirement first.
func (h *Handler) careerCourses(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, `
		SELECT co.id, co.skill_id, s.name::text, co.title, co.provider, co.url, co.level, co.duration_hours,
		       co.is_certification, co.is_free
		FROM career_skills cs
		JOIN courses co ON co.skill_id = cs.skill_id AND co.is_active
		JOIN skills s ON s.id = co.skill_id
		WHERE cs.career_id = $1 AND cs.is_active
		ORDER BY cs.is_core DESC, cs.weight DESC, s.name, co.level`, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Course])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// ---- writes ----

type careerInput struct {
	Code        string   `json:"code" binding:"required,max=30"`
	Name        string   `json:"name" binding:"required,max=150"`
	Domain      *string  `json:"domain" binding:"omitempty,max=80"`
	Description *string  `json:"description"`
	AvgPackage  *float64 `json:"avg_package" binding:"omitempty,gte=0,lte=500"`
	MinCGPA     float64  `json:"min_cgpa" binding:"gte=0,lte=10"`
	Skills      []struct {
		SkillID       int64   `json:"skill_id" binding:"required"`
		RequiredLevel int     `json:"required_level" binding:"required,min=1,max=5"`
		Weight        float64 `json:"weight" binding:"omitempty,gt=0,lte=10"`
		IsCore        bool    `json:"is_core"`
	} `json:"skills" binding:"dive"`
}

func (h *Handler) save(c *gin.Context, id int64) {
	in, ok := request.Bind[careerInput](c)
	if !ok {
		return
	}
	in.Code = strings.ToUpper(strings.TrimSpace(in.Code))
	in.Name = strings.TrimSpace(in.Name)
	if in.Code == "" || in.Name == "" {
		response.Error(c, response.BadRequest("code and name are required"))
		return
	}
	skillIDs := []int64{}
	seen := map[int64]bool{}
	for i := range in.Skills {
		if seen[in.Skills[i].SkillID] {
			response.Error(c, response.BadRequest("A skill is listed twice"))
			return
		}
		seen[in.Skills[i].SkillID] = true
		skillIDs = append(skillIDs, in.Skills[i].SkillID)
		if in.Skills[i].Weight == 0 {
			in.Skills[i].Weight = 1
		}
	}
	var skillCount int
	if err := h.db.QueryRow(c, `SELECT count(*)::int FROM skills WHERE id = ANY($1) AND is_active`, skillIDs).Scan(&skillCount); err != nil {
		response.Error(c, err)
		return
	}
	if skillCount != len(skillIDs) {
		response.Error(c, response.BadRequest("One or more skill_ids are invalid"))
		return
	}
	a := actor.From(c)
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if id == 0 {
			if err := tx.QueryRow(c, `INSERT INTO careers (code, name, domain, description, avg_package, min_cgpa, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id`,
				in.Code, in.Name, in.Domain, in.Description, in.AvgPackage, in.MinCGPA, a.ID).Scan(&id); err != nil {
				return err
			}
		} else if _, err := tx.Exec(c, `UPDATE careers SET code = $2, name = $3, domain = $4, description = $5,
			avg_package = $6, min_cgpa = $7, updated_by = $8 WHERE id = $1`,
			id, in.Code, in.Name, in.Domain, in.Description, in.AvgPackage, in.MinCGPA, a.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(c, `UPDATE career_skills SET is_active = false, updated_by = $2
			WHERE career_id = $1 AND is_active`, id, a.ID); err != nil {
			return err
		}
		for _, s := range in.Skills {
			if _, err := tx.Exec(c, `INSERT INTO career_skills (career_id, skill_id, required_level, weight, is_core, created_by, updated_by)
				VALUES ($1, $2, $3, $4, $5, $6, $6)`, id, s.SkillID, s.RequiredLevel, s.Weight, s.IsCore, a.ID); err != nil {
				return err
			}
		}
		// Stored matches were computed against the old requirements.
		_, err := tx.Exec(c, `DELETE FROM career_matches WHERE career_id = $1`, id)
		return err
	})
	if err != nil {
		if dbutil.UniqueViolation(err) == "ux_careers_code" {
			response.Error(c, response.Conflict("A career with this code already exists"))
			return
		}
		response.Error(c, err)
		return
	}
	ca, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, ca)
}

func (h *Handler) create(c *gin.Context) { h.save(c, 0) }

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	h.save(c, id)
}

func (h *Handler) remove(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	a := actor.From(c)
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(c, `UPDATE careers SET is_active = false, updated_by = $2 WHERE id = $1`, id, a.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(c, `UPDATE career_skills SET is_active = false, updated_by = $2
			WHERE career_id = $1 AND is_active`, id, a.ID); err != nil {
			return err
		}
		_, err := tx.Exec(c, `DELETE FROM career_matches WHERE career_id = $1`, id) // derived
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Career deleted"})
}
