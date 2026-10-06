// Package media attaches uploaded files to people: profile photos, student resumes and the
// documents a student keeps on file (verified by staff). Files are uploaded first through
// POST /files; these endpoints take the returned file_id.
package media

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/files"
	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	perms    *rbac.Cache
	students *student.Service
	notify   *notify.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, perms: perms, students: students, notify: n}
	can := func(p ...string) gin.HandlerFunc { return middleware.RequirePermission(perms, p...) }

	r.PUT("/users/me/photo", h.setMyPhoto)
	r.PUT("/users/:id/photo", h.setUserPhoto)
	r.PUT("/students/:id/resume", h.setResume)

	r.GET("/students/:id/documents", can("document.view"), h.listDocuments)
	r.POST("/students/:id/documents", can("document.create"), h.addDocument)
	r.PATCH("/students/:id/documents/:docId", can("document.verify"), h.verifyDocument)
	r.DELETE("/students/:id/documents/:docId", can("document.delete"), h.deleteDocument)
	r.GET("/documents/pending", can("document.verify"), h.pending)
}

type fileBody struct {
	FileID *int64 `json:"file_id"` // null removes the file
}

func isStaff(a actor.Actor) bool { return a.Has("admin", "placement_officer", "hod", "staff") }

// canManageStudent: the student themself, or staff who can see the student (their department),
// the same rule as recording student skills.
func (h *Handler) canManageStudent(c *gin.Context, a actor.Actor, id int64, allowSelf bool) error {
	if allowSelf && a.ID == id {
		return nil
	}
	if !isStaff(a) {
		return response.Forbidden("You cannot change this student's files")
	}
	_, err := h.students.Get(c, a, id) // department scope; 404 for non-students
	return err
}

// ---- photos ----

func (h *Handler) setMyPhoto(c *gin.Context) {
	h.setPhoto(c, actor.From(c).ID)
}

// setUserPhoto: admins (user.update) for anyone; staff for students in their scope.
func (h *Handler) setUserPhoto(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if a.ID != id {
		canUsers, err := h.perms.HasAny(c, a.Roles, "user.update")
		if err != nil {
			response.Error(c, err)
			return
		}
		if !canUsers {
			if err := h.canManageStudent(c, a, id, false); err != nil {
				response.Error(c, err)
				return
			}
		}
	}
	h.setPhoto(c, id)
}

func (h *Handler) setPhoto(c *gin.Context, userID int64) {
	body, ok := request.Bind[fileBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	var link *files.Link
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var old *int64
		if err := tx.QueryRow(c, `SELECT photo_file_id FROM users WHERE id = $1 AND is_active FOR UPDATE`, userID).Scan(&old); err != nil {
			if dbutil.IsNoRows(err) {
				return response.NotFound("User not found")
			}
			return err
		}
		if err := files.Swap(c, tx, old, body.FileID, a.ID, "profile_photo", "users", userID); err != nil {
			return err
		}
		return tx.QueryRow(c, `UPDATE users SET photo_file_id = $2, updated_by = $3 WHERE id = $1 RETURNING file_json(photo_file_id)`,
			userID, body.FileID, a.ID).Scan(&link)
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"photo": link})
}

// ---- resume ----

func (h *Handler) setResume(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if err := h.canManageStudent(c, a, id, true); err != nil {
		response.Error(c, err)
		return
	}
	body, ok := request.Bind[fileBody](c)
	if !ok {
		return
	}
	var link *files.Link
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var old *int64
		if err := tx.QueryRow(c, `SELECT resume_file_id FROM student_profiles WHERE user_id = $1 AND is_active FOR UPDATE`, id).Scan(&old); err != nil {
			if dbutil.IsNoRows(err) {
				return response.NotFound("Student not found")
			}
			return err
		}
		if err := files.Swap(c, tx, old, body.FileID, a.ID, "resume", "student_profiles", id); err != nil {
			return err
		}
		return tx.QueryRow(c, `UPDATE student_profiles SET resume_file_id = $2, updated_by = $3 WHERE user_id = $1 AND is_active
			RETURNING file_json(resume_file_id)`, id, body.FileID, a.ID).Scan(&link)
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"resume": link})
}

// ---- student documents ----

var docTypes = map[string]string{
	"id_proof": "ID proof", "photo_id": "Photo ID", "marksheet_10": "10th mark sheet", "marksheet_12": "12th mark sheet",
	"diploma": "Diploma certificate", "transfer_certificate": "Transfer certificate", "community_certificate": "Community certificate",
	"income_certificate": "Income certificate", "course_certificate": "Course certificate",
	"internship_certificate": "Internship certificate", "other": "Other",
}

