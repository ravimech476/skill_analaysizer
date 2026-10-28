package kb

import (
	"context"
	"log/slog"

	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/pkg/response"
)

// IngestInput is a document to index: its bytes, and who may retrieve it.
type IngestInput struct {
	Title        string
	DocType      string
	SourceName   string // original file name; its extension decides how the text is read
	Data         []byte
	DepartmentID *int64
	SubjectID    *int64
	CreatedBy    int64
}

// createdBy is NULL for documents the application adds itself.
func createdBy(id int64) *int64 {
	if id == 0 {
		return nil
	}
	return &id
}

// Ingest reads the text of a document, cuts it into passages, embeds them and stores everything in one
// transaction. Errors that the user can act on (unreadable file, too long) come back as 400s.
func (s *Service) Ingest(ctx context.Context, in IngestInput) (id int64, passages int, err error) {
	text, err := ExtractText(in.SourceName, in.Data)
	if err != nil {
		return 0, 0, response.BadRequest(err.Error())
	}
	chunks := Chunk(text, chunkWords, chunkOverlap)
	if len(chunks) == 0 {
		return 0, 0, response.BadRequest("No readable text was found in this file (scanned PDFs need OCR, which is not supported)")
	}
	if len(chunks) > maxChunks {
		return 0, 0, response.BadRequest("This document is too long; split it into smaller files")
	}

	vecs, err := s.emb.EmbedDocuments(ctx, chunks)
	if err != nil {
		slog.Error("kb: embedding failed", "err", err)
		return 0, 0, response.ServiceUnavailable("The embedding model is not available right now. Please try again later.")
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx)

	if err := tx.QueryRow(ctx, `
		INSERT INTO kb_documents (title, doc_type, department_id, subject_id, source_name, chunk_count, embed_model, created_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
		in.Title, in.DocType, in.DepartmentID, in.SubjectID, in.SourceName, len(chunks), s.emb.Model(), createdBy(in.CreatedBy)).Scan(&id); err != nil {
		return 0, 0, mapFKError(err)
	}
	batch := &pgx.Batch{}
	for i, ch := range chunks {
		batch.Queue(`INSERT INTO kb_chunks (document_id, position, content, embedding) VALUES ($1, $2, $3, $4)`, id, i, ch, vecs[i])
	}
	br := tx.SendBatch(ctx, batch)
	for range chunks {
		if _, err := br.Exec(); err != nil {
			br.Close()
			return 0, 0, err
		}
	}
	if err := br.Close(); err != nil {
		return 0, 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return id, len(chunks), nil
}
