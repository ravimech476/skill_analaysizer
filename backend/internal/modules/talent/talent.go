package talent

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	perms    *rbac.Cache
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service) {
	h := &Handler{db: db, students: students, perms: perms}

	r.GET("/assessments/questionnaires/:kind", h.questionnaire)
	r.POST("/students/:id/assessments/:kind", h.submitAssessment)
	r.POST("/students/:id/communication-review", h.reviewCommunication)
	r.GET("/students/:id/talent-profile", h.profile)

	r.POST("/students/:id/coding-profiles", h.addPlatform)
	r.PUT("/coding-profiles/:id", h.updatePlatform)
	r.DELETE("/coding-profiles/:id", h.removePlatform)
	r.PUT("/coding-profiles/:id/verify", h.verifyPlatform)

	r.POST("/students/:id/projects", h.addProject)
	r.PUT("/projects/:id", h.updateProject)
	r.DELETE("/projects/:id", h.removeProject)
	r.PUT("/projects/:id/review", h.reviewProject)
}

// ---- access ----

// isStaff says whether the caller may record and verify data for students (the same permission that
// governs a student's skills).
func (h *Handler) isStaff(c *gin.Context) bool {
	ok, err := h.perms.HasAny(c.Request.Context(), middleware.Roles(c), "student_skill.update")
	return err == nil && ok
}

// authorize checks the caller may see this student (through the usual role scoping) and, for writes, that the
// caller is the student or staff. Parents can read but never write. It returns whether the caller is the student.
func (h *Handler) authorize(c *gin.Context, studentID int64, write bool) (self bool, err error) {
	a := actor.From(c)
	if _, err := h.students.Get(c, a, studentID); err != nil {
		return false, err
	}
	self = a.ID == studentID
	if write && !self && !h.isStaff(c) {
		return false, response.Forbidden("Only the student or staff can change this")
	}
	return self, nil
}

// ownerOf returns the student a row belongs to.
func (h *Handler) ownerOf(c *gin.Context, table string, id int64) (int64, error) {
	var sid int64
	if err := h.db.QueryRow(c, `SELECT student_id FROM `+table+` WHERE id = $1 AND is_active`, id).Scan(&sid); err != nil {
		if dbutil.IsNoRows(err) {
			return 0, response.NotFound("Not found")
		}
		return 0, err
	}
	return sid, nil
}

// ---- questionnaires ----

func (h *Handler) questionnaire(c *gin.Context) {
	q, ok := questionnaires[c.Param("kind")]
	if !ok {
		response.Error(c, response.NotFound("Unknown questionnaire"))
		return
	}
	response.OK(c, q)
}

type StoredResult struct {
	TakenAt time.Time `json:"taken_at"`
	Result
	// Signals are facts the app already holds that bear on the result (learning behaviour only).
	Signals map[string]any `json:"signals,omitempty"`
}

