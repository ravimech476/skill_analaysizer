// Package aptitude runs a short timed test (quantitative, logical and verbal reasoning). Questions are drawn
// at random from the question bank, the correct answers never leave the server, and the score, section
// scores and time limit are all worked out here.
package aptitude

import (
	"fmt"
	"math"
	"math/rand/v2"
	"sort"
)

// Sections of the test, in display order.
var Sections = []string{"quantitative", "logical", "verbal"}

const (
	// PerSection questions are asked from each section.
	PerSection = 5
	// TimeLimitSec is how long a student has to finish.
	TimeLimitSec = 15 * 60
	// GraceSec forgives a slow network at the deadline.
	GraceSec = 30
	// RetakeAfterHours is how long a student waits between attempts, so the same questions cannot be memorised in one sitting.
	RetakeAfterHours = 24
)

// Pick draws n questions from each section, at random, without repeats. It fails when a section has fewer than n.
func Pick(pool map[string][]int64, n int, rnd *rand.Rand) ([]int64, error) {
	var out []int64
	for _, s := range Sections {
		ids := append([]int64(nil), pool[s]...)
		if len(ids) < n {
			return nil, fmt.Errorf("the %s section has only %d question(s), %d are needed", s, len(ids), n)
		}
		rnd.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] })
		out = append(out, ids[:n]...)
	}
	return out, nil
}

// Asked is a question that was put to the student, with its section and the correct option letter.
type Asked struct {
	ID      int64
	Section string
	Correct string // "a" to "d"
}

// SectionScore is the result for one section.
type SectionScore struct {
	Correct int     `json:"correct"`
	Total   int     `json:"total"`
	Percent float64 `json:"percent"`
}

// Result is the outcome of a submitted test.
type Result struct {
	Score    float64                 `json:"score"` // 0-100, the share of questions answered correctly
	Correct  int                     `json:"correct"`
	Total    int                     `json:"total"`
	Sections map[string]SectionScore `json:"sections"`
}

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return math.Round(float64(a)/float64(b)*1000) / 10
}

// Score marks the answers (question id to the chosen letter). An unanswered or invalid answer is wrong.
func Score(asked []Asked, answers map[int64]string) Result {
	res := Result{Sections: map[string]SectionScore{}, Total: len(asked)}
	for _, q := range asked {
		s := res.Sections[q.Section]
		s.Total++
		if answers[q.ID] == q.Correct {
			s.Correct++
			res.Correct++
		}
		res.Sections[q.Section] = s
	}
	for k, s := range res.Sections {
		s.Percent = pct(s.Correct, s.Total)
		res.Sections[k] = s
	}
	res.Score = pct(res.Correct, res.Total)
	return res
}

// ValidAnswers keeps only answers for questions that were asked and whose letter is a to d, so a forged
// request cannot smuggle in other question ids.
func ValidAnswers(asked []Asked, raw map[int64]string) map[int64]string {
	ok := map[int64]bool{}
	for _, q := range asked {
		ok[q.ID] = true
	}
	out := map[int64]string{}
	for id, a := range raw {
		if ok[id] && (a == "a" || a == "b" || a == "c" || a == "d") {
			out[id] = a
		}
	}
	return out
}

// SortedSections lists a result's sections in the order of Sections.
func SortedSections(r Result) []string {
	var names []string
	for k := range r.Sections {
		names = append(names, k)
	}
	sort.Slice(names, func(i, j int) bool { return index(names[i]) < index(names[j]) })
	return names
}

func index(s string) int {
	for i, x := range Sections {
		if x == s {
			return i
		}
	}
	return len(Sections)
}
