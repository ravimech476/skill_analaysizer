package talent

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

// TraitScore is the result for one trait: 0-100, a level and a plain-language reading.
type TraitScore struct {
	Key     string  `json:"key"`
	Label   string  `json:"label"`
	Score   float64 `json:"score"`
	Level   string  `json:"level"` // low | moderate | high
	Meaning string  `json:"meaning"`
}

// Result is what a completed questionnaire produces.
type Result struct {
	Kind   string       `json:"kind"`
	Traits []TraitScore `json:"traits"`
	// Headline is a one-line summary: the top interest code, the strongest personality traits, and so on.
	Headline string `json:"headline"`
}

func levelOf(score float64) string {
	switch {
	case score >= 65:
		return "high"
	case score >= 40:
		return "moderate"
	}
	return "low"
}

// Validate checks that every question has an answer from 1 to 5 and that no unknown question was answered.
func Validate(q *Questionnaire, answers map[string]int) error {
	for _, qu := range q.Questions {
		v, ok := answers[qu.ID]
		if !ok {
			return fmt.Errorf("question %s has no answer", qu.ID)
		}
		if v < 1 || v > 5 {
			return fmt.Errorf("answer to %s must be from 1 to 5", qu.ID)
		}
	}
	if len(answers) != len(q.Questions) {
		return fmt.Errorf("unknown questions in the answers")
	}
	return nil
}

// Score turns validated answers into trait scores. A trait's score is the mean of its answers (reverse-worded
// items count as 6 minus the answer) rescaled so that 1 becomes 0 and 5 becomes 100.
func Score(q *Questionnaire, answers map[string]int) Result {
	sum := map[string]float64{}
	n := map[string]int{}
	for _, qu := range q.Questions {
		v := float64(answers[qu.ID])
		if qu.Reverse {
			v = 6 - v
		}
		sum[qu.Trait] += v
		n[qu.Trait]++
	}
	res := Result{Kind: q.Kind}
	for _, t := range q.Traits {
		if n[t.Key] == 0 {
			continue
		}
		s := math.Round((sum[t.Key]/float64(n[t.Key])-1)/4*1000) / 10
		res.Traits = append(res.Traits, TraitScore{Key: t.Key, Label: t.Label, Score: s, Level: levelOf(s), Meaning: meaning(q.Kind, t.Key, levelOf(s))})
	}
	res.Headline = headline(q.Kind, res.Traits)
	return res
}

// riasecLetter maps an interest trait to its Holland letter.
var riasecLetter = map[string]string{"realistic": "R", "investigative": "I", "artistic": "A", "social": "S", "enterprising": "E", "conventional": "C"}

// fieldsFor suggests the kind of work each Holland type points to (a pointer, not a prediction).
var fieldsFor = map[string]string{
	"realistic":     "hardware, embedded systems, networks and DevOps",
	"investigative": "data science, machine learning, research and analysis",
	"artistic":      "UI/UX design, front-end and product design",
	"social":        "training, customer success, consulting and support",
	"enterprising":  "product management, business analysis and sales engineering",
	"conventional":  "databases, testing, quality assurance and operations",
}

func headline(kind string, traits []TraitScore) string {
	switch kind {
	case "interests":
		var types []TraitScore
		for _, t := range traits {
			if _, ok := riasecLetter[t.Key]; ok {
				types = append(types, t)
			}
		}
		sort.SliceStable(types, func(i, j int) bool { return types[i].Score > types[j].Score })
		if len(types) < 3 {
			return ""
		}
		code := riasecLetter[types[0].Key] + riasecLetter[types[1].Key] + riasecLetter[types[2].Key]
		return fmt.Sprintf("Interest code %s. Strongest pull towards %s.", code, fieldsFor[types[0].Key])
	default:
		var high, low []string
		for _, t := range traits {
			switch t.Level {
			case "high":
				high = append(high, strings.ToLower(t.Label))
			case "low":
				low = append(low, strings.ToLower(t.Label))
			}
		}
		out := ""
		if len(high) > 0 {
			out = "Strengths: " + strings.Join(high, ", ") + "."
		}
		if len(low) > 0 {
			if out != "" {
				out += " "
			}
			out += "To work on: " + strings.Join(low, ", ") + "."
		}
		if out == "" {
			out = "A balanced profile with no standout high or low area."
		}
		return out
	}
}

