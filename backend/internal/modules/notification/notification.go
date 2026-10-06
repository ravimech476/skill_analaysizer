// Package notification exposes the inbox, sending notices and device-token registration.
package notification

import (
	"context"
	"fmt"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db     *pgxpool.Pool
	notify *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, n *notify.Service) {
	h := &Handler{db: db, notify: n}
	can := func(p string) gin.HandlerFunc { return middleware.RequirePermission(perms, p) }
	g := r.Group("/notifications")
	// Every signed-in user has an inbox; no extra permission needed to read their own.
	g.GET("", h.inbox)
	g.GET("/unread-count", h.unreadCount)
	g.POST("/read-all", h.readAll)
	g.POST("/:id/read", h.markRead)
	g.DELETE("/:id", h.hide)
	g.POST("", can("notification.create"), h.send)
	g.GET("/sent", can("notification.create"), h.sent)

	r.POST("/device-tokens", h.registerToken)
	r.DELETE("/device-tokens", h.removeToken)
}

type Item struct {
	ID            int64       `json:"id"`
	Title         string      `json:"title"`
	Body          string      `json:"body"`
	Type          string      `json:"type"`
	ReferenceType *string     `json:"reference_type"`
	ReferenceID   *int64      `json:"reference_id"`
	SenderName    *string     `json:"sender_name"`
	IsRead        bool        `json:"is_read"`
	ReadAt        *time.Time  `json:"read_at"`
	CreatedAt     time.Time   `json:"created_at"`
	Attachment    *files.Link `json:"attachment"`
}

// inbox: ?unread_only=true&type=&page=&page_size=
func (h *Handler) inbox(c *gin.Context) {
	a := actor.From(c)
	p := pagination.FromQuery(c)
	where := []string{"r.user_id = $1", "r.is_active", "n.is_active"}
	args := []any{a.ID}
	if c.Query("unread_only") == "true" {
		where = append(where, "NOT r.is_read")
	}
	if t := c.Query("type"); t != "" {
		args = append(args, t)
		where = append(where, fmt.Sprintf("n.type = $%d", len(args)))
	}
	cond := strings.Join(where, " AND ")
	var total, unread int64
	if err := h.db.QueryRow(c, `SELECT count(*) FILTER (WHERE `+cond+`), count(*) FILTER (WHERE r.user_id = $1 AND r.is_active AND n.is_active AND NOT r.is_read)
		FROM notification_recipients r JOIN notifications n ON n.id = r.notification_id WHERE r.user_id = $1`, args...).Scan(&total, &unread); err != nil {
		response.Error(c, err)
		return
	}
	args = append(args, p.PageSize, p.Offset())
	rows, err := h.db.Query(c, `
		SELECT n.id, n.title, n.body, n.type, n.reference_type, n.reference_id, u.name, r.is_read, r.read_at, n.created_at,
		       file_json(n.attachment_file_id)
		FROM notification_recipients r
		JOIN notifications n ON n.id = r.notification_id
		LEFT JOIN users u ON u.id = n.created_by
		WHERE `+cond+fmt.Sprintf(` ORDER BY n.created_at DESC, n.id DESC LIMIT $%d OFFSET $%d`, len(args)-1, len(args)), args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Item])
	if err != nil {
		response.Error(c, err)
		return
	}
	c.JSON(200, gin.H{"success": true, "data": list, "meta": response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total}, "unread": unread})
}

func (h *Handler) unreadCount(c *gin.Context) {
	var n int64
	if err := h.db.QueryRow(c, `SELECT count(*) FROM notification_recipients r JOIN notifications n ON n.id = r.notification_id
		WHERE r.user_id = $1 AND r.is_active AND n.is_active AND NOT r.is_read`, actor.From(c).ID).Scan(&n); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"unread": n})
}

func (h *Handler) markRead(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	tag, err := h.db.Exec(c, `UPDATE notification_recipients SET is_read = true, read_at = COALESCE(read_at, now())
		WHERE notification_id = $1 AND user_id = $2 AND is_active`, id, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if tag.RowsAffected() == 0 {
		response.Error(c, response.NotFound("Notification not found"))
		return
	}
	response.OK(c, gin.H{"message": "Marked as read"})
}

func (h *Handler) readAll(c *gin.Context) {
	tag, err := h.db.Exec(c, `UPDATE notification_recipients SET is_read = true, read_at = now()
		WHERE user_id = $1 AND is_active AND NOT is_read`, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"updated": tag.RowsAffected()})
}

// hide removes a notification from the caller's inbox only.
func (h *Handler) hide(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	tag, err := h.db.Exec(c, `UPDATE notification_recipients SET is_active = false WHERE notification_id = $1 AND user_id = $2 AND is_active`, id, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if tag.RowsAffected() == 0 {
		response.Error(c, response.NotFound("Notification not found"))
		return
	}
	response.OK(c, gin.H{"message": "Removed"})
}

// ---- sending notices ----

type sendBody struct {
	Title          string `json:"title" binding:"required,max=200"`
	Body           string `json:"body" binding:"required,max=4000"`
	Type           string `json:"type" binding:"omitempty,oneof=general placement marks skill"`
	TargetType     string `json:"target_type" binding:"required,oneof=all role department class user"`
	TargetID       *int64 `json:"target_id"`
	IncludeParents bool   `json:"include_parents"`
	// Optional file uploaded with POST /files (category notification_attachment).
	AttachmentFileID *int64 `json:"attachment_file_id"`
}

// checkScope: admin and placement officers can reach anyone; HOD/staff only their own department,
// its classes and its students (plus classes they are incharge of).
func (h *Handler) checkScope(ctx context.Context, a actor.Actor, b *sendBody) error {
	if b.TargetType != "all" && (b.TargetID == nil || *b.TargetID <= 0) {
		return response.BadRequest("target_id is required for this target")
	}
	if a.Has("admin", "placement_officer") {
		return nil
	}
	if b.TargetType == "all" || b.TargetType == "role" {
		return response.Forbidden("Only an admin or placement officer can notify everyone or a whole role")
	}
	var dept *int64
	if err := h.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&dept); err != nil {
		return err
	}
	var ok bool
	var err error
	switch b.TargetType {
	case "department":
		ok = dept != nil && *dept == *b.TargetID
	case "class":
		err = h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM classes WHERE id = $1 AND is_active AND (department_id = $2 OR class_incharge_id = $3))`,
			*b.TargetID, dept, a.ID).Scan(&ok)
	case "user":
		err = h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE id = $1 AND is_active AND department_id = $2)`, *b.TargetID, dept).Scan(&ok)
	}
	if err != nil {
		return err
	}
	if !ok {
		return response.Forbidden("You can only notify your own department, its classes and its students")
	}
	return nil
}

