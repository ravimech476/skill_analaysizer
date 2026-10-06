// Package xlsxutil builds simple styled Excel workbooks and sends them as downloads.
package xlsxutil

import (
	"bytes"
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

type Book struct {
	f      *excelize.File
	header int
	first  bool
}

func New() *Book {
	f := excelize.NewFile()
	header, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"#E8F0FF"}, Pattern: 1},
	})
	return &Book{f: f, header: header, first: true}
}

// Sheet adds a sheet with an optional title block, a bold header row and data rows.
// Column widths follow the longest value (capped).
func (b *Book) Sheet(name string, title []string, headers []string, rows [][]any) {
	if b.first {
		b.f.SetSheetName("Sheet1", name)
		b.first = false
	} else {
		_, _ = b.f.NewSheet(name)
	}
	r := 1
	for _, t := range title {
		_ = b.f.SetCellStr(name, fmt.Sprintf("A%d", r), t)
		r++
	}
	if len(title) > 0 {
		r++
	}
	headerRow := r
	for i, h := range headers {
		cell, _ := excelize.CoordinatesToCellName(i+1, r)
		_ = b.f.SetCellStr(name, cell, h)
	}
	if len(headers) > 0 {
		last, _ := excelize.CoordinatesToCellName(len(headers), r)
		_ = b.f.SetCellStyle(name, fmt.Sprintf("A%d", r), last, b.header)
		r++
	}
	widths := make([]int, len(headers))
	for i, h := range headers {
		widths[i] = len(h)
	}
	for _, row := range rows {
		for i, v := range row {
			cell, _ := excelize.CoordinatesToCellName(i+1, r)
			switch x := v.(type) {
			case nil:
			case string:
				_ = b.f.SetCellStr(name, cell, x) // text keeps register numbers / mobiles intact
			default:
				_ = b.f.SetCellValue(name, cell, x)
			}
			if i < len(widths) {
				if l := len(fmt.Sprint(v)); l > widths[i] {
					widths[i] = l
				}
			}
		}
		r++
	}
	for i, w := range widths {
		col, _ := excelize.ColumnNumberToName(i + 1)
		_ = b.f.SetColWidth(name, col, col, float64(min(max(w+2, 8), 60)))
	}
	if len(headers) > 0 {
		_ = b.f.SetPanes(name, &excelize.Panes{Freeze: true, YSplit: headerRow, TopLeftCell: fmt.Sprintf("A%d", headerRow+1), ActivePane: "bottomLeft"})
	}
}

// Send writes the workbook as an attachment.
func (b *Book) Send(c *gin.Context, filename string) {
	defer b.f.Close()
	b.f.SetActiveSheet(0)
	var buf bytes.Buffer
	if err := b.f.Write(&buf); err != nil {
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, SafeName(filename)))
	c.Data(http.StatusOK, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())
}

// SafeName keeps file names to letters, digits, dot, dash and underscore.
func SafeName(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '-', r == '_':
			return r
		case r == ' ':
			return '_'
		}
		return -1
	}, s)
}
