// Package kb is the knowledge base behind the AI assistant: staff upload documents (syllabus, notes,
// question papers…), they are cut into passages and embedded, and the chat finds the passages whose
// meaning is closest to a question.
package kb

import (
	"context"
	"io"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

const (
	maxFileBytes = 10 << 20
	// MinScore drops passages that are only vaguely related, so an unrelated question gets no sources
	// instead of a misleading one. Tuned for nomic-embed-text.
	MinScore = 0.53
	// RelativeCut also drops passages scoring well below the best match for the same question.
	RelativeCut = 0.8
)

var docTypes = map[string]bool{"syllabus": true, "notes": true, "question_paper": true, "placement": true, "resume": true, "roadmap": true, "other": true}

type Service struct {
	db  *pgxpool.Pool
	emb *Embedder
}

func NewService(db *pgxpool.Pool, emb *Embedder) *Service { return &Service{db: db, emb: emb} }

// Scope says which documents a caller may retrieve: documents with no department are for everyone,
// the rest only for their own department (or for everyone when All is set, e.g. admins).
type Scope struct {
	All          bool
	DepartmentID *int64
}

type Hit struct {
	DocumentID int64   `json:"document_id"`
	Title      string  `json:"title"`
	DocType    string  `json:"doc_type"`
	Content    string  `json:"content"`
	Score      float64 `json:"score"`
}

// Search returns up to k passages closest in meaning to the query, best first.
func (s *Service) Search(ctx context.Context, query string, scope Scope, k int) ([]Hit, error) {
	query = strings.TrimSpace(query)
	if query == "" || k <= 0 {
		return nil, nil
	}
	qv, err := s.emb.EmbedQuery(ctx, query)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `
		SELECT d.id, d.title, d.doc_type, c.content, c.embedding
		FROM kb_chunks c JOIN kb_documents d ON d.id = c.document_id
		WHERE d.is_active AND d.embed_model = $1
		  AND ($2 OR d.department_id IS NULL OR d.department_id = $3)`, s.emb.Model(), scope.All, scope.DepartmentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var hits []Hit
	for rows.Next() {
		var h Hit
		var vec []float32
		if err := rows.Scan(&h.DocumentID, &h.Title, &h.DocType, &h.Content, &vec); err != nil {
			return nil, err
		}
		if h.Score = Cosine(qv, vec); h.Score >= MinScore {
			hits = append(hits, h)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].Score > hits[j].Score })
	if len(hits) > 0 {
		keep := hits[:0]
		for _, h := range hits {
			if h.Score >= hits[0].Score*RelativeCut {
				keep = append(keep, h)
			}
		}
		hits = keep
	}
	if len(hits) > k {
		hits = hits[:k]
	}
	return hits, nil
}

// ---- HTTP ----

type Handler struct{ svc *Service }

func Register(r *gin.RouterGroup, perms *rbac.Cache, svc *Service) {
	h := &Handler{svc: svc}
	can := middleware.RequirePermission(perms, "kb.manage")
	r.POST("/kb/documents", can, h.upload)
	r.GET("/kb/documents", can, h.list)
	r.DELETE("/kb/documents/:id", can, h.remove)
	r.POST("/kb/search", can, h.search)
}

type Document struct {
	ID             int64     `json:"id"`
	Title          string    `json:"title"`
	DocType        string    `json:"doc_type"`
	DepartmentID   *int64    `json:"department_id"`
	DepartmentName *string   `json:"department_name"`
	SubjectID      *int64    `json:"subject_id"`
	SubjectName    *string   `json:"subject_name"`
	SourceName     string    `json:"source_name"`
	ChunkCount     int       `json:"chunk_count"`
	CreatedAt      time.Time `json:"created_at"`
}

// canSeeAllDepartments: admins and placement officers work across departments; staff and HODs
// are tied to their own.
func canSeeAllDepartments(a actor.Actor) bool { return a.Has("admin", "placement_officer") }

func (h *Handler) userDepartment(ctx context.Context, id int64) (*int64, error) {
	var d *int64
	err := h.svc.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, id).Scan(&d)
	return d, err
}

