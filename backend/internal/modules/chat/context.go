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
	attendance, scores, readiness       bool
	questionbank, profile               bool
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
		placement:    hasAny(m, "drive", "placement", "placed", "company", "package", "salary", "lpa", "hiring", "hire", "job", "eligible", "eligibility", "apply", "offer"),
		interview:    hasAny(m, "interview", "question", "prepare", "preparation", "practice", "round", "resume", "cv", "roadmap", "tips"),
		learn:        hasAny(m, "course", "learn", "study", "improve", "gap", "skill", "material", "notes", "resource", "weak", "strong", "mark", "backlog"),
		career:       hasAny(m, "career", "role", "path", "future", "domain"),
		attendance:   hasAny(m, "attendance", "absent", "present", "bunking", "leave"),
		scores:       hasAny(m, "aptitude", "coding score", "communication score", "psychometric", "test score"),
		readiness:    hasAny(m, "ready", "readiness", "placement ready", "how ready", "risk"),
		questionbank: hasAny(m, "question paper", "previous year", "past paper", "question bank", "old question"),
		profile:      hasAny(m, "detail", "profile", "performance", "how am i", "how is", "everything about", "full detail", "about student", "tell me about"),
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
	if in.attendance && st != nil {
		if err := h.writeAttendance(ctx, &b, st.ID); err != nil {
			return "", err
		}
	}
	if in.scores && st != nil {
		h.writeScores(ctx, &b, st.ID)
	}
	if in.readiness && st != nil {
		if err := h.writeReadiness(ctx, &b, st); err != nil {
			return "", err
		}
	}
	if in.questionbank {
		if err := h.writeQuestionBank(ctx, &b, msg); err != nil {
			return "", err
		}
	}
	if in.profile && st != nil {
		if err := h.writeFullProfile(ctx, &b, st); err != nil {
			return "", err
		}
	}
	return b.String(), nil
}

// writeAttendance lists attendance per subject for a student.
func (h *Handler) writeAttendance(ctx context.Context, b *strings.Builder, studentID int64) error {
	rows, err := h.db.Query(ctx, `
		SELECT s.name, a.total_classes, a.classes_attended, a.percentage::float8
		FROM attendance a
		JOIN subjects s ON s.id = a.subject_id
		WHERE a.student_id = $1 AND a.is_active
		ORDER BY a.percentage`, studentID)
	if err != nil {
		return err
	}
	defer rows.Close()
	var lines []string
	for rows.Next() {
		var name string
		var total, attended int
		var pct float64
		if err := rows.Scan(&name, &total, &attended, &pct); err != nil {
			return err
		}
		tag := ""
		if pct < 75 {
			tag = " (below 75% — at risk)"
		}
		lines = append(lines, fmt.Sprintf("%s: %d/%d classes = %.1f%%%s", name, attended, total, pct, tag))
	}
	if len(lines) == 0 {
		b.WriteString("Attendance: no records yet\n")
	} else {
		fmt.Fprintf(b, "ATTENDANCE\n- %s\n", strings.Join(lines, "\n- "))
	}
	return rows.Err()
}

// writeScores adds aptitude, coding, communication, psychometric scores from the student profile.
func (h *Handler) writeScores(ctx context.Context, b *strings.Builder, studentID int64) {
	var apt, cod, comm, psych *float64
	_ = h.db.QueryRow(ctx, `
		SELECT aptitude_score::float8, coding_score::float8, communication_score::float8, psychometric_score::float8
		FROM student_profiles WHERE user_id = $1 AND is_active`, studentID).Scan(&apt, &cod, &comm, &psych)
	type score struct {
		name string
		val  *float64
	}
	scores := []score{{"Aptitude", apt}, {"Coding", cod}, {"Communication", comm}, {"Psychometric", psych}}
	var parts []string
	for _, s := range scores {
		if s.val != nil && *s.val > 0 {
			parts = append(parts, fmt.Sprintf("%s: %.1f/100", s.name, *s.val))
		}
	}
	if len(parts) == 0 {
		b.WriteString("Assessment scores: none recorded yet\n")
	} else {
		fmt.Fprintf(b, "ASSESSMENT SCORES: %s\n", strings.Join(parts, ", "))
	}
}

