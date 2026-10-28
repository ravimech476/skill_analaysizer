package kb

import (
	"strings"
	"testing"
)

func TestParseSections(t *testing.T) {
	got := ParseSections("intro line\n\n## First topic\nBody one.\nMore.\n\n## Second\r\nBody two.\n")
	if len(got) != 2 || got[0].Title != "First topic" || got[0].Body != "Body one.\nMore." || got[1].Body != "Body two." {
		t.Errorf("sections: %+v", got)
	}
	if len(ParseSections("no headings here")) != 0 {
		t.Error("text before the first heading is not a section")
	}
}

func TestSourceNameChangesWithText(t *testing.T) {
	a := Section{Title: "Career path: Data Analyst", Body: "one"}
	p1, n1 := sourceName(a)
	_, n2 := sourceName(Section{Title: a.Title, Body: "two"})
	if p1 != "seed-career-path-data-analyst-" || !strings.HasPrefix(n1, p1) || !strings.HasSuffix(n1, ".txt") {
		t.Errorf("name: %q %q", p1, n1)
	}
	if n1 == n2 {
		t.Error("an edited section must get a new source name so it is re-ingested")
	}
	if _, again := sourceName(a); again != n1 {
		t.Error("the same text must give the same name so it is not ingested twice")
	}
}

func TestBuiltInKnowledgeIsWellFormed(t *testing.T) {
	allowed := map[string]bool{"syllabus": true, "notes": true, "question_paper": true, "placement": true, "resume": true, "roadmap": true, "other": true}
	titles := map[string]bool{}
	total := 0
	for _, f := range seedFiles {
		if !allowed[f.DocType] {
			t.Errorf("%s: document type %q is not allowed by the database", f.File, f.DocType)
		}
		raw, err := knowledgeFS.ReadFile("knowledge/" + f.File)
		if err != nil {
			t.Fatal(err)
		}
		secs := ParseSections(string(raw))
		if len(secs) == 0 {
			t.Errorf("%s has no sections", f.File)
		}
		for _, s := range secs {
			total++
			if titles[s.Title] {
				t.Errorf("duplicate title %q", s.Title)
			}
			titles[s.Title] = true
			words := len(strings.Fields(s.Title + " " + s.Body))
			if words < 40 {
				t.Errorf("%q is too short to be useful (%d words)", s.Title, words)
			}
			if words > chunkWords {
				t.Errorf("%q has %d words and would be split across passages; keep each section within %d", s.Title, words, chunkWords)
			}
		}
	}
	if total < 30 {
		t.Errorf("expected a substantial knowledge base, got %d sections", total)
	}
}
