package kb

import "strings"

const (
	chunkWords   = 300 // roughly a few paragraphs: small enough to be specific, large enough to carry context
	chunkOverlap = 40  // words repeated between neighbours so a sentence cut at the edge is still found
	maxChunks    = 2000
)

// Chunk cuts text into overlapping passages of about size words. It prefers to break at paragraph
// ends, so a passage usually starts and ends on a natural boundary.
func Chunk(text string, size, overlap int) []string {
	if size <= 0 {
		size = chunkWords
	}
	if overlap < 0 || overlap >= size {
		overlap = 0
	}

	// Words keep their paragraph breaks as a marker so we can break there when we get close to size.
	type word struct {
		w     string
		endsP bool
	}
	var words []word
	for _, para := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		fields := strings.Fields(para)
		for i, f := range fields {
			words = append(words, word{f, i == len(fields)-1})
		}
	}
	if len(words) == 0 {
		return nil
	}

	var out []string
	for start := 0; start < len(words); {
		end := start + size
		if end >= len(words) {
			end = len(words)
		} else {
			// Look back (up to a quarter of the passage) for a paragraph end to break on.
			for i := end; i > end-size/4 && i > start+1; i-- {
				if words[i-1].endsP {
					end = i
					break
				}
			}
		}
		parts := make([]string, 0, end-start)
		for _, w := range words[start:end] {
			parts = append(parts, w.w)
		}
		out = append(out, strings.Join(parts, " "))
		if end == len(words) {
			break
		}
		next := end - overlap
		if next <= start {
			next = end
		}
		start = next
	}
	return out
}
