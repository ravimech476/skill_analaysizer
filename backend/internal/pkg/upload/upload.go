// Package upload holds what every Excel import shares: reading the posted file, parsing the
// first sheet into header-addressed rows, and recording the run in bulk_upload_jobs.
package upload

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/xuri/excelize/v2"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
)

const (
	MaxFileBytes = 5 << 20
	MaxRows      = 5000
)

// File reads the .xlsx posted as form field "file".
func File(c *gin.Context) (name string, data []byte, err error) {
	fh, err := c.FormFile("file")
	if err != nil {
		return "", nil, response.BadRequest("Attach the Excel file as form field 'file'")
	}
	if fh.Size > MaxFileBytes {
		return "", nil, response.BadRequest("File is larger than 5 MB")
	}
	if !strings.HasSuffix(strings.ToLower(fh.Filename), ".xlsx") {
		return "", nil, response.BadRequest("Only .xlsx files are supported")
	}
	src, err := fh.Open()
	if err != nil {
		return "", nil, err
	}
	defer src.Close()
	data, err = io.ReadAll(io.LimitReader(src, MaxFileBytes+1))
	return fh.Filename, data, err
}

// Table is the first sheet of a workbook: a header row plus data rows.
type Table struct {
	header map[string]int
	Data   [][]string
	First  int               // spreadsheet row number of Data[0]
	Info   map[string]string // key/value pairs from an optional "Info" sheet (column A → B)
}

// NormHeader turns "Register No*" into "register_no".
func NormHeader(s string) string {
	s = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(s), "*")))
	return strings.NewReplacer(" ", "_", "-", "_").Replace(s)
}

// Parse reads the first sheet; every name in required must appear in the header row.
func Parse(data []byte, required []string) (*Table, error) {
	f, err := excelize.OpenReader(bytes.NewReader(data))
	if err != nil {
		return nil, response.BadRequest("Could not read the Excel file")
	}
	defer f.Close()
	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return nil, response.BadRequest("The workbook has no sheets")
	}
	// RawCellValue keeps mobiles as digits and dates as serial numbers.
	all, err := f.GetRows(sheets[0], excelize.Options{RawCellValue: true})
	if err != nil {
		return nil, response.BadRequest("Could not read the first sheet")
	}
	if len(all) < 2 {
		return nil, response.BadRequest("The sheet has no data rows")
	}
	t := &Table{header: map[string]int{}, First: 2, Info: map[string]string{}}
	for i, h := range all[0] {
		if n := NormHeader(h); n != "" {
			t.header[n] = i
		}
	}
	var missing []string
	for _, col := range required {
		if _, ok := t.header[NormHeader(col)]; !ok {
			missing = append(missing, NormHeader(col))
		}
	}
	if len(missing) > 0 {
		return nil, response.BadRequest("Missing required columns: " + strings.Join(missing, ", ") + ". Download the template for the expected format.")
	}
	t.Data = all[1:]
	// Drop trailing blank rows (Excel often reports formatted-but-empty rows).
	for len(t.Data) > 0 && IsBlank(t.Data[len(t.Data)-1]) {
		t.Data = t.Data[:len(t.Data)-1]
	}
	if len(t.Data) > MaxRows {
		return nil, response.BadRequest(fmt.Sprintf("At most %d rows per upload", MaxRows))
	}
	if info, err := f.GetRows("Info", excelize.Options{RawCellValue: true}); err == nil {
		for _, r := range info {
			if len(r) >= 2 && strings.TrimSpace(r[0]) != "" {
				t.Info[NormHeader(r[0])] = strings.TrimSpace(r[1])
			}
		}
	}
	return t, nil
}

func IsBlank(r []string) bool {
	for _, v := range r {
		if strings.TrimSpace(v) != "" {
			return false
		}
	}
	return true
}

// Has reports whether the sheet has the column.
func (t *Table) Has(col string) bool {
	_, ok := t.header[col]
	return ok
}

// Get returns a trimmed cell by column name ("" when the column or cell is absent).
func (t *Table) Get(r []string, col string) string {
	i, ok := t.header[col]
	if !ok || i >= len(r) {
		return ""
	}
	v := strings.TrimSpace(r[i])
	// Numbers typed into Excel can come back as "9000000001.0" or "9.000000001E9".
	if f, err := strconv.ParseFloat(v, 64); err == nil && strings.ContainsAny(v, ".eE") && f == float64(int64(f)) {
		return strconv.FormatInt(int64(f), 10)
	}
	return v
}

