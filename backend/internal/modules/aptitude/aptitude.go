package aptitude

import (
	"context"
	"encoding/json"
	"math/rand/v2"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, students *student.Service) {
	h := &Handler{db: db, students: students}
	r.GET("/students/:id/aptitude", h.summary)
	r.POST("/students/:id/aptitude/start", h.start)
	r.POST("/aptitude/attempts/:id/submit", h.submit)
}

// Question is what a student sees: never the correct answer.
type Question struct {
	ID      int64    `json:"id"`
	Section string   `json:"section"`
	Text    string   `json:"text"`
	Options []string `json:"options"`
}

func (h *Handler) questions(ctx context.Context, ids []int64) ([]Question, error) {
	rows, err := h.db.Query(ctx, `
		SELECT id, section, question, option_a, option_b, option_c, option_d FROM aptitude_questions WHERE id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	byID := map[int64]Question{}
	for rows.Next() {
		var q Question
		var a, b, c, d string
		if err := rows.Scan(&q.ID, &q.Section, &q.Text, &a, &b, &c, &d); err != nil {
			return nil, err
		}
		q.Options = []string{a, b, c, d}
		byID[q.ID] = q
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Keep the order the attempt was created with.
	out := make([]Question, 0, len(ids))
	for _, id := range ids {
		if q, ok := byID[id]; ok {
			out = append(out, q)
		}
	}
	return out, nil
}

type attemptView struct {
	AttemptID    int64      `json:"attempt_id"`
	TimeLimitSec int        `json:"time_limit_sec"`
	RemainingSec int        `json:"remaining_sec"`
	Questions    []Question `json:"questions"`
}

type historyItem struct {
	ID          int64                   `json:"id"`
	SubmittedAt time.Time               `json:"submitted_at"`
	Score       float64                 `json:"score"`
	Sections    map[string]SectionScore `json:"sections"`
}

// summary shows the latest results and whether the student can take the test now.
func (h *Handler) summary(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, `
		SELECT id, submitted_at, score::float8, section_scores FROM aptitude_attempts
		WHERE student_id = $1 AND status = 'submitted' ORDER BY id DESC LIMIT 10`, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	history := []historyItem{}
	for rows.Next() {
		var it historyItem
		var sections []byte
		if err := rows.Scan(&it.ID, &it.SubmittedAt, &it.Score, &sections); err != nil {
			response.Error(c, err)
			return
		}
		_ = json.Unmarshal(sections, &it.Sections)
		history = append(history, it)
	}
	if err := rows.Err(); err != nil {
		response.Error(c, err)
		return
	}

	var latest *historyItem
	var canTakeAfter *time.Time
	if len(history) > 0 {
		latest = &history[0]
		t := history[0].SubmittedAt.Add(RetakeAfterHours * time.Hour)
		if t.After(time.Now()) {
			canTakeAfter = &t
		}
	}
	var inProgress bool
	_ = h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM aptitude_attempts WHERE student_id = $1 AND status = 'in_progress'
		AND started_at + make_interval(secs => time_limit_sec + $2) > now())`, id, GraceSec).Scan(&inProgress)
	response.OK(c, gin.H{
		"latest":         latest,
		"history":        history,
		"can_take_after": canTakeAfter,
		"in_progress":    inProgress,
		"per_section":    PerSection,
		"time_limit_sec": TimeLimitSec,
	})
}

