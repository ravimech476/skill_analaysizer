// Package skillsuggest proposes skills from marks, in two ways. For a student, the level of each skill is
// worked out in code from the marks in the subjects that build it, so every number can be traced. For a
// subject, a language model proposes which skills it builds, since that needs reading what the subject is
// about. Both only propose: staff accept or edit before anything is saved.
package skillsuggest

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

// levelFor converts a mark percentage into a 1-5 proficiency. Below 50% (not a pass in most
// regulations) there is no evidence of the skill, so no level is suggested.
func levelFor(percent float64) int {
	switch {
	case percent >= 90:
		return 5
	case percent >= 80:
		return 4
	case percent >= 70:
		return 3
	case percent >= 60:
		return 2
	case percent >= 50:
		return 1
	}
	return 0
}

// SubjectMark is a student's latest result in one subject.
type SubjectMark struct {
	SubjectID int64
	Subject   string
	Percent   float64
}

// SkillLink says a subject builds a skill, and how strongly (the weight from subject_skills).
type SkillLink struct {
	SkillID int64
	Skill   string
	Weight  float64
}

// Evidence is one subject's contribution to a suggested level.
type Evidence struct {
	SubjectID int64   `json:"subject_id"`
	Subject   string  `json:"subject"`
	Percent   float64 `json:"percent"`
	Weight    float64 `json:"weight"`
}

// Candidate is a skill level the marks support.
type Candidate struct {
	SkillID  int64
	Skill    string
	Level    int
	Percent  float64 // weighted average over the subjects that build the skill
	Current  int     // 0 when the student has no level recorded for the skill
	Evidence []Evidence
}

// Candidates works out, for every skill the student's subjects build, the level the marks support. It only
// returns skills where that level is above what the student already has, so an accepted suggestion can
// never lower a level that staff or the student recorded.
func Candidates(marks []SubjectMark, links map[int64][]SkillLink, current map[int64]int) []Candidate {
	type acc struct {
		name              string
		weighted, weights float64
		ev                []Evidence
	}
	bySkill := map[int64]*acc{}
	for _, m := range marks {
		for _, l := range links[m.SubjectID] {
			if l.Weight <= 0 {
				continue
			}
			a := bySkill[l.SkillID]
			if a == nil {
				a = &acc{name: l.Skill}
				bySkill[l.SkillID] = a
			}
			a.weighted += m.Percent * l.Weight
			a.weights += l.Weight
			a.ev = append(a.ev, Evidence{SubjectID: m.SubjectID, Subject: m.Subject, Percent: round1(m.Percent), Weight: l.Weight})
		}
	}

	var out []Candidate
	for id, a := range bySkill {
		pct := a.weighted / a.weights
		lvl := levelFor(pct)
		if lvl == 0 || lvl <= current[id] {
			continue
		}
		sort.Slice(a.ev, func(i, j int) bool { return a.ev[i].SubjectID < a.ev[j].SubjectID })
		out = append(out, Candidate{SkillID: id, Skill: a.name, Level: lvl, Percent: round1(pct), Current: current[id], Evidence: a.ev})
	}
	// Highest first, then by name so the order is stable.
	sort.Slice(out, func(i, j int) bool {
		if out[i].Level != out[j].Level {
			return out[i].Level > out[j].Level
		}
		return out[i].Skill < out[j].Skill
	})
	return out
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

// Explain says in plain words why a level is suggested, using only the stored evidence.
func Explain(c Candidate) string {
	subj := ""
	for i, e := range c.Evidence {
		if i > 0 {
			subj += ", "
		}
		subj += fmt.Sprintf("%s %.0f%%", e.Subject, e.Percent)
	}
	s := fmt.Sprintf("%s: level %d from marks (%s)", c.Skill, c.Level, subj)
	if c.Current > 0 {
		s += fmt.Sprintf("; currently recorded as %d", c.Current)
	}
	return s
}

// Summarize writes the short note staff see above the suggestions. It is built from the numbers alone: a
// language model was tried for this and invented claims, which is not acceptable in a record about a student.
func Summarize(name string, marks []SubjectMark, cands []Candidate, unmapped []string) string {
	if len(marks) == 0 {
		return name + " has no marks recorded yet, so there is nothing to base skill suggestions on."
	}
	sorted := append([]SubjectMark(nil), marks...)
	sort.Slice(sorted, func(i, j int) bool {
		if sorted[i].Percent != sorted[j].Percent {
			return sorted[i].Percent > sorted[j].Percent
		}
		return sorted[i].Subject < sorted[j].Subject
	})

	var strong, weak []string
	for _, m := range sorted {
		label := fmt.Sprintf("%s (%.0f%%)", m.Subject, m.Percent)
		switch {
		case m.Percent >= 80 && len(strong) < 3:
			strong = append(strong, label)
		case m.Percent < 60:
			weak = append(weak, label)
		}
	}

	var parts []string
	if len(strong) > 0 {
		parts = append(parts, fmt.Sprintf("%s is strongest in %s.", name, joinAnd(strong)))
	}
	if len(weak) > 0 {
		parts = append(parts, "Needs attention: "+joinAnd(weak)+".")
	}
	switch len(cands) {
	case 0:
		parts = append(parts, "The marks do not support any skill level above what is already recorded.")
	default:
		names := make([]string, len(cands))
		for i, c := range cands {
			names[i] = fmt.Sprintf("%s to level %d", c.Skill, c.Level)
		}
		parts = append(parts, "The marks support raising "+joinAnd(names)+".")
	}
	if len(unmapped) > 0 {
		parts = append(parts, "No skill mapping exists for "+joinAnd(unmapped)+", so those marks were not used.")
	}
	return strings.Join(parts, " ")
}

func joinAnd(items []string) string {
	switch len(items) {
	case 0:
		return ""
	case 1:
		return items[0]
	}
	return strings.Join(items[:len(items)-1], ", ") + " and " + items[len(items)-1]
}
