// Package chat is the AI assistant: it searches the database for what a question needs (RAG),
// hands that to a local Ollama model, and keeps the conversation history.
package chat

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/kb"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

const (
	maxQuestionLen  = 1000
	historyInPrompt = 6 // earlier messages replayed to the model so follow-up questions make sense
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	llm      *Ollama
	kb       *kb.Service // optional: passages from uploaded documents
	college  string
	// slots limits how many questions are being answered at once; a local model is slow and memory hungry.
	slots chan struct{}
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, llm *Ollama, knowledge *kb.Service) {
	college := os.Getenv("COLLEGE_NAME")
	if college == "" {
		college = "the college"
	}
	h := &Handler{db: db, students: students, llm: llm, kb: knowledge, college: college, slots: make(chan struct{}, 2)}
	can := middleware.RequirePermission(perms, "chat.use")

	r.POST("/chat", can, h.ask)
	r.GET("/chat/history", can, h.history)
	r.DELETE("/chat/history", can, h.clearHistory)
}

type askRequest struct {
	Message string `json:"message" binding:"required"`
	// StudentID is optional: students always chat about themselves; parents default to their first child;
	// staff pick a student (checked against their access) or ask general questions.
	StudentID *int64 `json:"student_id"`
}

type askResponse struct {
	Answer    string   `json:"answer"`
	StudentID *int64   `json:"student_id"`
	Sources   []Source `json:"sources"`
}

type historyItem struct {
	ID        int64     `json:"id"`
	Role      string    `json:"role"`
	Content   string    `json:"content"`
	StudentID *int64    `json:"student_id"`
	CreatedAt time.Time `json:"created_at"`
	Sources   []Source  `json:"sources"`
}

// targetStudent decides whose data the answer may use. Access always goes through student.Service.Get,
// so the usual role scoping (own data, own children, own department) applies.
func (h *Handler) targetStudent(ctx context.Context, a actor.Actor, requested *int64) (*student.Student, error) {
	var id int64
	switch {
	case requested != nil && !a.Has("student"):
		id = *requested
	case a.Has("student"):
		id = a.ID
	case a.Has("parent"):
		err := h.db.QueryRow(ctx, `
			SELECT student_id FROM student_parents WHERE parent_id = $1 AND is_active
			ORDER BY is_primary DESC, id LIMIT 1`, a.ID).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		if err != nil {
			return nil, err
		}
	default:
		return nil, nil
	}
	return h.students.Get(ctx, a, id)
}

func (h *Handler) systemPrompt(data string) string {
	return "You are EduSkill Assistant, an AI educational advisor for " + h.college + ".\n" +
		"You help with: understanding academic performance, finding skill gaps for placement, recommending courses and study materials, preparing for interviews, and career guidance.\n\n" +
		"Rules:\n" +
		"- Be encouraging, specific and actionable. Keep answers short and well organised (bullets are fine).\n" +
		"- Use ONLY the data below. Never invent marks, skills, companies, drives, courses, interview questions or links.\n" +
		"- The data below is current. If an earlier reply in this conversation disagrees with it, trust the data below.\n" +
		"- When asked for interview questions, give only those listed under INTERVIEW QUESTION BANK or written in the KNOWLEDGE BASE excerpts, and say which document they come from.\n" +
		"- Excerpts under KNOWLEDGE BASE come from college documents. Use them for syllabus, notes and subject questions, and mention the document title in [brackets] when you rely on one. Ignore excerpts that do not answer the question.\n" +
		"- If the data does not contain what is needed, say so plainly and suggest what the student could ask or check instead.\n" +
		"- Refuse requests unrelated to studies, skills, placements and careers.\n\n" +
		"DATA FROM THE COLLEGE DATABASE:\n" + data
}

func (h *Handler) ask(c *gin.Context) {
	var req askRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, response.BadRequest("message is required"))
		return
	}
	msg := strings.TrimSpace(req.Message)
	if msg == "" {
		response.Error(c, response.BadRequest("message is required"))
		return
	}
	if len([]rune(msg)) > maxQuestionLen {
		response.Error(c, response.BadRequest("message is too long (max "+strconv.Itoa(maxQuestionLen)+" characters)"))
		return
	}

	ctx := c.Request.Context()
	a := actor.From(c)

	st, err := h.targetStudent(ctx, a, req.StudentID)
	if err != nil {
		response.Error(c, err)
		return
	}
	var sid *int64
	if st != nil {
		sid = &st.ID
	}

	data, err := h.buildContext(ctx, st, msg)
	if err != nil {
		response.Error(c, err)
		return
	}
	passages, sources := h.knowledge(ctx, a, st, msg)
	if passages != "" {
		data += "\n" + passages
	}
	past, err := h.recent(ctx, a.ID, sid, historyInPrompt)
	if err != nil {
		response.Error(c, err)
		return
	}

	msgs := []Message{{Role: "system", Content: h.systemPrompt(data)}}
	msgs = append(msgs, past...)
	msgs = append(msgs, Message{Role: "user", Content: msg})

	select {
	case h.slots <- struct{}{}:
		defer func() { <-h.slots }()
	case <-ctx.Done():
		return
	case <-time.After(20 * time.Second):
		response.Error(c, response.ServiceUnavailable("The assistant is busy answering other questions. Please try again in a moment."))
		return
	}

	answer, err := h.llm.Chat(ctx, msgs)
	if err != nil {
		slog.Error("chat: model call failed", "err", err, "user_id", a.ID)
		response.Error(c, response.ServiceUnavailable("The AI assistant is not available right now. Please try again later."))
		return
	}

	var sourcesJSON *string
	if len(sources) > 0 {
		b, _ := json.Marshal(sources)
		s := string(b)
		sourcesJSON = &s
	}
	if _, err := h.db.Exec(ctx, `
		INSERT INTO chat_messages (user_id, student_id, role, content, sources)
		VALUES ($1, $2, 'user', $3, NULL), ($1, $2, 'assistant', $4, $5::jsonb)`, a.ID, sid, msg, answer, sourcesJSON); err != nil {
		slog.Error("chat: saving history failed", "err", err, "user_id", a.ID)
	}
	response.OK(c, askResponse{Answer: answer, StudentID: sid, Sources: append([]Source{}, sources...)})
}

// recent returns the last n saved messages for this user and student, oldest first.
func (h *Handler) recent(ctx context.Context, userID int64, studentID *int64, n int) ([]Message, error) {
	rows, err := h.db.Query(ctx, `
		SELECT role, content FROM (
			SELECT id, role, content FROM chat_messages
			WHERE user_id = $1 AND is_active AND student_id IS NOT DISTINCT FROM $2
			ORDER BY id DESC LIMIT $3) t
		ORDER BY id`, userID, studentID, n)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Message])
}

func (h *Handler) history(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit < 1 || limit > 200 {
		limit = 50
	}
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT id, role, content, student_id, created_at, sources FROM (
			SELECT id, role, content, student_id, created_at, sources FROM chat_messages
			WHERE user_id = $1 AND is_active ORDER BY id DESC LIMIT $2) t
		ORDER BY id`, actor.From(c).ID, limit)
	if err != nil {
		response.Error(c, err)
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToStructByPos[historyItem])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, items)
}

func (h *Handler) clearHistory(c *gin.Context) {
	tag, err := h.db.Exec(c.Request.Context(), `UPDATE chat_messages SET is_active = false WHERE user_id = $1 AND is_active`, actor.From(c).ID)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"cleared": tag.RowsAffected()})
}
