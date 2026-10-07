package router

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/config"
	"skills-analyzer/internal/files"
	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/analyzer"
	"skills-analyzer/internal/modules/auth"
	"skills-analyzer/internal/modules/bulkupload"
	"skills-analyzer/internal/modules/class"
	"skills-analyzer/internal/modules/marks"
	"skills-analyzer/internal/modules/master"
	"skills-analyzer/internal/modules/media"
	"skills-analyzer/internal/modules/notification"
	"skills-analyzer/internal/modules/permission"
	"skills-analyzer/internal/modules/placement"
	"skills-analyzer/internal/modules/reports"
	"skills-analyzer/internal/modules/role"
	"skills-analyzer/internal/modules/skillscore"
	"skills-analyzer/internal/modules/staff"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/modules/user"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/rbac"
	"skills-analyzer/internal/sms"
)

func New(ctx context.Context, cfg *config.Config, db *pgxpool.Pool) (*gin.Engine, error) {
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	// Only trust X-Forwarded-For from the configured reverse proxies, so rate limits see real client IPs.
	if err := r.SetTrustedProxies(cfg.TrustedProxies); err != nil {
		return nil, err
	}
	r.Use(middleware.RequestID(), middleware.AccessLog(), gin.Recovery(), middleware.SecurityHeaders(cfg.IsProduction()),
		middleware.BodyLimit(1<<20, 12<<20))
	r.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.CORSOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Authorization", "Content-Type"},
		ExposeHeaders:    []string{"Content-Disposition"}, // lets the web app keep the server's file names on downloads
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))
	r.NoRoute(func(c *gin.Context) { response.Error(c, response.NotFound("Route not found")) })

	tokens := security.NewTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL)
	perms := rbac.NewCache(db)

	sender, err := sms.New(cfg.SMS)
	if err != nil {
		return nil, err
	}
	slog.Info("otp delivery", "provider", cfg.SMS.Provider)
	authSvc, err := auth.NewService(auth.NewRepository(db), cfg, tokens, perms, sender)
	if err != nil {
		return nil, err
	}
	authH := auth.NewHandler(authSvc)
	roleH := role.NewHandler(role.NewService(role.NewRepository(db), perms))
	userH := user.NewHandler(user.NewService(user.NewRepository(db)))
	permH := permission.NewHandler(db)

	r.GET("/health", func(c *gin.Context) {
		if err := db.Ping(c.Request.Context()); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "db_down"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok", "env": cfg.AppEnv})
	})

	// Phase 8: uploaded files, served through signed links
	store, err := files.NewLocalStore(cfg.FilesDir)
	if err != nil {
		return nil, err
	}
	fileSvc := files.Init(db, store, cfg.JWTSecret)
	fileSvc.StartCleanup(ctx)

	// Per client IP. Campus Wi-Fi puts many users behind one IP, so these are generous; password
	// guessing is stopped per account in the auth service instead.
	v1 := r.Group("/api/v1", middleware.RateLimit(middleware.NewLimiter(cfg.RateLimitPerMinute, time.Minute), "api"))
	authH.RegisterPublic(v1.Group("/auth", middleware.RateLimit(middleware.NewLimiter(cfg.AuthRateLimitPerMinute, time.Minute), "auth")))
	fileSvc.RegisterPublic(v1)

	private := v1.Group("", middleware.Auth(tokens))
	authH.RegisterPrivate(private.Group("/auth"))
	fileSvc.RegisterPrivate(private)
	userH.Register(private.Group("/users"), perms)
	roleH.Register(private.Group("/roles"), perms)
	permH.Register(private.Group("/permissions"), perms)

	// Phase 2: academic setup, classes, students, staff, bulk upload
	for _, res := range master.Resources {
		master.Register(private, db, perms, res)
	}
	class.Register(private, db, perms)
	studentSvc := student.NewService(db)
	student.NewHandler(studentSvc).Register(private, perms)
	staff.Register(private, db, perms)

	// Phase 5: notifications (used by the modules below for automatic alerts)
	var pusher *notify.ExpoPusher
	if cfg.PushEnabled {
		pusher = notify.NewExpoPusher(cfg.ExpoPushURL)
	}
	notifier := notify.New(db, pusher)
	notification.Register(private, db, perms, notifier)

	// Phase 2 + 7: Excel imports (students, staff, student skills)
	bulkupload.Register(private, db, perms, studentSvc, notifier)

	// Phase 3: marks, grading, CGPA, subject allocation
	marks.Register(private, db, perms, studentSvc, notifier)

	// Phase 4: student skills, job roles, skill analyzer, placement
	placement.Register(private, db, perms, studentSvc, notifier)

	// Phase 7: analytics dashboard (exports live in their own modules)
	reports.Register(private, db, perms)

	// Phase 7b: student/class/department skill analyzer
	analyzer.Register(private, db, perms, studentSvc)

	// Phase 8: photos, resumes and student documents (placement files live in the placement module)
	media.Register(private, db, perms, studentSvc, notifier)

	// Phase 10: blended skill scores (declared + assessed + certified + academic).
	// Registered after placement so the analyzer is already reading the scores
	// these endpoints maintain.
	skillscore.Register(private, db, perms, studentSvc)

	return r, nil
}
