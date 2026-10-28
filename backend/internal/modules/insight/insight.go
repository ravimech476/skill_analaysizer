package insight

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/modules/chat"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	llm      *chat.Ollama
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, students *student.Service, llm *chat.Ollama) {
	h := &Handler{db: db, students: students, llm: llm}
	r.GET("/students/:id/insight", h.get)
}

const wordingTimeout = 90 * time.Second

var wordingSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"summary":    map[string]any{"type": "string"},
		"next_steps": map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "maxItems": 3},
	},
	"required": []string{"summary", "next_steps"},
}

const wordingPrompt = `You are a supportive placement coach. Turn the FACTS about a student into a short note.
Rules:
- Use only the facts. Never add a number, name, company, skill or subject that is not in the facts.
- Write the summary as 2 or 3 plain sentences to the student, in second person.
- Write up to 3 next steps, each one short sentence that follows from the facts.
- Do not promise a job or give salary advice.`

// reword asks the model to put the facts into friendlier words. It returns false when the model is
// unavailable or when its text strays from the facts.
func (h *Handler) reword(ctx context.Context, f *Facts, base *Insight) bool {
	ctx, cancel := context.WithTimeout(ctx, wordingTimeout)
	defer cancel()
	factsText := f.Text()
	raw, err := h.llm.ChatStructured(ctx, []chat.Message{
		{Role: "system", Content: wordingPrompt},
		{Role: "user", Content: "FACTS:\n" + factsText + "\nDraft next steps:\n- " + strings.Join(base.NextSteps, "\n- ")},
	}, wordingSchema, 400)
	if err != nil {
		slog.Warn("insight wording unavailable", "err", err)
		return false
	}
	var out struct {
		Summary   string   `json:"summary"`
		NextSteps []string `json:"next_steps"`
	}
	if json.Unmarshal([]byte(raw), &out) != nil || strings.TrimSpace(out.Summary) == "" {
		return false
	}
	if !Allowed(out.Summary+"\n"+strings.Join(out.NextSteps, "\n"), factsText) {
		slog.Info("insight wording rejected: it went beyond the facts")
		return false
	}
	base.Summary = strings.TrimSpace(out.Summary)
	if len(out.NextSteps) > 0 {
		base.NextSteps = out.NextSteps
	}
	base.Source = "llm"
	return true
}

type stored struct {
	Hash        string
	Body        []byte
	GeneratedAt time.Time
}

func (h *Handler) get(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	facts, err := Gather(c, h.db, id)
	if err != nil {
		if dbutil.IsNoRows(err) {
			response.Error(c, response.NotFound("Student not found"))
			return
		}
		response.Error(c, err)
		return
	}
	hash := facts.Hash()

	var old stored
	err = h.db.QueryRow(c, `SELECT facts_hash, body, generated_at FROM student_insights WHERE student_id = $1`, id).
		Scan(&old.Hash, &old.Body, &old.GeneratedAt)
	if err != nil && !dbutil.IsNoRows(err) {
		response.Error(c, err)
		return
	}
	if err == nil && old.Hash == hash && c.Query("refresh") != "true" {
		var in Insight
		if json.Unmarshal(old.Body, &in) == nil {
			response.OK(c, gin.H{"insight": in, "generated_at": old.GeneratedAt, "up_to_date": true})
			return
		}
	}

	in := Compose(facts)
	h.reword(c, facts, in)
	body, _ := json.Marshal(in)
	now := time.Now()
	if _, err := h.db.Exec(c, `
		INSERT INTO student_insights (student_id, facts_hash, body, generated_at) VALUES ($1, $2, $3, $4)
		ON CONFLICT (student_id) DO UPDATE SET facts_hash = EXCLUDED.facts_hash, body = EXCLUDED.body, generated_at = EXCLUDED.generated_at`,
		id, hash, body, now); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"insight": in, "generated_at": now, "up_to_date": true})
}
