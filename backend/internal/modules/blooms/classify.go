// Package blooms suggests a Bloom's Taxonomy level for exam questions. Two independent signals are
// combined: the action verb the question starts with (the way faculty classify by hand) and a local
// language model. When they agree the suggestion is high confidence; when they disagree staff are
// told to look. Nothing is saved until a staff member applies it.
package blooms

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"skills-analyzer/internal/modules/chat"
)

// Levels are the six levels of the revised taxonomy, lowest to highest, as stored in question_bank.
var Levels = []string{"remember", "understand", "apply", "analyze", "evaluate", "create"}

func validLevel(s string) bool {
	for _, l := range Levels {
		if l == s {
			return true
		}
	}
	return false
}

// Suggestion is the result for one question.
type Suggestion struct {
	Level      string `json:"level"`
	Confidence string `json:"confidence"` // high | medium | low
	Reason     string `json:"reason"`
	// Method says which signals produced the level: "verb+model", "verb", "model".
	Method string `json:"method"`
}

// ---- signal 1: the action verb ----

// verbRules maps leading phrases to a level. Longer phrases come first so "write a program" wins over "write".
var verbRules = []struct {
	level   string
	phrases []string
}{
	{"create", []string{"design", "develop", "create", "propose", "formulate", "construct", "compose", "devise", "plan", "build", "invent", "generate", "come up with", "suggest a new"}},
	{"evaluate", []string{"evaluate", "justify", "assess", "critique", "criticize", "criticise", "judge", "recommend", "argue", "defend", "validate", "rate", "which is better", "how effective", "do you agree"}},
	{"analyze", []string{"analyze", "analyse", "compare", "contrast", "differentiate", "distinguish", "examine", "investigate", "categorize", "categorise", "break down", "why", "relate", "what is the difference", "how does the", "infer", "deduce"}},
	{"apply", []string{"write a program", "write an algorithm", "write a code", "write a query", "solve", "calculate", "compute", "apply", "demonstrate", "implement", "use", "execute", "show that", "find", "determine", "trace", "simulate", "evaluate the expression", "convert", "perform", "sketch"}},
	{"understand", []string{"explain", "describe", "summarize", "summarise", "discuss", "illustrate", "interpret", "paraphrase", "give an example", "classify", "outline", "write short notes", "write short note", "write a short note", "write notes", "elaborate", "how", "what do you mean", "in your own words", "give reasons"}},
	{"remember", []string{"define", "list", "state", "name", "identify", "recall", "label", "what is", "what are", "who", "when", "where", "which", "mention", "enumerate", "write down", "give the", "write the", "write any", "tell", "recite", "match", "fill in", "true or false", "choose"}},
}

var (
	// Strips "Q1.", "1)", "(a)", "(iv)" style numbering, but never part of a word such as "Quicksort".
	leadNumbering = regexp.MustCompile(`^\s*(?:q(?:uestion)?\s*\.?\s*\d+\s*[.):]?\s*)?(?:\(?(?:\d{1,2}|[a-z]|[ivx]{1,4})[.)]\s*)*`)
	nonWord       = regexp.MustCompile(`[^a-z0-9' ]+`)
)

type verbMatch struct {
	level  string
	phrase string
	strong bool // the phrase opens the question, as in "Define …" or "Write a program …"
}

// verbSignal finds the action verb. A phrase at the very start is strong evidence; one that only appears
// later in the sentence is weak and is used only if nothing opens the question.
func verbSignal(question string) (verbMatch, bool) {
	q := strings.ToLower(strings.TrimSpace(question))
	q = leadNumbering.ReplaceAllString(q, "")
	q = strings.TrimSpace(nonWord.ReplaceAllString(q, " "))
	q = strings.Join(strings.Fields(q), " ")
	if q == "" {
		return verbMatch{}, false
	}

	var best verbMatch
	bestLen, found := 0, false
	for _, rule := range verbRules {
		for _, p := range rule.phrases {
			if q == p || strings.HasPrefix(q, p+" ") {
				if len(p) > bestLen {
					best, bestLen, found = verbMatch{rule.level, p, true}, len(p), true
				}
			}
		}
	}
	if found {
		return best, true
	}

	// Not at the start: look for the phrase anywhere, taking the earliest one.
	padded := " " + q + " "
	earliest := len(padded)
	for _, rule := range verbRules {
		for _, p := range rule.phrases {
			// Single short words such as "use" or "find" are too common mid-sentence to mean anything.
			if len(p) < 5 && !strings.Contains(p, " ") {
				continue
			}
			if i := strings.Index(padded, " "+p+" "); i >= 0 && i < earliest {
				best, earliest, found = verbMatch{rule.level, p, false}, i, true
			}
		}
	}
	return best, found
}

// ---- signal 2: the language model ----

