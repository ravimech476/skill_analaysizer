package career

import (
	"fmt"
	"sort"
)

// The prep plan turns a career match into things a student can do: which skills to build and with what,
// what to practise, which projects to build, which study habits to fix and how it could fit into weeks.
// It is built only from recorded facts and fixed rules, so the same record gives the same plan.

const (
	DefaultHoursPerWeek = 6
	MaxWeeks            = 8
	defaultCourseHours  = 6
	weeklyProblems      = 10
)

type Idea struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Level       int    `json:"level"`
}

type Trait struct {
	Score float64
	Level string
}

// PlanInput is everything the plan may use. Missing data is nil or empty, never a guess.
type PlanInput struct {
	Target          *Match
	Others          []*Match // the other matches, best first
	CodingRelevance float64  // how much the target career relies on programming, 0-1
	Learning        map[string]Trait
	AptitudeScore   *float64
	AptitudeParts   map[string]float64 // latest section percentages
	Coding          *float64
	Communication   *float64
	Ideas           []Idea
	HoursPerWeek    int
}

type SkillStep struct {
	Skill    string      `json:"skill"`
	Level    int         `json:"level"`
	Needed   int         `json:"needed"`
	IsCore   bool        `json:"is_core"`
	Courses  []CourseRef `json:"courses"`
	HoursEst int         `json:"hours"`
}

type Action struct {
	Area string `json:"area"`
	Why  string `json:"why"`
	Do   string `json:"do"`
}

type Alternative struct {
	Career   string  `json:"career"`
	Interest float64 `json:"interest"`
	Score    float64 `json:"score"`
}

type Week struct {
	Number int      `json:"number"`
	Hours  int      `json:"hours"`
	Study  []string `json:"study"`
}

type Plan struct {
	Career       string        `json:"career"`
	CareerID     int64         `json:"career_id"`
	Readiness    string        `json:"readiness"`
	Skills       []SkillStep   `json:"skills"`
	Practice     []Action      `json:"practice"`
	Projects     []Idea        `json:"projects"`
	Habits       []Action      `json:"habits"`
	Alternatives []Alternative `json:"alternatives"`
	HoursPerWeek int           `json:"hours_per_week"`
	TotalHours   int           `json:"total_hours"`
	Weeks        []Week        `json:"weeks"`
	MoreCourses  int           `json:"more_courses"`
}

var habitTips = []struct{ key, area, tip string }{
	{"planning", "Planning", "Write a weekly study plan on Sunday with fixed hours for each task."},
	{"consistency", "Consistency", "Study a little every day instead of cramming before exams."},
	{"practice", "Practice", "Test yourself with practice questions after each topic."},
	{"help", "Asking for help", "Ask a teacher or senior as soon as you are stuck for more than 30 minutes."},
	{"resources", "Using resources", "Follow one online course or video series next to your class notes."},
}

var sectionName = map[string]string{"quantitative": "quantitative", "logical": "logical reasoning", "verbal": "verbal"}

// BuildPlan makes the plan for one student and one target career.
func BuildPlan(in PlanInput) *Plan {
	hours := in.HoursPerWeek
	if hours < 2 || hours > 30 {
		hours = DefaultHoursPerWeek
	}
	t := in.Target
	p := &Plan{Career: t.Name, CareerID: t.CareerID, Readiness: t.Readiness, HoursPerWeek: hours,
		Skills: []SkillStep{}, Practice: []Action{}, Projects: []Idea{}, Habits: []Action{}, Alternatives: []Alternative{}, Weeks: []Week{}}

	// Skills: the match already orders gaps with core ones and the biggest gaps first.
	var queue []CourseRef
	seen := map[int64]bool{}
	for _, g := range t.Gaps {
		step := SkillStep{Skill: g.Name, Level: g.Level, Needed: g.RequiredLevel, IsCore: g.IsCore, Courses: g.Courses}
		if step.Courses == nil {
			step.Courses = []CourseRef{}
		}
		if len(g.Courses) > 0 {
			step.HoursEst = courseHours(g.Courses[0])
		}
		p.Skills = append(p.Skills, step)
		// Only the first course of each gap goes into the schedule; the rest are alternatives.
		if len(g.Courses) > 0 && !seen[g.Courses[0].ID] {
			seen[g.Courses[0].ID] = true
			queue = append(queue, g.Courses[0])
		}
	}

	p.Practice = practice(in)
	p.Habits = habits(in)
	p.Alternatives = alternatives(in)

	ideas := in.Ideas
	sort.SliceStable(ideas, func(i, j int) bool { return ideas[i].Level < ideas[j].Level })
	for i := 0; i < len(ideas) && i < 2; i++ {
		p.Projects = append(p.Projects, ideas[i])
	}

	p.Weeks, p.TotalHours, p.MoreCourses = schedule(queue, hours)
	return p
}

