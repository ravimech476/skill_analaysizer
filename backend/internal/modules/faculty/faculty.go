package faculty

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/middleware"
	"skills-analyzer/internal/modules/student"
	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type Handler struct {
	db       *pgxpool.Pool
	students *student.Service
	notify   *notify.Service
}

// Register adds the faculty routes and starts the daily snapshot that builds each student's score history.
func Register(ctx context.Context, r *gin.RouterGroup, db *pgxpool.Pool, perms *rbac.Cache, students *student.Service, n *notify.Service) {
	h := &Handler{db: db, students: students, notify: n}
	r.GET("/analyzer/readiness", middleware.RequirePermission(perms, "report.view"), h.readiness)
	r.POST("/analyzer/snapshot", middleware.RequirePermission(perms, "report.view"), h.snapshotNow)
	r.GET("/students/:id/score-history", middleware.RequirePermission(perms, "student.view"), h.history)
	go h.dailyLoop(ctx)
}

// Row is one student on the faculty dashboard. Score fields appear under the names both the web and the
// mobile app use.
type Row struct {
	ID            int64    `json:"student_id"`
	Name          string   `json:"name"`
	RegisterNo    string   `json:"register_no"`
	Department    string   `json:"department"`
	ClassLabel    string   `json:"class_label"`
	CGPA          float64  `json:"cgpa"`
	Backlogs      int      `json:"backlog_count"`
	SkillCount    int      `json:"skill_count"`
	SkillsScore   float64  `json:"skills_score"`
	Aptitude      *float64 `json:"aptitude_score"`
	Coding        *float64 `json:"coding_score"`
	Communication *float64 `json:"communication_score"`
	Attendance    *float64 `json:"attendance_score"`
	IsPlaced      bool     `json:"is_placed"`
	Readiness     float64  `json:"readiness_score"`
	Score         float64  `json:"score"`
	Change        *float64 `json:"change"` // readiness now minus about a month ago; nil without an earlier snapshot
	Risk          string   `json:"risk_level"`
	Reasons       []Reason `json:"risk_reasons"`

	inchargeID, hodID *int64
}

const gatherSQL = `
	SELECT u.id, u.name, sp.register_no, COALESCE(d.code, ''),
	       COALESCE(CASE WHEN c.id IS NULL THEN NULL
	            ELSE cd.code || ' ' || COALESCE((ARRAY['I','II','III','IV','V','VI'])[yl.level_no], yl.level_no::text) || '-' || c.section END, ''),
	       sp.cgpa::float8, sp.backlog_count,
	       (SELECT count(*) FROM student_skills ss WHERE ss.student_id = u.id AND ss.is_active)::int,
	       sp.aptitude_score::float8, sp.coding_score::float8, sp.communication_score::float8,
	       (SELECT round(avg(a.percentage)::numeric, 1)::float8 FROM attendance a WHERE a.student_id = u.id AND a.is_active),
	       EXISTS (SELECT 1 FROM placement_records pr WHERE pr.student_id = u.id AND pr.is_active),
	       h.readiness::float8, c.class_incharge_id, d.hod_id
	FROM student_profiles sp
	JOIN users u              ON u.id = sp.user_id AND u.is_active
	LEFT JOIN departments d   ON d.id = u.department_id
	LEFT JOIN classes c       ON c.id = sp.current_class_id
	LEFT JOIN departments cd  ON cd.id = c.department_id
	LEFT JOIN year_levels yl  ON yl.id = c.year_level_id
	LEFT JOIN LATERAL (
		SELECT sh.readiness FROM student_score_history sh
		WHERE sh.student_id = u.id AND sh.snapshot_date BETWEEN current_date - 30 AND current_date - 7
		ORDER BY sh.snapshot_date LIMIT 1) h ON true
	WHERE sp.is_active AND sp.lifecycle_status = 'studying'
	  AND ($1::bigint IS NULL OR sp.current_class_id = $1)
	  AND ($2::bigint IS NULL OR u.department_id = $2)`

