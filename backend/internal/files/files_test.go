package files

import (
	"bytes"
	"encoding/json"
	"io"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
)

func init() { signKey = []byte("test-key-test-key-test-key-12345") }

func TestSignedPathVerifies(t *testing.T) {
	p := SignedPath("abc")
	u, err := url.Parse(p)
	if err != nil {
		t.Fatal(err)
	}
	exp, err := strconv.ParseInt(u.Query().Get("exp"), 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if !verify("abc", exp, u.Query().Get("sig"), now) {
		t.Fatal("fresh link should verify")
	}
	if verify("abd", exp, u.Query().Get("sig"), now) {
		t.Fatal("signature must be bound to the uuid")
	}
	if verify("abc", exp+3600, u.Query().Get("sig"), now) {
		t.Fatal("signature must be bound to the expiry")
	}
	if verify("abc", exp, u.Query().Get("sig"), time.Unix(exp+1, 0)) {
		t.Fatal("expired link must not verify")
	}
	if exp-now.Unix() < 3600 || exp-now.Unix() > 7200 {
		t.Fatalf("link should live 1-2 hours, got %ds", exp-now.Unix())
	}
}

func TestLinkJSON(t *testing.T) {
	var l *Link
	if err := json.Unmarshal([]byte(`{"uuid":"u1","name":"a.pdf","type":"application/pdf","size":10}`), &l); err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(l)
	if !strings.Contains(string(b), `"url":"/files/u1?exp=`) || strings.Contains(string(b), `"uuid"`) {
		t.Fatalf("unexpected json %s", b)
	}
}

func TestCleanName(t *testing.T) {
	cases := map[string]string{
		`C:\fakepath\My "CV".PDF`: "My CV.pdf",
		"../../etc/passwd":        "passwd.pdf",
		"":                        "file.pdf",
		"photo.jpeg":              "photo.pdf",
	}
	for in, want := range cases {
		if got := cleanName(in, ".pdf"); got != want {
			t.Errorf("cleanName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestLocalStoreRejectsEscapes(t *testing.T) {
	s, err := NewLocalStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"", "../x", "a/../../x"} {
		if err := s.Put(key, bytes.NewReader([]byte("x"))); err == nil {
			t.Errorf("Put(%q) should fail", key)
		}
	}
	if err := s.Put("2026/09/ok.pdf", bytes.NewReader([]byte("hello"))); err != nil {
		t.Fatal(err)
	}
	f, err := s.Open("2026/09/ok.pdf")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(f)
	f.Close()
	if string(b) != "hello" {
		t.Fatalf("got %q", b)
	}
	if err := s.Delete("2026/09/ok.pdf"); err != nil {
		t.Fatal(err)
	}
	if err := s.Delete("2026/09/ok.pdf"); err != nil {
		t.Fatal("deleting a missing file should be a no-op")
	}
}