// meaning is the short reading shown next to a score. These are fixed texts, not model output.
func meaning(kind, key, level string) string {
	if m, ok := meanings[key+"/"+level]; ok {
		return m
	}
	if strings.HasPrefix(key, "val_") {
		switch level {
		case "high":
			return "This matters a lot to you when choosing a job."
		case "low":
			return "This is not a priority for you when choosing a job."
		}
		return "This matters somewhat to you when choosing a job."
	}
	if _, ok := riasecLetter[key]; ok {
		switch level {
		case "high":
			return "You would enjoy work in " + fieldsFor[key] + "."
		case "low":
			return "Work in " + fieldsFor[key] + " appeals to you less."
		}
		return "You are open to work in " + fieldsFor[key] + "."
	}
	return ""
}

var meanings = map[string]string{
	"extraversion/high":          "Energised by people; comfortable presenting, networking and leading discussions.",
	"extraversion/moderate":      "Comfortable in groups and on your own, depending on the situation.",
	"extraversion/low":           "Prefers focused, independent work; may need practice speaking up in groups and interviews.",
	"agreeableness/high":         "Cooperative and considerate; works well in teams.",
	"agreeableness/moderate":     "Balances helping others with standing your ground.",
	"agreeableness/low":          "Direct and competitive; practise listening and compromise in team projects.",
	"conscientiousness/high":     "Organised and dependable; meets deadlines and follows plans.",
	"conscientiousness/moderate": "Reasonably organised, with room to be more consistent.",
	"conscientiousness/low":      "Tends to work in bursts; a weekly plan and deadlines you set yourself would help.",
	"stability/high":             "Stays calm under pressure, a real advantage in exams and interviews.",
	"stability/moderate":         "Copes with most pressure, though big deadlines may cause stress.",
	"stability/low":              "Pressure can be hard; relaxation and mock interviews would build confidence.",
	"openness/high":              "Curious and creative; enjoys new ideas and learning beyond the syllabus.",
	"openness/moderate":          "Open to new ideas while valuing proven methods.",
	"openness/low":               "Prefers familiar, practical methods; try one new tool or topic each month.",
	"planning/high":              "Plans study time and sets clear goals.",
	"planning/moderate":          "Plans sometimes; a fixed weekly schedule would help.",
	"planning/low":               "Studies without a plan; start with a simple weekly timetable.",
	"consistency/high":           "Studies regularly instead of cramming.",
	"consistency/moderate":       "Fairly regular, with some last-minute study.",
	"consistency/low":            "Relies on cramming; short daily sessions would improve results.",
	"practice/high":              "Tests yourself and practises often, the habit that builds skill fastest.",
	"practice/moderate":          "Practises some of the time; add regular question practice.",
	"practice/low":               "Mostly re-reads notes; add self-testing and coding practice.",
	"help/high":                  "Asks for help and learns with peers.",
	"help/moderate":              "Asks for help sometimes.",
	"help/low":                   "Tends to struggle alone; ask teachers and form a study group.",
	"resources/high":             "Uses courses, videos and summaries beyond class material.",
	"resources/moderate":         "Uses some extra resources.",
	"resources/low":              "Relies on class material only; try one NPTEL or SWAYAM course.",
}

func init() {
	for k, v := range map[string]string{
		"speaking/high":         "Explains ideas clearly and speaks confidently, a strength for presentations and interviews.",
		"speaking/moderate":     "Speaks reasonably well; regular practice in front of a group would help.",
		"speaking/low":          "Finds speaking hard; try short talks, mock interviews and explaining topics to friends.",
		"writing/high":          "Writes clearly and checks the work; good for reports, emails and documentation.",
		"writing/moderate":      "Writes adequately; reading your drafts aloud and proofreading will improve it.",
		"writing/low":           "Writing is a weak area; practise short summaries and ask for feedback on emails and reports.",
		"listening/high":        "Listens carefully and checks understanding.",
		"listening/moderate":    "Listens well at times; summarising what you heard builds the habit.",
		"listening/low":         "Often loses focus while others explain; take notes and repeat key points back.",
		"teamwork/high":         "Shares the load and supports teammates.",
		"teamwork/moderate":     "Works well in teams most of the time.",
		"teamwork/low":          "Prefers working alone; practise splitting tasks and checking in with teammates.",
		"adaptability/high":     "Adjusts quickly to change and new tools.",
		"adaptability/moderate": "Copes with change, though sudden changes can be unsettling.",
		"adaptability/low":      "Finds change difficult; try learning one new tool or method each month.",
	} {
		meanings[k] = v
	}
}
