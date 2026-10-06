// Package files stores uploaded files and hands out signed, expiring links to them.
//
// Flow: a client uploads with POST /files (category decides the allowed types and size), gets a
// file id back, and passes that id to the record it belongs to (profile photo, resume, document…).
// The record's module calls Attach inside its transaction. Reading is done through signed links:
// any API that is allowed to return the record returns a Link, which serialises to a URL that is
// valid for about an hour. GET /files/:uuid only checks the signature, so <img> tags and mobile
// downloads work without an Authorization header.
package files

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
)

// ---- categories ----

type Rule struct {
	Types    []string // allowed sniffed content types
	MaxBytes int64
	Label    string
}

var (
	images    = []string{"image/jpeg", "image/png", "image/webp"}
	pdf       = []string{"application/pdf"}
	pdfImages = append(append([]string{}, pdf...), images...)
)

var Rules = map[string]Rule{
	"profile_photo":           {images, 2 << 20, "a JPG, PNG or WebP image up to 2 MB"},
	"company_logo":            {images, 1 << 20, "a JPG, PNG or WebP image up to 1 MB"},
	"resume":                  {pdf, 5 << 20, "a PDF up to 5 MB"},
	"offer_letter":            {pdfImages, 5 << 20, "a PDF or image up to 5 MB"},
	"job_description":         {pdf, 5 << 20, "a PDF up to 5 MB"},
	"certificate":             {pdfImages, 5 << 20, "a PDF or image up to 5 MB"},
	"student_document":        {pdfImages, 5 << 20, "a PDF or image up to 5 MB"},
	"notification_attachment": {pdfImages, 10 << 20, "a PDF or image up to 10 MB"},
}

var extFor = map[string]string{"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf"}

// ---- links ----

var signKey []byte // set by Init; links cannot be produced before that

// Link is a file reference as read from SQL (file_json(...)) and written to JSON as a signed URL.
type Link struct {
	UUID string `json:"uuid"`
	Name string `json:"name"`
	Type string `json:"type"`
	Size int64  `json:"size"`
}

// URL is relative to the API root (e.g. /files/<uuid>?exp=…&sig=…); clients prefix their API base URL.
func (l Link) URL() string { return SignedPath(l.UUID) }

func (l Link) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		URL  string `json:"url"`
		Name string `json:"name"`
		Type string `json:"type"`
		Size int64  `json:"size"`
	}{l.URL(), l.Name, l.Type, l.Size})
}

// UnmarshalJSON accepts the file_json() shape.
func (l *Link) UnmarshalJSON(b []byte) error {
	type raw Link
	return json.Unmarshal(b, (*raw)(l))
}

// Links stay stable for a whole hour (good for caching) and remain valid for 1–2 hours.
func expiry(now time.Time) int64 { return (now.Unix()/3600 + 2) * 3600 }

func sign(uuid string, exp int64) string {
	m := hmac.New(sha256.New, signKey)
	fmt.Fprintf(m, "%s.%d", uuid, exp)
	return base64.RawURLEncoding.EncodeToString(m.Sum(nil))[:32]
}

func SignedPath(uuid string) string {
	exp := expiry(time.Now())
	return fmt.Sprintf("/files/%s?exp=%d&sig=%s", uuid, exp, sign(uuid, exp))
}

func verify(uuid string, exp int64, sig string, now time.Time) bool {
	if exp < now.Unix() {
		return false
	}
	return hmac.Equal([]byte(sign(uuid, exp)), []byte(sig))
}

// ---- service ----

type Service struct {
	db    *pgxpool.Pool
	store Store
}

// Init wires the signing key (derived from the app secret) and returns the service.
func Init(db *pgxpool.Pool, store Store, secret string) *Service {
	m := hmac.New(sha256.New, []byte(secret))
	m.Write([]byte("file-links"))
	signKey = m.Sum(nil)
	return &Service{db: db, store: store}
}

// Info is what an upload returns.
type Info struct {
	ID       int64  `json:"id"`
	Category string `json:"category"`
	Link
}

func (i Info) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		ID       int64  `json:"id"`
		Category string `json:"category"`
		URL      string `json:"url"`
		Name     string `json:"name"`
		Type     string `json:"type"`
		Size     int64  `json:"size"`
	}{i.ID, i.Category, i.URL(), i.Name, i.Type, i.Size})
}

