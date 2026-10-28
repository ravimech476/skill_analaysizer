package skillsuggest

import (
	"context"
	"errors"
	"strings"
	"testing"

	"skills-analyzer/internal/modules/chat"
)

func TestLevelFor(t *testing.T) {
	cases := map[float64]int{100: 5, 90: 5, 89.9: 4, 80: 4, 79.9: 3, 70: 3, 69.9: 2, 60: 2, 59.9: 1, 50: 1, 49.9: 0, 0: 0}
	for pct, want := range cases {
		if got := levelFor(pct); got != want {
			t.Errorf("levelFor(%v) = %d, want %d", pct, got, want)
		}
	}
}

var (
	marks = []SubjectMark{
		{SubjectID: 1, Subject: "Data Structures", Percent: 90},
		{SubjectID: 2, Subject: "DS Lab", Percent: 70},
		{SubjectID: 3, Subject: "Discrete Maths", Percent: 40},
	}
	links = map[int64][]SkillLink{
		1: {{SkillID: 10, Skill: "DSA", Weight: 1}, {SkillID: 11, Skill: "SQL", Weight: 0.5}},
		2: {{SkillID: 10, Skill: "DSA", Weight: 1}},
		3: {{SkillID: 12, Skill: "Problem Solving", Weight: 1}},
	}
)

func TestCandidatesWeightedAverage(t *testing.T) {
	got := Candidates(marks, links, nil)
	byID := map[int64]Candidate{}
	for _, c := range got {
		byID[c.SkillID] = c
	}
	dsa := byID[10]
	if dsa.Percent != 80 || dsa.Level != 4 || len(dsa.Evidence) != 2 {
		t.Fatalf("DSA: want 80%% level 4 with 2 subjects, got %+v", dsa)
	}
	if byID[11].Level != 5 { // one subject at 90%
		t.Errorf("SQL: want level 5, got %+v", byID[11])
	}
	if _, ok := byID[12]; ok {
		t.Error("40% is below 50%, so Problem Solving must not be suggested")
	}
}

func TestCandidatesOrderAndEvidenceAreStable(t *testing.T) {
	got := Candidates(marks, links, nil)
	if len(got) != 2 || got[0].Skill != "SQL" || got[1].Skill != "DSA" {
		t.Fatalf("want SQL (5) before DSA (4), got %+v", got)
	}
	if got[1].Evidence[0].SubjectID != 1 || got[1].Evidence[1].SubjectID != 2 {
		t.Errorf("evidence should be sorted by subject id, got %+v", got[1].Evidence)
	}
}

func TestCandidatesNeverLowerOrRepeatExistingLevels(t *testing.T) {
	// Already recorded at 4 or 5: nothing to suggest. Recorded at 2: raise to 4.
	got := Candidates(marks, links, map[int64]int{10: 4, 11: 5})
	if len(got) != 0 {
		t.Fatalf("existing levels already match the marks, got %+v", got)
	}
	got = Candidates(marks, links, map[int64]int{10: 2})
	var dsa *Candidate
	for i := range got {
		if got[i].SkillID == 10 {
			dsa = &got[i]
		}
	}
	if dsa == nil || dsa.Level != 4 || dsa.Current != 2 {
		t.Fatalf("want a raise from 2 to 4, got %+v", dsa)
	}
}

func TestCandidatesIgnoreUnmappedSubjectsAndBadWeights(t *testing.T) {
	if got := Candidates([]SubjectMark{{SubjectID: 9, Subject: "Unmapped", Percent: 95}}, links, nil); len(got) != 0 {
		t.Errorf("a subject with no mapping gives no suggestion, got %+v", got)
	}
	zero := map[int64][]SkillLink{1: {{SkillID: 10, Skill: "DSA", Weight: 0}}}
	if got := Candidates(marks, zero, nil); len(got) != 0 {
		t.Errorf("zero weight must not divide by zero or count, got %+v", got)
	}
	if got := Candidates(nil, links, nil); len(got) != 0 {
		t.Errorf("no marks, no suggestions, got %+v", got)
	}
}

func TestExplainUsesOnlyEvidence(t *testing.T) {
	c := Candidates(marks, links, map[int64]int{10: 2})[1]
	s := Explain(c)
	for _, want := range []string{"DSA", "level 4", "Data Structures 90%", "DS Lab 70%", "currently recorded as 2"} {
		if !strings.Contains(s, want) {
			t.Errorf("explanation %q should contain %q", s, want)
		}
	}
}

var catalogue = []SkillOption{{1, "Python"}, {2, "SQL"}, {3, "Data Structures & Algorithms"}, {4, "Git"}, {5, "Docker"}, {6, "Aptitude"}}

