package blooms

import (
	"context"
	"log/slog"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/chat"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

const (
	maxQuestionLen = 5000 // same limit as the question bank itself
	maxReviewIDs   = 10   // one model call per question, so reviews are done in small batches
	maxApplyItems  = 500
)

type Handler struct {
	db  *pgxpool.Pool
	llm *chat.Ollama
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, llm *chat.Ollama) {
	h := &Handler{db: db, llm: llm}
	edit := middleware.RequirePermission(perms, "question_bank.create", "question_bank.update")
	update := middleware.RequirePermission(perms, "question_bank.update")

	r.POST("/blooms/suggest", edit, h.suggest)
	r.POST("/blooms/review", update, h.review)
	r.POST("/blooms/apply", update, h.apply)
}

// suggest classifies a question that is being typed into the form (not saved yet).
func (h *Handler) suggest(c *gin.Context) {
	var req struct {
		Question string `json:"question" binding:"required"`
		Marks    int    `json:"marks"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Question) == "" {
		response.Error(c, response.BadRequest("question is required"))
		return
	}
	if len([]rune(req.Question)) > maxQuestionLen {
		response.Error(c, response.BadRequest("question is too long"))
		return
	}
	s, err := Classify(c.Request.Context(), h.llm, req.Question, req.Marks)
	if err != nil {
		slog.Error("blooms: classify failed", "err", err)
		response.Error(c, response.ServiceUnavailable("Could not suggest a level for this question."))
		return
	}
	response.OK(c, s)
}

// ReviewItem compares the saved level with the suggested one for a stored question.
type ReviewItem struct {
	ID       int64  `json:"id"`
	Question string `json:"question"`
	Subject  string `json:"subject"`
	Marks    int    `json:"marks"`
	Current  string `json:"current"`
	Suggestion
	Differs bool `json:"differs"`
}

// review classifies stored questions (by id, at most maxReviewIDs per call) so staff can accept the suggestions.
func (h *Handler) review(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || len(req.IDs) == 0 {
		response.Error(c, response.BadRequest("ids is required"))
		return
	}
	if len(req.IDs) > maxReviewIDs {
		response.Error(c, response.BadRequest("send at most 10 question ids at a time"))
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT q.id, q.question, s.code || ' - ' || s.name, COALESCE(q.marks, 0), COALESCE(q.blooms_level, '')
		FROM question_bank q JOIN subjects s ON s.id = q.subject_id
		WHERE q.is_active AND q.id = ANY($1) ORDER BY q.id`, req.IDs)
	if err != nil {
		response.Error(c, err)
		return
	}
	type stored struct {
		id           int64
		question     string
		subject      string
		marks        int
		currentLevel string
	}
	var qs []stored
	for rows.Next() {
		var s stored
		if err := rows.Scan(&s.id, &s.question, &s.subject, &s.marks, &s.currentLevel); err != nil {
			rows.Close()
			response.Error(c, err)
			return
		}
		qs = append(qs, s)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		response.Error(c, err)
		return
	}

	out := make([]ReviewItem, 0, len(qs))
	for _, q := range qs {
		if c.Request.Context().Err() != nil {
			return
		}
		sug, err := Classify(c.Request.Context(), h.llm, q.question, q.marks)
		if err != nil {
			continue // leave it out; the question stays as it is
		}
		out = append(out, ReviewItem{ID: q.id, Question: q.question, Subject: q.subject, Marks: q.marks,
			Current: q.currentLevel, Suggestion: sug, Differs: sug.Level != q.currentLevel})
	}
	response.OK(c, out)
}

type applyItem struct {
	ID    int64  `json:"id"`
	Level string `json:"level"`
}

// apply saves the levels staff accepted.
func (h *Handler) apply(c *gin.Context) {
	var req struct {
		Items []applyItem `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Items) == 0 {
		response.Error(c, response.BadRequest("items is required"))
		return
	}
	if len(req.Items) > maxApplyItems {
		response.Error(c, response.BadRequest("too many items in one request"))
		return
	}
	for _, it := range req.Items {
		if it.ID <= 0 || !validLevel(it.Level) {
			response.Error(c, response.BadRequest("each item needs a question id and one of: "+strings.Join(Levels, ", ")))
			return
		}
	}

	n, err := h.applyAll(c.Request.Context(), actor.From(c).ID, req.Items)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"updated": n})
}

func (h *Handler) applyAll(ctx context.Context, userID int64, items []applyItem) (int, error) {
	tx, err := h.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	batch := &pgx.Batch{}
	for _, it := range items {
		batch.Queue(`UPDATE question_bank SET blooms_level = $2, updated_by = $3 WHERE id = $1 AND is_active`, it.ID, it.Level, userID)
	}
	br := tx.SendBatch(ctx, batch)
	updated := 0
	for range items {
		tag, err := br.Exec()
		if err != nil {
			br.Close()
			return 0, err
		}
		updated += int(tag.RowsAffected())
	}
	if err := br.Close(); err != nil {
		return 0, err
	}
	return updated, tx.Commit(ctx)
}