func (h *Handler) gather(ctx context.Context, classID, deptID *int64) ([]*Row, error) {
	rows, err := h.db.Query(ctx, gatherSQL, classID, deptID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*Row{}
	for rows.Next() {
		r := &Row{}
		var before *float64
		if err := rows.Scan(&r.ID, &r.Name, &r.RegisterNo, &r.Department, &r.ClassLabel, &r.CGPA, &r.Backlogs, &r.SkillCount,
			&r.Aptitude, &r.Coding, &r.Communication, &r.Attendance, &r.IsPlaced, &before, &r.inchargeID, &r.hodID); err != nil {
			return nil, err
		}
		m := Metrics{CGPA: r.CGPA, Backlogs: r.Backlogs, SkillCount: r.SkillCount, Aptitude: r.Aptitude,
			Coding: r.Coding, Communication: r.Communication, Attendance: r.Attendance}
		r.SkillsScore = round1(SkillsScore(r.SkillCount))
		r.Readiness = Readiness(m)
		r.Score = r.Readiness
		if before != nil {
			d := round1(r.Readiness - *before)
			r.Change = &d
		}
		r.Risk, r.Reasons = RiskNone, []Reason{}
		if !r.IsPlaced { // a placed student needs no placement alerts
			r.Risk, r.Reasons = Assess(m, r.Readiness, r.Change)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Readiness > out[j].Readiness })
	return out, nil
}

// scope applies the same department rule as the other staff reports.
func (h *Handler) scope(c *gin.Context) (class, dept *int64, ok bool) {
	a := actor.From(c)
	if !a.Has("admin", "placement_officer", "hod", "staff") {
		response.Error(c, response.Forbidden("Staff only"))
		return nil, nil, false
	}
	dept = request.QueryInt64(c, "department_id")
	if !a.Has("admin", "placement_officer") {
		var own *int64
		if err := h.db.QueryRow(c, `SELECT department_id FROM users WHERE id = $1`, a.ID).Scan(&own); err != nil {
			response.Error(c, err)
			return nil, nil, false
		}
		if own != nil {
			dept = own
		}
	}
	return request.QueryInt64(c, "class_id"), dept, true
}

type atRiskCounts struct {
	High   int `json:"high"`
	Medium int `json:"medium"`
}

func (h *Handler) readiness(c *gin.Context) {
	class, dept, ok := h.scope(c)
	if !ok {
		return
	}
	rows, err := h.gather(c, class, dept)
	if err != nil {
		response.Error(c, err)
		return
	}
	var sum float64
	var ready int
	var risk atRiskCounts
	for _, r := range rows {
		sum += r.Readiness
		if r.Readiness >= 70 {
			ready++
		}
		switch r.Risk {
		case RiskHigh:
			risk.High++
		case RiskMedium:
			risk.Medium++
		}
	}
	avg, abovePct := 0.0, 0.0
	top := ""
	if n := len(rows); n > 0 {
		avg = round1(sum / float64(n))
		abovePct = round1(float64(ready) / float64(n) * 100)
		top = rows[0].Name
	}
	response.OK(c, gin.H{
		"students": rows, "avg_readiness": avg, "avg_score": avg,
		"above_70_percent": abovePct, "ready_count": ready, "total_count": len(rows),
		"top_student": top, "at_risk": risk,
	})
}

// ---- score history ----

type Point struct {
	Date          string   `json:"date"`
	Readiness     float64  `json:"readiness"`
	CGPA          float64  `json:"cgpa"`
	Aptitude      *float64 `json:"aptitude"`
	Coding        *float64 `json:"coding"`
	Communication *float64 `json:"communication"`
	Attendance    *float64 `json:"attendance"`
	SkillCount    int      `json:"skill_count"`
	Risk          string   `json:"risk_level"`
}

// history: GET /students/:id/score-history?days=
func (h *Handler) history(c *gin.Context) {
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	if _, err := h.students.Get(c, actor.From(c), id); err != nil {
		response.Error(c, err)
		return
	}
	days := int64(365)
	if v := request.QueryInt64(c, "days"); v != nil && *v > 0 && *v < 3650 {
		days = *v
	}
	rows, err := h.db.Query(c, `
		SELECT to_char(snapshot_date, 'YYYY-MM-DD'), readiness::float8, cgpa::float8, aptitude::float8, coding::float8,
		       communication::float8, attendance::float8, skill_count, risk_level
		FROM student_score_history WHERE student_id = $1 AND snapshot_date >= current_date - $2::int
		ORDER BY snapshot_date`, id, days)
	if err != nil {
		response.Error(c, err)
		return
	}
	defer rows.Close()
	out := []Point{}
	for rows.Next() {
		var p Point
		if err := rows.Scan(&p.Date, &p.Readiness, &p.CGPA, &p.Aptitude, &p.Coding, &p.Communication, &p.Attendance, &p.SkillCount, &p.Risk); err != nil {
			response.Error(c, err)
			return
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, out)
}

// ---- daily snapshot and alerts ----

func (h *Handler) dailyLoop(ctx context.Context) {
	select {
	case <-time.After(30 * time.Second):
	case <-ctx.Done():
		return
	}
	t := time.NewTicker(6 * time.Hour) // safe to repeat: one row per student per day
	defer t.Stop()
	for {
		if n, err := h.Snapshot(ctx); err != nil {
			slog.Error("score snapshot failed", "err", err)
		} else {
			slog.Info("score snapshot done", "students", n)
		}
		select {
		case <-t.C:
		case <-ctx.Done():
			return
		}
	}
}

func (h *Handler) snapshotNow(c *gin.Context) {
	if !actor.From(c).Has("admin", "placement_officer") {
		response.Error(c, response.Forbidden("Only the placement cell can run the snapshot"))
		return
	}
	n, err := h.Snapshot(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, gin.H{"students": n})
}

// Snapshot stores today's scores for every studying student and alerts the class incharge (or the head of
// department) when a student has newly become high risk. The first snapshot of a student is a baseline and
// raises no alert, so switching the feature on does not flood staff.
func (h *Handler) Snapshot(ctx context.Context) (int, error) {
	rows, err := h.gather(ctx, nil, nil)
	if err != nil {
		return 0, err
	}
	previous := map[int64]string{}
	prev, err := h.db.Query(ctx, `SELECT DISTINCT ON (student_id) student_id, risk_level FROM student_score_history ORDER BY student_id, snapshot_date DESC`)
	if err != nil {
		return 0, err
	}
	for prev.Next() {
		var id int64
		var level string
		if err := prev.Scan(&id, &level); err != nil {
			prev.Close()
			return 0, err
		}
		previous[id] = level
	}
	prev.Close()
	if err := prev.Err(); err != nil {
		return 0, err
	}

	for _, r := range rows {
		if _, err := h.db.Exec(ctx, `
			INSERT INTO student_score_history (student_id, snapshot_date, readiness, cgpa, aptitude, coding, communication, attendance, skill_count, risk_level)
			VALUES ($1, current_date, $2, $3, $4, $5, $6, $7, $8, $9)
			ON CONFLICT (student_id, snapshot_date) DO UPDATE SET readiness = EXCLUDED.readiness, cgpa = EXCLUDED.cgpa,
			  aptitude = EXCLUDED.aptitude, coding = EXCLUDED.coding, communication = EXCLUDED.communication,
			  attendance = EXCLUDED.attendance, skill_count = EXCLUDED.skill_count, risk_level = EXCLUDED.risk_level`,
			r.ID, r.Readiness, r.CGPA, r.Aptitude, r.Coding, r.Communication, r.Attendance, r.SkillCount, r.Risk); err != nil {
			return 0, err
		}
		if was, seen := previous[r.ID]; seen && r.Risk == RiskHigh && was != RiskHigh {
			h.alert(ctx, r)
		}
	}
	return len(rows), nil
}

func (h *Handler) alert(ctx context.Context, r *Row) {
	recipients := []int64{}
	switch {
	case r.inchargeID != nil:
		recipients = append(recipients, *r.inchargeID)
	case r.hodID != nil:
		recipients = append(recipients, *r.hodID)
	}
	if len(recipients) == 0 {
		return
	}
	texts := make([]string, 0, len(r.Reasons))
	for _, x := range r.Reasons {
		texts = append(texts, x.Text)
	}
	rt, rid := notify.Ref("at_risk", r.ID)
	h.notify.SendSafe(ctx, notify.Notice{
		Title:   fmt.Sprintf("At-risk student: %s (%s)", r.Name, r.RegisterNo),
		Body:    strings.Join(texts, ". ") + ".",
		Type:    notify.TypeGeneral,
		RefType: rt, RefID: rid,
	}, recipients)
}
