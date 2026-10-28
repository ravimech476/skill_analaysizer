package files

import (
	"archive/zip"
	"bytes"
	"strings"
)

const (
	docxType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
	pptxType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
)

// sniffOffice tells a real Word or PowerPoint file from any other zip. Browsers and Go's sniffer both
// call these "application/zip", which would let any archive through, so the zip's own contents are
// checked and the file name must agree with them. Returns "" when it is neither.
func sniffOffice(name string, data []byte) string {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return ""
	}
	var content, word, slides bool
	for _, f := range zr.File {
		switch f.Name {
		case "[Content_Types].xml":
			content = true
		case "word/document.xml":
			word = true
		case "ppt/presentation.xml":
			slides = true
		}
	}
	lower := strings.ToLower(name)
	switch {
	case content && word && strings.HasSuffix(lower, ".docx"):
		return docxType
	case content && slides && strings.HasSuffix(lower, ".pptx"):
		return pptxType
	}
	return ""
}