// writeReadiness computes and writes the placement readiness score.
func (h *Handler) writeReadiness(ctx context.Context, b *strings.Builder, st *student.Student) error {
	var skillCount int
	_ = h.db.QueryRow(ctx, `SELECT count(*) FROM student_skills WHERE student_id = $1 AND is_active`, st.ID).Scan(&skillCount)
	var avgAttendance float64
	_ = h.db.QueryRow(ctx, `SELECT COALESCE(avg(percentage), 0)::float8 FROM attendance WHERE student_id = $1 AND is_active`, st.ID).Scan(&avgAttendance)
	var apt, cod, comm float64
	_ = h.db.QueryRow(ctx, `
		SELECT COALESCE(aptitude_score, 0)::float8, COALESCE(coding_score, 0)::float8, COALESCE(communication_score, 0)::float8
		FROM student_profiles WHERE user_id = $1 AND is_active`, st.ID).Scan(&apt, &cod, &comm)

	cgpaPart := (st.CGPA / 10.0) * 100 * 0.25
	skillPart := math.Min(float64(skillCount)/5.0*100, 100) * 0.20
	aptPart := apt * 0.15
	codPart := cod * 0.15
	attPart := avgAttendance * 0.15
	commPart := comm * 0.10
	readiness := math.Round(cgpaPart + skillPart + aptPart + codPart + attPart + commPart)

	risk := "Low risk"
	if readiness < 30 {
		risk = "HIGH RISK"
	} else if readiness < 50 {
		risk = "Medium risk"
	} else if readiness >= 70 {
		risk = "Placement ready"
	}

	fmt.Fprintf(b, "PLACEMENT READINESS: %.0f/100 (%s)\n", readiness, risk)
	fmt.Fprintf(b, "  Breakdown: CGPA %.0f + Skills %.0f + Aptitude %.0f + Coding %.0f + Attendance %.0f + Communication %.0f\n",
		cgpaPart, skillPart, aptPart, codPart, attPart, commPart)
	return nil
}

// writeQuestionBank fetches relevant previous year questions based on subject keywords in the message.
func (h *Handler) writeQuestionBank(ctx context.Context, b *strings.Builder, msg string) error {
	lower := strings.ToLower(msg)
	rows, err := h.db.Query(ctx, `
		SELECT s.name, et.name, qb.year, qb.question, qb.marks, qb.blooms_level
		FROM question_bank qb
		JOIN subjects s ON s.id = qb.subject_id
		LEFT JOIN exam_types et ON et.id = qb.exam_type_id
		WHERE qb.is_active AND lower(s.name) LIKE '%' || $1 || '%'
		ORDER BY qb.year DESC, qb.marks DESC LIMIT 6`, lower)
	if err != nil {
		// If no subject match, try without filter
		rows, err = h.db.Query(ctx, `
			SELECT s.name, et.name, qb.year, qb.question, qb.marks, qb.blooms_level
			FROM question_bank qb
			JOIN subjects s ON s.id = qb.subject_id
			LEFT JOIN exam_types et ON et.id = qb.exam_type_id
			WHERE qb.is_active
			ORDER BY qb.year DESC LIMIT 6`)
		if err != nil {
			return err
		}
	}
	defer rows.Close()
	var lines []string
	for rows.Next() {
		var subject, question, blooms string
		var exam *string
		var year, marks int
		if err := rows.Scan(&subject, &exam, &year, &question, &marks, &blooms); err != nil {
			return err
		}
		examName := "General"
		if exam != nil {
			examName = *exam
		}
		lines = append(lines, fmt.Sprintf("[%s, %s, %d, %d marks, %s] %s", subject, examName, year, marks, blooms, clip(question, 200)))
	}
	if len(lines) > 0 {
		fmt.Fprintf(b, "QUESTION BANK (previous year questions)\n- %s\n", strings.Join(lines, "\n- "))
	}
	return rows.Err()
}

// writeFullProfile adds extra details when a general "tell me about" or "details" question is asked.
func (h *Handler) writeFullProfile(ctx context.Context, b *strings.Builder, st *student.Student) error {
	// Attendance summary
	var avgAtt float64
	_ = h.db.QueryRow(ctx, `SELECT COALESCE(avg(percentage), 0)::float8 FROM attendance WHERE student_id = $1 AND is_active`, st.ID).Scan(&avgAtt)
	if avgAtt > 0 {
		fmt.Fprintf(b, "Average attendance: %.1f%%\n", avgAtt)
	}
	// Assessment scores
	h.writeScores(ctx, b, st.ID)
	// Placement status
	var placedCount int
	_ = h.db.QueryRow(ctx, `SELECT count(*) FROM placement_records WHERE student_id = $1 AND is_active`, st.ID).Scan(&placedCount)
	if placedCount > 0 {
		rows, err := h.db.Query(ctx, `
			SELECT co.name::text, j.title, pr.package_lpa::float8
			FROM placement_records pr
			JOIN companies co ON co.id = pr.company_id
			JOIN company_job_roles j ON j.id = pr.job_role_id
			WHERE pr.student_id = $1 AND pr.is_active`, st.ID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var company, title string
				var pkg float64
				if rows.Scan(&company, &title, &pkg) == nil {
					fmt.Fprintf(b, "Placed at: %s - %s (%.2f LPA)\n", company, title, pkg)
				}
			}
		}
	} else {
		b.WriteString("Placement status: not yet placed\n")
	}
	// Application count
	var appCount int
	_ = h.db.QueryRow(ctx, `SELECT count(*) FROM placement_applications WHERE student_id = $1 AND is_active`, st.ID).Scan(&appCount)
	if appCount > 0 {
		fmt.Fprintf(b, "Active applications: %d\n", appCount)
	}
	return nil
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
