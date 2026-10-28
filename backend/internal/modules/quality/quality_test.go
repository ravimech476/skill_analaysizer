package quality

import "testing"

func p(id int64, reg string) Person { return Person{ID: id, Name: reg, RegisterNo: reg} }

var sample = []Check{
	{Key: "e", Area: "marks", Label: "Bad marks", Severity: Error},
	{Key: "w", Area: "profile", Label: "No email", Severity: Warning},
	{Key: "i", Area: "profile", Label: "No photo", Severity: Info},
}

func TestAggregateCountsAndRanks(t *testing.T) {
	hits := map[string][]Person{
		"e": {p(1, "A1")},
		"w": {p(1, "A1"), p(2, "A2")},
		"i": {p(1, "A1"), p(2, "A2"), p(3, "A3")},
	}
	r := Aggregate(10, sample, hits)
	if r.Errors != 1 || r.Warnings != 2 || r.Infos != 3 {
		t.Errorf("severity counts: %+v", r)
	}
	// Students 1 and 2 have an error or warning; 3 has only an info issue, which does not block.
	if r.CleanStudents != 8 {
		t.Errorf("clean students: %d", r.CleanStudents)
	}
	if r.Checks[0].Key != "e" {
		t.Errorf("errors should be listed first: %+v", r.Checks)
	}
	if len(r.NeedAttention) != 3 || r.NeedAttention[0].ID != 1 || r.NeedAttention[0].Score != 6 {
		t.Errorf("attention list: %+v", r.NeedAttention)
	}
	for _, a := range r.Areas {
		switch a.Key {
		case "marks":
			if a.Clean != 9 || a.Percent != 90 {
				t.Errorf("marks area: %+v", a)
			}
		case "profile":
			if a.Clean != 7 { // students 1, 2 and 3 each have a profile issue
				t.Errorf("profile area: %+v", a)
			}
		}
	}
}

func TestAggregateWithNoStudentsOrIssues(t *testing.T) {
	r := Aggregate(0, sample, map[string][]Person{})
	if r.Students != 0 || r.CleanStudents != 0 || len(r.NeedAttention) != 0 {
		t.Errorf("empty: %+v", r)
	}
	r = Aggregate(5, sample, map[string][]Person{})
	if r.CleanStudents != 5 || r.Areas[0].Percent != 100 {
		t.Errorf("nothing wrong: %+v", r)
	}
}

func TestSampleIsLimited(t *testing.T) {
	var many []Person
	for i := 1; i <= 20; i++ {
		many = append(many, p(int64(i), "R"))
	}
	r := Aggregate(20, sample, map[string][]Person{"w": many})
	for _, c := range r.Checks {
		if c.Key == "w" && (len(c.Sample) != sampleSize || c.Count != 20) {
			t.Errorf("sample %d, count %d", len(c.Sample), c.Count)
		}
	}
	if len(r.NeedAttention) != attentionTop {
		t.Errorf("attention list should be capped, got %d", len(r.NeedAttention))
	}
}

func TestEveryCheckIsComplete(t *testing.T) {
	seen := map[string]bool{}
	areas := map[string]bool{}
	for _, a := range Areas {
		areas[a.Key] = true
	}
	for _, c := range Checks {
		if c.Key == "" || c.Label == "" || c.Where == "" || c.Hint == "" || seen[c.Key] || !areas[c.Area] {
			t.Errorf("bad check: %+v", c)
		}
		if _, ok := severityWeight[c.Severity]; !ok {
			t.Errorf("%s: unknown severity %q", c.Key, c.Severity)
		}
		seen[c.Key] = true
	}
}
