package kb

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/dslipak/pdf"
)

// ExtractText returns the plain text of a .txt, .md, .docx or .pdf file.
func ExtractText(name string, data []byte) (text string, err error) {
	// PDF parsers panic on some malformed files; that must never take the server down.
	defer func() {
		if r := recover(); r != nil {
			text, err = "", fmt.Errorf("could not read this file (%v)", r)
		}
	}()

	switch strings.ToLower(filepath.Ext(name)) {
	case ".txt", ".md":
		if !utf8.Valid(data) {
			return "", fmt.Errorf("the text file is not valid UTF-8")
		}
		return string(data), nil
	case ".docx":
		return docxText(data)
	case ".pdf":
		return pdfText(data)
	default:
		return "", fmt.Errorf("unsupported file type: use .pdf, .docx, .txt or .md")
	}
}

func pdfText(data []byte) (string, error) {
	r, err := pdf.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return "", fmt.Errorf("could not read the PDF: %w", err)
	}
	rd, err := r.GetPlainText()
	if err != nil {
		return "", fmt.Errorf("could not read the PDF text: %w", err)
	}
	b, err := io.ReadAll(io.LimitReader(rd, 50<<20))
	if err != nil {
		return "", fmt.Errorf("could not read the PDF text: %w", err)
	}
	return string(b), nil
}

// docxText reads word/document.xml and joins the text runs, one line per paragraph.
func docxText(data []byte) (string, error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return "", fmt.Errorf("could not read the Word file: %w", err)
	}
	for _, f := range zr.File {
		if f.Name != "word/document.xml" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		defer rc.Close()

		var b strings.Builder
		dec := xml.NewDecoder(io.LimitReader(rc, 100<<20))
		inText := false
		for {
			tok, err := dec.Token()
			if err == io.EOF {
				break
			}
			if err != nil {
				return "", fmt.Errorf("could not read the Word file: %w", err)
			}
			switch t := tok.(type) {
			case xml.StartElement:
				switch t.Name.Local {
				case "t":
					inText = true
				case "tab":
					b.WriteByte(' ')
				case "br":
					b.WriteByte('\n')
				}
			case xml.EndElement:
				switch t.Name.Local {
				case "t":
					inText = false
				case "p":
					b.WriteByte('\n')
				}
			case xml.CharData:
				if inText {
					b.Write(t)
				}
			}
		}
		return b.String(), nil
	}
	return "", fmt.Errorf("this does not look like a Word (.docx) file")
}
