package placement

import (
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/files"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

// Single-file slots on placement records: company logo, job description, offer letter.
// Each takes {file_id} from POST /files, or {file_id: null} to remove the file.

type fileBody struct {
	FileID *int64 `json:"file_id"`
}

// swapSlot replaces the file in table.column for row id and returns the new link.
func (h *Handler) swapSlot(c *gin.Context, table, column, category, key string, id int64) {
	body, ok := request.Bind[fileBody](c)
	if !ok {
		return
	}
	a := actor.From(c)
	var link *files.Link
	err := pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		var old *int64
		// table/column come from the fixed call sites below, never from input.
		if err := tx.QueryRow(c, `SELECT `+column+` FROM `+table+` WHERE id = $1 AND is_active FOR UPDATE`, id).Scan(&old); err != nil {
			if dbutil.IsNoRows(err) {
				return response.NotFound("Record not found")
			}
			return err
		}
		if err := files.Swap(c, tx, old, body.FileID, a.ID, category, table, id); err != nil {
			return err
		}
		return tx.QueryRow(c, `UPDATE `+table+` SET `+column+` = $2, updated_by = $3 WHERE id = $1 RETURNING file_json(`+column+`)`,
			id, body.FileID, a.ID).Scan(&link)
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{key: link})
}

// PUT /companies/:id/logo
func (h *Handler) setCompanyLogo(c *gin.Context) {
	if id, ok := request.ID(c, "id"); ok {
		h.swapSlot(c, "companies", "logo_file_id", "company_logo", "logo", id)
	}
}

// PUT /job-roles/:id/jd
func (h *Handler) setJobDescription(c *gin.Context) {
	if id, ok := request.ID(c, "id"); ok {
		h.swapSlot(c, "company_job_roles", "jd_file_id", "job_description", "jd", id)
	}
}

// PUT /placements/:id/offer-letter (placement team; scoped like the placement list)
func (h *Handler) setOfferLetter(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	var visible bool
	if err := h.db.QueryRow(c, `SELECT EXISTS (SELECT 1 FROM placement_records pr JOIN users u ON u.id = pr.student_id
		WHERE pr.id = $1 AND pr.is_active AND ($2::bigint IS NULL OR u.department_id = $2))`, id, scope).Scan(&visible); err != nil {
		response.Error(c, err)
		return
	}
	if !visible {
		response.Error(c, response.NotFound("Placement record not found"))
		return
	}
	h.swapSlot(c, "placement_records", "offer_letter_file_id", "offer_letter", "offer_letter", id)
}