// ---- jobs ----

type RowError struct {
	Row        int    `json:"row"`
	RegisterNo string `json:"register_no"` // register no / employee code identifying the row
	Name       string `json:"name"`
	Message    string `json:"message"`
}

type Job struct {
	ID          int64      `json:"id"`
	UploadType  string     `json:"upload_type"`
	FileName    string     `json:"file_name"`
	TotalRows   int        `json:"total_rows"`
	SuccessRows int        `json:"success_rows"`
	FailedRows  int        `json:"failed_rows"`
	Errors      []RowError `json:"errors"`
	Status      string     `json:"status"`
	DryRun      bool       `json:"dry_run"`
	CreatedBy   *string    `json:"created_by_name"`
	CreatedAt   time.Time  `json:"created_at"`
}

// Start records a job in the 'processing' state.
func Start(ctx context.Context, db *pgxpool.Pool, uploadType, fileName string, total int, dryRun bool, actorID int64) (int64, error) {
	var id int64
	err := db.QueryRow(ctx, `INSERT INTO bulk_upload_jobs (upload_type, file_name, total_rows, status, dry_run, created_by, updated_by)
		VALUES ($1, $2, $3, 'processing', $4, $5, $5) RETURNING id`, uploadType, fileName, total, dryRun, actorID).Scan(&id)
	return id, err
}

// Finish stores the outcome and returns the job.
func Finish(ctx context.Context, db *pgxpool.Pool, id int64, success int, errs []RowError, actorID int64) (*Job, error) {
	if errs == nil {
		errs = []RowError{}
	}
	raw, _ := json.Marshal(errs)
	if _, err := db.Exec(ctx, `UPDATE bulk_upload_jobs SET success_rows = $2, failed_rows = $3, errors = $4, status = 'completed', updated_by = $5
		WHERE id = $1`, id, success, len(errs), raw, actorID); err != nil {
		return nil, err
	}
	return Find(ctx, db, id)
}

const SelectJob = `SELECT j.id, j.upload_type, j.file_name, j.total_rows, j.success_rows, j.failed_rows, j.errors,
	j.status, j.dry_run, u.name, j.created_at FROM bulk_upload_jobs j LEFT JOIN users u ON u.id = j.created_by`

func ScanJob(row pgx.Row) (*Job, error) {
	j := &Job{}
	var raw []byte
	if err := row.Scan(&j.ID, &j.UploadType, &j.FileName, &j.TotalRows, &j.SuccessRows, &j.FailedRows, &raw,
		&j.Status, &j.DryRun, &j.CreatedBy, &j.CreatedAt); err != nil {
		return nil, err
	}
	j.Errors = []RowError{}
	_ = json.Unmarshal(raw, &j.Errors)
	return j, nil
}

func Find(ctx context.Context, db *pgxpool.Pool, id int64) (*Job, error) {
	j, err := ScanJob(db.QueryRow(ctx, SelectJob+" WHERE j.id = $1 AND j.is_active", id))
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Upload not found")
	}
	return j, err
}

// RowMessage turns an error into a message fit for the row-error list.
func RowMessage(err error) string {
	var ae *response.AppError
	if errors.As(err, &ae) {
		return ae.Message
	}
	return "Unexpected error: " + err.Error()
}

// ExcelDate accepts an Excel serial number, YYYY-MM-DD, DD-MM-YYYY or DD/MM/YYYY and returns YYYY-MM-DD.
func ExcelDate(s, field string) (*string, error) {
	if s == "" {
		return nil, nil
	}
	if serial, err := strconv.ParseFloat(s, 64); err == nil {
		t, err := excelize.ExcelDateToTime(serial, false)
		if err != nil {
			return nil, fmt.Errorf("%s %q is not a valid date", field, s)
		}
		out := t.Format("2006-01-02")
		return &out, nil
	}
	for _, layout := range []string{"2006-01-02", "02-01-2006", "02/01/2006", "2006/01/02"} {
		if t, err := time.Parse(layout, s); err == nil {
			out := t.Format("2006-01-02")
			return &out, nil
		}
	}
	return nil, fmt.Errorf("%s %q is not a valid date (use YYYY-MM-DD)", field, s)
}
