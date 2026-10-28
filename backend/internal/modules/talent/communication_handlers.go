package talent

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

// Review is a staff member's rating of a student's communication.
type Review struct {
	Rubric     map[string]int `json:"rubric"`
	Score      float64        `json:"score"`
	Notes      *string        `json:"notes"`
	ReviewedAt time.Time      `json:"reviewed_at"`
	ReviewedBy *string        `json:"reviewed_by"`
}

// CommunicationSummary is everything the screen needs for the communication and soft-skills card.
type CommunicationSummary struct {
	Self    *StoredResult `json:"self"`
	Review  *Review       `json:"review"`
	Score   *float64      `json:"score"`
	Formula string        `json:"formula"`
}

func (h *Handler) latestReview(ctx context.Context, studentID int64) (*Review, error) {
	var r Review
	var rubric []byte
	err := h.db.QueryRow(ctx, `
		SELECT c.rubric, c.score::float8, c.notes, c.created_at, u.name
		FROM communication_reviews c LEFT JOIN users u ON u.id = c.created_by
		WHERE c.student_id = $1 AND c.is_active ORDER BY c.id DESC LIMIT 1`, studentID).
		Scan(&rubric, &r.Score, &r.Notes, &r.ReviewedAt, &r.ReviewedBy)
	if err != nil {
		if dbutil.IsNoRows(err) {
			return nil, nil
		}
		return nil, err
	}
	_ = json.Unmarshal(rubric, &r.Rubric)
	return &r, nil
}

func (h *Handler) communicationSummary(ctx context.Context, studentID int64, self *StoredResult) (*CommunicationSummary, error) {
	review, err := h.latestReview(ctx, studentID)
	if err != nil {
		return nil, err
	}
	var reviewScore *float64
	if review != nil {
		reviewScore = &review.Score
	}
	var selfResult *Result
	if self != nil {
		selfResult = &self.Result
	}
	return &CommunicationSummary{
		Self:    self,
		Review:  review,
		Score:   CommunicationScore(reviewScore, SelfMean(selfResult)),
		Formula: "Set by a staff review of speaking, writing, listening and teamwork. When the student has also answered the questionnaire, their own answers count 30%. Without a staff review there is no score.",
	}, nil
}

// syncCommunicationScore keeps student_profiles.communication_score (read by the placement readiness score) equal to
// the communication score. With no staff review the stored score is left as it was.
func (h *Handler) syncCommunicationScore(ctx context.Context, studentID int64) {
	psy, err := h.latest(ctx, studentID)
	if err != nil {
		return
	}
	cs, err := h.communicationSummary(ctx, studentID, psy["communication"])
	if err != nil || cs.Score == nil {
		return
	}
	_, _ = h.db.Exec(ctx, `UPDATE student_profiles SET communication_score = $2 WHERE user_id = $1`, studentID, *cs.Score)
}

// reviewCommunication lets staff rate a student's communication; the student cannot rate themselves.
func (h *Handler) reviewCommunication(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if err := h.requireReviewer(c, id); err != nil {
		response.Error(c, err)
		return
	}
	var b struct {
		Rubric map[string]int `json:"rubric" binding:"required"`
		Notes  *string        `json:"notes" binding:"omitempty,max=1000"`
	}
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Send {\"rubric\": {\"speaking\":1-5, ...}}"))
		return
	}
	score, err := ReviewScore(b.Rubric)
	if err != nil {
		response.Error(c, response.BadRequest(err.Error()))
		return
	}
	if b.Notes != nil {
		n := strings.TrimSpace(*b.Notes)
		if n == "" {
			b.Notes = nil
		} else {
			b.Notes = &n
		}
	}
	rubric, _ := json.Marshal(b.Rubric)
	if _, err := h.db.Exec(c, `INSERT INTO communication_reviews (student_id, rubric, score, notes, created_by) VALUES ($1, $2, $3, $4, $5)`,
		id, rubric, score, b.Notes, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCommunicationScore(c, id)
	response.Created(c, gin.H{"score": score})
}
