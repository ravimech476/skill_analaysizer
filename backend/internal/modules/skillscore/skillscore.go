// Package skillscore turns the evidence a college already holds about a student —
// the level staff recorded, a verified certificate, assessment results and subject marks —
// into one blended 0-100 score per skill, which the analyzer and career matching read.
//
// skill_scores is a derived cache: Recompute deletes and rebuilds a student's rows, the
// same way the analyzer rebuilds skill_match_results. Rows with source 'test' are owned by
// the assessment module and are never touched here, only read when blending.
package skillscore

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
)

// Sources that make up a blended score, in reporting order.
var Sources = []string{"declared", "test", "cert", "academic"}

const (
	// ConfigWeights holds how much each source counts: {"declared":0.1,"test":0.45,...}.
	ConfigWeights = "skill_score_weights"
	// ConfigMatch holds the skill/academic split of a match score: {"skill":0.7,"academic":0.3}.
	ConfigMatch = "match_weights"
	// ConfigThreshold holds the minimum mark percentage for auto-assigning skills.
	ConfigThreshold = "global_mark_threshold"
)

// LevelStep converts a 1-5 proficiency level to the 0-100 scale (level 4 → 80).
const LevelStep = 20.0

// ---- settings ----

type Setting struct {
	Key         string          `json:"key"`
	Value       json.RawMessage `json:"value"`
	Description *string         `json:"description"`
	UpdatedAt   time.Time       `json:"updated_at"`
	UpdatedBy   *string         `json:"updated_by"`
}

// configValue returns the raw JSON value of a config key, or "{}" when the key does not exist.
func configValue(ctx context.Context, q dbutil.DBTX, key string) (json.RawMessage, error) {
	var raw json.RawMessage
	err := q.QueryRow(ctx, `SELECT value FROM app_config WHERE key = $1`, key).Scan(&raw)
	if dbutil.IsNoRows(err) {
		return json.RawMessage("{}"), nil
	}
	return raw, err
}

// Weights reads a weight map from app_config. Missing keys count as zero.
func Weights(ctx context.Context, q dbutil.DBTX, key string) (map[string]float64, error) {
	var raw []byte
	err := q.QueryRow(ctx, `SELECT value FROM app_config WHERE key = $1`, key).Scan(&raw)
	if dbutil.IsNoRows(err) {
		return map[string]float64{}, nil
	}
	if err != nil {
		return nil, err
	}
	out := map[string]float64{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("setting %s is not a map of numbers: %w", key, err)
	}
	return out, nil
}

// MatchWeights returns the skill/academic split, falling back to 70/30 when unset.
func MatchWeights(ctx context.Context, q dbutil.DBTX) (skill, academic float64, err error) {
	w, err := Weights(ctx, q, ConfigMatch)
	if err != nil {
		return 0, 0, err
	}
	skill, academic = w["skill"], w["academic"]
	if skill+academic <= 0 {
		return 0.7, 0.3, nil
	}
	total := skill + academic
	return skill / total, academic / total, nil
}

// ---- recompute ----

// lockSpace namespaces the advisory locks below, so they cannot collide with any other use.
const lockSpace = 825511

