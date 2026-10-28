package talent

import (
	"math"
	"strings"
	"testing"
)

// answers builds a full answer set where every question gets v.
func answers(q *Questionnaire, v int) map[string]int {
	m := map[string]int{}
	for _, qu := range q.Questions {
		m[qu.ID] = v
	}
	return m
}

func traitByKey(r Result, key string) TraitScore {
	for _, t := range r.Traits {
		if t.Key == key {
			return t
		}
	}
	return TraitScore{}
}

// Every questionnaire must be internally consistent: unique ids, every question measuring a declared trait,
// and every trait measured; a mistake here would silently skew scores.
func TestQuestionnairesAreConsistent(t *testing.T) {
	for kind, q := range questionnaires {
		if q.Kind != kind || len(q.Scale) != 5 {
			t.Errorf("%s: kind and five-point scale must be set", kind)
		}
		traits := map[string]bool{}
		for _, tr := range q.Traits {
			traits[tr.Key] = true
		}
		ids, measured := map[string]bool{}, map[string]bool{}
		for _, qu := range q.Questions {
			if ids[qu.ID] {
				t.Errorf("%s: duplicate question id %s", kind, qu.ID)
			}
			ids[qu.ID] = true
			if !traits[qu.Trait] {
				t.Errorf("%s: question %s measures unknown trait %q", kind, qu.ID, qu.Trait)
			}
			measured[qu.Trait] = true
			if strings.TrimSpace(qu.Text) == "" {
				t.Errorf("%s: question %s has no text", kind, qu.ID)
			}
		}
		for k := range traits {
			if !measured[k] {
				t.Errorf("%s: trait %s has no questions", kind, k)
			}
		}
	}
	if len(kinds) != len(questionnaires) {
		t.Error("kinds and questionnaires must list the same questionnaires")
	}
}

func TestScoreRange(t *testing.T) {
	q := questionnaires["personality"]
	// All answers 5: forward items score 100 and reverse items 0, so each trait (2 forward, 2 reverse) is 50.
	for _, tr := range Score(q, answers(q, 5)).Traits {
		if tr.Score != 50 {
			t.Errorf("%s: all 5s should give 50 for a balanced trait, got %v", tr.Key, tr.Score)
		}
	}
	l := questionnaires["learning"]
	hi := Score(l, answers(l, 5))
	lo := Score(l, answers(l, 1))
	if s := traitByKey(hi, "planning").Score; s != 100 {
		t.Errorf("planning with all 5s = %v, want 100", s)
	}
	if s := traitByKey(lo, "planning").Score; s != 0 {
		t.Errorf("planning with all 1s = %v, want 0", s)
	}
	for _, tr := range append(hi.Traits, lo.Traits...) {
		if tr.Score < 0 || tr.Score > 100 || math.IsNaN(tr.Score) {
			t.Errorf("%s out of range: %v", tr.Key, tr.Score)
		}
	}
}

func TestReverseScoring(t *testing.T) {
	l := questionnaires["learning"]
	a := answers(l, 5)
	a["k3"] = 1 // disagreeing that you postpone studying is a good consistency answer
	if s := traitByKey(Score(l, a), "consistency").Score; s != 100 {
		t.Errorf("a reverse item counts as 6 minus the answer, consistency = %v", s)
	}
	a["k3"] = 5 // agreeing that you postpone studying lowers consistency
	if s := traitByKey(Score(l, a), "consistency").Score; math.Abs(s-66.7) > 0.05 {
		t.Errorf("consistency with one reversed 5 = %v, want about 66.7", s)
	}
}

func TestLevels(t *testing.T) {
	for score, want := range map[float64]string{0: "low", 39.9: "low", 40: "moderate", 64.9: "moderate", 65: "high", 100: "high"} {
		if got := levelOf(score); got != want {
			t.Errorf("levelOf(%v) = %s, want %s", score, got, want)
		}
	}
}

func TestInterestCodeAndFields(t *testing.T) {
	q := questionnaires["interests"]
	a := answers(q, 3)
	for _, qu := range q.Questions {
		switch qu.Trait {
		case "investigative":
			a[qu.ID] = 5
		case "artistic":
			a[qu.ID] = 4
		case "social":
			a[qu.ID] = 4
			if qu.ID == "s4" {
				a[qu.ID] = 3 // social slightly lower than artistic
			}
		}
	}
	r := Score(q, a)
	if !strings.Contains(r.Headline, "Interest code IAS") {
		t.Errorf("want code IAS (investigative, artistic, social), got %q", r.Headline)
	}
	if !strings.Contains(r.Headline, "data science") {
		t.Errorf("headline should point to the strongest type's field, got %q", r.Headline)
	}
	// Values are scored too but are never part of the interest code.
	if v := traitByKey(r, "val_salary"); v.Score != 50 || v.Meaning == "" {
		t.Errorf("value item: got %+v", v)
	}
}

