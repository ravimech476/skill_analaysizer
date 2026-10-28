package kb

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"
)

// Embedder turns text into vectors with a local Ollama embedding model (nothing leaves the machine).
type Embedder struct {
	baseURL string
	model   string
	http    *http.Client
}

func NewEmbedder(baseURL, model string) *Embedder {
	return &Embedder{baseURL: baseURL, model: model, http: &http.Client{Timeout: 3 * time.Minute}}
}

func (e *Embedder) Model() string { return e.model }

// nomic-embed-text is trained with a task prefix; using it noticeably improves matching.
const (
	docPrefix   = "search_document: "
	queryPrefix = "search_query: "
)

func (e *Embedder) embed(ctx context.Context, prefix string, texts []string) ([][]float32, error) {
	in := make([]string, len(texts))
	for i, t := range texts {
		in[i] = prefix + t
	}
	body, _ := json.Marshal(map[string]any{"model": e.model, "input": in})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, e.baseURL+"/api/embed", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := e.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ollama unreachable: %w", err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 64<<20))
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ollama embed returned %d: %s", res.StatusCode, strings.TrimSpace(string(raw)))
	}
	var out struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("ollama embed reply: %w", err)
	}
	if len(out.Embeddings) != len(texts) {
		return nil, fmt.Errorf("ollama returned %d vectors for %d texts", len(out.Embeddings), len(texts))
	}
	return out.Embeddings, nil
}

// EmbedDocuments embeds passages in batches.
func (e *Embedder) EmbedDocuments(ctx context.Context, texts []string) ([][]float32, error) {
	const batch = 16
	out := make([][]float32, 0, len(texts))
	for i := 0; i < len(texts); i += batch {
		j := min(i+batch, len(texts))
		v, err := e.embed(ctx, docPrefix, texts[i:j])
		if err != nil {
			return nil, err
		}
		out = append(out, v...)
	}
	return out, nil
}

func (e *Embedder) EmbedQuery(ctx context.Context, q string) ([]float32, error) {
	v, err := e.embed(ctx, queryPrefix, []string{q})
	if err != nil {
		return nil, err
	}
	return v[0], nil
}

// Cosine is the similarity of two vectors in [-1, 1]; 0 if they differ in length or either is all zeros.
func Cosine(a, b []float32) float64 {
	if len(a) != len(b) || len(a) == 0 {
		return 0
	}
	var dot, na, nb float64
	for i := range a {
		x, y := float64(a[i]), float64(b[i])
		dot += x * y
		na += x * x
		nb += y * y
	}
	if na == 0 || nb == 0 {
		return 0
	}
	return dot / (math.Sqrt(na) * math.Sqrt(nb))
}