// start begins a test for the signed-in student (it cannot be started for someone else) or resumes the one in
// progress. A student who has finished a test must wait before the next.
func (h *Handler) start(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	if a.ID != id {
		response.Error(c, response.Forbidden("A student has to take the test themselves"))
		return
	}

	// Resume an unfinished attempt that is still within its time.
	var attemptID int64
	var ids []int64
	var limit int
	var remaining float64
	var raw []byte
	err := h.db.QueryRow(c, `
		SELECT id, question_ids, time_limit_sec, extract(epoch FROM (started_at + make_interval(secs => time_limit_sec) - now()))
		FROM aptitude_attempts WHERE student_id = $1 AND status = 'in_progress' ORDER BY id DESC LIMIT 1`, id).Scan(&attemptID, &raw, &limit, &remaining)
	if err == nil && remaining > -GraceSec {
		_ = json.Unmarshal(raw, &ids)
		qs, qerr := h.questions(c, ids)
		if qerr != nil {
			response.Error(c, qerr)
			return
		}
		response.OK(c, attemptView{AttemptID: attemptID, TimeLimitSec: limit, RemainingSec: max(0, int(remaining)), Questions: qs})
		return
	}
	if err != nil && !dbutil.IsNoRows(err) {
		response.Error(c, err)
		return
	}
	// Whatever was left unfinished is now past its time.
	_, _ = h.db.Exec(c, `UPDATE aptitude_attempts SET status = 'expired' WHERE student_id = $1 AND status = 'in_progress'`, id)

	var last *time.Time
	_ = h.db.QueryRow(c, `SELECT max(submitted_at) FROM aptitude_attempts WHERE student_id = $1 AND status = 'submitted'`, id).Scan(&last)
	if last != nil {
		if next := last.Add(RetakeAfterHours * time.Hour); next.After(time.Now()) {
			response.Error(c, response.TooManyRequests("You can take the test again after "+next.Local().Format("02 Jan, 15:04")))
			return
		}
	}

	rows, err := h.db.Query(c, `SELECT section, id FROM aptitude_questions WHERE is_active`)
	if err != nil {
		response.Error(c, err)
		return
	}
	pool := map[string][]int64{}
	for rows.Next() {
		var s string
		var qid int64
		if err := rows.Scan(&s, &qid); err != nil {
			rows.Close()
			response.Error(c, err)
			return
		}
		pool[s] = append(pool[s], qid)
	}
	rows.Close()
	picked, err := Pick(pool, PerSection, rand.New(rand.NewPCG(uint64(time.Now().UnixNano()), uint64(id))))
	if err != nil {
		response.Error(c, response.ServiceUnavailable("The test is not ready: "+err.Error()))
		return
	}
	enc, _ := json.Marshal(picked)
	if err := h.db.QueryRow(c, `INSERT INTO aptitude_attempts (student_id, question_ids, time_limit_sec) VALUES ($1, $2, $3) RETURNING id`,
		id, enc, TimeLimitSec).Scan(&attemptID); err != nil {
		response.Error(c, err)
		return
	}
	qs, err := h.questions(c, picked)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, attemptView{AttemptID: attemptID, TimeLimitSec: TimeLimitSec, RemainingSec: TimeLimitSec, Questions: qs})
}

// submit marks the answers on the server. It fails when the time is up, and nobody can submit for someone else.
func (h *Handler) submit(c *gin.Context) {
	attemptID, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Answers map[string]string `json:"answers" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Send {\"answers\": {\"<question id>\": \"a\"-\"d\"}}"))
		return
	}
	raw := map[int64]string{}
	for k, v := range body.Answers {
		if n, err := strconv.ParseInt(k, 10, 64); err == nil {
			raw[n] = v
		}
	}

	a := actor.From(c)
	var result Result
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var studentID int64
		var qraw []byte
		var status string
		var late bool
		if err := tx.QueryRow(c, `
			SELECT student_id, question_ids, status, now() > started_at + make_interval(secs => time_limit_sec + $2)
			FROM aptitude_attempts WHERE id = $1 FOR UPDATE`, attemptID, GraceSec).Scan(&studentID, &qraw, &status, &late); err != nil {
			if dbutil.IsNoRows(err) {
				return response.NotFound("Attempt not found")
			}
			return err
		}
		if studentID != a.ID {
			return response.NotFound("Attempt not found")
		}
		if status != "in_progress" {
			return response.Conflict("This test has already been " + status)
		}
		if late {
			return errTimeUp
		}
		var ids []int64
		_ = json.Unmarshal(qraw, &ids)
		rows, err := tx.Query(c, `SELECT id, section, correct FROM aptitude_questions WHERE id = ANY($1)`, ids)
		if err != nil {
			return err
		}
		var asked []Asked
		for rows.Next() {
			var q Asked
			if err := rows.Scan(&q.ID, &q.Section, &q.Correct); err != nil {
				rows.Close()
				return err
			}
			asked = append(asked, q)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		answers := ValidAnswers(asked, raw)
		result = Score(asked, answers)
		ans, _ := json.Marshal(answers)
		sec, _ := json.Marshal(result.Sections)
		if _, err := tx.Exec(c, `
			UPDATE aptitude_attempts SET status = 'submitted', submitted_at = now(), answers = $2, score = $3, section_scores = $4 WHERE id = $1`,
			attemptID, ans, result.Score, sec); err != nil {
			return err
		}
		_, err = tx.Exec(c, `UPDATE student_profiles SET aptitude_score = $2 WHERE user_id = $1`, studentID, result.Score)
		return err
	})
	if err == errTimeUp {
		// Recorded outside the rolled-back transaction, so the attempt does not stay open.
		_, _ = h.db.Exec(c, `UPDATE aptitude_attempts SET status = 'expired' WHERE id = $1 AND status = 'in_progress'`, attemptID)
		response.Error(c, response.BadRequest("Time is up, so this attempt was not scored. You can start again after the waiting period."))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, result)
}

type timeUp struct{}

func (timeUp) Error() string { return "time is up" }

var errTimeUp error = timeUp{}
