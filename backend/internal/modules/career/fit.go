package career

import (
	"fmt"
	"math"
	"strings"
)

// A career is matched on what a student can do (skills and marks) and, when they have taken the
// questionnaires, on how well the role suits them: their interests, personality and coding record.
// The second part only nudges the ranking, so marks and skills stay the main reason for a match.
const (
	// FitWeight is the share of the final score that comes from fit, when any fit data exists.
	FitWeight = 0.25

	interestWeight    = 0.4
	personalityWeight = 0.3
	codingWeight      = 0.3 // scaled by how much the career relies on programming
)

// FitProfile is what is known about a student beyond skills. Traits are 0-100 scores keyed by
// the questionnaire trait key (realistic, investigative, ..., conscientiousness, ...).
type FitProfile struct {
	Traits map[string]float64
	Coding *float64 // programming skill index, nil until verified
}

// FitDetail explains the fit part of a match so a student can see why a role was nudged up or down.
type FitDetail struct {
	Interest    *float64 `json:"interest"`
	Personality *float64 `json:"personality"`
	Coding      *float64 `json:"coding"`
	Score       *float64 `json:"score"`
	Notes       []string `json:"notes"`
}

var hollandTrait = map[byte]string{
	'R': "realistic", 'I': "investigative", 'A': "artistic", 'S': "social", 'E': "enterprising", 'C': "conventional",
}

var hollandName = map[byte]string{
	'R': "hands-on", 'I': "investigative", 'A': "creative", 'S': "people-oriented", 'E': "enterprising", 'C': "detail-oriented",
}

// InterestFit compares a student's interest scores with a career's Holland code. The first letter
// counts most. It is nil when either side is missing.
func InterestFit(p FitProfile, code string) *float64 {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		return nil
	}
	weights := []float64{3, 2, 1}
	var got, total float64
	for i := 0; i < len(code) && i < len(weights); i++ {
		key, ok := hollandTrait[code[i]]
		if !ok {
			continue
		}
		v, have := p.Traits[key]
		if !have {
			continue
		}
		got += weights[i] * v
		total += weights[i]
	}
	if total == 0 {
		return nil
	}
	return ptr(round2(got / total))
}

// PersonalityFit is the mean score on the traits that help in a role. Nil when the student has
// taken no personality questionnaire or the career names no traits.
func PersonalityFit(p FitProfile, traits []string) *float64 {
	var sum float64
	var n int
	for _, t := range traits {
		if v, ok := p.Traits[t]; ok {
			sum += v
			n++
		}
	}
	if n == 0 {
		return nil
	}
	return ptr(round2(sum / float64(n)))
}

// CodingFit is the programming index, shown only for careers that rely on programming.
func CodingFit(p FitProfile, relevance float64) *float64 {
	if p.Coding == nil || relevance <= 0 {
		return nil
	}
	return ptr(round2(*p.Coding))
}

// Combine merges the parts that exist into one 0-100 score, re-weighting when some are missing.
func Combine(interest, personality, coding *float64, codingRelevance float64) *float64 {
	var got, total float64
	add := func(v *float64, w float64) {
		if v != nil && w > 0 {
			got += *v * w
			total += w
		}
	}
	add(interest, interestWeight)
	add(personality, personalityWeight)
	add(coding, codingWeight*math.Min(codingRelevance, 1))
	if total == 0 {
		return nil
	}
	return ptr(round2(got / total))
}

// Blend mixes the skills-and-marks score with the fit score.
func Blend(base float64, fit *float64) float64 {
	if fit == nil {
		return base
	}
	return round2(base*(1-FitWeight) + *fit*FitWeight)
}

// Evaluate computes the fit of one student for one career.
func Evaluate(p FitProfile, code string, traits []string, codingRelevance float64) *FitDetail {
	d := &FitDetail{Notes: []string{}}
	d.Interest = InterestFit(p, code)
	d.Personality = PersonalityFit(p, traits)
	d.Coding = CodingFit(p, codingRelevance)
	d.Score = Combine(d.Interest, d.Personality, d.Coding, codingRelevance)
	if d.Score == nil {
		return d
	}
	if v := d.Interest; v != nil {
		switch {
		case *v >= 70:
			d.Notes = append(d.Notes, fmt.Sprintf("your interests suit this role (%s work)", describe(code)))
		case *v < 40:
			d.Notes = append(d.Notes, "your interests point more towards other kinds of work")
		}
	}
	if v := d.Personality; v != nil {
		switch {
		case *v >= 70:
			d.Notes = append(d.Notes, "your personality profile fits the way this role works")
		case *v < 45:
			d.Notes = append(d.Notes, "this role leans on traits you scored lower on")
		}
	}
	if v := d.Coding; v != nil && codingRelevance >= 0.5 {
		switch {
		case *v >= 70:
			d.Notes = append(d.Notes, "your coding record is strong for it")
		case *v < 40:
			d.Notes = append(d.Notes, "it needs more programming practice than you have verified so far")
		}
	}
	return d
}

func describe(code string) string {
	parts := []string{}
	for i := 0; i < len(code) && i < 2; i++ {
		if n, ok := hollandName[code[i]]; ok {
			parts = append(parts, n)
		}
	}
	return strings.Join(parts, " and ")
}

func ptr(v float64) *float64 { return &v }
