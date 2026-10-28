package skillsuggest

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"skills-analyzer/internal/modules/chat"
)

// model is what this package needs from the language model (the Ollama client satisfies it).
type model interface {
	ChatJSON(ctx context.Context, msgs []chat.Message, schema map[string]any) (string, error)
}

// SkillOption is a skill from the college's catalogue; the model may only choose from these.
type SkillOption struct {
	ID   int64
	Name string
}

// MappingSuggestion is one proposed subject→skill link.
type MappingSuggestion struct {
	SkillID int64   `json:"skill_id"`
	Skill   string  `json:"skill"`
	Weight  float64 `json:"weight"`
	Reason  string  `json:"reason"`
}

const (
	maxMapped       = 4
	primaryWeight   = 1.0
	secondaryWeight = 0.5
)

const mappingPrompt = `You decide which skills from a fixed catalogue a college subject directly develops.
Rules:
- Choose between 1 and 4 skills, only ones a student must practise to do well in this subject. Fewer is better.
- Use only skills from the catalogue, spelled exactly.
- Do not choose general soft skills (Communication, Teamwork, Aptitude, Problem Solving) unless the subject is explicitly about them.
- "primary" is the subject's core skill, "secondary" is a supporting one.
- If nothing in the catalogue clearly fits, or you are not sure, return an empty list. Most catalogue skills are about computing, so subjects such as electronics, signals or circuits often have no match.
Give each choice a reason of at most 12 words.`

func mappingSchema(options []SkillOption) map[string]any {
	names := make([]string, len(options))
	for i, o := range options {
		names[i] = o.Name
	}
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"skills": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"skill":    map[string]any{"type": "string", "enum": names},
						"strength": map[string]any{"type": "string", "enum": []string{"primary", "secondary"}},
						"reason":   map[string]any{"type": "string"},
					},
					"required": []string{"skill", "strength", "reason"},
				},
			},
		},
		"required": []string{"skills"},
	}
}

// parseMapping keeps only valid, distinct catalogue skills, primary ones first, at most maxMapped.
func parseMapping(raw string, options []SkillOption) ([]MappingSuggestion, error) {
	var out struct {
		Skills []struct {
			Skill    string `json:"skill"`
			Strength string `json:"strength"`
			Reason   string `json:"reason"`
		} `json:"skills"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(raw)), &out); err != nil {
		return nil, fmt.Errorf("model did not return JSON: %w", err)
	}
	byName := map[string]SkillOption{}
	for _, o := range options {
		byName[strings.ToLower(o.Name)] = o
	}
	seen := map[int64]bool{}
	var primary, secondary []MappingSuggestion
	for _, s := range out.Skills {
		opt, ok := byName[strings.ToLower(strings.TrimSpace(s.Skill))]
		if !ok || seen[opt.ID] {
			continue
		}
		seen[opt.ID] = true
		m := MappingSuggestion{SkillID: opt.ID, Skill: opt.Name, Weight: secondaryWeight, Reason: strings.TrimSpace(s.Reason)}
		if strings.EqualFold(s.Strength, "primary") {
			m.Weight = primaryWeight
			primary = append(primary, m)
		} else {
			secondary = append(secondary, m)
		}
	}
	all := append(primary, secondary...)
	if len(all) > maxMapped {
		all = all[:maxMapped]
	}
	return all, nil
}

// SuggestMapping asks the model which catalogue skills a subject builds. syllabus holds excerpts of uploaded
// syllabus documents for the subject, when there are any; they make the answer much better than the name alone.
func SuggestMapping(ctx context.Context, llm model, code, name, subjectType string, syllabus []string, options []SkillOption) ([]MappingSuggestion, error) {
	if len(options) == 0 {
		return nil, fmt.Errorf("there are no skills in the catalogue")
	}
	names := make([]string, len(options))
	for i, o := range options {
		names[i] = o.Name
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Subject: %s (%s)\nType: %s\n", name, code, subjectType)
	if len(syllabus) > 0 {
		b.WriteString("Syllabus excerpts:\n")
		for _, s := range syllabus {
			b.WriteString("- " + strings.Join(strings.Fields(s), " ") + "\n")
		}
	}
	b.WriteString("Skill catalogue: " + strings.Join(names, ", "))

	raw, err := llm.ChatJSON(ctx, []chat.Message{{Role: "system", Content: mappingPrompt}, {Role: "user", Content: b.String()}}, mappingSchema(options))
	if err != nil {
		return nil, err
	}
	return parseMapping(raw, options)
}
