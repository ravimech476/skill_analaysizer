package sms

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// post sends a request and turns a non-2xx answer into an error with a short body excerpt.
func post(ctx context.Context, client *http.Client, req *http.Request, provider, to string) ([]byte, error) {
	req = req.WithContext(ctx)
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", provider, err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode < 200 || res.StatusCode > 299 {
		slog.Warn("sms failed", "provider", provider, "to", mask(to), "status", res.StatusCode, "body", string(body))
		return body, fmt.Errorf("%s: HTTP %d", provider, res.StatusCode)
	}
	slog.Info("sms sent", "provider", provider, "to", mask(to))
	return body, nil
}

// ---- MSG91 (India, DLT) ----

// MSG91 uses the Flow API: the DLT-approved template holds the wording and ##otp## / ##minutes##.
type MSG91 struct {
	client        *http.Client
	base, authKey string
	template, cc  string
}

func (p *MSG91) Send(ctx context.Context, m Message) error {
	to := international(m.To, p.cc)
	payload, _ := json.Marshal(map[string]any{
		"template_id": p.template,
		"short_url":   "0",
		"recipients":  []map[string]string{{"mobiles": to, "otp": m.OTP, "minutes": strconv.Itoa(m.Minutes)}},
	})
	req, err := http.NewRequest(http.MethodPost, p.base+"/api/v5/flow", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("authkey", p.authKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	body, err := post(ctx, p.client, req, "msg91", to)
	if err != nil {
		return err
	}
	// MSG91 can answer 200 with {"type":"error"}.
	var r struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	}
	if json.Unmarshal(body, &r) == nil && strings.EqualFold(r.Type, "error") {
		return fmt.Errorf("msg91: %s", r.Message)
	}
	return nil
}

// ---- Twilio ----

type Twilio struct {
	client                 *http.Client
	base, sid, token, from string
	cc                     string
}

func (p *Twilio) Send(ctx context.Context, m Message) error {
	to := "+" + international(m.To, p.cc)
	form := url.Values{"To": {to}, "Body": {m.Text}}
	if strings.HasPrefix(p.from, "MG") {
		form.Set("MessagingServiceSid", p.from)
	} else {
		form.Set("From", p.from)
	}
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/2010-04-01/Accounts/%s/Messages.json", p.base, url.PathEscape(p.sid)),
		strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.SetBasicAuth(p.sid, p.token)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	_, err = post(ctx, p.client, req, "twilio", to)
	return err
}

// ---- Webhook ----

// Webhook POSTs {"to","message","otp","minutes"} to your own endpoint, which relays it to any gateway.
type Webhook struct {
	client         *http.Client
	url, token, cc string
}

func (p *Webhook) Send(ctx context.Context, m Message) error {
	to := international(m.To, p.cc)
	payload, _ := json.Marshal(map[string]any{"to": to, "message": m.Text, "otp": m.OTP, "minutes": m.Minutes})
	req, err := http.NewRequest(http.MethodPost, p.url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if p.token != "" {
		req.Header.Set("Authorization", "Bearer "+p.token)
	}
	_, err = post(ctx, p.client, req, "webhook", to)
	return err
}
