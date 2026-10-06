// Package master is a small config-driven CRUD engine for simple lookup tables
// (departments, academic years, subjects, exam types, …). Each Resource declares its
// columns once; list/get/create/update/deactivate endpoints, validation, FK checks
// and unique-violation messages come for free. Complex modules (classes, students)
// have their own packages.
package master

import (
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Kind int

const (
	String Kind = iota
	Upper       // string stored upper-case (codes)
	Int
	Number
	Bool
	Date // "YYYY-MM-DD"
	FK   // int64 id that must exist (active) in Field.Ref
)

type Field struct {
	Name     string
	Kind     Kind
	Required bool
	Max      int      // max length for strings
	Enum     []string // allowed values for strings
	Ref      string   // FK target table
	Min, Cap *float64 // numeric bounds (inclusive)
	Default  any      // used when the value is omitted
}

type InUse struct {
	SQL     string // must select a row when the record is referenced; $1 = id
	Message string
}

type Resource struct {
	Name    string // singular, for messages ("Department")
	Path    string // "/departments"
	Table   string
	Perm    string // permission module ("department")
	Fields  []Field
	Search  []string // columns matched by ?search=
	OrderBy string
	Extra   []string          // extra select expressions, e.g. "(SELECT name FROM users WHERE id = t.hod_id) AS hod_name"
	Uniques map[string]string // unique index name → user-facing message
	InUse   []InUse
	// ReadOnly exposes only GET endpoints (seeded masters like semesters).
	ReadOnly bool
	// Validate runs after per-field normalisation (e.g. end_date > start_date).
	Validate func(v map[string]any) error
	// BeforeWrite runs inside the write transaction (id = 0 on create).
	BeforeWrite func(ctx context.Context, tx pgx.Tx, id int64, v map[string]any) error
}

func F(n float64) *float64 { return &n }

type Handler struct {
	db  *pgxpool.Pool
	res *Resource
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, res *Resource) {
	h := &Handler{db: db, res: res}
	can := func(action string) gin.HandlerFunc { return middleware.RequirePermission(perms, res.Perm+"."+action) }
	g := r.Group(res.Path)
	g.GET("", can("view"), h.list)
	g.GET("/:id", can("view"), h.get)
	if res.ReadOnly {
		return
	}
	g.POST("", can("create"), h.create)
	g.PUT("/:id", can("update"), h.update)
	g.PATCH("/:id/status", can("delete"), h.setStatus)
	g.DELETE("/:id", can("delete"), h.delete)
}

// ---- reads ----

func (h *Handler) selectSQL() string {
	cols := []string{"t.id"}
	for _, f := range h.res.Fields {
		switch f.Kind {
		case Date:
			cols = append(cols, fmt.Sprintf("to_char(t.%[1]s, 'YYYY-MM-DD') AS %[1]s", f.Name))
		case Number:
			cols = append(cols, fmt.Sprintf("t.%[1]s::float8 AS %[1]s", f.Name))
		case String, Upper:
			cols = append(cols, fmt.Sprintf("t.%[1]s::text AS %[1]s", f.Name))
		default:
			cols = append(cols, "t."+f.Name)
		}
	}
	cols = append(cols, "t.is_active", "t.created_at", "t.updated_at")
	cols = append(cols, h.res.Extra...)
	return "SELECT " + strings.Join(cols, ", ") + " FROM " + h.res.Table + " t"
}

func collect(rows pgx.Rows) ([]map[string]any, error) {
	defer rows.Close()
	out := []map[string]any{}
	fields := rows.FieldDescriptions()
	for rows.Next() {
		vals, err := rows.Values()
		if err != nil {
			return nil, err
		}
		m := make(map[string]any, len(vals))
		for i, v := range vals {
			m[fields[i].Name] = v
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// list: ?search=&status=active|inactive|all&page=&page_size=&all=true and ?<fk/int/bool field>=value filters.
func (h *Handler) list(c *gin.Context) {
	where := []string{"true"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }

	switch c.Query("status") {
	case "inactive":
		where = append(where, "NOT t.is_active")
	case "all":
	default:
		where = append(where, "t.is_active")
	}
	if s := strings.TrimSpace(c.Query("search")); s != "" && len(h.res.Search) > 0 {
		ph := arg("%" + s + "%")
		parts := make([]string, len(h.res.Search))
		for i, col := range h.res.Search {
			parts[i] = fmt.Sprintf("t.%s::text ILIKE %s", col, ph)
		}
		where = append(where, "("+strings.Join(parts, " OR ")+")")
	}
	for _, f := range h.res.Fields {
		q, ok := c.GetQuery(f.Name)
		if !ok || q == "" {
			continue
		}
		switch f.Kind {
		case FK, Int, Bool, Upper, String:
			where = append(where, fmt.Sprintf("t.%s::text = %s", f.Name, arg(q)))
		}
	}
	cond := " WHERE " + strings.Join(where, " AND ")

	p := pagination.FromQuery(c)
	if c.Query("all") == "true" {
		p = pagination.Params{Page: 1, PageSize: 1000}
	}
	var total int64
	if err := h.db.QueryRow(c, "SELECT count(*) FROM "+h.res.Table+" t"+cond, args...).Scan(&total); err != nil {
		response.Error(c, err)
		return
	}
	q := h.selectSQL() + cond + " ORDER BY " + h.res.OrderBy + fmt.Sprintf(" LIMIT %s OFFSET %s", arg(p.PageSize), arg(p.Offset()))
	rows, err := h.db.Query(c, q, args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	data, err := collect(rows)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.List(c, data, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}

func (h *Handler) find(ctx context.Context, id int64) (map[string]any, error) {
	rows, err := h.db.Query(ctx, h.selectSQL()+" WHERE t.id = $1", id)
	if err != nil {
		return nil, err
	}
	data, err := collect(rows)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, response.NotFound(h.res.Name + " not found")
	}
	return data[0], nil
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	row, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, row)
}

// ---- writes ----

func (h *Handler) normalize(ctx context.Context, body map[string]any) (map[string]any, error) {
	out := map[string]any{}
	for _, f := range h.res.Fields {
		raw, present := body[f.Name]
		if !present || raw == nil {
			raw = f.Default
		}
		v, err := normalizeValue(f, raw)
		if err != nil {
			return nil, response.BadRequest(fmt.Sprintf("%s: %s", f.Name, err.Error()))
		}
		if v == nil && f.Required {
			return nil, response.BadRequest(f.Name + " is required")
		}
		if f.Kind == FK && v != nil {
			var ok bool
			if err := h.db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM "+f.Ref+" WHERE id = $1 AND is_active)", v).Scan(&ok); err != nil {
				return nil, err
			}
			if !ok {
				return nil, response.BadRequest(f.Name + " does not exist")
			}
		}
		out[f.Name] = v
	}
	if h.res.Validate != nil {
		if err := h.res.Validate(out); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func normalizeValue(f Field, raw any) (any, error) {
	if raw == nil {
		return nil, nil
	}
	switch f.Kind {
	case String, Upper:
		s, ok := raw.(string)
		if !ok {
			return nil, fmt.Errorf("must be text")
		}
		s = strings.TrimSpace(s)
		if s == "" {
			return nil, nil
		}
		if f.Kind == Upper {
			s = strings.ToUpper(s)
		}
		if f.Max > 0 && len([]rune(s)) > f.Max {
			return nil, fmt.Errorf("must be at most %d characters", f.Max)
		}
		if len(f.Enum) > 0 && !contains(f.Enum, s) {
			return nil, fmt.Errorf("must be one of %s", strings.Join(f.Enum, ", "))
		}
		return s, nil
	case Int, FK:
		n, ok := raw.(float64)
		if !ok || n != math.Trunc(n) {
			return nil, fmt.Errorf("must be a whole number")
		}
		if err := bounds(f, n); err != nil {
			return nil, err
		}
		return int64(n), nil
	case Number:
		n, ok := raw.(float64)
		if !ok {
			return nil, fmt.Errorf("must be a number")
		}
		if err := bounds(f, n); err != nil {
			return nil, err
		}
		return n, nil
	case Bool:
		b, ok := raw.(bool)
		if !ok {
			return nil, fmt.Errorf("must be true or false")
		}
		return b, nil
	case Date:
		s, ok := raw.(string)
		if !ok || strings.TrimSpace(s) == "" {
			return nil, nil
		}
		t, err := time.Parse("2006-01-02", strings.TrimSpace(s))
		if err != nil {
			return nil, fmt.Errorf("must be a date in YYYY-MM-DD format")
		}
		return t, nil
	}
	return nil, fmt.Errorf("unsupported field kind")
}

func bounds(f Field, n float64) error {
	if f.Min != nil && n < *f.Min {
		return fmt.Errorf("must be at least %v", *f.Min)
	}
	if f.Cap != nil && n > *f.Cap {
		return fmt.Errorf("must be at most %v", *f.Cap)
	}
	return nil
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func (h *Handler) mapErr(err error) error {
	if name := dbutil.UniqueViolation(err); name != "" {
		if msg, ok := h.res.Uniques[name]; ok {
			return response.Conflict(msg)
		}
		return response.Conflict("A " + strings.ToLower(h.res.Name) + " with the same value already exists")
	}
	return err
}

func (h *Handler) bindBody(c *gin.Context) (map[string]any, bool) {
	var body map[string]any
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Invalid JSON body"))
		return nil, false
	}
	return body, true
}

func (h *Handler) create(c *gin.Context) {
	body, ok := h.bindBody(c)
	if !ok {
		return
	}
	v, err := h.normalize(c, body)
	if err != nil {
		response.Error(c, err)
		return
	}
	a := actor.From(c)
	cols, ph, args := []string{}, []string{}, []any{}
	for _, f := range h.res.Fields {
		args = append(args, v[f.Name])
		cols = append(cols, f.Name)
		ph = append(ph, fmt.Sprintf("$%d", len(args)))
	}
	args = append(args, a.ID)
	cols = append(cols, "created_by", "updated_by")
	ph = append(ph, fmt.Sprintf("$%d", len(args)), fmt.Sprintf("$%d", len(args)))

	var id int64
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if h.res.BeforeWrite != nil {
			if err := h.res.BeforeWrite(c, tx, 0, v); err != nil {
				return err
			}
		}
		return tx.QueryRow(c, fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s) RETURNING id",
			h.res.Table, strings.Join(cols, ", "), strings.Join(ph, ", ")), args...).Scan(&id)
	})
	if err != nil {
		response.Error(c, h.mapErr(err))
		return
	}
	row, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, row)
}

