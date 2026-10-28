package aptitude

import (
	"math/rand/v2"
	"testing"
)

func pool(n int) map[string][]int64 {
	p := map[string][]int64{}
	var id int64
	for _, s := range Sections {
		for i := 0; i < n; i++ {
			id++
			p[s] = append(p[s], id)
		}
	}
	return p
}

func TestPickDrawsFromEverySectionWithoutRepeats(t *testing.T) {
	p := pool(10)
	got, err := Pick(p, PerSection, rand.New(rand.NewPCG(1, 2)))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != PerSection*len(Sections) {
		t.Fatalf("want %d questions, got %d", PerSection*len(Sections), len(got))
	}
	seen := map[int64]bool{}
	bySection := map[string]int{}
	for _, id := range got {
		if seen[id] {
			t.Errorf("question %d repeated", id)
		}
		seen[id] = true
		for s, ids := range p {
			for _, x := range ids {
				if x == id {
					bySection[s]++
				}
			}
		}
	}
	for _, s := range Sections {
		if bySection[s] != PerSection {
			t.Errorf("%s: want %d questions, got %d", s, PerSection, bySection[s])
		}
	}
}

func TestPickVariesAndFailsWhenThePoolIsTooSmall(t *testing.T) {
	a, _ := Pick(pool(10), PerSection, rand.New(rand.NewPCG(1, 1)))
	b, _ := Pick(pool(10), PerSection, rand.New(rand.NewPCG(9, 9)))
	same := true
	for i := range a {
		if a[i] != b[i] {
			same = false
		}
	}
	if same {
		t.Error("different seeds should give different tests")
	}
	if _, err := Pick(pool(PerSection-1), PerSection, rand.New(rand.NewPCG(1, 1))); err == nil {
		t.Error("a section with too few questions must be reported, not silently shortened")
	}
}

func TestScoreAndSections(t *testing.T) {
	asked := []Asked{
		{1, "quantitative", "a"}, {2, "quantitative", "b"},
		{3, "logical", "c"}, {4, "logical", "d"},
		{5, "verbal", "a"}, {6, "verbal", "b"},
	}
	r := Score(asked, map[int64]string{1: "a", 2: "a", 3: "c", 4: "d", 5: "a"}) // 6 left unanswered
	if r.Correct != 4 || r.Total != 6 || r.Score != 66.7 {
		t.Errorf("overall: %+v", r)
	}
	if s := r.Sections["quantitative"]; s.Correct != 1 || s.Total != 2 || s.Percent != 50 {
		t.Errorf("quantitative: %+v", s)
	}
	if s := r.Sections["logical"]; s.Percent != 100 {
		t.Errorf("logical: %+v", s)
	}
	if s := r.Sections["verbal"]; s.Correct != 1 || s.Percent != 50 {
		t.Errorf("an unanswered question is wrong: %+v", s)
	}
	if empty := Score(nil, nil); empty.Score != 0 || empty.Total != 0 {
		t.Errorf("no questions should not divide by zero: %+v", empty)
	}
}

func TestValidAnswersDropsForgedEntries(t *testing.T) {
	asked := []Asked{{1, "verbal", "a"}, {2, "verbal", "b"}}
	got := ValidAnswers(asked, map[int64]string{1: "a", 2: "z", 99: "a", 3: "b"})
	if len(got) != 1 || got[1] != "a" {
		t.Errorf("only valid answers to asked questions may remain, got %v", got)
	}
	// A forged answer for a question that was not asked must never raise the score.
	if r := Score(asked, got); r.Correct != 1 || r.Total != 2 {
		t.Errorf("score with forged entries: %+v", r)
	}
}

func TestSortedSections(t *testing.T) {
	r := Score([]Asked{{1, "verbal", "a"}, {2, "quantitative", "a"}, {3, "logical", "a"}}, nil)
	got := SortedSections(r)
	want := []string{"quantitative", "logical", "verbal"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}

func TestSettingsAreSensible(t *testing.T) {
	if TimeLimitSec < 5*60 || PerSection < 3 || GraceSec < 0 || RetakeAfterHours < 1 {
		t.Error("test settings look wrong")
	}
}
