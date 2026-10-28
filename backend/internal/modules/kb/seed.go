package kb

import (
	"context"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"
)

// The built-in knowledge base: career paths, industry skills and general placement knowledge that ships
// with the application, so the assistant can answer questions the college has not uploaded documents for.
// Each "## " section becomes one document of its own, which keeps retrieval precise. Editing a section
// replaces its old version the next time the server starts; sections are never touched once they match.

//go:embed knowledge/*.md
var knowledgeFS embed.FS

// seedFiles says which document type each built-in file is stored as.
var seedFiles = []struct{ File, DocType string }{
	{"career-paths.md", "roadmap"},
	{"industry-skills.md", "placement"},
	{"domain-knowledge.md", "notes"},
}

type Section struct {
	Title string
	Body  string
}

// ParseSections splits a markdown file into its "## " sections.
func ParseSections(md string) []Section {
	var out []Section
	var cur *Section
	for _, line := range strings.Split(strings.ReplaceAll(md, "\r\n", "\n"), "\n") {
		if strings.HasPrefix(line, "## ") {
			out = append(out, Section{Title: strings.TrimSpace(strings.TrimPrefix(line, "## "))})
			cur = &out[len(out)-1]
			continue
		}
		if cur != nil {
			cur.Body += line + "\n"
		}
	}
	for i := range out {
		out[i].Body = strings.TrimSpace(out[i].Body)
	}
	return out
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

func slug(s string) string { return strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(s), "-"), "-") }

// sourceName identifies one version of a section: its slug plus a short hash of its text.
func sourceName(s Section) (prefix, full string) {
	sum := sha256.Sum256([]byte(s.Title + "\n" + s.Body))
	prefix = "seed-" + slug(s.Title) + "-"
	return prefix, prefix + hex.EncodeToString(sum[:4]) + ".txt"
}

// SeedKnowledge adds the built-in sections that are missing or changed and returns how many it added.
// It needs the embedding model, so it can fail and be retried on the next start.
func (s *Service) SeedKnowledge(ctx context.Context) (int, error) {
	added := 0
	for _, f := range seedFiles {
		raw, err := knowledgeFS.ReadFile("knowledge/" + f.File)
		if err != nil {
			return added, err
		}
		for _, sec := range ParseSections(string(raw)) {
			prefix, name := sourceName(sec)
			var exists bool
			if err := s.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM kb_documents WHERE source_name = $1 AND is_active AND embed_model = $2)`,
				name, s.emb.Model()).Scan(&exists); err != nil {
				return added, err
			}
			if exists {
				continue
			}
			// An older version of this section, or one made with another embedding model, is replaced.
			if _, err := s.db.Exec(ctx, `UPDATE kb_documents SET is_active = false WHERE source_name LIKE $1 AND is_active`, prefix+"%"); err != nil {
				return added, err
			}
			if _, _, err := s.Ingest(ctx, IngestInput{
				Title: sec.Title, DocType: f.DocType, SourceName: name,
				Data: []byte(sec.Title + "\n\n" + sec.Body),
			}); err != nil {
				return added, fmt.Errorf("%s: %w", sec.Title, err)
			}
			added++
		}
	}
	return added, nil
}

// SeedInBackground runs SeedKnowledge once without holding up start-up, retrying while the embedding model
// is not ready yet.
func (s *Service) SeedInBackground(ctx context.Context) {
	go func() {
		for attempt := 1; attempt <= 5; attempt++ {
			n, err := s.SeedKnowledge(ctx)
			if err == nil {
				if n > 0 {
					slog.Info("knowledge base seeded", "documents", n)
				}
				return
			}
			slog.Warn("knowledge base seeding will retry", "added", n, "err", err)
			select {
			case <-time.After(time.Minute):
			case <-ctx.Done():
				return
			}
		}
	}()
}
