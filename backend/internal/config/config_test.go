package config

import (
	"strings"
	"testing"

	"skills-analyzer/internal/sms"
)

func safe() *Config {
	return &Config{
		AppEnv:        "production",
		JWTSecret:     strings.Repeat("a1", 32),
		SMS:           sms.Config{Provider: "msg91"},
		AdminPassword: "Str0ng-Passw0rd!",
		CORSOrigins:   []string{"https://college.example.edu"},
	}
}

func TestProductionAcceptsSafeSettings(t *testing.T) {
	if err := safe().checkProduction(); err != nil {
		t.Fatal(err)
	}
}

func TestProductionRefusesUnsafeSettings(t *testing.T) {
	cases := map[string]func(c *Config){
		"OTP_DEBUG":      func(c *Config) { c.OTPDebug = true },
		"JWT_SECRET":     func(c *Config) { c.JWTSecret = "generate-a-random-string-of-at-least-32-chars" },
		"SMS_PROVIDER":   func(c *Config) { c.SMS.Provider = "console" },
		"ADMIN_PASSWORD": func(c *Config) { c.AdminPassword = "CHANGE_ME" },
		"CORS_ORIGINS":   func(c *Config) { c.CORSOrigins = []string{"*"} },
	}
	for want, breakIt := range cases {
		c := safe()
		breakIt(c)
		err := c.checkProduction()
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: expected a complaint, got %v", want, err)
		}
	}
}

func TestSplitList(t *testing.T) {
	got := splitList(" https://a.edu , ,https://b.edu")
	if len(got) != 2 || got[0] != "https://a.edu" || got[1] != "https://b.edu" {
		t.Fatalf("got %v", got)
	}
}
