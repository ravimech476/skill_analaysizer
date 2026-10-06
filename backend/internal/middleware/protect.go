package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/response"
)

// RequestID tags every request with X-Request-ID (kept from the proxy when present) for log correlation.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader("X-Request-ID")
		if id == "" || len(id) > 64 {
			b := make([]byte, 8)
			_, _ = rand.Read(b)
			id = hex.EncodeToString(b)
		}
		c.Set("request_id", id)
		c.Header("X-Request-ID", id)
		c.Next()
	}
}

// AccessLog writes one structured line per request (no query strings: they can carry signed file links).
func AccessLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		status := c.Writer.Status()
		level := slog.LevelInfo
		switch {
		case status >= 500:
			level = slog.LevelError
		case status >= 400:
			level = slog.LevelWarn
		}
		attrs := []any{"method", c.Request.Method, "path", c.Request.URL.Path, "status", status,
			"ms", time.Since(start).Milliseconds(), "ip", c.ClientIP(), "request_id", c.GetString("request_id")}
		if uid, ok := c.Get("auth.user_id"); ok {
			attrs = append(attrs, "user_id", uid)
		}
		slog.Log(c, level, "request", attrs...)
	}
}

// SecurityHeaders sets conservative defaults for an API. HSTS only when served over HTTPS in production.
func SecurityHeaders(production bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		if production {
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}

// BodyLimit caps request bodies: small for JSON, larger for multipart uploads.
func BodyLimit(jsonBytes, multipartBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Body == nil || c.Request.Method == http.MethodGet {
			c.Next()
			return
		}
		limit := jsonBytes
		if strings.HasPrefix(c.GetHeader("Content-Type"), "multipart/") {
			limit = multipartBytes
		}
		if c.Request.ContentLength > limit {
			response.Error(c, response.TooLarge(fmt.Sprintf("The request is too large (limit %d MB)", limit>>20)))
			c.Abort()
			return
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		c.Next()
	}
}

// Limiter counts hits per key in fixed windows. It is in-memory, which suits the single API
// container this app runs as; put a shared store behind it before running several API replicas.
type Limiter struct {
	max    int
	window int64 // seconds
	mu     sync.Mutex
	cur    int64
	counts map[string]int
}

// NewLimiter allows max hits per key per window (max <= 0 disables it).
func NewLimiter(max int, window time.Duration) *Limiter {
	return &Limiter{max: max, window: int64(window.Seconds()), counts: map[string]int{}}
}

// Allow records a hit and reports whether the key is still under its limit (and seconds to wait if not).
func (l *Limiter) Allow(key string, now time.Time) (bool, int) {
	if l.max <= 0 {
		return true, 0
	}
	w := now.Unix() / l.window
	l.mu.Lock()
	defer l.mu.Unlock()
	if w != l.cur { // new window: forget old counts (also keeps memory bounded)
		l.cur = w
		l.counts = map[string]int{}
	}
	l.counts[key]++
	if l.counts[key] > l.max {
		return false, int(l.window - now.Unix()%l.window)
	}
	return true, 0
}

// Peek reports whether the key is already over its limit without counting a hit.
func (l *Limiter) Peek(key string, now time.Time) (bool, int) {
	if l.max <= 0 {
		return true, 0
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if now.Unix()/l.window != l.cur || l.counts[key] < l.max {
		return true, 0
	}
	return false, int(l.window - now.Unix()%l.window)
}

// RateLimit rejects a client IP that exceeds the limiter's budget with 429 and Retry-After.
func RateLimit(l *Limiter, scope string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if ok, wait := l.Allow(scope+"|"+c.ClientIP(), time.Now()); !ok {
			c.Header("Retry-After", fmt.Sprint(wait))
			response.Error(c, response.TooManyRequests(fmt.Sprintf("Too many requests. Please wait %d seconds and try again.", wait)))
			c.Abort()
			return
		}
		c.Next()
	}
}