func (h *Handler) submitAssessment(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	q, found := questionnaires[c.Param("kind")]
	if !found {
		response.Error(c, response.NotFound("Unknown questionnaire"))
		return
	}
	if _, err := h.authorize(c, id, true); err != nil {
		response.Error(c, err)
		return
	}
	var body struct {
		Answers map[string]int `json:"answers" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("Send the answers as {\"answers\": {\"question id\": 1-5}}"))
		return
	}
	if err := Validate(q, body.Answers); err != nil {
		response.Error(c, response.BadRequest(err.Error()))
		return
	}
	res := Score(q, body.Answers)
	answers, _ := json.Marshal(body.Answers)
	scores, _ := json.Marshal(res)
	var at time.Time
	if err := h.db.QueryRow(c, `
		INSERT INTO student_assessments (student_id, kind, answers, scores, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING created_at`,
		id, q.Kind, answers, scores, actor.From(c).ID).Scan(&at); err != nil {
		response.Error(c, err)
		return
	}
	if q.Kind == "communication" {
		h.syncCommunicationScore(c, id)
	}
	out := StoredResult{TakenAt: at, Result: res}
	if q.Kind == "learning" {
		out.Signals = h.learningSignals(c, id)
	}
	response.Created(c, out)
}

// learningSignals are facts the app holds about how the student studies, shown beside the self-report.
func (h *Handler) learningSignals(ctx context.Context, studentID int64) map[string]any {
	out := map[string]any{}
	var attendance *float64
	_ = h.db.QueryRow(ctx, `SELECT round(avg(percentage)::numeric, 1)::float8 FROM attendance WHERE student_id = $1 AND is_active`, studentID).Scan(&attendance)
	if attendance != nil {
		out["attendance_percent"] = *attendance
	}
	var asked int
	_ = h.db.QueryRow(ctx, `SELECT count(*)::int FROM chat_messages WHERE user_id = $1 AND role = 'user' AND is_active AND created_at > now() - interval '30 days'`, studentID).Scan(&asked)
	out["ai_questions_30_days"] = asked
	return out
}

func (h *Handler) latest(ctx context.Context, studentID int64) (map[string]*StoredResult, error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT ON (kind) kind, scores, created_at
		FROM student_assessments WHERE student_id = $1 AND is_active ORDER BY kind, id DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]*StoredResult{}
	for rows.Next() {
		var kind string
		var scores []byte
		var at time.Time
		if err := rows.Scan(&kind, &scores, &at); err != nil {
			return nil, err
		}
		sr := &StoredResult{TakenAt: at}
		if err := json.Unmarshal(scores, &sr.Result); err != nil {
			return nil, err
		}
		if kind == "learning" {
			sr.Signals = h.learningSignals(ctx, studentID)
		}
		out[kind] = sr
	}
	return out, rows.Err()
}

// ---- coding profiles ----

type Platform struct {
	ID             int64      `json:"id"`
	Platform       string     `json:"platform"`
	Username       string     `json:"username"`
	ProfileURL     *string    `json:"profile_url"`
	ProblemsSolved int        `json:"problems_solved"`
	Rating         *int       `json:"rating"`
	Verified       bool       `json:"verified"`
	VerifiedAt     *time.Time `json:"verified_at"`
}

type Project struct {
	ID           int64          `json:"id"`
	Title        string         `json:"title"`
	Description  *string        `json:"description"`
	TechStack    *string        `json:"tech_stack"`
	RepoURL      *string        `json:"repo_url"`
	LiveURL      *string        `json:"live_url"`
	Status       string         `json:"status"`
	Verified     bool           `json:"verified"`
	VerifiedAt   *time.Time     `json:"verified_at"`
	Rubric       map[string]int `json:"rubric"`
	QualityScore *float64       `json:"quality_score"`
	ReviewNotes  *string        `json:"review_notes"`
}

type Coding struct {
	Breakdown
	Profiles []Platform `json:"profiles"`
	Projects []Project  `json:"projects"`
}

func (h *Handler) coding(ctx context.Context, studentID int64) (*Coding, error) {
	out := &Coding{Profiles: []Platform{}, Projects: []Project{}}

	rows, err := h.db.Query(ctx, `
		SELECT id, platform, username, profile_url, problems_solved, rating, verified, verified_at
		FROM coding_profiles WHERE student_id = $1 AND is_active ORDER BY platform`, studentID)
	if err != nil {
		return nil, err
	}
	out.Profiles, err = pgx.CollectRows(rows, pgx.RowToStructByPos[Platform])
	if err != nil {
		return nil, err
	}

	prows, err := h.db.Query(ctx, `
		SELECT id, title, description, tech_stack, repo_url, live_url, status, verified, verified_at, rubric, quality_score::float8, review_notes
		FROM student_projects WHERE student_id = $1 AND is_active ORDER BY id DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer prows.Close()
	for prows.Next() {
		var p Project
		var rubric []byte
		if err := prows.Scan(&p.ID, &p.Title, &p.Description, &p.TechStack, &p.RepoURL, &p.LiveURL, &p.Status, &p.Verified, &p.VerifiedAt, &rubric, &p.QualityScore, &p.ReviewNotes); err != nil {
			return nil, err
		}
		if len(rubric) > 0 {
			_ = json.Unmarshal(rubric, &p.Rubric)
		}
		out.Projects = append(out.Projects, p)
	}
	if err := prows.Err(); err != nil {
		return nil, err
	}

	var pi []PlatformInput
	for _, p := range out.Profiles {
		pi = append(pi, PlatformInput{ProblemsSolved: p.ProblemsSolved, Verified: p.Verified})
	}
	var ji []ProjectInput
	for _, p := range out.Projects {
		ji = append(ji, ProjectInput{QualityScore: p.QualityScore, Verified: p.Verified})
	}
	out.Breakdown = Index(pi, ji)
	return out, nil
}

// syncCodingScore keeps student_profiles.coding_score (which the placement readiness score reads) equal to the
// programming skill index. With nothing verified the stored score is left as staff entered it.
func (h *Handler) syncCodingScore(ctx context.Context, studentID int64) {
	cd, err := h.coding(ctx, studentID)
	if err != nil || cd.Index == nil {
		return
	}
	_, _ = h.db.Exec(ctx, `UPDATE student_profiles SET coding_score = $2 WHERE user_id = $1`, studentID, *cd.Index)
}

func (h *Handler) profile(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.authorize(c, id, false); err != nil {
		response.Error(c, err)
		return
	}
	psy, err := h.latest(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	cd, err := h.coding(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	var aptitude *float64
	_ = h.db.QueryRow(c, `SELECT aptitude_score::float8 FROM student_profiles WHERE user_id = $1`, id).Scan(&aptitude)
	comm, err := h.communicationSummary(c, id, psy["communication"])
	if err != nil {
		response.Error(c, err)
		return
	}
	delete(psy, "communication") // shown in its own card
	response.OK(c, gin.H{"student_id": id, "psychometric": psy, "aptitude_score": aptitude, "coding": cd, "communication": comm})
}

type platformBody struct {
	Platform       string  `json:"platform" binding:"required"`
	Username       string  `json:"username" binding:"required,max=100"`
	ProfileURL     *string `json:"profile_url"`
	ProblemsSolved int     `json:"problems_solved" binding:"min=0,max=100000"`
	Rating         *int    `json:"rating" binding:"omitempty,min=0,max=10000"`
}

func (b *platformBody) check() error {
	b.Platform = strings.ToLower(strings.TrimSpace(b.Platform))
	b.Username = strings.TrimSpace(b.Username)
	if !oneOf(Platforms, b.Platform) {
		return response.BadRequest("platform must be one of: " + strings.Join(Platforms, ", "))
	}
	if b.Username == "" {
		return response.BadRequest("username is required")
	}
	if b.ProfileURL != nil {
		u := strings.TrimSpace(*b.ProfileURL)
		if u == "" {
			b.ProfileURL = nil
		} else if !ValidURL(u) {
			return response.BadRequest("profile_url must start with http:// or https://")
		} else {
			b.ProfileURL = &u
		}
	}
	return nil
}

func (h *Handler) addPlatform(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.authorize(c, id, true); err != nil {
		response.Error(c, err)
		return
	}
	var b platformBody
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Check the platform, username and numbers", err.Error()))
		return
	}
	if err := b.check(); err != nil {
		response.Error(c, err)
		return
	}
	a := actor.From(c)
	var newID int64
	err := h.db.QueryRow(c, `
		INSERT INTO coding_profiles (student_id, platform, username, profile_url, problems_solved, rating, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id`, id, b.Platform, b.Username, b.ProfileURL, b.ProblemsSolved, b.Rating, a.ID).Scan(&newID)
	if dbutil.UniqueViolation(err) != "" {
		response.Error(c, response.Conflict("This platform is already listed; edit it instead"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, id)
	response.Created(c, gin.H{"id": newID})
}

func (h *Handler) updatePlatform(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "coding_profiles", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	self, err := h.authorize(c, sid, true)
	if err != nil {
		response.Error(c, err)
		return
	}
	var b platformBody
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Check the platform, username and numbers", err.Error()))
		return
	}
	if err := b.check(); err != nil {
		response.Error(c, err)
		return
	}
	// A student's own change has to be verified again; staff changes keep the verification they gave.
	_, err = h.db.Exec(c, `
		UPDATE coding_profiles SET platform = $2, username = $3, profile_url = $4, problems_solved = $5, rating = $6, updated_by = $7,
		       verified = CASE WHEN $8 THEN false ELSE verified END
		WHERE id = $1 AND is_active`, id, b.Platform, b.Username, b.ProfileURL, b.ProblemsSolved, b.Rating, actor.From(c).ID, self)
	if dbutil.UniqueViolation(err) != "" {
		response.Error(c, response.Conflict("This platform is already listed"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"message": "Saved"})
}

func (h *Handler) removePlatform(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "coding_profiles", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.authorize(c, sid, true); err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.db.Exec(c, `UPDATE coding_profiles SET is_active = false, updated_by = $2 WHERE id = $1`, id, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"message": "Removed"})
}

func (h *Handler) verifyPlatform(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "coding_profiles", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if err := h.requireReviewer(c, sid); err != nil {
		response.Error(c, err)
		return
	}
	var b struct {
		Verified bool `json:"verified"`
	}
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Send {\"verified\": true|false}"))
		return
	}
	a := actor.From(c)
	if _, err := h.db.Exec(c, `
		UPDATE coding_profiles SET verified = $2::boolean, verified_by = CASE WHEN $2::boolean THEN $3::bigint END, verified_at = CASE WHEN $2::boolean THEN now() END, updated_by = $3::bigint
		WHERE id = $1 AND is_active`, id, b.Verified, a.ID); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"verified": b.Verified})
}

