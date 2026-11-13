// Package faculty serves what staff need to watch a class: placement readiness for every student,
// who is at risk and why, and how each student's scores have moved over time. Everything here is
// computed from recorded data with configurable rules, so staff can always see why a student was flagged.
package faculty

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

	"skills-analyzer/internal/pkg/dbutil"
)

const skillsForFull = 5 // recorded skills that give the full skills score

// app_config keys for readiness scoring.
const (
	ConfigReadinessWeights = "readiness_weights"
	ConfigRiskThresholds   = "risk_thresholds"
)

const (
	RiskHigh   = "high"
	RiskMedium = "medium"
	RiskNone   = "none"
)

// ReadinessWeights holds the configurable weight for each readiness component.
// All weights should sum to 1.0.
type ReadinessWeights struct {
	CGPA          float64 `json:"cgpa"`
	Skills        float64 `json:"skills"`
	Aptitude      float64 `json:"aptitude"`
	Coding        float64 `json:"coding"`
	Attendance    float64 `json:"attendance"`
	Communication float64 `json:"communication"`
}

// DefaultReadinessWeights is the fallback when no config row exists.
var DefaultReadinessWeights = ReadinessWeights{
	CGPA: 0.25, Skills: 0.20, Aptitude: 0.15,
	Coding: 0.15, Attendance: 0.15, Communication: 0.10,
}

// RiskThresholds controls when overall readiness maps to a risk level.
// A student whose readiness is below High is high risk; below Medium is medium risk.
type RiskThresholds struct {
	High   float64 `json:"high"`
	Medium float64 `json:"medium"`
}

// DefaultRiskThresholds is the fallback when no config row exists.
var DefaultRiskThresholds = RiskThresholds{High: 30, Medium: 50}

// LoadReadinessWeights reads weights from app_config, falling back to defaults.
func LoadReadinessWeights(ctx context.Context, db dbutil.DBTX) (ReadinessWeights, error) {
	var raw []byte
	err := db.QueryRow(ctx, `SELECT value FROM app_config WHERE key = $1`, ConfigReadinessWeights).Scan(&raw)
	if err != nil {
		if dbutil.IsNoRows(err) {
			return DefaultReadinessWeights, nil
		}
		return DefaultReadinessWeights, err
	}
	w := DefaultReadinessWeights
	if err := json.Unmarshal(raw, &w); err != nil {
		return DefaultReadinessWeights, nil
	}
	return w, nil
}

// LoadRiskThresholds reads risk thresholds from app_config, falling back to defaults.
func LoadRiskThresholds(ctx context.Context, db dbutil.DBTX) (RiskThresholds, error) {
	var raw []byte
	err := db.QueryRow(ctx, `SELECT value FROM app_config WHERE key = $1`, ConfigRiskThresholds).Scan(&raw)
	if err != nil {
		if dbutil.IsNoRows(err) {
			return DefaultRiskThresholds, nil
		}
		return DefaultRiskThresholds, err
	}
	rt := DefaultRiskThresholds
	if err := json.Unmarshal(raw, &rt); err != nil {
		return DefaultRiskThresholds, nil
	}
	return rt, nil
}

// Metrics are the recorded figures for one student. A nil pointer means "not recorded".
type Metrics struct {
	CGPA          float64
	Backlogs      int
	SkillCount    int
	Aptitude      *float64
	Coding        *float64
	Communication *float64
	Attendance    *float64
}

func val(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

// SkillsScore turns the number of recorded skills into 0-100.
func SkillsScore(count int) float64 {
	return math.Min(float64(count)/skillsForFull*100, 100)
}

// Readiness is the placement readiness score out of 100, using the given weights.
func Readiness(m Metrics, w ReadinessWeights) float64 {
	cgpa := math.Min(math.Max(m.CGPA, 0), 10) * 10
	total := cgpa*w.CGPA + SkillsScore(m.SkillCount)*w.Skills + val(m.Aptitude)*w.Aptitude +
		val(m.Coding)*w.Coding + val(m.Attendance)*w.Attendance + val(m.Communication)*w.Communication
	return round1(total)
}

// Reason is one cause for concern, in words a faculty member can act on.
type Reason struct {
	Level string `json:"level"`
	Text  string `json:"text"`
}

// Assess lists what is worrying about a student and the overall risk. change is the movement in readiness
// over the last weeks (nil when there is no earlier snapshot to compare with). rt controls when overall
// readiness triggers a risk flag.
func Assess(m Metrics, readiness float64, change *float64, rt RiskThresholds) (string, []Reason) {
	var rs []Reason
	add := func(level, format string, args ...any) { rs = append(rs, Reason{level, fmt.Sprintf(format, args...)}) }

	if m.Attendance != nil {
		switch {
		case *m.Attendance < 65:
			add(RiskHigh, "Attendance is %.0f%%, below 65%%", *m.Attendance)
		case *m.Attendance < 75:
			add(RiskMedium, "Attendance is %.0f%%, below 75%%", *m.Attendance)
		}
	}
	switch {
	case m.Backlogs >= 3:
		add(RiskHigh, "%d backlogs", m.Backlogs)
	case m.Backlogs >= 1:
		add(RiskMedium, "%d backlog(s)", m.Backlogs)
	}
	if m.CGPA > 0 {
		switch {
		case m.CGPA < 5.5:
			add(RiskHigh, "CGPA is %.2f, below 5.5", m.CGPA)
		case m.CGPA < 6.5:
			add(RiskMedium, "CGPA is %.2f, below 6.5", m.CGPA)
		}
	}
	if m.Aptitude != nil && *m.Aptitude < 40 {
		add(RiskMedium, "Aptitude score is %.0f, below 40", *m.Aptitude)
	}
	if change != nil {
		switch {
		case *change <= -15:
			add(RiskHigh, "Readiness fell by %.0f points recently", -*change)
		case *change <= -8:
			add(RiskMedium, "Readiness fell by %.0f points recently", -*change)
		}
	}
	// A student with nothing recorded yet is a data gap (see the data quality report), not a risk.
	// Use configurable thresholds for overall readiness risk.
	if m.CGPA > 0 {
		switch {
		case readiness < rt.High:
			add(RiskHigh, "Overall readiness is only %.0f, below %.0f", readiness, rt.High)
		case readiness < rt.Medium:
			add(RiskMedium, "Overall readiness is only %.0f, below %.0f", readiness, rt.Medium)
		}
	}

	level := RiskNone
	for _, r := range rs {
		if r.Level == RiskHigh {
			return RiskHigh, rs
		}
		level = RiskMedium
	}
	return level, rs
}