// Recompute rebuilds declared, cert, academic and blended scores for the given students.
// Safe to call with an empty list, and idempotent: the same inputs always give the same rows.
//
// It MUST run inside a transaction — Recompute takes a per-student advisory lock that is held
// until commit. Two rebuilds of the same student would otherwise delete and re-insert the same
// rows at the same time and one of them would hit ux_skill_scores; that happens for real when a
// weight change starts a background rebuild while someone saves a skill.
func Recompute(ctx context.Context, q dbutil.DBTX, actorID int64, studentIDs []int64) error {
	ids := distinct(studentIDs)
	if len(ids) == 0 {
		return nil
	}
	// distinct() sorts, and unnest keeps the array's order, so every caller takes the locks in
	// the same order and they cannot deadlock against each other.
	if _, err := q.Exec(ctx, `SELECT pg_advisory_xact_lock($2, (sid % 2147483647)::int)
		FROM unnest($1::bigint[]) AS sid`, ids, lockSpace); err != nil {
		return err
	}
	// Derived rows, so they are replaced rather than soft-deleted (as skill_match_results are).
	// 'test' rows belong to the assessment module.
	if _, err := q.Exec(ctx, `DELETE FROM skill_scores WHERE student_id = ANY($1) AND source <> 'test'`, ids); err != nil {
		return err
	}
	// What staff recorded, plus the same level again as independent evidence once the
	// certificate behind it has been verified.
	if _, err := q.Exec(ctx, `
		INSERT INTO skill_scores (student_id, skill_id, source, score, detail, created_by, updated_by)
		SELECT student_id, skill_id, source, score, detail, $2, $2 FROM (
			SELECT x.student_id, x.skill_id, 'declared'::varchar AS source, (x.proficiency * 20)::numeric AS score,
			       jsonb_build_object('proficiency', x.proficiency, 'entered_as', x.source) AS detail
			FROM student_skills x
			WHERE x.is_active AND x.student_id = ANY($1)
			UNION ALL
			SELECT x.student_id, x.skill_id, 'cert'::varchar, (x.proficiency * 20)::numeric,
			       jsonb_build_object('proficiency', x.proficiency, 'verified_at', x.certificate_verified_at)
			FROM student_skills x
			WHERE x.is_active AND x.student_id = ANY($1) AND x.certificate_verified
		) s`, ids, actorID); err != nil {
		return err
	}
	// Marks reach a skill through subject_skills: per subject take the latest attempt of a
	// final exam (any exam when there is no final), then average the percentages by weight.
	if _, err := q.Exec(ctx, `
		WITH best AS (
			SELECT DISTINCT ON (m.student_id, m.subject_id) m.student_id, m.subject_id,
			       LEAST(100, GREATEST(0, m.marks_obtained / NULLIF(m.max_marks, 0) * 100)) AS pct
			FROM student_marks m
			JOIN exam_types et ON et.id = m.exam_type_id
			WHERE m.is_active AND m.marks_obtained IS NOT NULL AND m.student_id = ANY($1)
			ORDER BY m.student_id, m.subject_id, et.is_final DESC, m.attempt_no DESC
		)
		INSERT INTO skill_scores (student_id, skill_id, source, score, detail, created_by, updated_by)
		SELECT b.student_id, ms.skill_id, 'academic'::varchar,
		       ROUND(SUM(b.pct * ms.weight) / SUM(ms.weight), 2),
		       jsonb_build_object('subjects', jsonb_agg(jsonb_build_object(
		           'subject_id', b.subject_id, 'percent', ROUND(b.pct, 2), 'weight', ms.weight) ORDER BY b.subject_id)),
		       $2, $2
		FROM best b
		JOIN subject_skills ms ON ms.subject_id = b.subject_id AND ms.is_active
		WHERE b.pct IS NOT NULL
		GROUP BY b.student_id, ms.skill_id`, ids, actorID); err != nil {
		return err
	}
	// Blend whatever sources exist, renormalising their weights so a missing source
	// neither helps nor hurts. detail records the inputs, so a student can be shown why.
	_, err := q.Exec(ctx, `
		WITH cfg AS (
			SELECT COALESCE((SELECT value FROM app_config WHERE key = 'skill_score_weights'), '{}'::jsonb) AS v
		), parts AS (
			SELECT s.student_id, s.skill_id, s.source, s.score,
			       COALESCE((SELECT (v ->> s.source)::numeric FROM cfg), 0) AS wt
			FROM skill_scores s
			WHERE s.is_active AND s.student_id = ANY($1) AND s.source <> 'blended'
		)
		INSERT INTO skill_scores (student_id, skill_id, source, score, detail, created_by, updated_by)
		SELECT student_id, skill_id, 'blended'::varchar,
		       LEAST(100, GREATEST(0, ROUND(SUM(score * wt) / SUM(wt), 2))),
		       jsonb_build_object('scores', jsonb_object_agg(source, score), 'weights', jsonb_object_agg(source, wt)),
		       $2, $2
		FROM parts
		GROUP BY student_id, skill_id
		HAVING SUM(wt) > 0`, ids, actorID)
	return err
}

// ForSubject recomputes every student who has marks in a subject. Used when a subject's
// skill mapping changes, since that silently changes those students' academic scores.
func ForSubject(ctx context.Context, db *pgxpool.Pool, actorID int64, subjectID int64) error {
	rows, err := db.Query(ctx, `SELECT DISTINCT student_id FROM student_marks WHERE subject_id = $1 AND is_active`, subjectID)
	if err != nil {
		return err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[int64])
	if err != nil {
		return err
	}
	return InBatches(ctx, db, actorID, ids)
}

// InBatches recomputes a large set of students a few hundred at a time, so one call
// cannot hold a long transaction or build a huge parameter array.
func InBatches(ctx context.Context, db *pgxpool.Pool, actorID int64, studentIDs []int64) error {
	const batch = 200
	ids := distinct(studentIDs)
	for start := 0; start < len(ids); start += batch {
		end := min(start+batch, len(ids))
		if err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
			return Recompute(ctx, tx, actorID, ids[start:end])
		}); err != nil {
			return err
		}
	}
	return nil
}

// ---- reading scores ----

// SourceScore is one source's contribution, with the evidence behind it: the proficiency
// behind a declared score, the subjects and percentages behind an academic one.
type SourceScore struct {
	Source string          `json:"source"`
	Score  float64         `json:"score"`
	Weight float64         `json:"weight"`
	Detail json.RawMessage `json:"detail"`
}