func TestEveryTraitLevelHasAMeaning(t *testing.T) {
	for _, kind := range []string{"personality", "learning"} {
		q := questionnaires[kind]
		for _, tr := range q.Traits {
			for _, lvl := range []string{"low", "moderate", "high"} {
				if meaning(kind, tr.Key, lvl) == "" {
					t.Errorf("%s/%s/%s has no reading", kind, tr.Key, lvl)
				}
			}
		}
	}
}

func TestValidate(t *testing.T) {
	q := questionnaires["learning"]
	if err := Validate(q, answers(q, 3)); err != nil {
		t.Errorf("complete answers should pass: %v", err)
	}
	missing := answers(q, 3)
	delete(missing, "p1")
	if Validate(q, missing) == nil {
		t.Error("a missing answer must be rejected")
	}
	for _, bad := range []int{0, 6, -1} {
		a := answers(q, 3)
		a["p1"] = bad
		if Validate(q, a) == nil {
			t.Errorf("answer %d must be rejected", bad)
		}
	}
	extra := answers(q, 3)
	extra["zz"] = 3
	if Validate(q, extra) == nil {
		t.Error("an unknown question id must be rejected")
	}
}

func TestQualityScore(t *testing.T) {
	good := map[string]int{"readability": 5, "structure": 4, "testing": 3, "documentation": 4}
	if s, err := QualityScore(good); err != nil || s != 80 {
		t.Errorf("mean 4 of 5 = 80, got %v, %v", s, err)
	}
	for name, bad := range map[string]map[string]int{
		"missing criterion": {"readability": 5, "structure": 4, "testing": 3},
		"out of range":      {"readability": 6, "structure": 4, "testing": 3, "documentation": 4},
		"unknown key":       {"readability": 5, "structure": 4, "testing": 3, "style": 4},
		"zero":              {"readability": 0, "structure": 4, "testing": 3, "documentation": 4},
	} {
		if _, err := QualityScore(bad); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

func f(v float64) *float64 { return &v }

func TestIndexOnlyCountsVerified(t *testing.T) {
	// Nothing verified: no index at all, however much is listed.
	b := Index([]PlatformInput{{ProblemsSolved: 500}}, []ProjectInput{{QualityScore: f(90)}})
	if b.Index != nil || b.PlatformScore != nil || b.ProjectScore != nil {
		t.Errorf("unverified entries must not count, got %+v", b)
	}

	// Platform only: 150 of 300 problems is 50.
	b = Index([]PlatformInput{{ProblemsSolved: 150, Verified: true}}, nil)
	if b.Index == nil || *b.Index != 50 || b.ProblemsCounted != 150 {
		t.Errorf("platform only: %+v", b)
	}
	// Problems across platforms add up and cap at 100.
	b = Index([]PlatformInput{{ProblemsSolved: 250, Verified: true}, {ProblemsSolved: 250, Verified: true}, {ProblemsSolved: 999, Verified: false}}, nil)
	if *b.Index != 100 || b.ProblemsCounted != 500 || b.VerifiedPlatforms != 2 {
		t.Errorf("cap and unverified exclusion: %+v", b)
	}
	// Projects only: the mean of verified, reviewed projects.
	b = Index(nil, []ProjectInput{{QualityScore: f(80), Verified: true}, {QualityScore: f(60), Verified: true}, {QualityScore: f(10), Verified: false}, {Verified: true}})
	if *b.Index != 70 || b.VerifiedProjects != 2 {
		t.Errorf("projects only: %+v", b)
	}
	// Both: half and half.
	b = Index([]PlatformInput{{ProblemsSolved: 300, Verified: true}}, []ProjectInput{{QualityScore: f(60), Verified: true}})
	if *b.Index != 80 || *b.PlatformScore != 100 || *b.ProjectScore != 60 {
		t.Errorf("both: %+v", b)
	}
	if !strings.Contains(b.Formula, "300") {
		t.Errorf("the formula shown to staff should state the yardstick, got %q", b.Formula)
	}
}

func TestValidURL(t *testing.T) {
	for u, want := range map[string]bool{
		"https://leetcode.com/u/arun": true, "http://example.com": true, " https://github.com/x/y ": true,
		"javascript:alert(1)": false, "ftp://example.com": false, "leetcode.com/u/arun": false, "": false, "https://": false,
	} {
		if got := ValidURL(u); got != want {
			t.Errorf("ValidURL(%q) = %v, want %v", u, got, want)
		}
	}
}

func strp(s string) *string { return &s }

func TestPlatformBodyCheck(t *testing.T) {
	ok := platformBody{Platform: " LeetCode ", Username: " arun ", ProfileURL: strp("https://leetcode.com/u/arun")}
	if err := ok.check(); err != nil || ok.Platform != "leetcode" || ok.Username != "arun" {
		t.Errorf("should normalise and accept: %+v, %v", ok, err)
	}
	for name, b := range map[string]platformBody{
		"unknown platform": {Platform: "myspace", Username: "x"},
		"blank username":   {Platform: "leetcode", Username: "  "},
		"script url":       {Platform: "leetcode", Username: "x", ProfileURL: strp("javascript:alert(1)")},
	} {
		if err := b.check(); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
	empty := platformBody{Platform: "leetcode", Username: "x", ProfileURL: strp("  ")}
	if err := empty.check(); err != nil || empty.ProfileURL != nil {
		t.Errorf("a blank url should become none: %+v, %v", empty, err)
	}
}

func TestProjectBodyCheck(t *testing.T) {
	ok := projectBody{Title: " Library app ", RepoURL: strp("https://github.com/a/b")}
	if err := ok.check(); err != nil || ok.Title != "Library app" || ok.Status != "completed" {
		t.Errorf("defaults and trimming: %+v, %v", ok, err)
	}
	if err := (&projectBody{Title: "x", Status: "paused"}).check(); err == nil {
		t.Error("an unknown status must be rejected")
	}
	if err := (&projectBody{Title: "x", LiveURL: strp("javascript:1")}).check(); err == nil {
		t.Error("a script live_url must be rejected")
	}
	if err := (&projectBody{Title: "   "}).check(); err == nil {
		t.Error("a blank title must be rejected")
	}
}

func TestReviewScore(t *testing.T) {
	if s, err := ReviewScore(map[string]int{"speaking": 4, "writing": 3, "listening": 5, "teamwork": 4}); err != nil || s != 80 {
		t.Errorf("mean 4 of 5 = 80, got %v, %v", s, err)
	}
	for name, bad := range map[string]map[string]int{
		"missing":  {"speaking": 4, "writing": 3, "listening": 5},
		"too high": {"speaking": 6, "writing": 3, "listening": 5, "teamwork": 4},
		"unknown":  {"speaking": 4, "writing": 3, "listening": 5, "humour": 4},
	} {
		if _, err := ReviewScore(bad); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

func TestCommunicationScore(t *testing.T) {
	if CommunicationScore(nil, f(90)) != nil {
		t.Error("a self-report alone must not set the score")
	}
	if s := CommunicationScore(f(60), nil); s == nil || *s != 60 {
		t.Errorf("review alone counts fully, got %v", s)
	}
	// 70% review + 30% self: 0.7*60 + 0.3*100 = 72
	if s := CommunicationScore(f(60), f(100)); s == nil || *s != 72 {
		t.Errorf("blend = %v, want 72", s)
	}
}

func TestSelfMean(t *testing.T) {
	if SelfMean(nil) != nil || SelfMean(&Result{}) != nil {
		t.Error("nothing to average")
	}
	q := questionnaires["communication"]
	if m := SelfMean(ptrResult(Score(q, answers(q, 5)))); m == nil || *m != 66.7 {
		t.Errorf("all 5s with one reversed item in three averages 66.7, got %v", m)
	}
}

func ptrResult(r Result) *Result { return &r }

func TestCommunicationQuestionnaire(t *testing.T) {
	q := questionnaires["communication"]
	if q == nil || len(q.Traits) != 5 || len(q.Questions) != 15 {
		t.Fatalf("communication questionnaire: %+v", q)
	}
	for _, tr := range q.Traits {
		for _, lvl := range []string{"low", "moderate", "high"} {
			if meaning("communication", tr.Key, lvl) == "" {
				t.Errorf("communication/%s/%s has no reading", tr.Key, lvl)
			}
		}
	}
}
