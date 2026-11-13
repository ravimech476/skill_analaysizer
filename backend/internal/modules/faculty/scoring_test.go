package faculty

import "testing"

func f(v float64) *float64 { return &v }

var dw = DefaultReadinessWeights
var dr = DefaultRiskThresholds

func TestReadinessWeights(t *testing.T) {
	// Everything perfect: 100.
	full := Metrics{CGPA: 10, SkillCount: 5, Aptitude: f(100), Coding: f(100), Communication: f(100), Attendance: f(100)}
	if got := Readiness(full, dw); got != 100 {
		t.Errorf("full marks: %v", got)
	}
	// Nothing recorded except CGPA 8: only the CGPA share counts.
	if got := Readiness(Metrics{CGPA: 8}, dw); got != 20 {
		t.Errorf("cgpa only: %v", got)
	}
	// The programming index now counts: it is worth 15 points.
	a := Readiness(Metrics{CGPA: 8}, dw)
	b := Readiness(Metrics{CGPA: 8, Coding: f(100)}, dw)
	if b-a != 15 {
		t.Errorf("coding share: %v", b-a)
	}
	if Readiness(Metrics{CGPA: 15, SkillCount: 50}, dw) > 45 {
		t.Error("values above the maximum must be capped")
	}
}

func TestAssessLevels(t *testing.T) {
	level, rs := Assess(Metrics{CGPA: 8, Attendance: f(90)}, 70, nil, dr)
	if level != RiskNone || len(rs) != 0 {
		t.Errorf("healthy student flagged: %v %v", level, rs)
	}
	level, _ = Assess(Metrics{CGPA: 8, Attendance: f(70)}, 70, nil, dr)
	if level != RiskMedium {
		t.Errorf("attendance 70: %v", level)
	}
	level, rs = Assess(Metrics{CGPA: 8, Attendance: f(60), Backlogs: 1}, 70, nil, dr)
	if level != RiskHigh || len(rs) != 2 {
		t.Errorf("attendance 60 with a backlog: %v %v", level, rs)
	}
	level, _ = Assess(Metrics{CGPA: 5}, 70, nil, dr)
	if level != RiskHigh {
		t.Errorf("cgpa 5: %v", level)
	}
}

func TestAssessIgnoresMissingData(t *testing.T) {
	// No attendance and no CGPA recorded is a data problem, not a risk by itself.
	level, rs := Assess(Metrics{}, 50, nil, dr)
	if level != RiskNone || len(rs) != 0 {
		t.Errorf("missing data flagged: %v %v", level, rs)
	}
}

func TestLowReadinessNeedsSomeData(t *testing.T) {
	if level, _ := Assess(Metrics{}, 0, nil, dr); level != RiskNone {
		t.Errorf("no data at all: %v", level)
	}
	if level, _ := Assess(Metrics{CGPA: 8}, 25, nil, dr); level != RiskHigh {
		t.Errorf("recorded marks but very low readiness (below high threshold): %v", level)
	}
	if level, _ := Assess(Metrics{CGPA: 8}, 40, nil, dr); level != RiskMedium {
		t.Errorf("recorded marks but low readiness (below medium threshold): %v", level)
	}
}

func TestAssessUsesTheChangeInReadiness(t *testing.T) {
	m := Metrics{CGPA: 8, Attendance: f(90)}
	if level, _ := Assess(m, 70, f(-10), dr); level != RiskMedium {
		t.Errorf("fall of 10: %v", level)
	}
	if level, _ := Assess(m, 70, f(-20), dr); level != RiskHigh {
		t.Errorf("fall of 20: %v", level)
	}
	if level, _ := Assess(m, 70, f(-3), dr); level != RiskNone {
		t.Errorf("small fall: %v", level)
	}
	if level, _ := Assess(m, 70, f(12), dr); level != RiskNone {
		t.Errorf("rise: %v", level)
	}
}

func TestCustomWeightsAffectReadiness(t *testing.T) {
	// Custom weights: only CGPA matters.
	w := ReadinessWeights{CGPA: 1.0}
	m := Metrics{CGPA: 10}
	if got := Readiness(m, w); got != 100 {
		t.Errorf("all-CGPA weights, perfect CGPA: %v", got)
	}
	if got := Readiness(Metrics{CGPA: 10, SkillCount: 5}, w); got != 100 {
		t.Errorf("skills should not matter with zero weight: %v", got)
	}
}

func TestCustomRiskThresholds(t *testing.T) {
	rt := RiskThresholds{High: 40, Medium: 60}
	// readiness 35 should be high risk with threshold 40
	if level, _ := Assess(Metrics{CGPA: 8}, 35, nil, rt); level != RiskHigh {
		t.Errorf("readiness 35 with high threshold 40: %v", level)
	}
	// readiness 50 should be medium risk with threshold 60
	if level, _ := Assess(Metrics{CGPA: 8}, 50, nil, rt); level != RiskMedium {
		t.Errorf("readiness 50 with medium threshold 60: %v", level)
	}
	// readiness 65 should be no risk
	if level, _ := Assess(Metrics{CGPA: 8}, 65, nil, rt); level != RiskNone {
		t.Errorf("readiness 65 with medium threshold 60: %v", level)
	}
}