func (h *Handler) send(c *gin.Context) {
	b, ok := request.Bind[sendBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	b.Title, b.Body = strings.TrimSpace(b.Title), strings.TrimSpace(b.Body)
	if b.Title == "" || b.Body == "" {
		response.Error(c, response.BadRequest("Title and message are required"))
		return
	}
	if err := h.checkScope(c, a, b); err != nil {
		response.Error(c, err)
		return
	}
	if b.TargetType == "all" {
		b.TargetID = nil
	}
	ids, err := h.notify.Resolve(c, b.TargetType, b.TargetID, b.IncludeParents)
	if err != nil {
		response.Error(c, err)
		return
	}
	if len(ids) == 0 {
		response.Error(c, response.BadRequest("Nobody matches this target"))
		return
	}
	id, count, err := h.notify.Send(c, notify.Notice{Title: b.Title, Body: b.Body, Type: b.Type, TargetType: b.TargetType, TargetID: b.TargetID, CreatedBy: a.ID,
		AttachmentFileID: b.AttachmentFileID}, ids)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, gin.H{"id": id, "recipients": count})
}

type SentItem struct {
	ID          int64       `json:"id"`
	Title       string      `json:"title"`
	Body        string      `json:"body"`
	Type        string      `json:"type"`
	TargetType  string      `json:"target_type"`
	TargetLabel *string     `json:"target_label"`
	SenderName  *string     `json:"sender_name"`
	Recipients  int         `json:"recipients"`
	ReadCount   int         `json:"read_count"`
	CreatedAt   time.Time   `json:"created_at"`
	Attachment  *files.Link `json:"attachment"`
}

// sent: manual notices sent by the caller (admins see everyone's).
func (h *Handler) sent(c *gin.Context) {
	a := actor.From(c)
	p := pagination.FromQuery(c)
	rows, err := h.db.Query(c, `
		SELECT n.id, n.title, n.body, n.type, n.target_type,
		       CASE n.target_type
		            WHEN 'all' THEN 'Everyone'
		            WHEN 'role' THEN (SELECT name FROM roles WHERE id = n.target_id)
		            WHEN 'department' THEN (SELECT code || ' department' FROM departments WHERE id = n.target_id)
		            WHEN 'class' THEN (SELECT d.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section
		                               FROM classes c JOIN departments d ON d.id = c.department_id JOIN year_levels yl ON yl.id = c.year_level_id WHERE c.id = n.target_id)
		            WHEN 'user' THEN (SELECT name FROM users WHERE id = n.target_id)
		       END,
		       u.name,
		       (SELECT count(*) FROM notification_recipients r WHERE r.notification_id = n.id)::int,
		       (SELECT count(*) FROM notification_recipients r WHERE r.notification_id = n.id AND r.is_read)::int,
		       n.created_at, file_json(n.attachment_file_id)
		FROM notifications n LEFT JOIN users u ON u.id = n.created_by
		WHERE n.is_active AND n.reference_type IS NULL AND ($1 OR n.created_by = $2)
		ORDER BY n.created_at DESC LIMIT $3 OFFSET $4`, a.IsAdmin(), a.ID, p.PageSize, p.Offset())
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := pgx.CollectRows(rows, pgx.RowToStructByPos[SentItem])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// ---- device tokens (mobile push) ----

type tokenBody struct {
	Token    string `json:"token" binding:"required,max=300"`
	Platform string `json:"platform" binding:"omitempty,oneof=android ios web"`
}

// registerToken links a device's Expo push token to the signed-in user (a token moves with whoever last signed in).
func (h *Handler) registerToken(c *gin.Context) {
	b, ok := request.Bind[tokenBody](c)
	if !ok {
		return
	}
	if b.Platform == "" {
		b.Platform = "android"
	}
	a := actor.From(c)
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(c, `UPDATE device_tokens SET is_active = false WHERE token = $1 AND is_active AND user_id <> $2`, b.Token, a.ID); err != nil {
			return err
		}
		_, err := tx.Exec(c, `INSERT INTO device_tokens (user_id, token, platform, created_by, updated_by) VALUES ($1, $2, $3, $1, $1)
			ON CONFLICT (token) WHERE is_active DO UPDATE SET platform = EXCLUDED.platform`, a.ID, b.Token, b.Platform)
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Device registered"})
}

func (h *Handler) removeToken(c *gin.Context) {
	b, ok := request.Bind[tokenBody](c)
	if !ok {
		return
	}
	if _, err := h.db.Exec(c, `UPDATE device_tokens SET is_active = false WHERE token = $1 AND user_id = $2 AND is_active`, b.Token, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Device removed"})
}
