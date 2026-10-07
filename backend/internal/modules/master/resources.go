package master

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/pkg/response"
)

// Resources lists every simple master exposed under /api/v1.
var Resources = []*Resource{
	{
		Name:  "Department",
		Path:  "/departments",
		Table: "departments",
		Perm:  "department",
		Fields: []Field{
			{Name: "name", Kind: String, Required: true, Max: 150},
			{Name: "code", Kind: Upper, Required: true, Max: 20},
			{Name: "hod_id", Kind: FK, Ref: "users"},
		},
		Search:  []string{"name", "code"},
		OrderBy: "t.name",
		Extra: []string{
			"(SELECT name FROM users WHERE id = t.hod_id) AS hod_name",
			"(SELECT count(*) FROM classes c WHERE c.department_id = t.id AND c.is_active)::int AS class_count",
			`(SELECT count(*) FROM student_profiles sp JOIN users u ON u.id = sp.user_id
			   WHERE u.department_id = t.id AND sp.is_active AND u.is_active)::int AS student_count`,
		},
		Uniques: map[string]string{"ux_departments_code": "Department code is already used"},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM classes WHERE department_id = $1 AND is_active", Message: "Department has classes; delete them first"},
			{SQL: "SELECT 1 FROM users WHERE department_id = $1 AND is_active", Message: "Department has active students or staff"},
		},
		BeforeWrite: func(ctx context.Context, tx pgx.Tx, _ int64, v map[string]any) error {
			hod, _ := v["hod_id"].(int64)
			if hod == 0 {
				return nil
			}
			var ok bool
			err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
				WHERE ur.user_id = $1 AND ur.is_active AND r.slug IN ('hod', 'staff'))`, hod).Scan(&ok)
			if err != nil {
				return err
			}
			if !ok {
				return response.BadRequest("HOD must be a staff member")
			}
			return nil
		},
	},
	{
		Name:  "Academic year",
		Path:  "/academic-years",
		Table: "academic_years",
		Perm:  "academic_year",
		Fields: []Field{
			{Name: "name", Kind: String, Required: true, Max: 20},
			{Name: "start_date", Kind: Date, Required: true},
			{Name: "end_date", Kind: Date, Required: true},
			{Name: "is_current", Kind: Bool, Default: false},
		},
		Search:  []string{"name"},
		OrderBy: "t.start_date DESC",
		Uniques: map[string]string{
			"ux_academic_years_name":    "An academic year with this name already exists",
			"ux_academic_years_current": "Another academic year is already current",
		},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM classes WHERE academic_year_id = $1 AND is_active", Message: "Academic year has classes; delete them first"},
			{SQL: "SELECT 1 FROM academic_years WHERE id = $1 AND is_current", Message: "Mark another year as current before deleting this one"},
		},
		Validate: func(v map[string]any) error {
			if !datesOrdered(v["start_date"], v["end_date"]) {
				return response.BadRequest("end_date must be after start_date")
			}
			return nil
		},
		// Only one current year: marking this one current un-marks the others.
		BeforeWrite: func(ctx context.Context, tx pgx.Tx, id int64, v map[string]any) error {
			if cur, _ := v["is_current"].(bool); cur {
				_, err := tx.Exec(ctx, `UPDATE academic_years SET is_current = false WHERE is_current AND id <> $1`, id)
				return err
			}
			return nil
		},
	},
	{
		Name:  "Subject",
		Path:  "/subjects",
		Table: "subjects",
		Perm:  "subject",
		Fields: []Field{
			{Name: "code", Kind: Upper, Required: true, Max: 30},
			{Name: "name", Kind: String, Required: true, Max: 200},
			{Name: "credits", Kind: Number, Default: float64(0), Min: F(0), Cap: F(20)},
			{Name: "subject_type", Kind: String, Default: "theory", Enum: []string{"theory", "lab", "elective", "project"}},
		},
		Search:  []string{"code", "name"},
		OrderBy: "t.code",
		Uniques: map[string]string{"ux_subjects_code": "Subject code is already used"},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM curriculum WHERE subject_id = $1 AND is_active", Message: "Subject is part of a curriculum; remove it there first"},
			{SQL: "SELECT 1 FROM student_marks WHERE subject_id = $1 AND is_active", Message: "Subject has marks recorded"},
		},
	},
	{
		Name:  "Exam type",
		Path:  "/exam-types",
		Table: "exam_types",
		Perm:  "exam_type",
		Fields: []Field{
			{Name: "name", Kind: String, Required: true, Max: 60},
			{Name: "code", Kind: Upper, Required: true, Max: 20},
			{Name: "max_marks", Kind: Number, Required: true, Min: F(1), Cap: F(1000)},
			{Name: "is_final", Kind: Bool, Default: false},
			{Name: "sort_order", Kind: Int, Default: float64(0)},
			{Name: "pass_percent", Kind: Number, Default: float64(50), Min: F(0), Cap: F(100)},
		},
		Search:  []string{"name", "code"},
		OrderBy: "t.sort_order, t.name",
		Uniques: map[string]string{"ux_exam_types_code": "Exam type code is already used"},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM student_marks WHERE exam_type_id = $1 AND is_active", Message: "Exam type has marks recorded"},
		},
	},
	{
		Name:  "Skill",
		Path:  "/skills",
		Table: "skills",
		Perm:  "skill",
		Fields: []Field{
			{Name: "name", Kind: String, Required: true, Max: 100},
			{Name: "category", Kind: String, Default: "technical", Enum: []string{"programming", "framework", "database", "tool", "technical", "soft_skill", "domain"}},
		},
		Search:  []string{"name", "category"},
		OrderBy: "t.category, t.name",
		Extra: []string{
			"(SELECT count(*) FROM student_skills x WHERE x.skill_id = t.id AND x.is_active)::int AS student_count",
			"(SELECT count(*) FROM job_role_skills x WHERE x.skill_id = t.id AND x.is_active)::int AS job_role_count",
			"(SELECT count(*) FROM subject_skills x WHERE x.skill_id = t.id AND x.is_active)::int AS subject_count",
		},
		Uniques: map[string]string{"ux_skills_name": "A skill with this name already exists"},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM job_role_skills WHERE skill_id = $1 AND is_active", Message: "Skill is required by a job role; remove it there first"},
			{SQL: "SELECT 1 FROM subject_skills WHERE skill_id = $1 AND is_active", Message: "Skill is mapped to a subject; remove it there first"},
			{SQL: "SELECT 1 FROM student_skills WHERE skill_id = $1 AND is_active", Message: "Students have this skill recorded"},
		},
	},
	{
		Name:  "Company",
		Path:  "/companies",
		Table: "companies",
		Perm:  "company",
		Fields: []Field{
			{Name: "name", Kind: String, Required: true, Max: 200},
			{Name: "industry", Kind: String, Max: 100},
			{Name: "website", Kind: String, Max: 300},
			{Name: "location", Kind: String, Max: 150},
			{Name: "contact_person", Kind: String, Max: 150},
			{Name: "contact_email", Kind: String, Max: 150},
			{Name: "contact_mobile", Kind: String, Max: 15},
			{Name: "description", Kind: String, Max: 2000},
		},
		Search:  []string{"name", "industry", "location"},
		OrderBy: "t.name",
		Extra: []string{
			"(SELECT count(*) FROM company_job_roles j WHERE j.company_id = t.id AND j.is_active)::int AS job_role_count",
			"(SELECT count(*) FROM placement_records pr WHERE pr.company_id = t.id AND pr.is_active)::int AS placed_count",
			"(SELECT max(pr.package_lpa)::float8 FROM placement_records pr WHERE pr.company_id = t.id AND pr.is_active) AS highest_package",
		},
		Uniques: map[string]string{"ux_companies_name": "A company with this name already exists"},
		InUse: []InUse{
			{SQL: "SELECT 1 FROM company_job_roles WHERE company_id = $1 AND is_active", Message: "Company has job roles; delete them first"},
		},
	},
	{
		Name:     "Year level",
		Path:     "/year-levels",
		Table:    "year_levels",
		Perm:     "academic_year",
		Fields:   []Field{{Name: "name", Kind: String}, {Name: "level_no", Kind: Int}},
		OrderBy:  "t.level_no",
		ReadOnly: true,
	},
	{
		Name:     "Semester",
		Path:     "/semesters",
		Table:    "semesters",
		Perm:     "academic_year",
		Fields:   []Field{{Name: "name", Kind: String}, {Name: "sem_no", Kind: Int}, {Name: "year_level_id", Kind: FK, Ref: "year_levels"}},
		OrderBy:  "t.sem_no",
		ReadOnly: true,
	},
}

func datesOrdered(a, b any) bool {
	s, ok1 := a.(time.Time)
	e, ok2 := b.(time.Time)
	return !ok1 || !ok2 || e.After(s)
}