func optionalInt(c *gin.Context, field string) (*int64, bool) {
	v := strings.TrimSpace(c.PostForm(field))
	if v == "" {
		return nil, true
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n <= 0 {
		response.Error(c, response.BadRequest(field+" must be a number"))
		return nil, false
	}
	return &n, true
}

func (h *Handler) upload(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		response.Error(c, response.BadRequest("Attach the document as form field 'file'"))
		return
	}
	if fh.Size > maxFileBytes {
		response.Error(c, response.BadRequest("File is larger than 10 MB"))
		return
	}
	docType := strings.TrimSpace(c.DefaultPostForm("doc_type", "notes"))
	if !docTypes[docType] {
		response.Error(c, response.BadRequest("doc_type must be one of syllabus, notes, question_paper, placement, resume, roadmap, other"))
		return
	}
	title := strings.TrimSpace(c.PostForm("title"))
	if title == "" {
		title = strings.TrimSuffix(fh.Filename, "."+strings.TrimPrefix(extOf(fh.Filename), "."))
	}
	if len([]rune(title)) > 200 {
		response.Error(c, response.BadRequest("title is too long (max 200 characters)"))
		return
	}
	deptID, ok := optionalInt(c, "department_id")
	if !ok {
		return
	}
	subjectID, ok := optionalInt(c, "subject_id")
	if !ok {
		return
	}

	ctx := c.Request.Context()
	a := actor.From(c)
	if !canSeeAllDepartments(a) {
		// Staff and HODs can only add documents for their own department.
		own, err := h.userDepartment(ctx, a.ID)
		if err != nil {
			response.Error(c, err)
			return
		}
		if own != nil {
			deptID = own
		}
	}

	src, err := fh.Open()
	if err != nil {
		response.Error(c, err)
		return
	}
	defer src.Close()
	data, err := io.ReadAll(io.LimitReader(src, maxFileBytes+1))
	if err != nil {
		response.Error(c, err)
		return
	}

	id, passages, err := h.svc.Ingest(ctx, IngestInput{
		Title: title, DocType: docType, SourceName: fh.Filename, Data: data,
		DepartmentID: deptID, SubjectID: subjectID, CreatedBy: a.ID,
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, gin.H{"id": id, "title": title, "chunk_count": passages})
}

func extOf(name string) string {
	if i := strings.LastIndex(name, "."); i >= 0 {
		return name[i:]
	}
	return ""
}

// mapFKError turns an unknown department/subject id into a readable 400.
func mapFKError(err error) error {
	if dbutil.ForeignKeyViolation(err) {
		return response.BadRequest("department_id or subject_id does not exist")
	}
	return err
}

func (h *Handler) list(c *gin.Context) {
	ctx := c.Request.Context()
	a := actor.From(c)
	var dept *int64
	if !canSeeAllDepartments(a) {
		var err error
		if dept, err = h.userDepartment(ctx, a.ID); err != nil {
			response.Error(c, err)
			return
		}
	}
	rows, err := h.svc.db.Query(ctx, `
		SELECT d.id, d.title, d.doc_type, d.department_id, dp.name, d.subject_id, s.name, d.source_name, d.chunk_count, d.created_at
		FROM kb_documents d
		LEFT JOIN departments dp ON dp.id = d.department_id
		LEFT JOIN subjects s ON s.id = d.subject_id
		WHERE d.is_active AND ($1::bigint IS NULL OR d.department_id IS NULL OR d.department_id = $1)
		ORDER BY d.created_at DESC`, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	docs, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Document])
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, docs)
}

func (h *Handler) remove(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	a := actor.From(c)
	var dept *int64
	if !canSeeAllDepartments(a) {
		var err error
		if dept, err = h.userDepartment(ctx, a.ID); err != nil {
			response.Error(c, err)
			return
		}
	}
	tx, err := h.svc.db.Begin(ctx)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE kb_documents SET is_active = false
		WHERE id = $1 AND is_active AND ($2::bigint IS NULL OR department_id = $2)`, id, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	if tag.RowsAffected() == 0 {
		response.Error(c, response.NotFound("Document not found"))
		return
	}
	if _, err := tx.Exec(ctx, `DELETE FROM kb_chunks WHERE document_id = $1`, id); err != nil {
		response.Error(c, err)
		return
	}
	if err := tx.Commit(ctx); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"message": "Removed"})
}

func (h *Handler) search(c *gin.Context) {
	var req struct {
		Query string `json:"query" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Query) == "" {
		response.Error(c, response.BadRequest("query is required"))
		return
	}
	ctx := c.Request.Context()
	a := actor.From(c)
	scope := Scope{All: canSeeAllDepartments(a)}
	if !scope.All {
		var err error
		if scope.DepartmentID, err = h.userDepartment(ctx, a.ID); err != nil {
			response.Error(c, err)
			return
		}
	}
	hits, err := h.svc.Search(ctx, req.Query, scope, 5)
	if err != nil {
		slog.Error("kb: search failed", "err", err)
		response.Error(c, response.ServiceUnavailable("Search is not available right now."))
		return
	}
	if hits == nil {
		hits = []Hit{}
	}
	response.OK(c, hits)
}

// DepartmentFor applies the rule for adding documents: staff and HODs can only add them for their own
// department, while admins and placement officers may choose (nil means everyone).
func (s *Service) DepartmentFor(ctx context.Context, a actor.Actor, requested *int64) (*int64, error) {
	if canSeeAllDepartments(a) {
		return requested, nil
	}
	var own *int64
	if err := s.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&own); err != nil {
		return nil, err
	}
	if own != nil {
		return own, nil
	}
	return requested, nil
}
