package career

import (
	"context"
	"encoding/json"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

// prepPlan: GET /students/:id/prep-plan?career_id=&hours=
// Without career_id the plan is for the student's best match.
func (h *Handler) prepPlan(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.cached(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if len(list) == 0 {
		if list, err = h.evaluate(c, id); err != nil {
			response.Error(c, err)
			return
		}
		if err := h.store(c, id, a.ID, list); err != nil {
			response.Error(c, err)
			return
		}
	}
	if len(list) == 0 {
		response.Error(c, response.NotFound("There are no careers to plan for yet"))
		return
	}

	target := list[0]
	if want := request.QueryInt64(c, "career_id"); want != nil && *want > 0 {
		target = nil
		for _, m := range list {
			if m.CareerID == *want {
				target = m
			}
		}
		if target == nil {
			response.Error(c, response.NotFound("Career not found"))
			return
		}
	}
	others := []*Match{}
	for _, m := range list {
		if m.CareerID != target.CareerID {
			others = append(others, m)
		}
	}

	in := PlanInput{Target: target, Others: others, AptitudeParts: map[string]float64{}, Learning: map[string]Trait{}}
	if v := request.QueryInt64(c, "hours"); v != nil {
		in.HoursPerWeek = int(*v)
	}
	if err := h.planInputs(c, id, &in); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, BuildPlan(in))
}

func (h *Handler) planInputs(ctx context.Context, studentID int64, in *PlanInput) error {
	if err := h.db.QueryRow(ctx, `SELECT coding_relevance::float8 FROM careers WHERE id = $1`, in.Target.CareerID).Scan(&in.CodingRelevance); err != nil && !dbutil.IsNoRows(err) {
		return err
	}
	if err := h.db.QueryRow(ctx, `
		SELECT aptitude_score::float8, coding_score::float8, communication_score::float8 FROM student_profiles WHERE user_id = $1`, studentID).
		Scan(&in.AptitudeScore, &in.Coding, &in.Communication); err != nil && !dbutil.IsNoRows(err) {
		return err
	}

	var raw []byte
	err := h.db.QueryRow(ctx, `SELECT section_scores FROM aptitude_attempts
		WHERE student_id = $1 AND status = 'submitted' ORDER BY id DESC LIMIT 1`, studentID).Scan(&raw)
	if err != nil && !dbutil.IsNoRows(err) {
		return err
	}
	if err == nil {
		var sections map[string]struct {
			Percent float64 `json:"percent"`
		}
		if json.Unmarshal(raw, &sections) == nil {
			for k, v := range sections {
				in.AptitudeParts[k] = v.Percent
			}
		}
	}

	err = h.db.QueryRow(ctx, `SELECT scores FROM student_assessments
		WHERE student_id = $1 AND kind = 'learning' AND is_active ORDER BY id DESC LIMIT 1`, studentID).Scan(&raw)
	if err != nil && !dbutil.IsNoRows(err) {
		return err
	}
	if err == nil {
		var res struct {
			Traits []struct {
				Key   string  `json:"key"`
				Score float64 `json:"score"`
				Level string  `json:"level"`
			} `json:"traits"`
		}
		if json.Unmarshal(raw, &res) == nil {
			for _, t := range res.Traits {
				in.Learning[t.Key] = Trait{Score: t.Score, Level: t.Level}
			}
		}
	}

	rows, err := h.db.Query(ctx, `SELECT title, COALESCE(description, ''), level FROM career_project_ideas
		WHERE career_id = $1 AND is_active ORDER BY level, id`, in.Target.CareerID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var i Idea
		if err := rows.Scan(&i.Title, &i.Description, &i.Level); err != nil {
			return err
		}
		in.Ideas = append(in.Ideas, i)
	}
	return rows.Err()
}