type Document struct {
	ID           int64       `json:"id"`
	StudentID    int64       `json:"student_id"`
	StudentName  string      `json:"student_name"`
	RegisterNo   string      `json:"register_no"`
	ClassLabel   *string     `json:"class_label"`
	DocType      string      `json:"doc_type"`
	DocTypeLabel string      `json:"doc_type_label"`
	Title        string      `json:"title"`
	File         *files.Link `json:"file"`
	Status       string      `json:"status"`
	Remarks      *string     `json:"remarks"`
	VerifiedBy   *string     `json:"verified_by"`
	VerifiedAt   *time.Time  `json:"verified_at"`
	UploadedBy   *string     `json:"uploaded_by"`
	CreatedAt    time.Time   `json:"created_at"`
}

const selectDoc = `
	SELECT d.id, d.student_id, u.name, sp.register_no,
	       CASE WHEN c.id IS NULL THEN NULL
	            ELSE cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section END,
	       d.doc_type, d.title, file_json(d.file_id), d.status, d.remarks, v.name, d.verified_at, up.name, d.created_at
	FROM student_documents d
	JOIN users u ON u.id = d.student_id
	JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
	LEFT JOIN classes c ON c.id = sp.current_class_id
	LEFT JOIN departments cd ON cd.id = c.department_id
	LEFT JOIN year_levels yl ON yl.id = c.year_level_id
	LEFT JOIN users v ON v.id = d.verified_by
	LEFT JOIN users up ON up.id = d.created_by`

func scanDoc(row pgx.Row) (*Document, error) {
	d := &Document{}
	err := row.Scan(&d.ID, &d.StudentID, &d.StudentName, &d.RegisterNo, &d.ClassLabel, &d.DocType, &d.Title, &d.File,
		&d.Status, &d.Remarks, &d.VerifiedBy, &d.VerifiedAt, &d.UploadedBy, &d.CreatedAt)
	d.DocTypeLabel = docTypes[d.DocType]
	return d, err
}