type Score struct {
	SkillID  int64              `json:"skill_id"`
	Name     string             `json:"name"`
	Category string             `json:"category"`
	Score    float64            `json:"score"`
	Level    int                `json:"level"` // the 1-5 equivalent, for screens that show stars
	Sources  map[string]float64 `json:"sources"`
	Detail   json.RawMessage    `json:"detail"`
	// Breakdown is why the score is what it is, in Sources order.
	Breakdown []SourceScore `json:"breakdown"`
}

// Level converts a 0-100 score to the nearest 1-5 level (0 when there is no evidence).
func Level(score float64) int {
	if score <= 0 {
		return 0
	}
	lvl := int((score + LevelStep - 1) / LevelStep) // 1-20 → 1, 21-40 → 2, …
	return min(max(lvl, 1), 5)
}

// Of returns one student's blended scores, highest first, each with the per-source
// breakdown that produced it.
func Of(ctx context.Context, q dbutil.DBTX, studentID int64) ([]Score, error) {
	weights, err := Weights(ctx, q, ConfigWeights)
	if err != nil {
		return nil, err
	}
	rows, err := q.Query(ctx, `
		SELECT s.id, s.name::text, s.category, b.source, b.score::float8, b.detail
		FROM skill_scores b
		JOIN skills s ON s.id = b.skill_id
		WHERE b.student_id = $1 AND b.is_active
		ORDER BY s.name`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Score{}
	bySkill := map[int64]*Score{}
	parts := map[int64]map[string]SourceScore{}
	for rows.Next() {
		var id int64
		var name, category, source string
		var score float64
		var detail []byte
		if err := rows.Scan(&id, &name, &category, &source, &score, &detail); err != nil {
			return nil, err
		}
		sc, ok := bySkill[id]
		if !ok {
			sc = &Score{SkillID: id, Name: name, Category: category, Sources: map[string]float64{}, Breakdown: []SourceScore{}}
			bySkill[id] = sc
			parts[id] = map[string]SourceScore{}
			out = append(out, Score{}) // placeholder, filled in below
		}
		if source == "blended" {
			sc.Score, sc.Level, sc.Detail = score, Level(score), detail
			continue
		}
		sc.Sources[source] = score
		parts[id][source] = SourceScore{Source: source, Score: score, Weight: weights[source], Detail: detail}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out = out[:0]
	for _, sc := range bySkill {
		for _, name := range Sources { // keep the reporting order, skip sources with no row
			if p, ok := parts[sc.SkillID][name]; ok {
				sc.Breakdown = append(sc.Breakdown, p)
			}
		}
		out = append(out, *sc)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Score != out[j].Score {
			return out[i].Score > out[j].Score
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}

// Blended returns skill → 0-100 score for several students in one query, for the matchers.
func Blended(ctx context.Context, q dbutil.DBTX, studentIDs []int64) (map[int64]map[int64]float64, error) {
	out := map[int64]map[int64]float64{}
	if len(studentIDs) == 0 {
		return out, nil
	}
	rows, err := q.Query(ctx, `SELECT student_id, skill_id, score::float8 FROM skill_scores
		WHERE is_active AND source = 'blended' AND student_id = ANY($1)`, studentIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var sid, skid int64
		var score float64
		if err := rows.Scan(&sid, &skid, &score); err != nil {
			return nil, err
		}
		if out[sid] == nil {
			out[sid] = map[int64]float64{}
		}
		out[sid][skid] = score
	}
	return out, rows.Err()
}

// ComputedAt returns when each student's scores were last rebuilt, so a cached ranking
// can say whether it is out of date.
func ComputedAt(ctx context.Context, q dbutil.DBTX, studentIDs []int64) (map[int64]time.Time, error) {
	out := map[int64]time.Time{}
	if len(studentIDs) == 0 {
		return out, nil
	}
	rows, err := q.Query(ctx, `SELECT student_id, max(computed_at) FROM skill_scores
		WHERE is_active AND student_id = ANY($1) GROUP BY student_id`, studentIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var sid int64
		var at time.Time
		if err := rows.Scan(&sid, &at); err != nil {
			return nil, err
		}
		out[sid] = at
	}
	return out, rows.Err()
}

// distinct drops duplicates and sorts, so Recompute always locks students in the same order.
func distinct(ids []int64) []int64 {
	seen := make(map[int64]bool, len(ids))
	out := make([]int64, 0, len(ids))
	for _, id := range ids {
		if id > 0 && !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

// validWeights rejects a settings payload that would leave every source at zero.
func validWeights(v map[string]float64, allowed []string) error {
	total := 0.0
	for k, n := range v {
		if !contains(allowed, k) {
			return response.BadRequest(fmt.Sprintf("%q is not a known weight (expected %v)", k, allowed))
		}
		if n < 0 || n > 1 {
			return response.BadRequest(fmt.Sprintf("%s must be between 0 and 1", k))
		}
		total += n
	}
	if total <= 0 {
		return response.BadRequest("At least one weight must be above zero")
	}
	return nil
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}
