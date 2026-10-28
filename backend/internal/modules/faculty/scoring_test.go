package faculty

import "testing"

func f(v float64) *float64 { return &v }

func TestReadinessWeights(t *testing.T) {
	// Everything perfect: 100.
	full := Metrics{CGPA: 10, SkillCount: 5, Aptitude: f(100), Coding: f(100), Communication: f(100), Attendance: f(100)}
	if got := Readiness(full); got != 100 {
		t.Errorf("full marks: %v", got)
	}
	// Nothing recorded except CGPA 8: only the CGPA share counts.
	if got := Readiness(Metrics{CGPA: 8}); got != 20 {
		t.Errorf("cgpa only: %v", got)
	}
	// The programming index now counts: it is worth 15 points.
	a := Readiness(Metrics{CGPA: 8})
	b := Readiness(Metrics{CGPA: 8, Coding: f(100)})
	if b-a != 15 {
		t.Errorf("coding share: %v", b-a)
	}
	if Readiness(Metrics{CGPA: 15, SkillCount: 50}) > 45 {
		t.Error("values above the maximum must be capped")
	}
}

func TestAssessLevels(t *testing.T) {
	level, rs := Assess(Metrics{CGPA: 8, Attendance: f(90)}, 70, nil)
	if level != RiskNone || len(rs) != 0 {
		t.Errorf("healthy student flagged: %v %v", level, rs)
	}
	level, _ = Assess(Metrics{CGPA: 8, Attendance: f(70)}, 70, nil)
	if level != RiskMedium {
		t.Errorf("attendance 70: %v", level)
	}
	level, rs = Assess(Metrics{CGPA: 8, Attendance: f(60), Backlogs: 1}, 70, nil)
	if level != RiskHigh || len(rs) != 2 {
		t.Errorf("attendance 60 with a backlog: %v %v", level, rs)
	}
	level, _ = Assess(Metrics{CGPA: 5}, 70, nil)
	if level != RiskHigh {
		t.Errorf("cgpa 5: %v", level)
	}
}

func TestAssessIgnoresMissingData(t *testing.T) {
	// No attendance and no CGPA recorded is a data problem, not a risk by itself.
	level, rs := Assess(Metrics{}, 50, nil)
	if level != RiskNone || len(rs) != 0 {
		t.Errorf("missing data flagged: %v %v", level, rs)
	}
}

func TestLowReadinessNeedsSomeData(t *testing.T) {
	if level, _ := Assess(Metrics{}, 0, nil); level != RiskNone {
		t.Errorf("no data at all: %v", level)
	}
	if level, _ := Assess(Metrics{CGPA: 8}, 30, nil); level != RiskMedium {
		t.Errorf("recorded marks but very low readiness: %v", level)
	}
}

func TestAssessUsesTheChangeInReadiness(t *testing.T) {
	m := Metrics{CGPA: 8, Attendance: f(90)}
	if level, _ := Assess(m, 70, f(-10)); level != RiskMedium {
		t.Errorf("fall of 10: %v", level)
	}
	if level, _ := Assess(m, 70, f(-20)); level != RiskHigh {
		t.Errorf("fall of 20: %v", level)
	}
	if level, _ := Assess(m, 70, f(-3)); level != RiskNone {
		t.Errorf("small fall: %v", level)
	}
	if level, _ := Assess(m, 70, f(12)); level != RiskNone {
		t.Errorf("rise: %v", level)
	}
}
