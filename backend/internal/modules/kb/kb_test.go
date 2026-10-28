package kb

import (
	"archive/zip"
	"bytes"
	"fmt"
	"math"
	"strings"
	"testing"
)

func words(n int, prefix string) string {
	w := make([]string, n)
	for i := range w {
		w[i] = fmt.Sprintf("%s%d", prefix, i)
	}
	return strings.Join(w, " ")
}

func TestChunkShortTextIsOnePassage(t *testing.T) {
	got := Chunk("hello   world\n\nsecond paragraph", 300, 40)
	if len(got) != 1 || got[0] != "hello world second paragraph" {
		t.Fatalf("got %q", got)
	}
}

func TestChunkEmpty(t *testing.T) {
	if got := Chunk("  \n \r\n ", 300, 40); got != nil {
		t.Fatalf("want nil, got %q", got)
	}
}

func TestChunkOverlapAndCoverage(t *testing.T) {
	text := words(1000, "w")
	chunks := Chunk(text, 300, 40)
	if len(chunks) < 4 {
		t.Fatalf("expected at least 4 passages, got %d", len(chunks))
	}
	// Every word must appear in some passage, and neighbours must share the overlap.
	joined := strings.Join(chunks, " ")
	for _, w := range []string{"w0", "w299", "w300", "w999"} {
		if !strings.Contains(joined, w+" ") && !strings.HasSuffix(joined, w) {
			t.Fatalf("word %s was lost", w)
		}
	}
	first := strings.Fields(chunks[0])
	second := strings.Fields(chunks[1])
	if first[len(first)-1] == second[0] {
		t.Fatalf("passages should overlap, not just touch")
	}
	for i, c := range chunks {
		if n := len(strings.Fields(c)); n > 300 {
			t.Fatalf("passage %d has %d words (max 300)", i, n)
		}
	}
}

func TestChunkPrefersParagraphBreaks(t *testing.T) {
	text := words(270, "a") + "\n\n" + words(200, "b")
	chunks := Chunk(text, 300, 0)
	if len(chunks) != 2 {
		t.Fatalf("want 2 passages, got %d", len(chunks))
	}
	if strings.Contains(chunks[0], "b0") {
		t.Fatalf("first passage should end at the paragraph break, got tail %q", chunks[0][len(chunks[0])-20:])
	}
}

func TestExtractPlainText(t *testing.T) {
	got, err := ExtractText("notes.TXT", []byte("Unit 1: Arrays"))
	if err != nil || got != "Unit 1: Arrays" {
		t.Fatalf("got %q, %v", got, err)
	}
	if _, err := ExtractText("notes.txt", []byte{0xff, 0xfe, 0xfd}); err == nil {
		t.Fatal("invalid UTF-8 should be rejected")
	}
	if _, err := ExtractText("data.xlsx", []byte("x")); err == nil {
		t.Fatal("unsupported type should be rejected")
	}
}

func docx(t *testing.T, body string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprint(w, `<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>`+body+`</w:body></w:document>`)
	zw.Close()
	return buf.Bytes()
}

func TestExtractDocx(t *testing.T) {
	data := docx(t, `<w:p><w:r><w:t>Data</w:t></w:r><w:r><w:t xml:space="preserve"> Structures</w:t></w:r></w:p><w:p><w:r><w:t>Unit 2</w:t></w:r></w:p>`)
	got, err := ExtractText("syllabus.docx", data)
	if err != nil {
		t.Fatal(err)
	}
	if got != "Data Structures\nUnit 2\n" {
		t.Fatalf("got %q", got)
	}
}

func TestExtractBrokenFilesDoNotPanic(t *testing.T) {
	for _, name := range []string{"a.pdf", "a.docx"} {
		if _, err := ExtractText(name, []byte("this is not a real file")); err == nil {
			t.Fatalf("%s: expected an error", name)
		}
	}
}

func TestCosine(t *testing.T) {
	cases := []struct {
		a, b []float32
		want float64
	}{
		{[]float32{1, 0}, []float32{1, 0}, 1},
		{[]float32{1, 0}, []float32{0, 1}, 0},
		{[]float32{1, 0}, []float32{-1, 0}, -1},
		{[]float32{1, 1}, []float32{2, 2}, 1},
		{[]float32{1, 2}, []float32{1}, 0},    // length mismatch
		{[]float32{0, 0}, []float32{1, 1}, 0}, // zero vector
		{nil, nil, 0},
	}
	for _, c := range cases {
		if got := Cosine(c.a, c.b); math.Abs(got-c.want) > 1e-9 {
			t.Errorf("Cosine(%v, %v) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}
