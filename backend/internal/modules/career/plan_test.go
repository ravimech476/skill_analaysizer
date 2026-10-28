package career

import (
	"strings"
	"testing"
)

func hrs(n int) *int { return &n }

func target() *Match {
	interest := 40.0
	return &Match{CareerID: 1, Name: "Backend Developer", Readiness: Close, Fit: &FitDetail{Interest: &interest}, Gaps: []SkillStanding{
		{Name: "SQL", Level: 1, RequiredLevel: 3, IsCore: true, Courses: []CourseRef{{ID: 10, Title: "SQL basics", Hours: hrs(10)}, {ID: 11, Title: "SQL advanced"}}},
		{Name: "Java", Level: 2, RequiredLevel: 4, Courses: []CourseRef{{ID: 20, Title: "Java OOP", Hours: hrs(8)}}},
	}}
}

func TestPlanSkillsAndSchedule(t *testing.T) {
	p := BuildPlan(PlanInput{Target: target(), HoursPerWeek: 6})
	if len(p.Skills) != 2 || p.Skills[0].Skill != "SQL" || p.Skills[0].HoursEst != 10 {
		t.Fatalf("skills: %+v", p.Skills)
	}
	// 10h + 8h at 6h a week: 6, 4+2, 6 => 3 weeks, 18 hours in total.
	if p.TotalHours != 18 || len(p.Weeks) != 3 {
		t.Fatalf("total %d, weeks %+v", p.TotalHours, p.Weeks)
	}
	if p.Weeks[0].Hours != 6 || !strings.Contains(p.Weeks[1].Study[0], "continued") {
		t.Errorf("weeks: %+v", p.Weeks)
	}
	sum := 0
	for _, w := range p.Weeks {
		sum += w.Hours
	}
	if sum != 18 {
		t.Errorf("hours scheduled %d", sum)
	}
}

func TestScheduleCapsWeeks(t *testing.T) {
	var q []CourseRef
	for i := 0; i < 6; i++ {
		q = append(q, CourseRef{ID: int64(i), Title: "C", Hours: hrs(20)})
	}
	weeks, _, more := schedule(q, 6)
	if len(weeks) != MaxWeeks || more == 0 {
		t.Errorf("weeks %d, more %d", len(weeks), more)
	}
	if w, tot, m := schedule(nil, 6); len(w) != 0 || tot != 0 || m != 0 {
		t.Error("nothing to schedule")
	}
}

func TestPracticeFollowsTheRecord(t *testing.T) {
	low := 45.0
	apt := 70.0
	p := BuildPlan(PlanInput{Target: target(), CodingRelevance: 1, Coding: &low, AptitudeScore: &apt,
		AptitudeParts: map[string]float64{"quantitative": 80, "verbal": 40}})
	var areas []string
	for _, a := range p.Practice {
		areas = append(areas, a.Area+":"+a.Why)
	}
	joined := strings.Join(areas, "|")
	if !strings.Contains(joined, "Coding:Your programming index is 45") || !strings.Contains(joined, "verbal") || strings.Contains(joined, "quantitative") {
		t.Errorf("practice: %v", joined)
	}
	// A career that does not use programming gets no coding advice.
	none := BuildPlan(PlanInput{Target: target(), CodingRelevance: 0.1, AptitudeScore: &apt})
	for _, a := range none.Practice {
		if a.Area == "Coding" {
			t.Error("coding advice for a career that does not rely on it")
		}
	}
}

func TestHabitsOnlyForNonHighTraits(t *testing.T) {
	p := BuildPlan(PlanInput{Target: target(), Learning: map[string]Trait{"planning": {83, "high"}, "consistency": {40, "low"}}})
	if len(p.Habits) != 1 || p.Habits[0].Area != "Consistency" {
		t.Errorf("habits: %+v", p.Habits)
	}
	none := BuildPlan(PlanInput{Target: target()})
	if len(none.Habits) != 1 || none.Habits[0].Area != "Habits" {
		t.Errorf("with no questionnaire the plan should ask for it: %+v", none.Habits)
	}
}

func TestAlternativesOnlyWhenTargetIsAPoorInterestFit(t *testing.T) {
	good, bad := 80.0, 30.0
	other := &Match{Name: "Data Analyst", Readiness: Close, FinalScore: 70, Fit: &FitDetail{Interest: &good}}
	poor := &Match{Name: "Support", Readiness: Explore, FinalScore: 60, Fit: &FitDetail{Interest: &good}}
	in := PlanInput{Target: target(), Others: []*Match{poor, other}}
	got := BuildPlan(in).Alternatives
	if len(got) != 1 || got[0].Career != "Data Analyst" {
		t.Errorf("alternatives: %+v", got)
	}
	in.Target.Fit.Interest = &good
	if len(BuildPlan(in).Alternatives) != 0 {
		t.Error("no alternatives when the target already suits the student")
	}
	_ = bad
}

func TestProjectsAreEasiestFirst(t *testing.T) {
	p := BuildPlan(PlanInput{Target: target(), Ideas: []Idea{{"C", "", 3}, {"A", "", 1}, {"B", "", 2}}})
	if len(p.Projects) != 2 || p.Projects[0].Title != "A" || p.Projects[1].Title != "B" {
		t.Errorf("projects: %+v", p.Projects)
	}
}
