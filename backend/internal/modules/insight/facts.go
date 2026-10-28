// Package insight writes a short, plain-language reading of one student's record for the student and
// their faculty. Every fact in it is computed here from the database; a local language model is only
// allowed to put those facts into friendlier words, and its text is thrown away when it brings in
// anything that is not in the facts.
package insight

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"

	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/pkg/dbutil"
)

type SkillFact struct {
	Name  string  `json:"name"`
	Level int     `json:"level"`
	Score float64 `json:"score"`
}

type SubjectFact struct {
	Name    string  `json:"name"`
	Percent float64 `json:"percent"`
}

type CareerFact struct {
	Name      string  `json:"name"`
	Readiness string  `json:"readiness"`
	Score     float64 `json:"score"`
	Gap       string  `json:"gap,omitempty"`
	GapLevel  int     `json:"gap_level"`
	GapNeeds  int     `json:"gap_needs"`
}

// Facts is everything the insight may say. Nothing outside it is allowed in the text.
type Facts struct {
	Name          string        `json:"name"`
	CGPA          float64       `json:"cgpa"`
	Backlogs      int           `json:"backlogs"`
	StrongSubject []SubjectFact `json:"strong_subjects"`
	WeakSubject   []SubjectFact `json:"weak_subjects"`
	TopSkills     []SkillFact   `json:"top_skills"`
	LowSkills     []SkillFact   `json:"low_skills"`
	Aptitude      *float64      `json:"aptitude"`
	Communication *float64      `json:"communication"`
	Coding        *float64      `json:"coding"`
	InterestCode  string        `json:"interest_code"`
	Personality   []string      `json:"personality_strengths"`
	Careers       []CareerFact  `json:"careers"`
}

