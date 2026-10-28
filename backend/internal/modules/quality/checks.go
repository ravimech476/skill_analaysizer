// Package quality reports how complete and consistent the student data is before it is analysed.
// The skill, career and insight features all read the same records, so gaps or contradictions here
// quietly lower the quality of every result. Each check is one plain SQL condition, so it is easy to
// read, review and extend.
package quality

import (
	"sort"
)

const (
	Error   = "error"   // contradicts itself or another record; analysis may be wrong
	Warning = "warning" // missing data that weakens the analysis
	Info    = "info"    // optional data that improves it
)

// Area groups checks so the report can show how complete each kind of data is.
type Area struct{ Key, Label string }

var Areas = []Area{
	{"profile", "Personal details"},
	{"marks", "Marks and results"},
	{"attendance", "Attendance"},
	{"skills", "Skills"},
	{"assessments", "Assessments"},
	{"identity", "Duplicate records"},
}

// Check is one rule. Where is a condition over the student alias "st" (see StudentsCTE); a student for
// whom it is true has the issue.
type Check struct {
	Key      string
	Area     string
	Label    string
	Severity string
	Hint     string
	Where    string
}

// StudentsCTE is the set of students being checked: those currently studying, in the chosen department.
const StudentsCTE = `WITH st AS (
	SELECT u.id, u.name, sp.register_no, u.mobile, u.email::text AS email, u.dob, u.gender,
	       sp.cgpa, sp.backlog_count, sp.aptitude_score
	FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
	WHERE sp.is_active AND sp.lifecycle_status = 'studying' AND ($1::bigint IS NULL OR u.department_id = $1))`

var Checks = []Check{
	{"no_mobile", "profile", "No mobile number", Warning, "Add it on the student's profile so notifications and OTP login work.",
		`COALESCE(btrim(st.mobile), '') = ''`},
	{"no_email", "profile", "No email address", Warning, "Add it on the student's profile.",
		`COALESCE(btrim(st.email), '') = ''`},
	{"no_dob", "profile", "No date of birth", Info, "Add it on the student's profile.", `st.dob IS NULL`},
	{"no_gender", "profile", "No gender recorded", Info, "Add it on the student's profile.", `st.gender IS NULL`},
	{"no_cgpa", "marks", "CGPA not set", Warning, "Run the grading or promotion step so the CGPA is calculated.", `COALESCE(st.cgpa, 0) = 0`},
	{"no_marks", "marks", "No marks recorded", Warning, "Enter or import the student's marks.",
		`NOT EXISTS (SELECT 1 FROM student_marks m WHERE m.student_id = st.id AND m.is_active)`},
	{"pass_without_marks", "marks", "Marked as passed but has no marks", Error, "Enter the marks or correct the result.",
		`EXISTS (SELECT 1 FROM student_marks m WHERE m.student_id = st.id AND m.is_active AND m.result = 'pass' AND m.marks_obtained IS NULL)`},
	{"marks_without_result", "marks", "Marks without a pass or fail result", Error, "Re-save the marks so the result is worked out.",
		`EXISTS (SELECT 1 FROM student_marks m WHERE m.student_id = st.id AND m.is_active AND m.marks_obtained IS NOT NULL AND m.result IS NULL)`},
	{"marks_without_grade", "marks", "Marks without a grade", Info, "Check the grade scale covers these marks.",
		`EXISTS (SELECT 1 FROM student_marks m JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
			WHERE m.student_id = st.id AND m.is_active AND m.marks_obtained IS NOT NULL AND m.grade IS NULL)`},
	{"backlog_mismatch", "marks", "Backlog count differs from failed subjects", Warning, "Recheck the latest attempt of each failed subject.",
		`st.backlog_count <> (SELECT count(*) FROM (
			SELECT DISTINCT ON (m.subject_id) m.result FROM student_marks m
			JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
			WHERE m.student_id = st.id AND m.is_active ORDER BY m.subject_id, m.attempt_no DESC) x WHERE x.result = 'fail')`},
	{"no_attendance", "attendance", "No attendance recorded", Info, "Enter or import attendance.",
		`NOT EXISTS (SELECT 1 FROM attendance a WHERE a.student_id = st.id AND a.is_active)`},
	{"attendance_mismatch", "attendance", "Attendance percentage does not match the counts", Error, "Re-save the attendance so the percentage is recalculated.",
		`EXISTS (SELECT 1 FROM attendance a WHERE a.student_id = st.id AND a.is_active AND a.total_classes > 0
			AND abs(a.percentage - 100.0 * a.classes_attended / a.total_classes) > 0.5)`},
	{"no_skills", "skills", "No skills recorded", Warning, "Check marks for suggestions or record skills on the student's analysis page.",
		`NOT EXISTS (SELECT 1 FROM student_skills s WHERE s.student_id = st.id AND s.is_active)
		 AND NOT EXISTS (SELECT 1 FROM skill_scores s WHERE s.student_id = st.id AND s.is_active)`},
	{"no_assessments", "assessments", "No psychometric questionnaire taken", Info, "Ask the student to take them under their analysis.",
		`NOT EXISTS (SELECT 1 FROM student_assessments sa WHERE sa.student_id = st.id AND sa.is_active AND sa.kind IN ('personality', 'interests', 'learning'))`},
	{"no_aptitude", "assessments", "Aptitude test not taken", Info, "Ask the student to take it under their analysis.", `st.aptitude_score IS NULL`},
	{"stale_coding", "assessments", "Coding profile waiting for verification over 30 days", Warning, "Open the student's coding profile and verify or reject it.",
		`EXISTS (SELECT 1 FROM coding_profiles cp WHERE cp.student_id = st.id AND cp.is_active AND NOT cp.verified AND cp.created_at < now() - interval '30 days')`},
	{"duplicate_mobile", "identity", "Mobile number shared with another user", Error, "Check that these are different people and correct the number.",
		`COALESCE(btrim(st.mobile), '') <> '' AND EXISTS (SELECT 1 FROM users o WHERE o.is_active AND o.id <> st.id AND o.mobile = st.mobile)`},
	{"duplicate_person", "identity", "Same name and date of birth as another student", Warning, "Check for a student registered twice.",
		`st.dob IS NOT NULL AND EXISTS (SELECT 1 FROM users o JOIN student_profiles op ON op.user_id = o.id AND op.is_active
			WHERE o.is_active AND o.id <> st.id AND o.dob = st.dob AND lower(o.name) = lower(st.name))`},
}

