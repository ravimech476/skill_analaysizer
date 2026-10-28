package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"skills-analyzer/internal/modules/student"
)

// intents are cheap keyword checks that decide which database tables are searched for a question.
type intents struct {
	placement, interview, learn, career bool
	// category narrows the interview bank to one kind of entry (resume tips, career roadmaps) when asked for.
	category  string
	companies []companyRef
}

type companyRef struct {
	ID   int64
	Name string
}

func hasAny(s string, words ...string) bool {
	for _, w := range words {
		if strings.Contains(s, w) {
			return true
		}
	}
	return false
}

func (h *Handler) detectIntents(ctx context.Context, msg string) (intents, error) {
	m := strings.ToLower(msg)
	in := intents{
		placement: hasAny(m, "drive", "placement", "placed", "company", "package", "salary", "lpa", "hiring", "hire", "job", "eligible", "eligibility", "apply", "offer"),
		interview: hasAny(m, "interview", "question", "prepare", "preparation", "practice", "round", "aptitude", "resume", "cv", "roadmap", "tips"),
		learn:     hasAny(m, "course", "learn", "study", "improve", "gap", "skill", "material", "notes", "resource", "weak", "strong", "mark", "backlog"),
		career:    hasAny(m, "career", "role", "path", "future", "domain"),
	}
	switch {
	case hasAny(m, "resume", " cv"):
		in.category = "resume"
	case hasAny(m, "roadmap", "how do i become", "how to become"):
		in.category = "career"
	}
	rows, err := h.db.Query(ctx, `SELECT id, name::text FROM companies WHERE is_active`)
	if err != nil {
		return in, err
	}
	defer rows.Close()
	for rows.Next() {
		var c companyRef
		if err := rows.Scan(&c.ID, &c.Name); err != nil {
			return in, err
		}
		if strings.Contains(m, strings.ToLower(c.Name)) {
			in.companies = append(in.companies, c)
		}
	}
	if len(in.companies) > 0 {
		in.placement, in.interview = true, in.interview || hasAny(m, "interview", "question", "prepare")
	}
	if in.category != "" {
		in.companies = nil // resume tips and roadmaps are not company specific
	}
	return in, rows.Err()
}

func clip(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if r := []rune(s); len(r) > n {
		return string(r[:n]) + "…"
	}
	return s
}

// buildContext searches the database for what the question needs and returns it as plain text for the prompt.
// st may be nil (a staff member asking a general question); then only institution-wide data is used.
func (h *Handler) buildContext(ctx context.Context, st *student.Student, msg string) (string, error) {
	in, err := h.detectIntents(ctx, msg)
	if err != nil {
		return "", err
	}
	var b strings.Builder

	var weakSubjects []int64
	skillLevel := map[string]int{}
	if st != nil {
		fmt.Fprintf(&b, "STUDENT PROFILE\nName: %s (register no %s)\n", st.Name, st.RegisterNo)
		if st.DepartmentName != nil {
			fmt.Fprintf(&b, "Department: %s\n", *st.DepartmentName)
		}
		if st.ClassLabel != nil {
			fmt.Fprintf(&b, "Class: %s, batch %s\n", *st.ClassLabel, st.Batch)
		}
		fmt.Fprintf(&b, "CGPA: %.2f, backlogs: %d\n", st.CGPA, st.BacklogCount)

		if len(st.Skills) == 0 {
			b.WriteString("Skills: none recorded yet\n")
		} else {
			parts := make([]string, 0, len(st.Skills))
			for _, s := range st.Skills {
				parts = append(parts, fmt.Sprintf("%s %d/5", s.Name, s.Proficiency))
				skillLevel[strings.ToLower(s.Name)] = s.Proficiency
			}
			fmt.Fprintf(&b, "Skills (proficiency out of 5): %s\n", strings.Join(parts, ", "))
		}

		weakSubjects, err = h.writeMarks(ctx, &b, st.ID)
		if err != nil {
			return "", err
		}
	} else {
		b.WriteString("No specific student is selected, so no personal data is available.\n")
	}

	if in.placement {
		if err := h.writeDrives(ctx, &b, st, in, skillLevel); err != nil {
			return "", err
		}
	}
	if in.interview {
		if err := h.writeInterview(ctx, &b, in); err != nil {
			return "", err
		}
	}
	if in.learn && st != nil {
		if err := h.writeLearning(ctx, &b, st.ID, weakSubjects); err != nil {
			return "", err
		}
	}
	if in.career && st != nil {
		if err := h.writeCareers(ctx, &b, st.ID); err != nil {
			return "", err
		}
	}
	return b.String(), nil
}

