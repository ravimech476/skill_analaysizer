// Package faculty serves what staff need to watch a class: placement readiness for every student,
// who is at risk and why, and how each student's scores have moved over time. Everything here is
// computed from recorded data with fixed rules, so staff can always see why a student was flagged.
package faculty

import (
	"fmt"
	"math"
)

// Readiness weights. Missing data counts as zero: a student who has not yet shown a skill is not ready for it.
const (
	wCGPA          = 0.25
	wSkills        = 0.20
	wAptitude      = 0.15
	wCoding        = 0.15
	wAttendance    = 0.15
	wCommunication = 0.10

	skillsForFull = 5 // recorded skills that give the full skills score
)

const (
	RiskHigh   = "high"
	RiskMedium = "medium"
	RiskNone   = "none"
)

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

// Readiness is the placement readiness score out of 100.
func Readiness(m Metrics) float64 {
	cgpa := math.Min(math.Max(m.CGPA, 0), 10) * 10
	total := cgpa*wCGPA + SkillsScore(m.SkillCount)*wSkills + val(m.Aptitude)*wAptitude +
		val(m.Coding)*wCoding + val(m.Attendance)*wAttendance + val(m.Communication)*wCommunication
	return round1(total)
}

// Reason is one cause for concern, in words a faculty member can act on.
type Reason struct {
	Level string `json:"level"`
	Text  string `json:"text"`
}

// Assess lists what is worrying about a student and the overall risk. change is the movement in readiness
// over the last weeks (nil when there is no earlier snapshot to compare with).
func Assess(m Metrics, readiness float64, change *float64) (string, []Reason) {
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
	if m.CGPA > 0 && readiness < 40 {
		add(RiskMedium, "Overall readiness is only %.0f", readiness)
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
