package insight

import (
	"strings"
	"testing"
)

func sample() *Facts {
	apt, comm := 80.0, 40.0
	return &Facts{
		Name: "Arun Kumar", CGPA: 9.6, Backlogs: 0,
		StrongSubject: []SubjectFact{{"Data Structures", 94}},
		WeakSubject:   []SubjectFact{{"Physics", 52}},
		TopSkills:     []SkillFact{{"Java", 4, 78}, {"SQL", 3, 60}},
		Aptitude:      &apt, Communication: &comm,
		Careers: []CareerFact{{"Business Analyst", "ready", 80.5, "Teamwork", 0, 3}},
	}
}

func TestComposeUsesOnlyTheFacts(t *testing.T) {
	in := Compose(sample())
	if in.Source != "rules" || !strings.Contains(in.Summary, "9.60") || !strings.Contains(in.Summary, "Java and SQL") {
		t.Errorf("summary: %q", in.Summary)
	}
	joined := strings.Join(append(append(in.Strengths, in.FocusAreas...), in.NextSteps...), "\n")
	for _, want := range []string{"Data Structures", "Physics", "Communication score", "Teamwork"} {
		if !strings.Contains(joined, want) {
			t.Errorf("expected %q in %q", want, joined)
		}
	}
	if len(in.NextSteps) > 4 {
		t.Errorf("too many next steps: %d", len(in.NextSteps))
	}
}

func TestComposeOnAnEmptyRecord(t *testing.T) {
	in := Compose(&Facts{Name: "New Student"})
	if in.Summary == "" || len(in.NextSteps) == 0 {
		t.Errorf("an empty record should still get a summary and something to do: %+v", in)
	}
}

func TestAllowedAcceptsFactsAndRejectsInventions(t *testing.T) {
	facts := sample().Text()
	ok := "Your CGPA of 9.6 is excellent, and Java is your strongest skill. Work on Physics next."
	if !Allowed(ok, facts) {
		t.Error("text made only of facts was rejected")
	}
	if !Allowed("Your aptitude score of 80 is a real strength.", facts) {
		t.Error("a rounded fact number should be allowed")
	}
	for name, bad := range map[string]string{
		"invented number":  "You scored 91 in aptitude.",
		"invented company": "You are a great fit for Google.",
		"invented skill":   "Learning Kubernetes would help you.",
		"empty":            "  ",
	} {
		if Allowed(bad, facts) {
			t.Errorf("%s was allowed: %q", name, bad)
		}
	}
}

func TestHashChangesWithFacts(t *testing.T) {
	a := sample()
	b := sample()
	if a.Hash() != b.Hash() {
		t.Error("the same facts must hash the same")
	}
	b.CGPA = 9.1
	if a.Hash() == b.Hash() {
		t.Error("changed facts must change the hash")
	}
}