// requireReviewer allows only staff, and never the student whose data it is, to verify or review.
func (h *Handler) requireReviewer(c *gin.Context, studentID int64) error {
	self, err := h.authorize(c, studentID, true)
	if err != nil {
		return err
	}
	if self {
		return response.Forbidden("Only staff can verify")
	}
	return nil
}

// ---- projects ----

type projectBody struct {
	Title       string  `json:"title" binding:"required,max=150"`
	Description *string `json:"description" binding:"omitempty,max=2000"`
	TechStack   *string `json:"tech_stack" binding:"omitempty,max=300"`
	RepoURL     *string `json:"repo_url"`
	LiveURL     *string `json:"live_url"`
	Status      string  `json:"status"`
}

func (b *projectBody) check() error {
	b.Title = strings.TrimSpace(b.Title)
	if b.Title == "" {
		return response.BadRequest("title is required")
	}
	if b.Status == "" {
		b.Status = "completed"
	}
	if b.Status != "ongoing" && b.Status != "completed" {
		return response.BadRequest("status must be ongoing or completed")
	}
	for name, u := range map[string]**string{"repo_url": &b.RepoURL, "live_url": &b.LiveURL} {
		if *u == nil {
			continue
		}
		s := strings.TrimSpace(**u)
		switch {
		case s == "":
			*u = nil
		case !ValidURL(s):
			return response.BadRequest(name + " must start with http:// or https://")
		default:
			*u = &s
		}
	}
	return nil
}