var severityWeight = map[string]int{Error: 3, Warning: 2, Info: 1}

// Person is a student named in the report.
type Person struct {
	ID         int64  `json:"id"`
	Name       string `json:"name"`
	RegisterNo string `json:"register_no"`
}

type CheckResult struct {
	Key      string   `json:"key"`
	Area     string   `json:"area"`
	Label    string   `json:"label"`
	Severity string   `json:"severity"`
	Hint     string   `json:"hint"`
	Count    int      `json:"count"`
	Percent  float64  `json:"percent"`
	Sample   []Person `json:"sample"`
}

type AreaResult struct {
	Key     string  `json:"key"`
	Label   string  `json:"label"`
	Clean   int     `json:"clean_students"`
	Percent float64 `json:"percent"`
}

type StudentIssues struct {
	Person
	Score  int      `json:"score"`
	Issues []string `json:"issues"`
}

type Report struct {
	Students      int             `json:"students"`
	CleanStudents int             `json:"clean_students"` // no error or warning
	Errors        int             `json:"errors"`         // issues of that severity, summed over students
	Warnings      int             `json:"warnings"`
	Infos         int             `json:"infos"`
	Areas         []AreaResult    `json:"areas"`
	Checks        []CheckResult   `json:"checks"`
	NeedAttention []StudentIssues `json:"need_attention"`
}

const (
	sampleSize   = 5
	attentionTop = 15
)

func percent(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return float64(int(float64(a)/float64(b)*1000+0.5)) / 10
}

// Aggregate turns the students each check found into the report. It is separate from the database
// so the counting and ranking can be tested without one.
func Aggregate(total int, checks []Check, hits map[string][]Person) *Report {
	r := &Report{Students: total, Areas: []AreaResult{}, Checks: []CheckResult{}, NeedAttention: []StudentIssues{}}
	perStudent := map[int64]*StudentIssues{}
	areaDirty := map[string]map[int64]bool{}
	blocking := map[int64]bool{}

	for _, c := range checks {
		people := hits[c.Key]
		res := CheckResult{Key: c.Key, Area: c.Area, Label: c.Label, Severity: c.Severity, Hint: c.Hint,
			Count: len(people), Percent: percent(len(people), total), Sample: []Person{}}
		for i, p := range people {
			if i < sampleSize {
				res.Sample = append(res.Sample, p)
			}
			si := perStudent[p.ID]
			if si == nil {
				si = &StudentIssues{Person: p, Issues: []string{}}
				perStudent[p.ID] = si
			}
			si.Score += severityWeight[c.Severity]
			si.Issues = append(si.Issues, c.Label)
			if areaDirty[c.Area] == nil {
				areaDirty[c.Area] = map[int64]bool{}
			}
			areaDirty[c.Area][p.ID] = true
			switch c.Severity {
			case Error:
				r.Errors++
				blocking[p.ID] = true
			case Warning:
				r.Warnings++
				blocking[p.ID] = true
			default:
				r.Infos++
			}
		}
		r.Checks = append(r.Checks, res)
	}
	sort.SliceStable(r.Checks, func(i, j int) bool {
		if severityWeight[r.Checks[i].Severity] != severityWeight[r.Checks[j].Severity] {
			return severityWeight[r.Checks[i].Severity] > severityWeight[r.Checks[j].Severity]
		}
		return r.Checks[i].Count > r.Checks[j].Count
	})

	for _, a := range Areas {
		clean := total - len(areaDirty[a.Key])
		r.Areas = append(r.Areas, AreaResult{Key: a.Key, Label: a.Label, Clean: clean, Percent: percent(clean, total)})
	}
	r.CleanStudents = total - len(blocking)

	for _, si := range perStudent {
		r.NeedAttention = append(r.NeedAttention, *si)
	}
	sort.Slice(r.NeedAttention, func(i, j int) bool {
		a, b := r.NeedAttention[i], r.NeedAttention[j]
		if a.Score != b.Score {
			return a.Score > b.Score
		}
		return a.RegisterNo < b.RegisterNo
	})
	if len(r.NeedAttention) > attentionTop {
		r.NeedAttention = r.NeedAttention[:attentionTop]
	}
	return r
}