// Gather reads the facts for one student.
func Gather(ctx context.Context, db dbutil.DBTX, studentID int64) (*Facts, error) {
	f := &Facts{StrongSubject: []SubjectFact{}, WeakSubject: []SubjectFact{}, TopSkills: []SkillFact{}, LowSkills: []SkillFact{},
		Personality: []string{}, Careers: []CareerFact{}}
	err := db.QueryRow(ctx, `
		SELECT u.name, sp.cgpa::float8, COALESCE(sp.backlog_count, 0), sp.aptitude_score::float8, sp.communication_score::float8, sp.coding_score::float8
		FROM student_profiles sp JOIN users u ON u.id = sp.user_id
		WHERE sp.user_id = $1 AND sp.is_active`, studentID).Scan(&f.Name, &f.CGPA, &f.Backlogs, &f.Aptitude, &f.Communication, &f.Coding)
	if err != nil {
		return nil, err
	}

	rows, err := db.Query(ctx, `
		SELECT DISTINCT ON (m.subject_id) s.name, m.marks_obtained::float8, m.max_marks::float8
		FROM student_marks m
		JOIN subjects s ON s.id = m.subject_id
		JOIN exam_types et ON et.id = m.exam_type_id AND et.is_final
		WHERE m.student_id = $1 AND m.is_active
		ORDER BY m.subject_id, m.attempt_no DESC`, studentID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var name string
		var got, max float64
		if err := rows.Scan(&name, &got, &max); err != nil {
			rows.Close()
			return nil, err
		}
		if max <= 0 {
			continue
		}
		p := math.Round(got / max * 100)
		switch {
		case p >= 75:
			f.StrongSubject = append(f.StrongSubject, SubjectFact{name, p})
		case p < 60:
			f.WeakSubject = append(f.WeakSubject, SubjectFact{name, p})
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.Slice(f.StrongSubject, func(i, j int) bool { return f.StrongSubject[i].Percent > f.StrongSubject[j].Percent })
	sort.Slice(f.WeakSubject, func(i, j int) bool { return f.WeakSubject[i].Percent < f.WeakSubject[j].Percent })

	if err := f.loadSkills(ctx, db, studentID); err != nil {
		return nil, err
	}
	if err := f.loadAssessments(ctx, db, studentID); err != nil {
		return nil, err
	}
	if err := f.loadCareers(ctx, db, studentID); err != nil {
		return nil, err
	}
	return f, nil
}

func (f *Facts) loadSkills(ctx context.Context, db dbutil.DBTX, studentID int64) error {
	blended, err := skillscore.Blended(ctx, db, []int64{studentID})
	if err != nil {
		return err
	}
	scores := blended[studentID]
	if len(scores) == 0 {
		return nil
	}
	rows, err := db.Query(ctx, `SELECT id, name::text FROM skills WHERE is_active`)
	if err != nil {
		return err
	}
	names := map[int64]string{}
	for rows.Next() {
		var id int64
		var n string
		if err := rows.Scan(&id, &n); err != nil {
			rows.Close()
			return err
		}
		names[id] = n
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	all := []SkillFact{}
	for id, s := range scores {
		if n, ok := names[id]; ok && s > 0 {
			all = append(all, SkillFact{Name: n, Level: skillscore.Level(s), Score: math.Round(s*10) / 10})
		}
	}
	sort.Slice(all, func(i, j int) bool {
		if all[i].Score != all[j].Score {
			return all[i].Score > all[j].Score
		}
		return all[i].Name < all[j].Name
	})
	for i, s := range all {
		if i < 3 {
			f.TopSkills = append(f.TopSkills, s)
		}
	}
	// Only call a skill low when it is clearly behind the student's best ones.
	for i := len(all) - 1; i >= 3 && len(f.LowSkills) < 2; i-- {
		if all[i].Level <= 2 {
			f.LowSkills = append(f.LowSkills, all[i])
		}
	}
	return nil
}

var riasec = map[string]string{"realistic": "R", "investigative": "I", "artistic": "A", "social": "S", "enterprising": "E", "conventional": "C"}

func (f *Facts) loadAssessments(ctx context.Context, db dbutil.DBTX, studentID int64) error {
	rows, err := db.Query(ctx, `
		SELECT DISTINCT ON (kind) kind, scores FROM student_assessments
		WHERE student_id = $1 AND is_active AND kind IN ('personality', 'interests')
		ORDER BY kind, id DESC`, studentID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var kind string
		var raw []byte
		if err := rows.Scan(&kind, &raw); err != nil {
			return err
		}
		var res struct {
			Traits []struct {
				Key   string  `json:"key"`
				Label string  `json:"label"`
				Score float64 `json:"score"`
				Level string  `json:"level"`
			} `json:"traits"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			continue
		}
		switch kind {
		case "personality":
			for _, t := range res.Traits {
				if t.Level == "high" {
					f.Personality = append(f.Personality, strings.ToLower(t.Label))
				}
			}
		case "interests":
			type kv struct {
				letter string
				score  float64
			}
			var list []kv
			for _, t := range res.Traits {
				if l, ok := riasec[t.Key]; ok {
					list = append(list, kv{l, t.Score})
				}
			}
			sort.SliceStable(list, func(i, j int) bool { return list[i].score > list[j].score })
			for i := 0; i < len(list) && i < 3; i++ {
				f.InterestCode += list[i].letter
			}
		}
	}
	return rows.Err()
}

func (f *Facts) loadCareers(ctx context.Context, db dbutil.DBTX, studentID int64) error {
	rows, err := db.Query(ctx, `
		SELECT c.name, m.readiness, m.final_score::float8,
		       COALESCE(m.gaps->0->>'name', ''), COALESCE((m.gaps->0->>'level')::int, 0), COALESCE((m.gaps->0->>'required_level')::int, 0)
		FROM career_matches m JOIN careers c ON c.id = m.career_id AND c.is_active
		WHERE m.student_id = $1 AND m.is_active ORDER BY m.rank LIMIT 3`, studentID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var c CareerFact
		if err := rows.Scan(&c.Name, &c.Readiness, &c.Score, &c.Gap, &c.GapLevel, &c.GapNeeds); err != nil {
			return err
		}
		f.Careers = append(f.Careers, c)
	}
	return rows.Err()
}

// Hash identifies this exact set of facts, so a stored insight is reused until something changes.
func (f *Facts) Hash() string {
	sum := sha256.Sum256([]byte(f.Text()))
	return hex.EncodeToString(sum[:])
}

func num(v *float64) string { return fmt.Sprintf("%.1f", *v) }

// Text lists the facts one per line. It is what the model is given, and what its answer is checked against.
func (f *Facts) Text() string {
	var b strings.Builder
	fmt.Fprintf(&b, "Student: %s\nCGPA: %.2f\nBacklogs: %d\n", f.Name, f.CGPA, f.Backlogs)
	if len(f.StrongSubject) > 0 {
		b.WriteString("Strong subjects: " + joinSubjects(f.StrongSubject) + "\n")
	}
	if len(f.WeakSubject) > 0 {
		b.WriteString("Weak subjects: " + joinSubjects(f.WeakSubject) + "\n")
	}
	if len(f.TopSkills) > 0 {
		b.WriteString("Strongest skills: " + joinSkills(f.TopSkills) + "\n")
	}
	if len(f.LowSkills) > 0 {
		b.WriteString("Skills to build: " + joinSkills(f.LowSkills) + "\n")
	}
	if f.Aptitude != nil {
		b.WriteString("Aptitude test score: " + num(f.Aptitude) + " out of 100\n")
	}
	if f.Communication != nil {
		b.WriteString("Communication score: " + num(f.Communication) + " out of 100\n")
	}
	if f.Coding != nil {
		b.WriteString("Programming index: " + num(f.Coding) + " out of 100\n")
	}
	if f.InterestCode != "" {
		b.WriteString("Interest code: " + f.InterestCode + "\n")
	}
	if len(f.Personality) > 0 {
		b.WriteString("Personality strengths: " + strings.Join(f.Personality, ", ") + "\n")
	}
	for i, c := range f.Careers {
		fmt.Fprintf(&b, "Career match %d: %s, %s, score %.1f", i+1, c.Name, c.Readiness, c.Score)
		if c.Gap != "" {
			fmt.Fprintf(&b, ", biggest gap %s (level %d of %d needed)", c.Gap, c.GapLevel, c.GapNeeds)
		}
		b.WriteString("\n")
	}
	return b.String()
}

func joinSubjects(list []SubjectFact) string {
	parts := make([]string, 0, len(list))
	for _, s := range list {
		parts = append(parts, fmt.Sprintf("%s (%.0f%%)", s.Name, s.Percent))
	}
	return strings.Join(parts, ", ")
}

func joinSkills(list []SkillFact) string {
	parts := make([]string, 0, len(list))
	for _, s := range list {
		parts = append(parts, fmt.Sprintf("%s (level %d)", s.Name, s.Level))
	}
	return strings.Join(parts, ", ")
}

