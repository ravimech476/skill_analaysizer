package insight

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Insight is what the student and faculty see.
type Insight struct {
	Summary    string   `json:"summary"`
	Strengths  []string `json:"strengths"`
	FocusAreas []string `json:"focus_areas"`
	NextSteps  []string `json:"next_steps"`
	// Source says who wrote the summary and next steps: "llm" when the model's wording passed the check,
	// "rules" when it is the plain text built from the facts.
	Source string `json:"source"`
}

func names(list []SkillFact) string {
	out := make([]string, 0, len(list))
	for _, s := range list {
		out = append(out, s.Name)
	}
	return joinAnd(out)
}

func joinAnd(parts []string) string {
	switch len(parts) {
	case 0:
		return ""
	case 1:
		return parts[0]
	default:
		return strings.Join(parts[:len(parts)-1], ", ") + " and " + parts[len(parts)-1]
	}
}

// Compose builds the whole insight from the facts alone, with no model involved. It is also what the
// student sees when the model is unavailable or its wording is rejected.
func Compose(f *Facts) *Insight {
	in := &Insight{Strengths: []string{}, FocusAreas: []string{}, NextSteps: []string{}, Source: "rules"}

	summary := fmt.Sprintf("%s has a CGPA of %.2f with %d backlog(s).", f.Name, f.CGPA, f.Backlogs)
	if len(f.TopSkills) > 0 {
		summary += " The strongest skills on record are " + names(f.TopSkills) + "."
	}
	if len(f.Careers) > 0 {
		c := f.Careers[0]
		summary += fmt.Sprintf(" The closest career fit right now is %s (%s).", c.Name, c.Readiness)
	}
	in.Summary = summary

	if len(f.StrongSubject) > 0 {
		in.Strengths = append(in.Strengths, "Strong marks in "+joinSubjects(f.StrongSubject))
	}
	if f.Aptitude != nil && *f.Aptitude >= 65 {
		in.Strengths = append(in.Strengths, "Aptitude test score of "+num(f.Aptitude))
	}
	if f.Communication != nil && *f.Communication >= 65 {
		in.Strengths = append(in.Strengths, "Communication score of "+num(f.Communication))
	}
	if f.Coding != nil && *f.Coding >= 65 {
		in.Strengths = append(in.Strengths, "Programming index of "+num(f.Coding))
	}
	if len(f.Personality) > 0 {
		in.Strengths = append(in.Strengths, "Personality strengths: "+strings.Join(f.Personality, ", "))
	}

	if len(f.WeakSubject) > 0 {
		in.FocusAreas = append(in.FocusAreas, "Marks below 60% in "+joinSubjects(f.WeakSubject))
		in.NextSteps = append(in.NextSteps, "Revise "+f.WeakSubject[0].Name+" first, since it is the lowest.")
	}
	if f.Backlogs > 0 {
		in.FocusAreas = append(in.FocusAreas, fmt.Sprintf("%d backlog(s) to clear", f.Backlogs))
		in.NextSteps = append(in.NextSteps, "Plan the backlog exams, as many companies ask for no backlogs.")
	}
	if len(f.LowSkills) > 0 {
		in.FocusAreas = append(in.FocusAreas, "Skills still at a low level: "+names(f.LowSkills))
	}
	if f.Aptitude != nil && *f.Aptitude < 50 {
		in.FocusAreas = append(in.FocusAreas, "Aptitude test score of "+num(f.Aptitude))
		in.NextSteps = append(in.NextSteps, "Practise aptitude questions daily and retake the test.")
	}
	if f.Communication != nil && *f.Communication < 50 {
		in.FocusAreas = append(in.FocusAreas, "Communication score of "+num(f.Communication))
		in.NextSteps = append(in.NextSteps, "Take part in presentations or group discussions to build communication.")
	}
	if len(f.Careers) > 0 && f.Careers[0].Gap != "" {
		c := f.Careers[0]
		in.FocusAreas = append(in.FocusAreas, fmt.Sprintf("%s for %s: level %d of %d needed", c.Gap, c.Name, c.GapLevel, c.GapNeeds))
		in.NextSteps = append(in.NextSteps, "Build "+c.Gap+" to move closer to "+c.Name+".")
	}
	if f.Coding == nil {
		in.NextSteps = append(in.NextSteps, "Add coding platform profiles and projects so staff can verify them.")
	}
	if f.InterestCode == "" || len(f.Personality) == 0 {
		in.NextSteps = append(in.NextSteps, "Complete the personality and interest questionnaires for better career advice.")
	}
	if len(in.NextSteps) > 4 {
		in.NextSteps = in.NextSteps[:4]
	}
	return in
}

var (
	numberRe = regexp.MustCompile(`\d+(?:\.\d+)?`)
	wordRe   = regexp.MustCompile(`[A-Za-z][A-Za-z'+#./-]*`)
)

// Allowed reports whether the model's wording stays within the facts: every number in it has to be one
// of the fact numbers (or one rounded) and every capitalised word inside a sentence has to appear in the
// facts. A language model that adds a company, a figure or a skill the record does not contain fails.
func Allowed(text, facts string) bool {
	if strings.TrimSpace(text) == "" {
		return false
	}
	known := map[string]bool{}
	for _, n := range numberRe.FindAllString(facts, -1) {
		known[n] = true
		if v, err := strconv.ParseFloat(n, 64); err == nil {
			known[strconv.FormatFloat(float64(int(v+0.5)), 'f', -1, 64)] = true
			known[strconv.FormatFloat(float64(int(v)), 'f', -1, 64)] = true
			known[strconv.FormatFloat(float64(int(v*10+0.5))/10, 'f', -1, 64)] = true
		}
	}
	for _, n := range numberRe.FindAllString(text, -1) {
		if !known[n] {
			return false
		}
	}
	lower := strings.ToLower(facts)
	for _, sentence := range regexp.MustCompile(`[.!?]\s+|\n`).Split(text, -1) {
		words := wordRe.FindAllString(sentence, -1)
		for i, w := range words {
			if i == 0 || len(w) < 3 || w[0] < 'A' || w[0] > 'Z' {
				continue
			}
			if !strings.Contains(lower, strings.ToLower(strings.Trim(w, ".,'"))) {
				return false
			}
		}
	}
	return true
}