const systemPrompt = `You classify exam questions by Bloom's Taxonomy (revised) for a college.
Levels, lowest to highest:
- remember: recall facts, definitions, terms (define, list, state, name)
- understand: explain ideas in own words (explain, describe, summarize, discuss)
- apply: use knowledge in a new situation, solve, calculate, write a program (solve, compute, implement)
- analyze: break into parts, compare, find relationships or causes (compare, differentiate, examine)
- evaluate: judge or justify using criteria (justify, assess, critique, recommend)
- create: design or produce something new (design, develop, propose, formulate)
Judge by the thinking the student must do, not by the topic. Marks are a weak hint: more marks often means a higher level.
Answer with JSON only: the level and a reason of at most 15 words.`

var responseSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"level":  map[string]any{"type": "string", "enum": Levels},
		"reason": map[string]any{"type": "string"},
	},
	"required": []string{"level", "reason"},
}

// modelReplier is what Classify needs from the language model (the Ollama client satisfies it).
type modelReplier interface {
	ChatJSON(ctx context.Context, msgs []chat.Message, schema map[string]any) (string, error)
}

type modelAnswer struct {
	Level  string `json:"level"`
	Reason string `json:"reason"`
}

// parseModel reads the model's JSON and rejects anything that is not one of the six levels.
func parseModel(raw string) (modelAnswer, error) {
	var a modelAnswer
	if err := json.Unmarshal([]byte(strings.TrimSpace(raw)), &a); err != nil {
		return a, fmt.Errorf("model did not return JSON: %w", err)
	}
	a.Level = strings.ToLower(strings.TrimSpace(a.Level))
	if !validLevel(a.Level) {
		return a, fmt.Errorf("model returned an unknown level %q", a.Level)
	}
	a.Reason = strings.TrimSpace(a.Reason)
	return a, nil
}

func askModel(ctx context.Context, llm modelReplier, question string, marks int) (modelAnswer, error) {
	user := "Question: " + strings.TrimSpace(question)
	if marks > 0 {
		user += fmt.Sprintf("\nMarks: %d", marks)
	}
	raw, err := llm.ChatJSON(ctx, []chat.Message{{Role: "system", Content: systemPrompt}, {Role: "user", Content: user}}, responseSchema)
	if err != nil {
		return modelAnswer{}, err
	}
	return parseModel(raw)
}

// ---- combining the two ----

// combine turns the two signals into one suggestion. verb is nil when no action verb was found and model is
// nil when the model was unavailable or answered badly.
func combine(verb *verbMatch, model *modelAnswer) (Suggestion, error) {
	switch {
	case verb != nil && model != nil && verb.level == model.Level:
		return Suggestion{Level: verb.level, Confidence: "high", Method: "verb+model",
			Reason: fmt.Sprintf("Starts with “%s” and the model agrees. %s", verb.phrase, model.Reason)}, nil

	case verb != nil && model != nil:
		// They disagree. A verb that opens the question is what faculty go by, so it wins; otherwise the model does.
		if verb.strong {
			return Suggestion{Level: verb.level, Confidence: "low", Method: "verb+model",
				Reason: fmt.Sprintf("Starts with “%s” (%s), but the model thinks %s. Please check.", verb.phrase, verb.level, model.Level)}, nil
		}
		return Suggestion{Level: model.Level, Confidence: "low", Method: "verb+model",
			Reason: fmt.Sprintf("%s The word “%s” suggests %s. Please check.", model.Reason, verb.phrase, verb.level)}, nil

	case verb != nil:
		conf := "medium"
		if !verb.strong {
			conf = "low"
		}
		return Suggestion{Level: verb.level, Confidence: conf, Method: "verb",
			Reason: fmt.Sprintf("Based on the word “%s”. The model was not available.", verb.phrase)}, nil

	case model != nil:
		return Suggestion{Level: model.Level, Confidence: "medium", Method: "model", Reason: model.Reason}, nil
	}
	return Suggestion{}, fmt.Errorf("could not classify this question")
}

// Classify suggests a level for one question. A model failure is tolerated when the verb gave an answer.
func Classify(ctx context.Context, llm modelReplier, question string, marks int) (Suggestion, error) {
	question = strings.TrimSpace(question)
	if question == "" {
		return Suggestion{}, fmt.Errorf("the question is empty")
	}
	var verb *verbMatch
	if v, ok := verbSignal(question); ok {
		verb = &v
	}
	var model *modelAnswer
	if llm != nil {
		if a, err := askModel(ctx, llm, question, marks); err == nil {
			model = &a
		}
	}
	return combine(verb, model)
}

// VerbLevel gives the level suggested by the question's action verb alone, with no model call. It is for
// bulk jobs, where asking the model about every row would be slow. ok is false when no verb was found.
func VerbLevel(question string) (level string, ok bool) {
	v, found := verbSignal(question)
	if !found {
		return "", false
	}
	return v.level, true
}
