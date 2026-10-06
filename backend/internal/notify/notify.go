// Package notify stores in-app notifications and (optionally) sends mobile push via Expo.
// Other modules call Service.Send / SendSafe after their own transaction commits; a failed
// notification never fails the business action that triggered it.
package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"skills-analyzer/internal/files"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	TypeGeneral   = "general"
	TypePlacement = "placement"
	TypeMarks     = "marks"
	TypeSkill     = "skill"
	TypeSystem    = "system"
)

type Notice struct {
	Title      string
	Body       string
	Type       string
	TargetType string // all | role | department | class | user
	TargetID   *int64
	RefType    *string // what triggered it: job_role_open, job_role, marks, skill …
	RefID      *int64
	CreatedBy  int64
	// AttachmentFileID: an upload (category notification_attachment) by CreatedBy, attached in the same transaction.
	AttachmentFileID *int64
}

type Service struct {
	db   *pgxpool.Pool
	push *ExpoPusher // nil = push disabled
}

func New(db *pgxpool.Pool, push *ExpoPusher) *Service { return &Service{db: db, push: push} }

func Ref(kind string, id int64) (*string, *int64) { return &kind, &id }

// Send stores one notification for all recipients (deduplicated) and queues push. Returns id and recipient count.
func (s *Service) Send(ctx context.Context, n Notice, userIDs []int64) (int64, int, error) {
	ids := uniq(userIDs)
	if len(ids) == 0 {
		return 0, 0, nil
	}
	if n.Type == "" {
		n.Type = TypeGeneral
	}
	if n.TargetType == "" {
		n.TargetType = "user"
	}
	var id int64
	var count int64
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO notifications (title, body, type, target_type, target_id, reference_type, reference_id,
			attachment_file_id, created_by, updated_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9) RETURNING id`,
			n.Title, n.Body, n.Type, n.TargetType, n.TargetID, n.RefType, n.RefID, n.AttachmentFileID, nullID(n.CreatedBy)).Scan(&id); err != nil {
			return err
		}
		if n.AttachmentFileID != nil {
			if err := files.Attach(ctx, tx, *n.AttachmentFileID, n.CreatedBy, "notification_attachment", "notifications", id); err != nil {
				return err
			}
		}
		pushStatus := "skipped"
		if s.push != nil {
			pushStatus = "pending"
		}
		tag, err := tx.Exec(ctx, `INSERT INTO notification_recipients (notification_id, user_id, push_status, created_by, updated_by)
			SELECT $1, u.id, $3, $4, $4 FROM users u WHERE u.id = ANY($2) AND u.is_active`, id, ids, pushStatus, nullID(n.CreatedBy))
		count = tag.RowsAffected()
		return err
	})
	if err != nil {
		return 0, 0, err
	}
	if s.push != nil && count > 0 {
		go s.push.deliver(s.db, id, n.Title, n.Body, n.Type)
	}
	return id, int(count), nil
}

// SendSafe is Send for automatic alerts: errors are logged, never returned.
func (s *Service) SendSafe(ctx context.Context, n Notice, userIDs []int64) {
	if _, _, err := s.Send(context.WithoutCancel(ctx), n, userIDs); err != nil {
		slog.Error("notification failed", "title", n.Title, "err", err)
	}
}

// WithParents returns the students plus every active parent linked to them.
func (s *Service) WithParents(ctx context.Context, studentIDs []int64) []int64 {
	out := append([]int64{}, studentIDs...)
	rows, err := s.db.Query(ctx, `SELECT parent_id FROM student_parents WHERE student_id = ANY($1) AND is_active`, studentIDs)
	if err != nil {
		slog.Error("load parents for notification", "err", err)
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		if rows.Scan(&id) == nil {
			out = append(out, id)
		}
	}
	return out
}

// AlreadySent reports whether an automatic notice for this reference exists (to notify only once).
func (s *Service) AlreadySent(ctx context.Context, refType string, refID int64) bool {
	var ok bool
	_ = s.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM notifications WHERE reference_type = $1 AND reference_id = $2 AND is_active)`, refType, refID).Scan(&ok)
	return ok
}

