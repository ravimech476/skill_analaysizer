package blooms

import (
	"context"
	"errors"
	"strings"
	"testing"

	"skills-analyzer/internal/modules/chat"
)

func TestVerbSignal(t *testing.T) {
	cases := []struct {
		q         string
		level     string
		strong    bool
		wantFound bool
	}{
		{"Define a stack.", "remember", true, true},
		{"List any four applications of queues.", "remember", true, true},
		{"What is a deadlock?", "remember", true, true},
		{"Q1. State the properties of a binary tree.", "remember", true, true},
		{"(a) Name the four conditions for deadlock", "remember", true, true},
		{"Explain the working of quick sort.", "understand", true, true},
		{"Write short notes on hashing.", "understand", true, true},
		{"Discuss the advantages of normalization", "understand", true, true},
		{"Write a program to reverse a linked list.", "apply", true, true},
		{"Solve the recurrence T(n) = 2T(n/2) + n.", "apply", true, true},
		{"Calculate the shortest path using Dijkstra's algorithm.", "apply", true, true},
		{"Differentiate between process and thread.", "analyze", true, true},
		{"Compare BFS and DFS.", "analyze", true, true},
		{"What is the difference between stack and heap?", "analyze", true, true},
		{"Justify the use of B-trees for database indexing.", "evaluate", true, true},
		{"Critique the use of global variables.", "evaluate", true, true},
		{"Design a parking lot system.", "create", true, true},
		{"Develop an algorithm for a library system.", "create", true, true},
		// a verb later in the sentence is weak evidence
		{"With a neat diagram, explain virtual memory.", "understand", false, true},
		// "Quicksort" must not lose its first letter to numbering rules
		{"Quicksort is fast. Compare it with merge sort.", "analyze", false, true},
		{"Tell something about it", "remember", true, true},
		{"Zebra stripes of banana", "", false, false},
	}
	for _, c := range cases {
		v, ok := verbSignal(c.q)
		if ok != c.wantFound {
			t.Errorf("%q: found=%v, want %v", c.q, ok, c.wantFound)
			continue
		}
		if !ok {
			continue
		}
		if v.level != c.level || v.strong != c.strong {
			t.Errorf("%q: got level=%s strong=%v (phrase %q), want level=%s strong=%v", c.q, v.level, v.strong, v.phrase, c.level, c.strong)
		}
	}
}

func TestVerbSignalLongestPhraseWins(t *testing.T) {
	// "evaluate the expression" is arithmetic (apply), not "evaluate" (judge).
	if v, _ := verbSignal("Evaluate the expression 3 + 4 * 2"); v.level != "apply" {
		t.Errorf("got %s, want apply", v.level)
	}
	if v, _ := verbSignal("Evaluate the merits of agile methods"); v.level != "evaluate" {
		t.Errorf("got %s, want evaluate", v.level)
	}
}

func TestParseModel(t *testing.T) {
	a, err := parseModel(` {"level": "Apply", "reason": " uses a formula "} `)
	if err != nil || a.Level != "apply" || a.Reason != "uses a formula" {
		t.Fatalf("got %+v, %v", a, err)
	}
	for _, bad := range []string{``, `not json`, `{"level":"expert","reason":"x"}`, `{"reason":"x"}`} {
		if _, err := parseModel(bad); err == nil {
			t.Errorf("parseModel(%q) should fail", bad)
		}
	}
}

func TestCombine(t *testing.T) {
	strong := &verbMatch{level: "remember", phrase: "define", strong: true}
	weak := &verbMatch{level: "understand", phrase: "explain", strong: false}
	model := func(l string) *modelAnswer { return &modelAnswer{Level: l, Reason: "because"} }

	cases := []struct {
		name  string
		verb  *verbMatch
		model *modelAnswer
		level string
		conf  string
	}{
		{"agree", strong, model("remember"), "remember", "high"},
		{"disagree, strong verb wins", strong, model("analyze"), "remember", "low"},
		{"disagree, weak verb loses", weak, model("analyze"), "analyze", "low"},
		{"verb only, strong", strong, nil, "remember", "medium"},
		{"verb only, weak", weak, nil, "understand", "low"},
		{"model only", nil, model("create"), "create", "medium"},
	}
	for _, c := range cases {
		got, err := combine(c.verb, c.model)
		if err != nil || got.Level != c.level || got.Confidence != c.conf {
			t.Errorf("%s: got %+v, %v; want level=%s confidence=%s", c.name, got, err, c.level, c.conf)
		}
		if got.Reason == "" || got.Method == "" {
			t.Errorf("%s: reason and method must be filled in", c.name)
		}
	}
	if _, err := combine(nil, nil); err == nil {
		t.Error("no signals should be an error")
	}
}

type fakeLLM struct {
	reply string
	err   error
	got   []chat.Message
}

func (f *fakeLLM) ChatJSON(_ context.Context, msgs []chat.Message, _ map[string]any) (string, error) {
	f.got = msgs
	return f.reply, f.err
}

func TestClassifyUsesBothSignals(t *testing.T) {
	llm := &fakeLLM{reply: `{"level":"remember","reason":"asks for a definition"}`}
	s, err := Classify(context.Background(), llm, "Define a queue.", 2)
	if err != nil || s.Level != "remember" || s.Confidence != "high" || s.Method != "verb+model" {
		t.Fatalf("got %+v, %v", s, err)
	}
	if !strings.Contains(llm.got[1].Content, "Define a queue.") || !strings.Contains(llm.got[1].Content, "Marks: 2") {
		t.Errorf("prompt should carry the question and marks, got %q", llm.got[1].Content)
	}
}

func TestClassifySurvivesModelFailure(t *testing.T) {
	for name, llm := range map[string]*fakeLLM{
		"error":   {err: errors.New("ollama down")},
		"garbage": {reply: "I think it is hard"},
	} {
		s, err := Classify(context.Background(), llm, "Explain deadlock prevention.", 5)
		if err != nil || s.Level != "understand" || s.Method != "verb" {
			t.Errorf("%s: got %+v, %v", name, s, err)
		}
	}
	// No verb and no model: nothing to go on.
	if _, err := Classify(context.Background(), &fakeLLM{err: errors.New("down")}, "Zebra stripes of banana", 0); err == nil {
		t.Error("expected an error when neither signal works")
	}
	if _, err := Classify(context.Background(), nil, "   ", 0); err == nil {
		t.Error("an empty question should be rejected")
	}
}
