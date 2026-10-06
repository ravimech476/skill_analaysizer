package config

import (
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"

	"skills-analyzer/internal/sms"
)

type Config struct {
	AppEnv      string
	Port        string
	DatabaseURL string
	AutoMigrate bool

	JWTSecret       string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration

	OTPTTL         time.Duration
	OTPMaxAttempts int
	OTPResendAfter time.Duration
	// OTPDebug returns the OTP in the API response (dev only, never in production).
	OTPDebug bool

	CORSOrigins []string

	// Mobile push through Expo. Off by default so development never calls an outside service.
	PushEnabled bool
	ExpoPushURL string

	// Uploaded files are kept under FilesDir on local disk.
	FilesDir string

	// OTP delivery (see package sms).
	SMS sms.Config

	// TrustedProxies are the reverse proxies whose X-Forwarded-For is believed (empty = none).
	TrustedProxies []string
	// Requests per minute per client IP: all API calls, and the sign-in / OTP endpoints.
	RateLimitPerMinute     int
	AuthRateLimitPerMinute int
	// LogFormat is text or json (default json in production).
	LogFormat string

	AdminUsername string
	AdminPassword string
	AdminName     string
	AdminMobile   string
}

func Load() (*Config, error) {
	_ = godotenv.Load() // .env is optional; real env vars win

	cfg := &Config{
		AppEnv:          env("APP_ENV", "development"),
		Port:            env("PORT", "8080"),
		DatabaseURL:     env("DATABASE_URL", ""),
		AutoMigrate:     envBool("AUTO_MIGRATE", true),
		JWTSecret:       env("JWT_SECRET", ""),
		AccessTokenTTL:  envDuration("ACCESS_TOKEN_TTL", 15*time.Minute),
		RefreshTokenTTL: envDuration("REFRESH_TOKEN_TTL", 30*24*time.Hour),
		OTPTTL:          envDuration("OTP_TTL", 5*time.Minute),
		OTPMaxAttempts:  envInt("OTP_MAX_ATTEMPTS", 5),
		OTPResendAfter:  envDuration("OTP_RESEND_AFTER", 60*time.Second),
		OTPDebug:        envBool("OTP_DEBUG", false),
		CORSOrigins:     splitList(env("CORS_ORIGINS", "http://localhost:5180")),
		PushEnabled:     envBool("PUSH_ENABLED", false),
		ExpoPushURL:     env("EXPO_PUSH_URL", "https://exp.host/--/api/v2/push/send"),
		FilesDir:        env("FILES_DIR", "storage"),
		SMS: sms.Config{
			Provider:      env("SMS_PROVIDER", "console"),
			CountryCode:   env("SMS_COUNTRY_CODE", "91"),
			MSG91AuthKey:  env("MSG91_AUTH_KEY", ""),
			MSG91Template: env("MSG91_TEMPLATE_ID", ""),
			MSG91BaseURL:  env("MSG91_BASE_URL", ""),
			TwilioSID:     env("TWILIO_ACCOUNT_SID", ""),
			TwilioToken:   env("TWILIO_AUTH_TOKEN", ""),
			TwilioFrom:    env("TWILIO_FROM", ""),
			TwilioBaseURL: env("TWILIO_BASE_URL", ""),
			WebhookURL:    env("SMS_WEBHOOK_URL", ""),
			WebhookToken:  env("SMS_WEBHOOK_TOKEN", ""),
		},
		TrustedProxies:         splitList(env("TRUSTED_PROXIES", "")),
		RateLimitPerMinute:     envInt("RATE_LIMIT_PER_MINUTE", 3000),
		AuthRateLimitPerMinute: envInt("AUTH_RATE_LIMIT_PER_MINUTE", 120),
		AdminUsername:          env("ADMIN_USERNAME", "admin"),
		AdminPassword:          env("ADMIN_PASSWORD", ""),
		AdminName:              env("ADMIN_NAME", "Administrator"),
		AdminMobile:            env("ADMIN_MOBILE", ""),
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT_SECRET must be at least 32 characters")
	}
	cfg.LogFormat = env("LOG_FORMAT", map[bool]string{true: "json", false: "text"}[cfg.IsProduction()])
	if cfg.IsProduction() {
		if err := cfg.checkProduction(); err != nil {
			return nil, err
		}
	}
	return cfg, nil
}

// checkProduction refuses settings that are fine on a laptop but unsafe on a live server.
func (c *Config) checkProduction() error {
	var problems []string
	if c.OTPDebug {
		problems = append(problems, "OTP_DEBUG must be false")
	}
	if strings.Contains(strings.ToLower(c.JWTSecret), "change") || strings.Contains(c.JWTSecret, "generate-a-random") {
		problems = append(problems, "JWT_SECRET still has the example value; generate one with: openssl rand -hex 32")
	}
	if p := strings.ToLower(c.SMS.Provider); p == "" || p == "console" {
		problems = append(problems, "SMS_PROVIDER must be msg91, twilio or webhook (console only logs OTPs)")
	}
	if c.AdminPassword != "" && (len(c.AdminPassword) < 10 || strings.Contains(strings.ToUpper(c.AdminPassword), "CHANGE_ME")) {
		problems = append(problems, "ADMIN_PASSWORD must be at least 10 characters and not the example value")
	}
	if slices.ContainsFunc(c.CORSOrigins, func(o string) bool { return o == "*" }) {
		problems = append(problems, "CORS_ORIGINS must list your sites, not *")
	}
	if len(problems) > 0 {
		return fmt.Errorf("unsafe production settings:\n  - %s", strings.Join(problems, "\n  - "))
	}
	return nil
}

func splitList(s string) []string {
	out := []string{}
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func (c *Config) IsProduction() bool { return c.AppEnv == "production" }

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	if v, err := strconv.ParseBool(os.Getenv(key)); err == nil {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}

func envDuration(key string, def time.Duration) time.Duration {
	if v, err := time.ParseDuration(os.Getenv(key)); err == nil {
		return v
	}
	return def
}
