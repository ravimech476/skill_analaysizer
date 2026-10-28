package bulkupload

import "testing"

func TestOneOf(t *testing.T) {
	if !oneOf(interviewCategories, "hr") || oneOf(interviewCategories, "HR") || oneOf(interviewCategories, "") {
		t.Error("oneOf must match exactly (callers lowercase first)")
	}
}

func TestClipText(t *testing.T) {
	if got := clipText("short", 10); got != "short" {
		t.Errorf("got %q", got)
	}
	if got := clipText("இது ஒரு நீண்ட வாக்கியம்", 5); len([]rune(got)) != 6 || got[len(got)-3:] != "…" {
		t.Errorf("clipping must count characters, not bytes: got %q", got)
	}
}

func TestEveryImportColumnSetHasRequiredColumns(t *testing.T) {
	for name, cols := range map[string][]column{"interview": interviewColumns, "materials": materialColumns, "questions": questionColumns} {
		if len(required(cols)) == 0 {
			t.Errorf("%s: at least one column must be required", name)
		}
		for _, c := range cols {
			if c.Help == "" {
				t.Errorf("%s: column %q needs help text for the Instructions sheet", name, c.Header)
			}
		}
	}
}