func (h *Handler) addProject(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.authorize(c, id, true); err != nil {
		response.Error(c, err)
		return
	}
	var b projectBody
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Check the project details", err.Error()))
		return
	}
	if err := b.check(); err != nil {
		response.Error(c, err)
		return
	}
	var newID int64
	if err := h.db.QueryRow(c, `
		INSERT INTO student_projects (student_id, title, description, tech_stack, repo_url, live_url, status, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8) RETURNING id`,
		id, b.Title, b.Description, b.TechStack, b.RepoURL, b.LiveURL, b.Status, actor.From(c).ID).Scan(&newID); err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, gin.H{"id": newID})
}

func (h *Handler) updateProject(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "student_projects", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	self, err := h.authorize(c, sid, true)
	if err != nil {
		response.Error(c, err)
		return
	}
	var b projectBody
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Check the project details", err.Error()))
		return
	}
	if err := b.check(); err != nil {
		response.Error(c, err)
		return
	}
	// The student changing their own project means the earlier review no longer applies.
	if _, err := h.db.Exec(c, `
		UPDATE student_projects SET title = $2, description = $3, tech_stack = $4, repo_url = $5, live_url = $6, status = $7, updated_by = $8,
		       verified = CASE WHEN $9 THEN false ELSE verified END
		WHERE id = $1 AND is_active`, id, b.Title, b.Description, b.TechStack, b.RepoURL, b.LiveURL, b.Status, actor.From(c).ID, self); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"message": "Saved"})
}

func (h *Handler) removeProject(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "student_projects", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.authorize(c, sid, true); err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.db.Exec(c, `UPDATE student_projects SET is_active = false, updated_by = $2 WHERE id = $1`, id, actor.From(c).ID); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"message": "Removed"})
}

// reviewProject lets staff verify a project and rate its code with the rubric (or withdraw verification).
func (h *Handler) reviewProject(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	sid, err := h.ownerOf(c, "student_projects", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if err := h.requireReviewer(c, sid); err != nil {
		response.Error(c, err)
		return
	}
	var b struct {
		Verified bool           `json:"verified"`
		Rubric   map[string]int `json:"rubric"`
		Notes    *string        `json:"notes" binding:"omitempty,max=1000"`
	}
	if err := c.ShouldBindJSON(&b); err != nil {
		response.Error(c, response.BadRequest("Send {\"verified\": true, \"rubric\": {...}}"))
		return
	}
	a := actor.From(c)
	if !b.Verified {
		if _, err := h.db.Exec(c, `UPDATE student_projects SET verified = false, verified_by = NULL, verified_at = NULL, updated_by = $2 WHERE id = $1`, id, a.ID); err != nil {
			response.Error(c, err)
			return
		}
		h.syncCodingScore(c, sid)
		response.OK(c, gin.H{"verified": false})
		return
	}
	quality, err := QualityScore(b.Rubric)
	if err != nil {
		response.Error(c, response.BadRequest(err.Error()))
		return
	}
	rubric, _ := json.Marshal(b.Rubric)
	if _, err := h.db.Exec(c, `
		UPDATE student_projects SET verified = true, verified_by = $2, verified_at = now(), rubric = $3, quality_score = $4, review_notes = $5, updated_by = $2
		WHERE id = $1 AND is_active`, id, a.ID, rubric, quality, b.Notes); err != nil {
		response.Error(c, err)
		return
	}
	h.syncCodingScore(c, sid)
	response.OK(c, gin.H{"verified": true, "quality_score": quality})
}
