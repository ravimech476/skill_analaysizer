package chat

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Message is one turn sent to the model (role: system, user or assistant).
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Ollama talks to a local Ollama server. Nothing leaves the machine.
type Ollama struct {
	baseURL string
	model   string
	http    *http.Client
}

func NewOllama(baseURL, model string, timeout time.Duration) *Ollama {
	return &Ollama{baseURL: baseURL, model: model, http: &http.Client{Timeout: timeout}}
}

// Chat sends the conversation to /api/chat and returns the full (non-streamed) answer.
func (o *Ollama) Chat(ctx context.Context, msgs []Message) (string, error) {
	return o.send(ctx, map[string]any{
		"model":    o.model,
		"messages": msgs,
		"stream":   false,
		"options":  map[string]any{"temperature": 0.3, "num_predict": 700},
	})
}

// ChatJSON is for tasks with a fixed answer shape: the reply is forced to match the JSON schema
// (so a label can only be one of the allowed values) and sampled without randomness.
func (o *Ollama) ChatJSON(ctx context.Context, msgs []Message, schema map[string]any) (string, error) {
	return o.ChatStructured(ctx, msgs, schema, 200)
}

// ChatStructured is ChatJSON with a limit on the length of the reply, for answers longer than a label.
func (o *Ollama) ChatStructured(ctx context.Context, msgs []Message, schema map[string]any, maxTokens int) (string, error) {
	return o.send(ctx, map[string]any{
		"model":    o.model,
		"messages": msgs,
		"stream":   false,
		"format":   schema,
		"options":  map[string]any{"temperature": 0, "num_predict": maxTokens},
	})
}

func (o *Ollama) send(ctx context.Context, payload map[string]any) (string, error) {
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, o.baseURL+"/api/chat", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	res, err := o.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("ollama unreachable: %w", err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("ollama returned %d: %s", res.StatusCode, strings.TrimSpace(string(raw)))
	}
	var out struct {
		Message Message `json:"message"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("ollama reply: %w", err)
	}
	answer := strings.TrimSpace(out.Message.Content)
	if answer == "" {
		return "", fmt.Errorf("ollama returned an empty answer")
	}
	return answer, nil
}
