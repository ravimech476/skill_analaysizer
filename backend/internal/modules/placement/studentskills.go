package placement

import (
	"context"
	"fmt"
	"skills-analyzer/internal/files"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

var levelNames = []string{"", "Beginner", "Basic", "Intermediate", "Advanced", "Expert"}

type StudentSkill struct {
	SkillID        int64       `json:"skill_id"`
	Name           string      `json:"name"`
	Category       string      `json:"category"`
	Proficiency    int         `json:"proficiency"`
	Source         string      `json:"source"`
	CertificateURL *string     `json:"certificate_url"`
	Remarks        *string     `json:"remarks"`
	UpdatedAt      time.Time   `json:"updated_at"`
	RecordedBy     *string     `json:"recorded_by"`
	Certificate    *files.Link `json:"certificate"`
	Verified       bool        `json:"certificate_verified"`
	VerifiedAt     *time.Time  `json:"certificate_verified_at"`
	VerifiedBy     *string     `json:"certificate_verified_by"`
	// Score is the blended 0-100 score for this skill, which also counts assessments and marks.
	Score *float64 `json:"score"`
}

func (h *Handler) skillsOf(ctx context.Context, studentID int64) ([]StudentSkill, error) {
	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.name::text, s.category, x.proficiency, x.source, x.certificate_url, x.remarks, x.updated_at, u.name,
		       file_json(x.certificate_file_id), x.certificate_verified, x.certificate_verified_at, v.name,
		       (SELECT b.score::float8 FROM skill_scores b
		          WHERE b.student_id = x.student_id AND b.skill_id = x.skill_id AND b.is_active AND b.source = 'blended')
		FROM student_skills x JOIN skills s ON s.id = x.skill_id
		LEFT JOIN users u ON u.id = COALESCE(x.updated_by, x.created_by)
		LEFT JOIN users v ON v.id = x.certificate_verified_by
		WHERE x.student_id = $1 AND x.is_active ORDER BY x.proficiency DESC, s.name`, studentID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[StudentSkill])
}

func (h *Handler) studentSkills(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.skillsOf(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// upsertStudentSkill records or updates one skill level. Only staff/admin enter skills (students don't self-report).
func (h *Handler) upsertStudentSkill(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		SkillID        int64   `json:"skill_id" binding:"required"`
		Proficiency    int     `json:"proficiency" binding:"required,min=1,max=5"`
		Source         string  `json:"source" binding:"omitempty,oneof=assessment certification project internship course"`
		CertificateURL *string `json:"certificate_url" binding:"omitempty,max=500"`
		Remarks        *string `json:"remarks" binding:"omitempty,max=500"`
		// Optional uploaded certificate (POST /files, category certificate). Absent keeps the current one.
		CertificateFileID *int64 `json:"certificate_file_id"`
		RemoveCertificate bool   `json:"remove_certificate"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("skill_id and proficiency (1-5) are required", err.Error()))
		return
	}
	if body.Source == "" {
		body.Source = "assessment"
	}
	if body.CertificateURL != nil && strings.TrimSpace(*body.CertificateURL) == "" {
		body.CertificateURL = nil
	}
	if _, err := h.students.Get(c, a, id); err != nil { // staff limited to their department
		response.Error(c, err)
		return
	}
	var skillName string
	if err := h.db.QueryRow(c, `SELECT name::text FROM skills WHERE id = $1 AND is_active`, body.SkillID).Scan(&skillName); err != nil {
		if dbutil.IsNoRows(err) {
			err = response.BadRequest("skill_id does not exist")
		}
		response.Error(c, err)
		return
	}
	var prevLevel *int
	var prevCert *int64
	if err := h.db.QueryRow(c, `SELECT proficiency, certificate_file_id FROM student_skills WHERE student_id = $1 AND skill_id = $2 AND is_active`,
		id, body.SkillID).Scan(&prevLevel, &prevCert); err != nil && !dbutil.IsNoRows(err) {
		response.Error(c, err)
		return
	}
	cert := prevCert
	switch {
	case body.CertificateFileID != nil:
		cert = body.CertificateFileID
	case body.RemoveCertificate:
		cert = nil
	}
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var rowID int64
		if err := tx.QueryRow(c, `
			INSERT INTO student_skills (student_id, skill_id, proficiency, source, certificate_url, remarks, certificate_file_id, created_by, updated_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
			ON CONFLICT (student_id, skill_id) WHERE is_active
			DO UPDATE SET proficiency = EXCLUDED.proficiency, source = EXCLUDED.source, certificate_url = EXCLUDED.certificate_url,
			              remarks = EXCLUDED.remarks, certificate_file_id = EXCLUDED.certificate_file_id, updated_by = EXCLUDED.updated_by
			RETURNING id`,
			id, body.SkillID, body.Proficiency, body.Source, body.CertificateURL, body.Remarks, cert, a.ID).Scan(&rowID); err != nil {
			return err
		}
		if cert != prevCert {
			if err := files.Swap(c, tx, prevCert, cert, a.ID, "certificate", "student_skills", rowID); err != nil {
				return err
			}
		}
		// The recorded level feeds the blended score, so refresh it in the same transaction.
		return skillscore.Recompute(c, tx, a.ID, []int64{id})
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	if prevLevel == nil || *prevLevel != body.Proficiency {
		rt, rid := notify.Ref("skill", body.SkillID)
		h.notify.SendSafe(c, notify.Notice{Title: "Skill recorded: " + skillName,
			Body: fmt.Sprintf("%s is now recorded at level %d of 5 (%s). Higher levels improve your placement match.", skillName, body.Proficiency, levelNames[body.Proficiency]),
			Type: notify.TypeSkill, RefType: rt, RefID: rid, CreatedBy: a.ID}, []int64{id})
	}
	list, err := h.skillsOf(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

func (h *Handler) deleteStudentSkill(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	skillID, ok := request.ID(c, "skillId")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	// One transaction: removing the skill, releasing its certificate and rebuilding the
	// student's scores have to stand or fall together (Recompute also locks the student).
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var cert *int64
		err := tx.QueryRow(c, `UPDATE student_skills SET is_active = false, updated_by = $3
			WHERE student_id = $1 AND skill_id = $2 AND is_active
			RETURNING certificate_file_id`, id, skillID, a.ID).Scan(&cert)
		if dbutil.IsNoRows(err) {
			return response.NotFound("The student does not have this skill recorded")
		}
		if err != nil {
			return err
		}
		if err := files.Release(c, tx, cert, a.ID); err != nil {
			return err
		}
		return skillscore.Recompute(c, tx, a.ID, []int64{id})
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.skillsOf(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// verifyStudentSkill marks a skill's certificate as checked (or un-checks it). A verified
// certificate counts as independent evidence in the blended score, so this changes the number.
func (h *Handler) verifyStudentSkill(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	skillID, ok := request.ID(c, "skillId")
	if !ok {
		return
	}
	var body struct {
		Verified *bool `json:"verified" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("verified (true or false) is required"))
		return
	}
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	var skillName string
	var hasProof bool
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		err := tx.QueryRow(c, `SELECT s.name::text, x.certificate_file_id IS NOT NULL OR x.certificate_url IS NOT NULL
			FROM student_skills x JOIN skills s ON s.id = x.skill_id
			WHERE x.student_id = $1 AND x.skill_id = $2 AND x.is_active`, id, skillID).Scan(&skillName, &hasProof)
		if dbutil.IsNoRows(err) {
			return response.NotFound("The student does not have this skill recorded")
		}
		if err != nil {
			return err
		}
		if *body.Verified && !hasProof {
			return response.BadRequest("Attach the certificate before verifying it")
		}
		var at *time.Time
		var by *int64
		if *body.Verified {
			now := time.Now()
			at, by = &now, &a.ID
		}
		if _, err := tx.Exec(c, `UPDATE student_skills SET certificate_verified = $3, certificate_verified_at = $4,
			certificate_verified_by = $5, updated_by = $6
			WHERE student_id = $1 AND skill_id = $2 AND is_active`, id, skillID, *body.Verified, at, by, a.ID); err != nil {
			return err
		}
		return skillscore.Recompute(c, tx, a.ID, []int64{id})
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	if *body.Verified {
		rt, rid := notify.Ref("skill", skillID)
		h.notify.SendSafe(c, notify.Notice{Title: "Certificate verified: " + skillName,
			Body: skillName + " is now verified by the college. Verified skills carry more weight in your placement match.",
			Type: notify.TypeSkill, RefType: rt, RefID: rid, CreatedBy: a.ID}, []int64{id})
	}
	list, err := h.skillsOf(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// skillMatrix: GET /student-skills/matrix?class_id= — every student of a class × every skill any of them has.
func (h *Handler) skillMatrix(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	classID := request.QueryInt64(c, "class_id")
	if classID == nil {
		response.Error(c, response.BadRequest("class_id is required"))
		return
	}
	var deptID int64
	if err := h.db.QueryRow(c, `SELECT department_id FROM classes WHERE id = $1 AND is_active`, *classID).Scan(&deptID); err != nil {
		if dbutil.IsNoRows(err) {
			err = response.NotFound("Class not found")
		}
		response.Error(c, err)
		return
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	if scope != nil && *scope != deptID {
		response.Error(c, response.Forbidden("This class belongs to another department"))
		return
	}
	type row struct {
		StudentID  int64          `json:"student_id"`
		Name       string         `json:"name"`
		RegisterNo string         `json:"register_no"`
		Skills     map[string]int `json:"skills"` // skill id → level
		Count      int            `json:"skill_count"`
	}
	rows, err := h.db.Query(c, `
		SELECT u.id, u.name, sp.register_no, x.skill_id, x.proficiency
		FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
		LEFT JOIN student_skills x ON x.student_id = u.id AND x.is_active
		WHERE sp.current_class_id = $1 AND sp.is_active ORDER BY sp.register_no`, *classID)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []*row{}
	byID := map[int64]*row{}
	used := map[int64]bool{}
	for rows.Next() {
		var sid int64
		var name, reg string
		var skill *int64
		var lvl *int
		if err := rows.Scan(&sid, &name, &reg, &skill, &lvl); err != nil {
			response.Error(c, err)
			return
		}
		r, ok := byID[sid]
		if !ok {
			r = &row{StudentID: sid, Name: name, RegisterNo: reg, Skills: map[string]int{}}
			byID[sid] = r
			out = append(out, r)
		}
		if skill != nil {
			r.Skills[strconv.FormatInt(*skill, 10)] = *lvl
			r.Count++
			used[*skill] = true
		}
	}
	rows.Close()
	ids := []int64{}
	for id := range used {
		ids = append(ids, id)
	}
	srows, err := h.db.Query(c, `SELECT id, name::text, category FROM skills WHERE id = ANY($1) ORDER BY category, name`, ids)
	if err != nil {
		response.Error(c, err)
		return
	}
	type skillRef struct {
		ID       int64  `json:"id"`
		Name     string `json:"name"`
		Category string `json:"category"`
	}
	skills, err := pgx.CollectRows(srows, pgx.RowToStructByPos[skillRef])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"skills": skills, "rows": out})
}