// Resolve expands a target into user ids. includeParents adds parents of every student in the set.
func (s *Service) Resolve(ctx context.Context, targetType string, targetID *int64, includeParents bool) ([]int64, error) {
	var q string
	var args []any
	switch targetType {
	case "all":
		q = `SELECT id FROM users WHERE is_active`
	case "role":
		q = `SELECT ur.user_id FROM user_roles ur JOIN users u ON u.id = ur.user_id AND u.is_active WHERE ur.role_id = $1 AND ur.is_active`
		args = []any{targetID}
	case "department":
		q = `SELECT id FROM users WHERE department_id = $1 AND is_active`
		args = []any{targetID}
	case "class":
		q = `SELECT sp.user_id FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
		     WHERE sp.current_class_id = $1 AND sp.is_active
		     UNION SELECT class_incharge_id FROM classes WHERE id = $1 AND class_incharge_id IS NOT NULL`
		args = []any{targetID}
	case "user":
		q = `SELECT id FROM users WHERE id = $1 AND is_active`
		args = []any{targetID}
	default:
		return nil, nil
	}
	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[int64])
	if err != nil {
		return nil, err
	}
	if includeParents && targetType != "all" {
		ids = s.WithParents(ctx, ids)
	}
	return uniq(ids), nil
}

func nullID(id int64) *int64 {
	if id == 0 {
		return nil
	}
	return &id
}

func uniq(ids []int64) []int64 {
	seen := map[int64]bool{}
	out := []int64{}
	for _, id := range ids {
		if id > 0 && !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}

// ---- Expo push ----

// ExpoPusher sends to Expo's push service (https://docs.expo.dev/push-notifications/sending-notifications/).
type ExpoPusher struct {
	URL    string
	Client *http.Client
}

func NewExpoPusher(url string) *ExpoPusher {
	return &ExpoPusher{URL: url, Client: &http.Client{Timeout: 15 * time.Second}}
}

type expoMessage struct {
	To    []string       `json:"to"`
	Title string         `json:"title"`
	Body  string         `json:"body"`
	Sound string         `json:"sound"`
	Data  map[string]any `json:"data"`
}

func (p *ExpoPusher) deliver(db *pgxpool.Pool, notificationID int64, title, body, typ string) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	rows, err := db.Query(ctx, `SELECT dt.token FROM notification_recipients r
		JOIN device_tokens dt ON dt.user_id = r.user_id AND dt.is_active
		WHERE r.notification_id = $1 AND r.is_active`, notificationID)
	if err != nil {
		slog.Error("push: load tokens", "err", err)
		return
	}
	tokens, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		slog.Error("push: read tokens", "err", err)
		return
	}
	status := "sent"
	for i := 0; i < len(tokens); i += 100 { // Expo accepts up to 100 recipients per message
		end := min(i+100, len(tokens))
		msg := expoMessage{To: tokens[i:end], Title: title, Body: body, Sound: "default",
			Data: map[string]any{"notification_id": notificationID, "type": typ}}
		payload, _ := json.Marshal([]expoMessage{msg})
		req, _ := http.NewRequestWithContext(ctx, http.MethodPost, p.URL, bytes.NewReader(payload))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json")
		resp, err := p.Client.Do(req)
		if err != nil || resp.StatusCode >= 300 {
			status = "failed"
			slog.Error("push: send", "err", err, "notification_id", notificationID)
		}
		if resp != nil {
			resp.Body.Close()
		}
	}
	if len(tokens) == 0 {
		status = "skipped"
	}
	if _, err := db.Exec(ctx, `UPDATE notification_recipients SET push_status = $2 WHERE notification_id = $1 AND push_status = 'pending'`,
		notificationID, status); err != nil {
		slog.Error("push: update status", "err", err)
	}
}
