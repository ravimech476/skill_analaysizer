package chat

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"skills-analyzer/internal/modules/kb"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/pkg/actor"
)

const knowledgePassages = 4

// Source is a knowledge-base document an answer drew on, shown to the user under the answer.
type Source struct {
	DocumentID int64  `json:"document_id"`
	Title      string `json:"title"`
	DocType    string `json:"doc_type"`
}

// knowledge finds passages from uploaded documents that match the meaning of the question.
// It never fails the chat: if the embedding model is down the answer just has no sources.
func (h *Handler) knowledge(ctx context.Context, a actor.Actor, st *student.Student, msg string) (string, []Source) {
	if h.kb == nil {
		return "", nil
	}
	// Documents tied to a department are only for that department: the student's when the question is
	// about one, otherwise the asker's own. Admins and placement officers with no student in play see all.
	scope := kb.Scope{All: st == nil && a.Has("admin", "placement_officer")}
	switch {
	case scope.All:
	case st != nil:
		scope.DepartmentID = st.DepartmentID
	default:
		if err := h.db.QueryRow(ctx, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&scope.DepartmentID); err != nil {
			slog.Error("chat: knowledge scope failed", "err", err)
			return "", nil
		}
	}

	hits, err := h.kb.Search(ctx, msg, scope, knowledgePassages)
	if err != nil {
		slog.Error("chat: knowledge search failed", "err", err)
		return "", nil
	}
	if len(hits) == 0 {
		return "", nil
	}

	var b strings.Builder
	b.WriteString("KNOWLEDGE BASE (excerpts from college documents, most relevant first)\n")
	var sources []Source
	seen := map[int64]bool{}
	for _, hit := range hits {
		fmt.Fprintf(&b, "[%s] %s\n", hit.Title, clip(hit.Content, 1200))
		if !seen[hit.DocumentID] {
			seen[hit.DocumentID] = true
			sources = append(sources, Source{DocumentID: hit.DocumentID, Title: hit.Title, DocType: hit.DocType})
		}
	}
	return b.String(), sources
}