func (h *Handler) update(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	body, ok := h.bindBody(c)
	if !ok {
		return
	}
	v, err := h.normalize(c, body)
	if err != nil {
		response.Error(c, err)
		return
	}
	sets, args := []string{}, []any{id}
	for _, f := range h.res.Fields {
		args = append(args, v[f.Name])
		sets = append(sets, fmt.Sprintf("%s = $%d", f.Name, len(args)))
	}
	args = append(args, actor.From(c).ID)
	sets = append(sets, fmt.Sprintf("updated_by = $%d", len(args)))

	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if h.res.BeforeWrite != nil {
			if err := h.res.BeforeWrite(c, tx, id, v); err != nil {
				return err
			}
		}
		_, err := tx.Exec(c, fmt.Sprintf("UPDATE %s SET %s WHERE id = $1", h.res.Table, strings.Join(sets, ", ")), args...)
		return err
	})
	if err != nil {
		response.Error(c, h.mapErr(err))
		return
	}
	row, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, row)
}

func (h *Handler) deactivate(ctx context.Context, id, actorID int64) error {
	for _, chk := range h.res.InUse {
		var used bool
		if err := h.db.QueryRow(ctx, "SELECT EXISTS ("+chk.SQL+")", id).Scan(&used); err != nil {
			return err
		}
		if used {
			return response.Conflict(chk.Message)
		}
	}
	_, err := h.db.Exec(ctx, "UPDATE "+h.res.Table+" SET is_active = false, updated_by = $2 WHERE id = $1", id, actorID)
	return err
}

func (h *Handler) delete(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	if err := h.deactivate(c, id, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": h.res.Name + " deleted"})
}

// setStatus: PATCH /:id/status {"is_active": bool} — deactivate (with in-use checks) or restore.
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
	if _, err := h.find(c, id); err != nil {
		response.Error(c, err)
		return
	}
	a := actor.From(c)
	var err error
	if *body.IsActive {
		_, err = h.db.Exec(c, "UPDATE "+h.res.Table+" SET is_active = true, updated_by = $2 WHERE id = $1", id, a.ID)
		err = h.mapErr(err)
	} else {
		err = h.deactivate(c, id, a.ID)
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	row, err := h.find(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, row)
}
