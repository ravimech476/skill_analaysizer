package placement

import (
	"context"
	"fmt"
	"skills-analyzer/internal/files"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"

	"skills-analyzer/internal/notify"
	"skills-analyzer/internal/pkg/actor"
	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/request"
	"skills-analyzer/internal/pkg/response"
)

type Application struct {
	ID             int64     `json:"id"`
	JobRoleID      int64     `json:"job_role_id"`
	JobTitle       string    `json:"job_title"`
	CompanyID      int64     `json:"company_id"`
	CompanyName    string    `json:"company_name"`
	PackageLPA     float64   `json:"package_lpa"`
	DriveDate      *string   `json:"drive_date"`
	StudentID      int64     `json:"student_id"`
	StudentName    string    `json:"student_name"`
	RegisterNo     string    `json:"register_no"`
	DepartmentCode *string   `json:"department_code"`
	CGPA           float64   `json:"cgpa"`
	MatchScore     *float64  `json:"match_score"`
	Status         string    `json:"status"`
	Remarks        *string   `json:"remarks"`
	OfferDate      *string   `json:"offer_date"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

const selectApplication = `
	SELECT a.id, j.id, j.title, co.id, co.name::text, j.package_lpa::float8, to_char(j.drive_date, 'YYYY-MM-DD'),
	       u.id, u.name, sp.register_no, d.code, sp.cgpa::float8, a.match_score::float8, a.status, a.remarks,
	       (SELECT to_char(pr.offer_date, 'YYYY-MM-DD') FROM placement_records pr WHERE pr.application_id = a.id AND pr.is_active),
	       a.created_at, a.updated_at
	FROM placement_applications a
	JOIN company_job_roles j ON j.id = a.job_role_id
	JOIN companies co ON co.id = j.company_id
	JOIN users u ON u.id = a.student_id
	JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
	LEFT JOIN departments d ON d.id = u.department_id`

func (h *Handler) applicationsWhere(ctx context.Context, cond string, args ...any) ([]Application, error) {
	rows, err := h.db.Query(ctx, selectApplication+" WHERE a.is_active AND "+cond+" ORDER BY a.match_score DESC NULLS LAST, u.name", args...)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Application])
}

// shortlist adds eligible students to the role; ineligible or already-listed students are reported, not added.
func (h *Handler) shortlist(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		StudentIDs []int64 `json:"student_ids" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("student_ids is required"))
		return
	}
	role, err := h.findRole(c, id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if role.Status == "closed" || role.Status == "completed" {
		response.Error(c, response.Conflict("This job role is "+role.Status+"; reopen it to shortlist students"))
		return
	}
	ids := uniq(body.StudentIDs)
	matches, err := h.evaluate(c, role, candidateFilter{StudentIDs: ids})
	if err != nil {
		response.Error(c, err)
		return
	}
	type skip struct {
		StudentID int64  `json:"student_id"`
		Name      string `json:"name"`
		Reason    string `json:"reason"`
	}
	found := map[int64]bool{}
	added := 0
	skipped := []skip{}
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		for _, m := range matches {
			found[m.StudentID] = true
			switch {
			case m.ApplicationStatus != nil:
				skipped = append(skipped, skip{m.StudentID, m.Name, "Already " + *m.ApplicationStatus})
			case !m.IsEligible:
				skipped = append(skipped, skip{m.StudentID, m.Name, strings.Join(m.IneligibleReasons, "; ")})
			default:
				if _, err := tx.Exec(c, `INSERT INTO placement_applications (job_role_id, student_id, match_score, status, created_by, updated_by)
					VALUES ($1, $2, $3, 'shortlisted', $4, $4)`, id, m.StudentID, m.FinalScore, a.ID); err != nil {
					return err
				}
				added++
			}
		}
		return nil
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	for _, sid := range ids {
		if !found[sid] {
			skipped = append(skipped, skip{sid, "", "Not an active student"})
		}
	}
	if added > 0 {
		shortlisted := []int64{}
		for _, m := range matches {
			if m.IsEligible && m.ApplicationStatus == nil {
				shortlisted = append(shortlisted, m.StudentID)
			}
		}
		rt, rid := notify.Ref("job_role", role.ID)
		h.notify.SendSafe(c, notify.Notice{Title: "Shortlisted: " + role.CompanyName + " - " + role.Title,
			Body: fmt.Sprintf("Shortlisted for %s at %s (%.2f LPA). Watch for the next round details from the placement cell.", role.Title, role.CompanyName, role.PackageLPA),
			Type: notify.TypePlacement, RefType: rt, RefID: rid, CreatedBy: a.ID}, h.notify.WithParents(c, shortlisted))
	}
	response.OK(c, gin.H{"added": added, "skipped": skipped})
}