func TestParseMapping(t *testing.T) {
	raw := `{"skills":[
		{"skill":"sql","strength":"secondary","reason":" joins and queries "},
		{"skill":"Data Structures & Algorithms","strength":"primary","reason":"core"},
		{"skill":"Quantum Basketry","strength":"primary","reason":"invented"},
		{"skill":"SQL","strength":"primary","reason":"duplicate"}]}`
	got, err := parseMapping(raw, catalogue)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("unknown and duplicate skills must be dropped, got %+v", got)
	}
	if got[0].SkillID != 3 || got[0].Weight != 1 {
		t.Errorf("primary skill should come first with weight 1, got %+v", got[0])
	}
	if got[1].SkillID != 2 || got[1].Weight != 0.5 || got[1].Reason != "joins and queries" {
		t.Errorf("secondary skill: got %+v", got[1])
	}
}

func TestParseMappingCapAndBadInput(t *testing.T) {
	raw := `{"skills":[` + strings.Repeat(`{"skill":"Python","strength":"primary","reason":"x"},`, 0) +
		`{"skill":"Python","strength":"primary","reason":"a"},{"skill":"SQL","strength":"primary","reason":"b"},
		{"skill":"Git","strength":"secondary","reason":"c"},{"skill":"Docker","strength":"secondary","reason":"d"},
		{"skill":"Aptitude","strength":"secondary","reason":"e"}]}`
	got, err := parseMapping(raw, catalogue)
	if err != nil || len(got) != maxMapped {
		t.Fatalf("want %d suggestions, got %d (%v)", maxMapped, len(got), err)
	}
	if got, err := parseMapping(`{"skills":[]}`, catalogue); err != nil || len(got) != 0 {
		t.Errorf("an empty list is a valid answer, got %+v, %v", got, err)
	}
	if _, err := parseMapping(`not json`, catalogue); err == nil {
		t.Error("non-JSON must be rejected")
	}
}

type fakeModel struct {
	json string
	err  error
	user string
}

func (f *fakeModel) ChatJSON(_ context.Context, msgs []chat.Message, _ map[string]any) (string, error) {
	f.user = msgs[len(msgs)-1].Content
	return f.json, f.err
}

func TestSuggestMapping(t *testing.T) {
	m := &fakeModel{json: `{"skills":[{"skill":"Python","strength":"primary","reason":"programming"}]}`}
	got, err := SuggestMapping(context.Background(), m, "CS1", "Intro to Programming", "theory", []string{"Unit 1  variables\nand loops"}, catalogue)
	if err != nil || len(got) != 1 || got[0].Skill != "Python" {
		t.Fatalf("got %+v, %v", got, err)
	}
	for _, want := range []string{"Intro to Programming (CS1)", "Syllabus excerpts", "Unit 1 variables and loops", "Skill catalogue: Python, SQL"} {
		if !strings.Contains(m.user, want) {
			t.Errorf("prompt should contain %q, got:\n%s", want, m.user)
		}
	}

	if _, err := SuggestMapping(context.Background(), &fakeModel{err: errors.New("down")}, "X", "Y", "theory", nil, catalogue); err == nil {
		t.Error("a model failure must be reported, not hidden")
	}
	if _, err := SuggestMapping(context.Background(), m, "X", "Y", "theory", nil, nil); err == nil {
		t.Error("an empty catalogue must be an error")
	}
}

func TestSummarizeUsesOnlyTheNumbers(t *testing.T) {
	cands := Candidates(marks, links, map[int64]int{10: 2})
	s := Summarize("Arun", marks, cands, []string{"Discrete Maths"})
	if !strings.Contains(s, "Arun is strongest in Data Structures (90%).") {
		t.Errorf("only subjects at 80%% or more are strong, got %q", s)
	}
	for _, want := range []string{"Needs attention: Discrete Maths (40%).", "raising SQL to level 5 and DSA to level 4", "No skill mapping exists for Discrete Maths"} {
		if !strings.Contains(s, want) {
			t.Errorf("summary %q should contain %q", s, want)
		}
	}
}

func TestSummarizeEdgeCases(t *testing.T) {
	if s := Summarize("Asha", nil, nil, nil); !strings.Contains(s, "no marks recorded") {
		t.Errorf("no marks: got %q", s)
	}
	s := Summarize("Asha", []SubjectMark{{1, "Maths", 85}, {2, "Physics", 83}, {3, "Chemistry", 82}, {4, "English", 81}}, nil, nil)
	if !strings.Contains(s, "Maths (85%), Physics (83%) and Chemistry (82%).") || strings.Contains(s, "English") {
		t.Errorf("at most three strong subjects, best first, got %q", s)
	}
	if !strings.Contains(s, "do not support any skill level above what is already recorded") {
		t.Errorf("no candidates: got %q", s)
	}
}
