package talent

import (
	"fmt"
	"math"
	"strings"
)

// CommunicationCriteria are what staff rate (1 to 5) for communication.
var CommunicationCriteria = []string{"speaking", "writing", "listening", "teamwork"}

// ReviewScore turns a staff rubric into 0-100: the mean of the four criteria, each 1 to 5, times 20.
func ReviewScore(rubric map[string]int) (float64, error) {
	if len(rubric) != len(CommunicationCriteria) {
		return 0, fmt.Errorf("rate all four criteria: %s", strings.Join(CommunicationCriteria, ", "))
	}
	total := 0
	for _, c := range CommunicationCriteria {
		v, ok := rubric[c]
		if !ok || v < 1 || v > 5 {
			return 0, fmt.Errorf("%s must be rated from 1 to 5", c)
		}
		total += v
	}
	return math.Round(float64(total)/float64(len(CommunicationCriteria))*20*10) / 10, nil
}

// SelfWeight is how much the student's own answers count when a staff review exists (the review counts the rest).
const SelfWeight = 0.3

// CommunicationScore combines the staff review with the student's self-report. Without a staff review there is no
// score: a self-assessment alone is not enough to affect placement readiness. With a review but no self-report the
// review counts fully.
func CommunicationScore(review, self *float64) *float64 {
	if review == nil {
		return nil
	}
	s := *review
	if self != nil {
		s = (1-SelfWeight)*(*review) + SelfWeight*(*self)
	}
	s = math.Round(s*10) / 10
	return &s
}

// SelfMean is the mean of a questionnaire's trait scores (0-100), or nil when there are none.
func SelfMean(r *Result) *float64 {
	if r == nil || len(r.Traits) == 0 {
		return nil
	}
	var sum float64
	for _, t := range r.Traits {
		sum += t.Score
	}
	m := math.Round(sum/float64(len(r.Traits))*10) / 10
	return &m
}