func courseHours(c CourseRef) int {
	if c.Hours != nil && *c.Hours > 0 {
		return *c.Hours
	}
	return defaultCourseHours
}

func practice(in PlanInput) []Action {
	out := []Action{}
	if in.CodingRelevance >= 0.5 && (in.Coding == nil || *in.Coding < 70) {
		why := "You have no verified coding record yet."
		if in.Coding != nil {
			why = fmt.Sprintf("Your programming index is %.0f out of 100.", *in.Coding)
		}
		out = append(out, Action{"Coding", why + " " + in.Target.Name + " relies on programming.",
			fmt.Sprintf("Solve about %d problems a week on a coding platform. Add the profile so staff can verify it.", weeklyProblems)})
	}
	if in.AptitudeScore == nil {
		out = append(out, Action{"Aptitude", "You have not taken the aptitude test yet.", "Take the aptitude test to see which sections need work."})
	} else {
		keys := make([]string, 0, len(in.AptitudeParts))
		for k := range in.AptitudeParts {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			if v := in.AptitudeParts[k]; v < 60 {
				out = append(out, Action{"Aptitude", fmt.Sprintf("You scored %.0f%% in %s questions.", v, sectionName[k]),
					fmt.Sprintf("Practise a few %s questions every day, then retake the test.", sectionName[k])})
			}
		}
	}
	if in.Communication == nil {
		out = append(out, Action{"Communication", "A staff member has not rated your communication yet.", "Present in class or a viva so a staff member can rate it."})
	} else if *in.Communication < 60 {
		out = append(out, Action{"Communication", fmt.Sprintf("Your communication score is %.0f out of 100.", *in.Communication),
			"Join group discussions and practise short presentations."})
	}
	return out
}

func habits(in PlanInput) []Action {
	out := []Action{}
	if len(in.Learning) == 0 {
		return append(out, Action{"Habits", "You have not taken the learning behaviour questionnaire.", "Take it so study tips can match your habits."})
	}
	for _, h := range habitTips {
		if tr, ok := in.Learning[h.key]; ok && tr.Level != "high" {
			out = append(out, Action{h.area, fmt.Sprintf("Your score for %s is %.0f out of 100.", lower(h.area), tr.Score), h.tip})
		}
	}
	return out
}

func lower(s string) string {
	b := []byte(s)
	if len(b) > 0 && b[0] >= 'A' && b[0] <= 'Z' {
		b[0] += 'a' - 'A'
	}
	return string(b)
}

// alternatives names other careers that suit the student's interests better, but only when the target
// is a poor interest fit, so a plan is not undermined by a career that already suits them.
func alternatives(in PlanInput) []Alternative {
	out := []Alternative{}
	f := in.Target.Fit
	if f == nil || f.Interest == nil || *f.Interest >= 55 {
		return out
	}
	for _, m := range in.Others {
		if m.Fit == nil || m.Fit.Interest == nil || *m.Fit.Interest < 70 || m.Readiness == Explore {
			continue
		}
		out = append(out, Alternative{Career: m.Name, Interest: *m.Fit.Interest, Score: m.FinalScore})
		if len(out) == 2 {
			break
		}
	}
	return out
}

// schedule fills weeks with course hours in priority order. A course longer than a week continues into the next.
func schedule(queue []CourseRef, perWeek int) (weeks []Week, total, more int) {
	weeks = []Week{}
	week := Week{Number: 1}
	room := perWeek
	flush := func() {
		if len(week.Study) > 0 {
			weeks = append(weeks, week)
		}
		week = Week{Number: len(weeks) + 1}
		room = perWeek
	}
	for i, c := range queue {
		left := courseHours(c)
		total += left
		first := true
		for left > 0 {
			if len(weeks) >= MaxWeeks {
				more = len(queue) - i
				total -= left
				return weeks, total, more
			}
			use := min(left, room)
			label := c.Title
			if !first {
				label += " (continued)"
			}
			week.Study = append(week.Study, fmt.Sprintf("%s: %dh", label, use))
			week.Hours += use
			left -= use
			room -= use
			first = false
			if room == 0 {
				flush()
			}
		}
	}
	if len(week.Study) > 0 && len(weeks) < MaxWeeks {
		weeks = append(weeks, week)
	}
	return weeks, total, more
}
