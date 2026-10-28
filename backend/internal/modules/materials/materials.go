// Package materials adds files to the document libraries: study materials, company interview documents and
// question papers. Staff upload a PDF, Word or PowerPoint file, attach it to a row so students can download it,
// and can also index it for the AI assistant.
package materials

import (
	"context"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/files"
	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/kb"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

// kind describes one document library: where its rows live and how its files are filed.
type kind struct {
	path     string // route prefix, e.g. "/study-materials"
	table    string
	category string // file category, as in files.Rules
	// updatePerm is the permission needed to attach or remove a file.
	updatePerm string
	// info selects (title, type, subject_id, file_id) of one live row; $1 is the id.
	info string
	// kbType maps the row's type to a knowledge-base document type.
	kbType func(rowType string) string
	noun   string
}

var kinds = []kind{
	{
		path: "/study-materials", table: "study_materials", category: "study_material", updatePerm: "study_material.update",
		info:   `SELECT title, material_type, subject_id, file_id FROM study_materials WHERE id = $1 AND is_active`,
		kbType: studyType, noun: "Study material",
	},
	{
		path: "/interview-documents", table: "interview_documents", category: "interview_document", updatePerm: "interview.update",
		info:   `SELECT title, doc_type, NULL::bigint, file_id FROM interview_documents WHERE id = $1 AND is_active`,
		kbType: func(string) string { return "placement" }, noun: "Interview document",
	},
	{
		path: "/question-papers", table: "question_papers", category: "question_paper", updatePerm: "question_bank.update",
		info:   `SELECT title, doc_type, subject_id, file_id FROM question_papers WHERE id = $1 AND is_active`,
		kbType: func(string) string { return "question_paper" }, noun: "Question paper",
	},
}

type Handler struct {
	db    *pgxpool.Pool
	files *files.Service
	kb    *kb.Service
}

func Register(r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, fileSvc *files.Service, knowledge *kb.Service) {
	h := &Handler{db: db, files: fileSvc, kb: knowledge}
	for _, k := range kinds {
		r.PUT(k.path+"/:id/file", middleware.RequirePermission(perms, k.updatePerm), h.setFile(k))
		r.POST(k.path+"/:id/index-for-ai", middleware.RequirePermission(perms, "kb.manage"), h.indexForAI(k))
	}
}

// setFile attaches an uploaded file (of the kind's category) to a row, replacing any earlier one,
// or removes the file when file_id is null.
func (h *Handler) setFile(k kind) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := request.ID(c, "id")
		if !ok {
			return
		}
		var body struct {
			FileID *int64 `json:"file_id"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			response.Error(c, response.BadRequest("Send {\"file_id\": <id or null>}"))
			return
		}
		a := actor.From(c)
		err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
			var old *int64
			if err := tx.QueryRow(c, `SELECT file_id FROM `+k.table+` WHERE id = $1 AND is_active FOR UPDATE`, id).Scan(&old); err != nil {
				if dbutil.IsNoRows(err) {
					return response.NotFound(k.noun + " not found")
				}
				return err
			}
			if err := files.Swap(c, tx, old, body.FileID, a.ID, k.category, k.table, id); err != nil {
				return err
			}
			_, err := tx.Exec(c, `UPDATE `+k.table+` SET file_id = $2, updated_by = $3 WHERE id = $1`, id, body.FileID, a.ID)
			return err
		})
		if err != nil {
			response.Error(c, err)
			return
		}
		var link *files.Link
		if err := h.db.QueryRow(c, `SELECT file_json(file_id) FROM `+k.table+` WHERE id = $1`, id).Scan(&link); err != nil {
			response.Error(c, err)
			return
		}
		response.OK(c, gin.H{"file": link})
	}
}

// studyType maps a study material's type to a knowledge-base document type.
func studyType(materialType string) string {
	if materialType == "question_paper" {
		return "question_paper"
	}
	return "notes"
}

// canIndex says whether the AI assistant can read a file with this name (PowerPoint is not supported yet).
func canIndex(name string) bool {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".pdf", ".docx", ".txt", ".md":
		return true
	}
	return false
}

func (h *Handler) indexForAI(k kind) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := request.ID(c, "id")
		if !ok {
			return
		}
		ctx := c.Request.Context()
		a := actor.From(c)

		var title, rowType string
		var subjectID, fileID *int64
		if err := h.db.QueryRow(ctx, k.info, id).Scan(&title, &rowType, &subjectID, &fileID); err != nil {
			if dbutil.IsNoRows(err) {
				response.Error(c, response.NotFound(k.noun+" not found"))
				return
			}
			response.Error(c, err)
			return
		}
		if fileID == nil {
			response.Error(c, response.BadRequest("Attach a file first"))
			return
		}
		name, data, err := h.files.Read(ctx, *fileID)
		if err != nil {
			response.Error(c, err)
			return
		}
		if !canIndex(name) {
			response.Error(c, response.BadRequest("The AI assistant can read PDF and Word files. PowerPoint files cannot be indexed yet."))
			return
		}
		if h.alreadyIndexed(ctx, title, name, subjectID) {
			response.Error(c, response.Conflict("This document is already in the AI knowledge base"))
			return
		}
		dept, err := h.kb.DepartmentFor(ctx, a, nil)
		if err != nil {
			response.Error(c, err)
			return
		}
		docID, passages, err := h.kb.Ingest(ctx, kb.IngestInput{
			Title: title, DocType: k.kbType(rowType), SourceName: name, Data: data,
			DepartmentID: dept, SubjectID: subjectID, CreatedBy: a.ID,
		})
		if err != nil {
			response.Error(c, err)
			return
		}
		response.Created(c, gin.H{"document_id": docID, "chunk_count": passages})
	}
}

func (h *Handler) alreadyIndexed(ctx context.Context, title, source string, subjectID *int64) bool {
	var exists bool
	_ = h.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM kb_documents WHERE is_active AND title = $1 AND source_name = $2 AND subject_id IS NOT DISTINCT FROM $3)`,
		title, source, subjectID).Scan(&exists)
	return exists
}