func (h *Handler) docsWhere(ctx context.Context, cond, suffix string, args ...any) ([]*Document, error) {
	rows, err := h.db.Query(ctx, selectDoc+" WHERE d.is_active AND "+cond+" ORDER BY d.created_at DESC"+suffix, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Document{}
	for rows.Next() {
		d, err := scanDoc(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (h *Handler) findDoc(ctx context.Context, studentID, docID int64) (*Document, error) {
	d, err := scanDoc(h.db.QueryRow(ctx, selectDoc+" WHERE d.is_active AND d.id = $1 AND d.student_id = $2", docID, studentID))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Document not found")
	}
	return d, err
}

// listDocuments: anyone who can see the student (self, parents, staff of the department, admin).
func (h *Handler) listDocuments(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.docsWhere(c, "d.student_id = $1", "", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"documents": list, "types": docTypes})
}

type addDocBody struct {
	DocType string `json:"doc_type" binding:"required"`
	Title   string `json:"title" binding:"max=150"`
	FileID  int64  `json:"file_id" binding:"required"`
}

// addDocument: students add their own; staff add for students in their department.
// Staff uploads are verified straight away; a student's upload waits for staff.
func (h *Handler) addDocument(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	a := actor.From(c)
	if a.ID != id && !isStaff(a) {
		response.Error(c, response.Forbidden("You can only upload your own documents"))
		return
	}
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	body, ok := request.Bind[addDocBody](c)
	if !ok {
		return
	}
	label, known := docTypes[body.DocType]
	if !known {
		response.Error(c, response.BadRequest("Unknown doc_type"))
		return
	}
	title := strings.TrimSpace(body.Title)
	if title == "" {
		title = label
	}
	byStaff := a.ID != id && isStaff(a)
	var docID int64
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var verifier *int64
		var verifiedAt *time.Time
		status := "pending"
		if byStaff {
			now := time.Now()
			status, verifier, verifiedAt = "verified", &a.ID, &now
		}
		if err := tx.QueryRow(c, `INSERT INTO student_documents (student_id, doc_type, title, file_id, status, verified_by, verified_at, created_by, updated_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8) RETURNING id`,
			id, body.DocType, title, body.FileID, status, verifier, verifiedAt, a.ID).Scan(&docID); err != nil {
			return err
		}
		return files.Attach(c, tx, body.FileID, a.ID, "student_document", "student_documents", docID)
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	d, err := h.findDoc(c, id, docID)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, d)
}

type verifyBody struct {
	Status  string  `json:"status" binding:"required,oneof=verified rejected pending"`
	Remarks *string `json:"remarks" binding:"omitempty,max=500"`
}

// verifyDocument: staff mark a document verified / rejected (the student and parents are told).
func (h *Handler) verifyDocument(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	docID, ok := request.ID(c, "docId")
	if !ok {
		return
	}
	a := actor.From(c)
	if !isStaff(a) {
		response.Error(c, response.Forbidden("Only staff can verify documents"))
		return
	}
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	body, ok := request.Bind[verifyBody](c)
	if !ok {
		return
	}
	if body.Status == "rejected" && (body.Remarks == nil || strings.TrimSpace(*body.Remarks) == "") {
		response.Error(c, response.BadRequest("Give a reason when rejecting a document"))
		return
	}
	before, err := h.findDoc(c, id, docID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if _, err := h.db.Exec(c, `UPDATE student_documents SET status = $3::varchar, remarks = $4,
		verified_by = CASE WHEN $3::varchar = 'pending' THEN NULL ELSE $5::bigint END,
		verified_at = CASE WHEN $3::varchar = 'pending' THEN NULL ELSE now() END, updated_by = $5
		WHERE id = $1 AND student_id = $2 AND is_active`, docID, id, body.Status, body.Remarks, a.ID); err != nil {
		response.Error(c, err)
		return
	}
	d, err := h.findDoc(c, id, docID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if before.Status != d.Status && d.Status != "pending" {
		msg := fmt.Sprintf("Your %s (%s) was verified.", d.DocTypeLabel, d.Title)
		title := "Document verified"
		if d.Status == "rejected" {
			title = "Document rejected"
			msg = fmt.Sprintf("Your %s (%s) was rejected: %s. Please upload it again.", d.DocTypeLabel, d.Title, *d.Remarks)
		}
		rt, rid := notify.Ref("student_document", d.ID)
		h.notify.SendSafe(c, notify.Notice{Title: title, Body: msg, Type: notify.TypeSystem, RefType: rt, RefID: rid, CreatedBy: a.ID},
			h.notify.WithParents(c, []int64{id}))
	}
	response.OK(c, d)
}

// deleteDocument: students may remove their own until it is verified; staff any in their scope.
func (h *Handler) deleteDocument(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	docID, ok := request.ID(c, "docId")
	if !ok {
		return
	}
	a := actor.From(c)
	if a.ID != id && !isStaff(a) {
		response.Error(c, response.Forbidden("You can only delete your own documents"))
		return
	}
	if _, err := h.students.Get(c, a, id); err != nil {
		response.Error(c, err)
		return
	}
	d, err := h.findDoc(c, id, docID)
	if err != nil {
		response.Error(c, err)
		return
	}
	if !isStaff(a) && d.Status == "verified" {
		response.Error(c, response.Conflict("A verified document can only be removed by staff"))
		return
	}
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var fileID *int64
		if err := tx.QueryRow(c, `UPDATE student_documents SET is_active = false, updated_by = $2 WHERE id = $1 RETURNING file_id`,
			docID, a.ID).Scan(&fileID); err != nil {
			return err
		}
		return files.Release(c, tx, fileID, a.ID)
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"deleted": true})
}

// pending: the verification queue — documents waiting for staff (own department for HOD/staff).
func (h *Handler) pending(c *gin.Context) {
	a := actor.From(c)
	if !isStaff(a) {
		response.Error(c, response.Forbidden("Only staff can verify documents"))
		return
	}
	status := c.DefaultQuery("status", "pending")
	if status != "pending" && status != "verified" && status != "rejected" && status != "all" {
		response.Error(c, response.BadRequest("status must be pending, verified, rejected or all"))
		return
	}
	var dept *int64
	if !a.Has("admin", "placement_officer") {
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&dept); err != nil {
			response.Error(c, err)
			return
		}
	}
	p := pagination.FromQuery(c)
	cond := `($1 = 'all' OR d.status = $1) AND ($2::bigint IS NULL OR u.department_id = $2)
		AND ($3::bigint IS NULL OR sp.current_class_id = $3)`
	args := []any{status, dept, request.QueryInt64(c, "class_id")}
	var total int64
	if err := h.db.QueryRow(c, `SELECT count(*) FROM student_documents d JOIN users u ON u.id = d.student_id
		JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active WHERE d.is_active AND `+cond, args...).Scan(&total); err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.docsWhere(c, cond, fmt.Sprintf(" LIMIT %d OFFSET %d", p.PageSize, p.Offset()), args...)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.List(c, list, response.Meta{Page: p.Page, PageSize: p.PageSize, Total: total})
}