// Upload validates the file by its real content, stores it and records it as not yet attached.
func (s *Service) Upload(ctx context.Context, actorID int64, category string, fh *multipart.FileHeader) (*Info, error) {
	rule, ok := Rules[category]
	if !ok {
		return nil, response.BadRequest("Unknown file category")
	}
	if fh.Size <= 0 {
		return nil, response.BadRequest("The file is empty")
	}
	if fh.Size > rule.MaxBytes {
		return nil, response.BadRequest("Upload " + rule.Label)
	}
	src, err := fh.Open()
	if err != nil {
		return nil, err
	}
	defer src.Close()
	data, err := io.ReadAll(io.LimitReader(src, rule.MaxBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > rule.MaxBytes {
		return nil, response.BadRequest("Upload " + rule.Label)
	}
	ctype := http.DetectContentType(data)
	if i := strings.Index(ctype, ";"); i > 0 {
		ctype = ctype[:i]
	}
	if !contains(rule.Types, ctype) {
		return nil, response.BadRequest("This file type is not allowed here. Upload " + rule.Label)
	}
	sum := sha256.Sum256(data)
	name := cleanName(fh.Filename, extFor[ctype])

	var info Info
	info.Category, info.Name, info.Type, info.Size = category, name, ctype, int64(len(data))
	err = s.db.QueryRow(ctx, `INSERT INTO files (category, original_name, content_type, size_bytes, sha256, storage_key, created_by, updated_by)
		VALUES ($1, $2, $3, $4, $5, '', $6, $6) RETURNING id, uuid::text`,
		category, name, ctype, info.Size, hex.EncodeToString(sum[:]), actorID).Scan(&info.ID, &info.UUID)
	if err != nil {
		return nil, err
	}
	key := path.Join(time.Now().Format("2006/01"), info.UUID+extFor[ctype])
	if err := s.store.Put(key, bytes.NewReader(data)); err != nil {
		_, _ = s.db.Exec(ctx, `DELETE FROM files WHERE id = $1`, info.ID)
		return nil, err
	}
	if _, err := s.db.Exec(ctx, `UPDATE files SET storage_key = $2 WHERE id = $1`, info.ID, key); err != nil {
		return nil, err
	}
	return &info, nil
}

// Attach links an uploaded file to a record. The file must be the actor's own upload, of the
// expected category, and not attached anywhere else. Pass the caller's transaction as q.
func Attach(ctx context.Context, q dbutil.DBTX, fileID, actorID int64, category, refType string, refID int64) error {
	var cat string
	var owner *int64
	var curType *string
	var curID *int64
	err := q.QueryRow(ctx, `SELECT category, created_by, ref_type, ref_id FROM files WHERE id = $1 AND is_active FOR UPDATE`, fileID).
		Scan(&cat, &owner, &curType, &curID)
	if dbutil.IsNoRows(err) {
		return response.BadRequest("file_id does not exist")
	}
	if err != nil {
		return err
	}
	if cat != category {
		return response.BadRequest(fmt.Sprintf("This file was uploaded as %s, not %s", strings.ReplaceAll(cat, "_", " "), strings.ReplaceAll(category, "_", " ")))
	}
	if curType != nil && (*curType != refType || curID == nil || *curID != refID) {
		return response.BadRequest("This file is already attached to something else")
	}
	if curType == nil && (owner == nil || *owner != actorID) {
		return response.Forbidden("You can only attach files you uploaded")
	}
	_, err = q.Exec(ctx, `UPDATE files SET ref_type = $2, ref_id = $3, updated_by = $4 WHERE id = $1`, fileID, refType, refID, actorID)
	return err
}

// Release marks a file as no longer used (it is removed from disk by the cleanup job).
func Release(ctx context.Context, q dbutil.DBTX, fileID *int64, actorID int64) error {
	if fileID == nil {
		return nil
	}
	_, err := q.Exec(ctx, `UPDATE files SET is_active = false, updated_by = $2 WHERE id = $1 AND is_active`, *fileID, actorID)
	return err
}

// Swap attaches newID (if any) and releases oldID when it changed. Used for single-file slots.
func Swap(ctx context.Context, q dbutil.DBTX, oldID, newID *int64, actorID int64, category, refType string, refID int64) error {
	if newID != nil && oldID != nil && *newID == *oldID {
		return nil
	}
	if newID != nil {
		if err := Attach(ctx, q, *newID, actorID, category, refType, refID); err != nil {
			return err
		}
	}
	return Release(ctx, q, oldID, actorID)
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// cleanName keeps a readable, header-safe original name with the right extension.
func cleanName(name, ext string) string {
	// Browsers send a double quote in a file name as %22.
	name = path.Base(strings.ReplaceAll(strings.ReplaceAll(name, `\`, "/"), "%22", ""))
	name = strings.Map(func(r rune) rune {
		if r < 32 || r == '"' || r == '/' || r == '\\' || r == 127 {
			return -1
		}
		return r
	}, name)
	name = strings.TrimSpace(name)
	base := strings.TrimSuffix(name, path.Ext(name))
	if base == "" || base == "." {
		base = "file"
	}
	if len(base) > 120 {
		base = base[:120]
	}
	return base + ext
}
