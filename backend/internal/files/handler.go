package files

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
)

// RegisterPublic mounts GET /files/:uuid (signature-checked, no login).
func (s *Service) RegisterPublic(r *gin.RouterGroup) {
	r.GET("/files/:uuid", s.serve)
}

// RegisterPrivate mounts POST /files (any signed-in user; the category decides what is allowed).
func (s *Service) RegisterPrivate(r *gin.RouterGroup) {
	r.POST("/files", s.upload)
}

func (s *Service) upload(c *gin.Context) {
	a := actor.From(c)
	fh, err := c.FormFile("file")
	if err != nil {
		response.Error(c, response.BadRequest("Attach the file as form field 'file'"))
		return
	}
	category := c.PostForm("category")
	if category == "company_logo" || category == "job_description" {
		if !a.Has("admin", "placement_officer") {
			response.Error(c, response.Forbidden("Only the placement team can upload this"))
			return
		}
	}
	if category == "notification_attachment" && !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("Only staff can attach files to notices"))
		return
	}
	info, err := s.Upload(c, a.ID, category, fh)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.Created(c, info)
}

func (s *Service) serve(c *gin.Context) {
	uuid := c.Param("uuid")
	exp, _ := strconv.ParseInt(c.Query("exp"), 10, 64)
	if !verify(uuid, exp, c.Query("sig"), time.Now()) {
		response.Error(c, response.Forbidden("This link has expired. Reload the page to get a new one."))
		return
	}
	var name, ctype, key string
	err := s.db.QueryRow(c, `SELECT original_name, content_type, storage_key FROM files WHERE uuid::text = $1 AND is_active AND storage_key <> ''`, uuid).
		Scan(&name, &ctype, &key)
	if dbutil.IsNoRows(err) {
		response.Error(c, response.NotFound("File not found"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	f, err := s.store.Open(key)
	if err != nil {
		response.Error(c, response.NotFound("File not found"))
		return
	}
	defer f.Close()
	disp := "inline"
	if c.Query("download") == "1" {
		disp = "attachment"
	}
	ascii := strings.Map(func(r rune) rune {
		if r > 126 || r < 32 {
			return '_'
		}
		return r
	}, name)
	c.Header("Content-Type", ctype)
	c.Header("Content-Disposition", fmt.Sprintf(`%s; filename="%s"; filename*=UTF-8''%s`, disp, ascii, url.PathEscape(name)))
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Cache-Control", "private, max-age=3600")
	http.ServeContent(c.Writer, c.Request, "", time.Time{}, f)
}

// ---- cleanup ----

// Cleanup removes uploads that were never attached (after a day) and the bytes of replaced
// or deleted files (after a week, so an accidental replace can still be undone by an admin).
func (s *Service) Cleanup(ctx context.Context) (int, error) {
	rows, err := s.db.Query(ctx, `
		UPDATE files SET is_active = false WHERE ref_type IS NULL AND is_active AND created_at < now() - interval '1 day'
		RETURNING id`)
	if err != nil {
		return 0, err
	}
	rows.Close()
	rows, err = s.db.Query(ctx, `SELECT id, storage_key FROM files WHERE NOT is_active AND storage_key <> '' AND updated_at < now() - interval '7 days'
		OR (NOT is_active AND storage_key <> '' AND ref_type IS NULL)`)
	if err != nil {
		return 0, err
	}
	type item struct {
		id  int64
		key string
	}
	var list []item
	for rows.Next() {
		var it item
		if rows.Scan(&it.id, &it.key) == nil {
			list = append(list, it)
		}
	}
	rows.Close()
	n := 0
	for _, it := range list {
		if err := s.store.Delete(it.key); err != nil {
			continue
		}
		if _, err := s.db.Exec(ctx, `UPDATE files SET storage_key = '' WHERE id = $1`, it.id); err == nil {
			n++
		}
	}
	return n, nil
}

// StartCleanup runs Cleanup every hour until ctx ends.
func (s *Service) StartCleanup(ctx context.Context) {
	go func() {
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			if n, err := s.Cleanup(ctx); err != nil {
				log.Printf("files cleanup: %v", err)
			} else if n > 0 {
				log.Printf("files cleanup: removed %d stored files", n)
			}
			select {
			case <-ctx.Done():
				return
			case <-t.C:
			}
		}
	}()
}
