package materials

import (
	"strings"
	"testing"
)

func TestCanIndex(t *testing.T) {
	for name, want := range map[string]bool{
		"notes.pdf": true, "Notes.DOCX": true, "readme.txt": true, "a.md": true,
		"slides.pptx": false, "sheet.xlsx": false, "noext": false, "photo.png": false,
	} {
		if got := canIndex(name); got != want {
			t.Errorf("canIndex(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestStudyType(t *testing.T) {
	if studyType("question_paper") != "question_paper" {
		t.Error("question papers keep their type")
	}
	for _, other := range []string{"notes", "slides", "reference", "video", "link", ""} {
		if studyType(other) != "notes" {
			t.Errorf("%q should be indexed as notes", other)
		}
	}
}

// Every library must have its own file category, table and permission, and a knowledge-base type the
// knowledge base accepts; a typo here would only show up at upload time.
func TestKinds(t *testing.T) {
	kbTypes := map[string]bool{"syllabus": true, "notes": true, "question_paper": true, "placement": true, "resume": true, "roadmap": true, "other": true}
	paths, tables, cats := map[string]bool{}, map[string]bool{}, map[string]bool{}
	for _, k := range kinds {
		if paths[k.path] || tables[k.table] || cats[k.category] {
			t.Errorf("%s: path, table and file category must be unique", k.path)
		}
		paths[k.path], tables[k.table], cats[k.category] = true, true, true
		if !strings.HasPrefix(k.path, "/") || !strings.Contains(k.info, k.table) || !strings.Contains(k.info, "$1") {
			t.Errorf("%s: info query must read its own table with $1", k.path)
		}
		if !strings.HasSuffix(k.updatePerm, ".update") {
			t.Errorf("%s: updatePerm %q", k.path, k.updatePerm)
		}
		for _, rowType := range []string{"notes", "technical", "question_paper", "mixed", ""} {
			if got := k.kbType(rowType); !kbTypes[got] {
				t.Errorf("%s: kbType(%q) = %q is not a knowledge-base type", k.path, rowType, got)
			}
		}
	}
	if len(kinds) != 3 {
		t.Errorf("expected 3 document libraries, got %d", len(kinds))
	}
}
