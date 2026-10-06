package sms

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

type captured struct {
	path, auth, ctype string
	body              []byte
	user, pass        string
}

func server(t *testing.T, status int, reply string) (*httptest.Server, *captured) {
	t.Helper()
	c := &captured{}
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c.path, c.ctype = r.URL.Path, r.Header.Get("Content-Type")
		c.auth = r.Header.Get("Authorization")
		if c.auth == "" {
			c.auth = r.Header.Get("authkey")
		}
		c.user, c.pass, _ = r.BasicAuth()
		c.body, _ = io.ReadAll(r.Body)
		w.WriteHeader(status)
		_, _ = w.Write([]byte(reply))
	}))
	t.Cleanup(s.Close)
	return s, c
}

var msg = Message{To: "9876543210", Text: "123456 is your OTP", OTP: "123456", Minutes: 5}

func TestMSG91(t *testing.T) {
	s, c := server(t, 200, `{"type":"success","message":"3763646c3058373530393832"}`)
	p, err := New(Config{Provider: "msg91", MSG91AuthKey: "key1", MSG91Template: "tpl1", MSG91BaseURL: s.URL})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Send(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	var body struct {
		TemplateID string              `json:"template_id"`
		Recipients []map[string]string `json:"recipients"`
	}
	_ = json.Unmarshal(c.body, &body)
	if c.path != "/api/v5/flow" || c.auth != "key1" || body.TemplateID != "tpl1" {
		t.Fatalf("bad request: %s %s %s", c.path, c.auth, c.body)
	}
	if r := body.Recipients[0]; r["mobiles"] != "919876543210" || r["otp"] != "123456" || r["minutes"] != "5" {
		t.Fatalf("bad recipient %v", r)
	}
}

func TestMSG91ErrorIn200(t *testing.T) {
	s, _ := server(t, 200, `{"type":"error","message":"Template not approved"}`)
	p, _ := New(Config{Provider: "msg91", MSG91AuthKey: "k", MSG91Template: "t", MSG91BaseURL: s.URL})
	if err := p.Send(context.Background(), msg); err == nil || !strings.Contains(err.Error(), "Template not approved") {
		t.Fatalf("want template error, got %v", err)
	}
}

func TestTwilio(t *testing.T) {
	s, c := server(t, 201, `{"sid":"SM1"}`)
	p, err := New(Config{Provider: "twilio", TwilioSID: "AC1", TwilioToken: "tok", TwilioFrom: "+15550001111", TwilioBaseURL: s.URL})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Send(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	form, _ := url.ParseQuery(string(c.body))
	if c.path != "/2010-04-01/Accounts/AC1/Messages.json" || c.user != "AC1" || c.pass != "tok" {
		t.Fatalf("bad request %s %s", c.path, c.user)
	}
	if form.Get("To") != "+919876543210" || form.Get("From") != "+15550001111" || form.Get("Body") != msg.Text {
		t.Fatalf("bad form %v", form)
	}
}

func TestTwilioMessagingService(t *testing.T) {
	s, c := server(t, 201, `{}`)
	p, _ := New(Config{Provider: "twilio", TwilioSID: "AC1", TwilioToken: "t", TwilioFrom: "MG123", TwilioBaseURL: s.URL})
	_ = p.Send(context.Background(), msg)
	form, _ := url.ParseQuery(string(c.body))
	if form.Get("MessagingServiceSid") != "MG123" || form.Get("From") != "" {
		t.Fatalf("bad form %v", form)
	}
}

func TestWebhookAndHTTPErrors(t *testing.T) {
	s, c := server(t, 200, `ok`)
	p, _ := New(Config{Provider: "webhook", WebhookURL: s.URL + "/sms", WebhookToken: "secret"})
	if err := p.Send(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	var body map[string]any
	_ = json.Unmarshal(c.body, &body)
	if c.auth != "Bearer secret" || body["to"] != "919876543210" || body["otp"] != "123456" {
		t.Fatalf("bad webhook call %s %v", c.auth, body)
	}
	bad, _ := server(t, 500, `boom`)
	p, _ = New(Config{Provider: "webhook", WebhookURL: bad.URL})
	if err := p.Send(context.Background(), msg); err == nil {
		t.Fatal("HTTP 500 must be an error")
	}
}

func TestConfigValidation(t *testing.T) {
	for _, c := range []Config{{Provider: "msg91"}, {Provider: "twilio", TwilioSID: "x"}, {Provider: "webhook"}, {Provider: "carrier-pigeon"}} {
		if _, err := New(c); err == nil {
			t.Errorf("%s: missing settings should fail", c.Provider)
		}
	}
	s, _ := New(Config{})
	if !IsConsole(s) {
		t.Fatal("default provider should be console")
	}
}

func TestInternational(t *testing.T) {
	cases := map[string]string{"9876543210": "919876543210", "+919876543210": "919876543210", "447700900123": "447700900123"}
	for in, want := range cases {
		if got := international(in, "91"); got != want {
			t.Errorf("%s: got %s want %s", in, got, want)
		}
	}
}