// writeMarks lists the latest final-exam result per subject and returns the ids of weak subjects (<60%).
func (h *Handler) writeMarks(ctx context.Context, b *strings.Builder, studentID int64) ([]int64, error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT ON (m.subject_id) s.id, s.name, m.marks_obtained::float8, m.max_marks::float8, COALESCE(m.grade, '-')
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		WHERE m.student_id = $1 AND m.is_active
		ORDER BY m.subject_id, m.attempt_no DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var weak []int64
	var lines []string
	for rows.Next() {
		var id int64
		var name, grade string
		var got, max float64
		if err := rows.Scan(&id, &name, &got, &max, &grade); err != nil {
			return nil, err
		}
		if max <= 0 {
			continue
		}
		p := math.Round(got / max * 100)
		tag := ""
		switch {
		case p >= 75:
			tag = " (strong)"
		case p < 60:
			tag = " (weak)"
			weak = append(weak, id)
		}
		lines = append(lines, fmt.Sprintf("%s: %.0f%% grade %s%s", name, p, grade, tag))
	}
	if len(lines) == 0 {
		b.WriteString("Marks: no final-exam marks recorded yet\n")
	} else {
		fmt.Fprintf(b, "Subject results (latest final exam):\n- %s\n", strings.Join(lines, "\n- "))
	}
	return weak, rows.Err()
}

type driveSkill struct {
	Name      string `json:"name"`
	Level     int    `json:"level"`
	Mandatory bool   `json:"mandatory"`
	Have      int    `json:"have"`
}

