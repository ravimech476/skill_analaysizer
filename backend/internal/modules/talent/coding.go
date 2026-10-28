package talent

import (
	"fmt"
	"math"
	"net/url"
	"strings"
)

// Platforms a coding profile can be on.
var Platforms = []string{"leetcode", "hackerrank", "codechef", "codeforces", "geeksforgeeks", "hackerearth", "other"}

// ProblemsForFullScore is how many problems solved on verified platforms count as a full 100. It is a
// college-wide yardstick, not a measure of difficulty, and is shown to staff with the index.
const ProblemsForFullScore = 300.0

// RubricCriteria are what staff rate (1 to 5) when they review a project's code.
var RubricCriteria = []string{"readability", "structure", "testing", "documentation"}

func oneOf(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// ValidURL accepts only http and https links, so a stored link can never run script when clicked.
func ValidURL(s string) bool {
	u, err := url.Parse(strings.TrimSpace(s))
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// QualityScore turns a staff rubric into 0-100: the mean of the four criteria, each 1 to 5, times 20.
func QualityScore(rubric map[string]int) (float64, error) {
	if len(rubric) != len(RubricCriteria) {
		return 0, fmt.Errorf("rate all four criteria: %s", strings.Join(RubricCriteria, ", "))
	}
	total := 0
	for _, c := range RubricCriteria {
		v, ok := rubric[c]
		if !ok || v < 1 || v > 5 {
			return 0, fmt.Errorf("%s must be rated from 1 to 5", c)
		}
		total += v
	}
	return math.Round(float64(total)/float64(len(RubricCriteria))*20*10) / 10, nil
}

// PlatformInput is a coding profile, as far as the index is concerned.
type PlatformInput struct {
	ProblemsSolved int
	Verified       bool
}

// ProjectInput is a project, as far as the index is concerned.
type ProjectInput struct {
	QualityScore *float64
	Verified     bool
}

// Breakdown shows how the programming skill index was reached.
type Breakdown struct {
	PlatformScore     *float64 `json:"platform_score"`
	ProjectScore      *float64 `json:"project_score"`
	VerifiedPlatforms int      `json:"verified_platforms"`
	VerifiedProjects  int      `json:"verified_projects"`
	ProblemsCounted   int      `json:"problems_counted"`
	Index             *float64 `json:"index"`
	Formula           string   `json:"formula"`
}

// Index is the programming skill index (0-100). Only verified entries count: problems solved on verified
// platforms (300 or more is full marks) and the code-quality rating of verified, reviewed projects. When both
// exist they count equally; with only one, that one decides; with neither there is no index.
func Index(platforms []PlatformInput, projects []ProjectInput) Breakdown {
	b := Breakdown{Formula: fmt.Sprintf("Half from problems solved on verified platforms (%.0f solved = 100), half from the code-quality rating of verified projects. If only one exists it counts fully.", ProblemsForFullScore)}

	for _, p := range platforms {
		if p.Verified {
			b.VerifiedPlatforms++
			b.ProblemsCounted += p.ProblemsSolved
		}
	}
	if b.VerifiedPlatforms > 0 {
		s := math.Min(100, float64(b.ProblemsCounted)/ProblemsForFullScore*100)
		s = math.Round(s*10) / 10
		b.PlatformScore = &s
	}

	var sum float64
	for _, p := range projects {
		if p.Verified && p.QualityScore != nil {
			b.VerifiedProjects++
			sum += *p.QualityScore
		}
	}
	if b.VerifiedProjects > 0 {
		s := math.Round(sum/float64(b.VerifiedProjects)*10) / 10
		b.ProjectScore = &s
	}

	var idx float64
	switch {
	case b.PlatformScore != nil && b.ProjectScore != nil:
		idx = (*b.PlatformScore + *b.ProjectScore) / 2
	case b.PlatformScore != nil:
		idx = *b.PlatformScore
	case b.ProjectScore != nil:
		idx = *b.ProjectScore
	default:
		return b
	}
	idx = math.Round(idx*10) / 10
	b.Index = &idx
	return b
}