func (h *Handler) listApplications(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.applicationsWhere(c, "a.job_role_id = $1 AND ($2::bigint IS NULL OR u.department_id = $2)", id, scope)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

// updateApplication moves an application through the pipeline. "selected" creates the placement
// record (re-checking the higher-package rule); leaving "selected" withdraws it.
func (h *Handler) updateApplication(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	id, ok := request.ID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Status    string  `json:"status" binding:"required,oneof=shortlisted applied in_process selected rejected withdrawn"`
		Remarks   *string `json:"remarks"`
		OfferDate *string `json:"offer_date"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, response.BadRequest("status must be shortlisted, applied, in_process, selected, rejected or withdrawn"))
		return
	}
	offer, err := parseDate(body.OfferDate, "offer_date")
	if err != nil {
		response.Error(c, err)
		return
	}
	var studentID, roleID, companyID int64
	var pkg float64
	var prevStatus string
	err = h.db.QueryRow(c, `SELECT a.student_id, a.job_role_id, j.company_id, j.package_lpa::float8, a.status
		FROM placement_applications a JOIN company_job_roles j ON j.id = a.job_role_id WHERE a.id = $1 AND a.is_active`, id).
		Scan(&studentID, &roleID, &companyID, &pkg, &prevStatus)
	if dbutil.IsNoRows(err) {
		response.Error(c, response.NotFound("Application not found"))
		return
	}
	if err != nil {
		response.Error(c, err)
		return
	}
	err = pgx.BeginFunc(c, h.db, func(tx pgx.Tx) error {
		if body.Status == "selected" {
			var best *float64
			if err := tx.QueryRow(c, `SELECT max(package_lpa)::float8 FROM placement_records
				WHERE student_id = $1 AND is_active AND job_role_id <> $2`, studentID, roleID).Scan(&best); err != nil {
				return err
			}
			if best != nil && *best >= pkg {
				return response.Conflict(fmt.Sprintf("Student is already placed at %.2f LPA; only a higher package can be accepted", *best))
			}
			if _, err := tx.Exec(c, `INSERT INTO placement_records (student_id, company_id, job_role_id, application_id, package_lpa, offer_date, created_by, updated_by)
				SELECT $1, $2, $3, $4, $5, COALESCE($6, CURRENT_DATE), $7, $7
				WHERE NOT EXISTS (SELECT 1 FROM placement_records WHERE student_id = $1 AND job_role_id = $3 AND is_active)`,
				studentID, companyID, roleID, id, pkg, offer, a.ID); err != nil {
				return err
			}
		} else {
			if _, err := tx.Exec(c, `UPDATE placement_records SET is_active = false, updated_by = $2 WHERE application_id = $1 AND is_active`, id, a.ID); err != nil {
				return err
			}
		}
		_, err := tx.Exec(c, `UPDATE placement_applications SET status = $2, remarks = COALESCE($3, remarks), updated_by = $4 WHERE id = $1`,
			id, body.Status, body.Remarks, a.ID)
		return err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	list, err := h.applicationsWhere(c, "a.id = $1", id)
	if err != nil {
		response.Error(c, err)
		return
	}
	if body.Status != prevStatus {
		h.notifyStatus(c, list[0], a)
	}
	response.OK(c, list[0])
}

// notifyStatus tells the student and their parents about progress on an application.
func (h *Handler) notifyStatus(ctx context.Context, app Application, a actor.Actor) {
	where := app.JobTitle + " at " + app.CompanyName
	var title, body string
	switch app.Status {
	case "selected":
		title = "Selected: " + app.CompanyName + " - " + app.JobTitle
		body = fmt.Sprintf("Congratulations! %s has been selected for %s with a package of %.2f LPA.", app.StudentName, where, app.PackageLPA)
	case "in_process":
		title = app.CompanyName + ": moved to the next round"
		body = fmt.Sprintf("%s has moved to the next round for %s.", app.StudentName, where)
	case "rejected":
		title = "Placement update: " + app.CompanyName
		body = fmt.Sprintf("%s was not selected for %s. Keep improving; more drives are coming.", app.StudentName, where)
	default:
		return
	}
	rt, rid := notify.Ref("job_role", app.JobRoleID)
	h.notify.SendSafe(ctx, notify.Notice{Title: title, Body: body, Type: notify.TypePlacement, RefType: rt, RefID: rid, CreatedBy: a.ID},
		h.notify.WithParents(ctx, []int64{app.StudentID}))
}

// ---- placement records & stats ----

type Placement struct {
	ID             int64       `json:"id"`
	StudentID      int64       `json:"student_id"`
	StudentName    string      `json:"student_name"`
	RegisterNo     string      `json:"register_no"`
	DepartmentCode *string     `json:"department_code"`
	Batch          string      `json:"batch"`
	CompanyName    string      `json:"company_name"`
	JobTitle       string      `json:"job_title"`
	PackageLPA     float64     `json:"package_lpa"`
	OfferDate      *string     `json:"offer_date"`
	CreatedAt      time.Time   `json:"created_at"`
	OfferLetter    *files.Link `json:"offer_letter"`
}

// listPlacements: ?search=&company_id=&department_id=&batch=
func (h *Handler) listPlacements(c *gin.Context) {
	list, err := h.queryPlacements(c)
	if err != nil {
		response.Error(c, err)
		return
	}
	response.OK(c, list)
}

func (h *Handler) queryPlacements(c *gin.Context) ([]Placement, error) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		return nil, err
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		return nil, err
	}
	where := []string{"pr.is_active"}
	args := []any{}
	arg := func(v any) string { args = append(args, v); return fmt.Sprintf("$%d", len(args)) }
	if scope != nil {
		where = append(where, "u.department_id = "+arg(*scope))
	}
	if v := request.QueryInt64(c, "company_id"); v != nil {
		where = append(where, "pr.company_id = "+arg(*v))
	}
	if v := request.QueryInt64(c, "department_id"); v != nil {
		where = append(where, "u.department_id = "+arg(*v))
	}
	if b := c.Query("batch"); b != "" {
		where = append(where, "sp.batch = "+arg(b))
	}
	if s := strings.TrimSpace(c.Query("search")); s != "" {
		ph := arg("%" + s + "%")
		where = append(where, fmt.Sprintf("(u.name ILIKE %[1]s OR sp.register_no ILIKE %[1]s OR co.name::text ILIKE %[1]s)", ph))
	}
	rows, err := h.db.Query(c, `
		SELECT pr.id, u.id, u.name, sp.register_no, d.code, sp.batch, co.name::text, j.title, pr.package_lpa::float8,
		       to_char(pr.offer_date, 'YYYY-MM-DD'), pr.created_at, file_json(pr.offer_letter_file_id)
		FROM placement_records pr
		JOIN users u ON u.id = pr.student_id
		JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
		LEFT JOIN departments d ON d.id = u.department_id
		JOIN companies co ON co.id = pr.company_id
		JOIN company_job_roles j ON j.id = pr.job_role_id
		WHERE `+strings.Join(where, " AND ")+` ORDER BY pr.package_lpa DESC, u.name`, args...)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Placement])
}

// placementStats: headline numbers, per department and per company (?batch= to focus on one batch).
func (h *Handler) placementStats(c *gin.Context) {
	a := actor.From(c)
	if err := staffOnly(a); err != nil {
		response.Error(c, err)
		return
	}
	scope, err := h.scopeFor(c, a)
	if err != nil {
		response.Error(c, err)
		return
	}
	batch := c.Query("batch")
	type deptStat struct {
		Code     string  `json:"code"`
		Name     string  `json:"name"`
		Students int     `json:"students"`
		Placed   int     `json:"placed"`
		Percent  float64 `json:"percent"`
	}
	type companyStat struct {
		Company string  `json:"company"`
		Offers  int     `json:"offers"`
		Highest float64 `json:"highest"`
	}
	var totalStudents, placed, offers int
	var highest, average *float64
	err = h.db.QueryRow(c, `
		WITH st AS (
			SELECT u.id FROM student_profiles sp JOIN users u ON u.id = sp.user_id AND u.is_active
			WHERE sp.is_active AND ($1 = '' OR sp.batch = $1) AND ($2::bigint IS NULL OR u.department_id = $2)
		), best AS (
			SELECT pr.student_id, max(pr.package_lpa) AS pkg, count(*) AS n
			FROM placement_records pr JOIN st ON st.id = pr.student_id WHERE pr.is_active GROUP BY pr.student_id
		)
		SELECT (SELECT count(*) FROM st)::int, (SELECT count(*) FROM best)::int, COALESCE((SELECT sum(n) FROM best), 0)::int,
		       (SELECT max(pkg)::float8 FROM best), (SELECT round(avg(pkg), 2)::float8 FROM best)`, batch, scope).
		Scan(&totalStudents, &placed, &offers, &highest, &average)
	if err != nil {
		response.Error(c, err)
		return
	}
	rows, err := h.db.Query(c, `
		SELECT d.code, d.name, count(DISTINCT u.id)::int,
		       count(DISTINCT u.id) FILTER (WHERE EXISTS (SELECT 1 FROM placement_records pr WHERE pr.student_id = u.id AND pr.is_active))::int
		FROM departments d
		JOIN users u ON u.department_id = d.id AND u.is_active
		JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active AND ($1 = '' OR sp.batch = $1)
		WHERE d.is_active AND ($2::bigint IS NULL OR d.id = $2)
		GROUP BY d.id ORDER BY d.code`, batch, scope)
	if err != nil {
		response.Error(c, err)
		return
	}
	depts, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (deptStat, error) {
		var s deptStat
		err := r.Scan(&s.Code, &s.Name, &s.Students, &s.Placed)
		if s.Students > 0 {
			s.Percent = round2(float64(s.Placed) / float64(s.Students) * 100)
		}
		return s, err
	})
	if err != nil {
		response.Error(c, err)
		return
	}
	rows, err = h.db.Query(c, `
		SELECT co.name::text, count(*)::int, max(pr.package_lpa)::float8
		FROM placement_records pr JOIN companies co ON co.id = pr.company_id
		JOIN users u ON u.id = pr.student_id JOIN student_profiles sp ON sp.user_id = u.id AND sp.is_active
		WHERE pr.is_active AND ($1 = '' OR sp.batch = $1) AND ($2::bigint IS NULL OR u.department_id = $2)
		GROUP BY co.id ORDER BY count(*) DESC, co.name`, batch, scope)
	if err != nil {
		response.Error(c, err)
		return
	}
	companies, err := pgx.CollectRows(rows, pgx.RowToStructByPos[companyStat])
	if err != nil {
		response.Error(c, err)
		return
	}
	percent := 0.0
	if totalStudents > 0 {
		percent = round2(float64(placed) / float64(totalStudents) * 100)
	}
	response.OK(c, gin.H{
		"total_students": totalStudents, "placed_students": placed, "placed_percent": percent, "total_offers": offers,
		"highest_package": highest, "average_package": average, "by_department": depts, "by_company": companies,
	})
}
