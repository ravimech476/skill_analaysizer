// Package sms delivers OTP messages. The provider is chosen with SMS_PROVIDER:
//
//	console  logs the message (development only; refused when APP_ENV=production)
//	msg91    MSG91 Flow API with a DLT-approved OTP template (India)
//	twilio   Twilio Programmable Messaging
//	webhook  POSTs JSON to your own endpoint (any other gateway)
//
// Every provider gets the ready-made text and the bare OTP, because Indian DLT templates
// substitute variables instead of sending free text.
package sms

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

type Message struct {
	To      string // 10-digit Indian mobile or an E.164 number
	Text    string // full message, for providers that send free text
	OTP     string // the code itself, for template-based providers
	Minutes int    // validity, for templates that mention it
}

type Sender interface {
	Send(ctx context.Context, m Message) error
}

// Config holds every provider's settings; only the chosen provider's fields are needed.
type Config struct {
	Provider       string
	CountryCode    string // prepended to 10-digit numbers, default 91
	MSG91AuthKey   string
	MSG91Template  string // Flow template id (DLT approved); variables: otp, minutes
	MSG91BaseURL   string // override for tests
	TwilioSID      string
	TwilioToken    string
	TwilioFrom     string // sender number or Messaging Service SID (MG…)
	TwilioBaseURL  string // override for tests
	WebhookURL     string
	WebhookToken   string // sent as Authorization: Bearer <token>
	RequestTimeout time.Duration
}

// New builds the configured sender.
func New(c Config) (Sender, error) {
	if c.CountryCode == "" {
		c.CountryCode = "91"
	}
	if c.RequestTimeout == 0 {
		c.RequestTimeout = 10 * time.Second
	}
	client := &http.Client{Timeout: c.RequestTimeout}
	switch strings.ToLower(c.Provider) {
	case "", "console":
		return ConsoleSender{}, nil
	case "msg91":
		if c.MSG91AuthKey == "" || c.MSG91Template == "" {
			return nil, fmt.Errorf("SMS_PROVIDER=msg91 needs MSG91_AUTH_KEY and MSG91_TEMPLATE_ID")
		}
		base := c.MSG91BaseURL
		if base == "" {
			base = "https://control.msg91.com"
		}
		return &MSG91{client: client, base: base, authKey: c.MSG91AuthKey, template: c.MSG91Template, cc: c.CountryCode}, nil
	case "twilio":
		if c.TwilioSID == "" || c.TwilioToken == "" || c.TwilioFrom == "" {
			return nil, fmt.Errorf("SMS_PROVIDER=twilio needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM")
		}
		base := c.TwilioBaseURL
		if base == "" {
			base = "https://api.twilio.com"
		}
		return &Twilio{client: client, base: base, sid: c.TwilioSID, token: c.TwilioToken, from: c.TwilioFrom, cc: c.CountryCode}, nil
	case "webhook":
		if c.WebhookURL == "" {
			return nil, fmt.Errorf("SMS_PROVIDER=webhook needs SMS_WEBHOOK_URL")
		}
		return &Webhook{client: client, url: c.WebhookURL, token: c.WebhookToken, cc: c.CountryCode}, nil
	}
	return nil, fmt.Errorf("unknown SMS_PROVIDER %q (use console, msg91, twilio or webhook)", c.Provider)
}

// IsConsole reports whether s only logs messages.
func IsConsole(s Sender) bool {
	_, ok := s.(ConsoleSender)
	return ok
}

// ConsoleSender logs the message instead of sending it. Development only.
type ConsoleSender struct{}

func (ConsoleSender) Send(_ context.Context, m Message) error {
	slog.Info("SMS (console)", "to", m.To, "message", m.Text)
	return nil
}

// international turns a local 10-digit number into country code + number (no '+').
func international(mobile, cc string) string {
	d := strings.TrimPrefix(strings.TrimSpace(mobile), "+")
	if len(d) == 10 {
		return cc + d
	}
	return d
}

// mask hides most of a number for logs.
func mask(n string) string {
	if len(n) <= 4 {
		return "****"
	}
	return strings.Repeat("*", len(n)-4) + n[len(n)-4:]
}