func (h *Handler) writeDrives(ctx context.Context, b *strings.Builder, st *student.Student, in intents, skillLevel map[string]int) error {
	var studentID int64
	if st != nil {
		studentID = st.ID
	}
	companyIDs := make([]int64, 0, len(in.companies))
	for _, c := range in.companies {
		companyIDs = append(companyIDs, c.ID)
	}
	rows, err := h.db.Query(ctx, `
		SELECT co.name::text, j.title, j.package_lpa::float8, j.min_cgpa::float8, j.max_backlogs, j.status,
		       COALESCE(to_char(j.drive_date, 'YYYY-MM-DD'), ''),
		       COALESCE((SELECT jsonb_agg(jsonb_build_object('name', s.name::text, 'level', rs.required_level,
		                                                      'mandatory', rs.is_mandatory, 'have', COALESCE(ss.proficiency, 0)))
		                 FROM job_role_skills rs
		                 JOIN skills s ON s.id = rs.skill_id
		                 LEFT JOIN student_skills ss ON ss.skill_id = rs.skill_id AND ss.student_id = $1 AND ss.is_active
		                 WHERE rs.job_role_id = j.id AND rs.is_active), '[]'::jsonb)
		FROM company_job_roles j
		JOIN companies co ON co.id = j.company_id
		WHERE j.is_active AND co.is_active
		  AND ((cardinality($2::bigint[]) > 0 AND j.company_id = ANY($2)) OR (cardinality($2::bigint[]) = 0 AND j.status IN ('open', 'upcoming')))
		ORDER BY j.package_lpa DESC LIMIT 6`, studentID, companyIDs)
	if err != nil {
		return err
	}
	defer rows.Close()

	var lines []string
	for rows.Next() {
		var company, title, status, date string
		var pkg, minCGPA float64
		var maxBacklogs int
		var raw []byte
		if err := rows.Scan(&company, &title, &pkg, &minCGPA, &maxBacklogs, &status, &date, &raw); err != nil {
			return err
		}
		var skills []driveSkill
		_ = json.Unmarshal(raw, &skills)

		line := fmt.Sprintf("%s — %s, %.1f LPA, status %s", company, title, pkg, status)
		if date != "" {
			line += ", drive date " + date
		}
		line += fmt.Sprintf(". Needs CGPA >= %.2f and at most %d backlogs", minCGPA, maxBacklogs)
		if st != nil {
			if st.CGPA >= minCGPA && st.BacklogCount <= maxBacklogs {
				line += " (student meets this)"
			} else {
				line += " (student does NOT meet this)"
			}
		}
		line += "."
		if len(skills) > 0 {
			req, gaps := []string{}, []string{}
			for _, s := range skills {
				label := fmt.Sprintf("%s >=%d", s.Name, s.Level)
				if s.Mandatory {
					label += " (mandatory)"
				}
				req = append(req, label)
				if st != nil && s.Have < s.Level {
					gaps = append(gaps, fmt.Sprintf("%s (has %d, needs %d)", s.Name, s.Have, s.Level))
				}
			}
			line += " Required skills: " + strings.Join(req, ", ") + "."
			if st != nil {
				if len(gaps) == 0 {
					line += " Student meets every skill requirement."
				} else {
					line += " Skill gaps: " + strings.Join(gaps, ", ") + "."
				}
			}
		}
		lines = append(lines, line)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(lines) == 0 {
		b.WriteString("Placement drives: none found for this question\n")
	} else {
		fmt.Fprintf(b, "PLACEMENT DRIVES\n- %s\n", strings.Join(lines, "\n- "))
	}
	return nil
}

func (h *Handler) writeInterview(ctx context.Context, b *strings.Builder, in intents) error {
	companyIDs := make([]int64, 0, len(in.companies))
	for _, c := range in.companies {
		companyIDs = append(companyIDs, c.ID)
	}
	rows, err := h.db.Query(ctx, `
		SELECT COALESCE(co.name::text, 'General'), q.category, q.difficulty, q.question, COALESCE(q.answer, '')
		FROM interview_questions q LEFT JOIN companies co ON co.id = q.company_id
		WHERE q.is_active AND (cardinality($1::bigint[]) = 0 OR q.company_id = ANY($1))
		  AND (($2::text = '' AND q.category NOT IN ('resume', 'career')) OR q.category = $2)
		ORDER BY random() LIMIT 6`, companyIDs, in.category)
	if err != nil {
		return err
	}
	defer rows.Close()
	var lines []string
	for rows.Next() {
		var company, cat, diff, q, a string
		if err := rows.Scan(&company, &cat, &diff, &q, &a); err != nil {
			return err
		}
		line := fmt.Sprintf("[%s, %s, %s] %s", company, cat, diff, clip(q, 200))
		if a != "" {
			line += " Hint: " + clip(a, 200)
		}
		lines = append(lines, line)
	}
	if len(lines) > 0 {
		fmt.Fprintf(b, "INTERVIEW QUESTION BANK\n- %s\n", strings.Join(lines, "\n- "))
	}
	return rows.Err()
}

func (h *Handler) writeLearning(ctx context.Context, b *strings.Builder, studentID int64, weakSubjects []int64) error {
	courses, err := h.db.Query(ctx, `
		SELECT c.title, COALESCE(c.provider, ''), s.name::text, c.level, COALESCE(c.duration_hours, 0), c.is_free, COALESCE(c.url, '')
		FROM courses c
		JOIN skills s ON s.id = c.skill_id
		LEFT JOIN student_skills ss ON ss.skill_id = c.skill_id AND ss.student_id = $1 AND ss.is_active
		WHERE c.is_active AND COALESCE(ss.proficiency, 0) < 3
		ORDER BY COALESCE(ss.proficiency, 0), c.level, c.is_free DESC LIMIT 6`, studentID)
	if err != nil {
		return err
	}
	defer courses.Close()
	var lines []string
	for courses.Next() {
		var title, provider, skill, url string
		var level, hours int
		var free bool
		if err := courses.Scan(&title, &provider, &skill, &level, &hours, &free, &url); err != nil {
			return err
		}
		cost := "paid"
		if free {
			cost = "free"
		}
		line := fmt.Sprintf("%s (%s, %s, for skill %s, level %d, %d hrs)", title, provider, cost, skill, level, hours)
		if url != "" {
			line += " " + url
		}
		lines = append(lines, line)
	}
	if err := courses.Err(); err != nil {
		return err
	}
	if len(lines) > 0 {
		fmt.Fprintf(b, "RECOMMENDED COURSES (skills the student is below level 3 in)\n- %s\n", strings.Join(lines, "\n- "))
	}

	if len(weakSubjects) == 0 {
		return nil
	}
	mats, err := h.db.Query(ctx, `
		SELECT sm.title, sm.material_type, s.name, COALESCE(sm.url, '')
		FROM study_materials sm JOIN subjects s ON s.id = sm.subject_id
		WHERE sm.is_active AND sm.subject_id = ANY($1) ORDER BY s.name LIMIT 6`, weakSubjects)
	if err != nil {
		return err
	}
	defer mats.Close()
	lines = nil
	for mats.Next() {
		var title, typ, subject, url string
		if err := mats.Scan(&title, &typ, &subject, &url); err != nil {
			return err
		}
		line := fmt.Sprintf("%s (%s, subject %s)", title, typ, subject)
		if url != "" {
			line += " " + url
		}
		lines = append(lines, line)
	}
	if len(lines) > 0 {
		fmt.Fprintf(b, "STUDY MATERIALS for weak subjects\n- %s\n", strings.Join(lines, "\n- "))
	}
	return mats.Err()
}

func (h *Handler) writeCareers(ctx context.Context, b *strings.Builder, studentID int64) error {
	rows, err := h.db.Query(ctx, `
		SELECT c.name, cm.final_score::float8, cm.readiness, COALESCE(cm.explanation, '')
		FROM career_matches cm JOIN careers c ON c.id = cm.career_id
		WHERE cm.student_id = $1 AND cm.is_active ORDER BY cm.rank LIMIT 3`, studentID)
	if err != nil {
		return err
	}
	defer rows.Close()
	var lines []string
	for rows.Next() {
		var name, readiness, why string
		var score float64
		if err := rows.Scan(&name, &score, &readiness, &why); err != nil {
			return err
		}
		lines = append(lines, fmt.Sprintf("%s — match %.0f%%, readiness %s. %s", name, score, readiness, clip(why, 250)))
	}
	if len(lines) > 0 {
		fmt.Fprintf(b, "CAREER MATCHES\n- %s\n", strings.Join(lines, "\n- "))
	}
	return rows.Err()
}
