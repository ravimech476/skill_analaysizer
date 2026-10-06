# Skills Analyzer

College app for admin, staff, students and parents: academic records, mark history,
student skills, placement drives, and a **skill analyzer** that ranks students against a
company job role's required skills.

| Part | Stack | Folder | Status |
|---|---|---|---|
| API | Go + Gin + pgx, PostgreSQL | `backend/` | Phases 1–5 done: auth, RBAC, academic setup, classes, staff, students + parents, Excel bulk upload, marks + CGPA, skills, placement, **skill analyzer**, notifications, year-end promotion |
| Web | React + Vite + TypeScript + antd | `web/` | Phases 1–5: all modules above plus a notification bell and inbox; students/parents get My Marks, My Skills, Placement Drives and Skill Gap |
| Mobile | React Native (Expo SDK 57) | `mobile/` | same features; bulk upload is web-only (mobile shows upload history) |

Both apps serve **every user type** (admin, staff/HOD/placement officer, student, parent). Menus, tiles and
labels come from one config (`web/src/auth/access.ts`, copied to `mobile/src/auth/access.ts`; keep them in sync).
A feature appears when the user's roles grant any of its permissions, and its label adapts: a parent sees
"My Children / Children's Marks", a student sees "My Marks / Skill Gap". Modules not built yet show "Coming soon".

## Running everything

```bash
cd backend && go run ./cmd/api                 # API      http://localhost:8080
cd web && npm install && npm run dev -- --port 5180    # Web      http://localhost:5180
cd mobile && npm install && npx expo start     # Mobile   scan the QR with Expo Go (or press w for web on :8081)
```

On a real phone, `localhost` means the phone itself. Create `mobile/.env` with
`EXPO_PUBLIC_API_URL=http://<your-PC-LAN-IP>:8080/api/v1`. The Android emulator reaches the PC through `10.0.2.2`, and that address is the default.
The API's `CORS_ORIGINS` must list the web origins (defaults: 5180 web, 8081 Expo web). Port 5173 is avoided because another local app already uses it.

## Backend quick start

```bash
cd backend
cp .env.example .env        # set DATABASE_URL, JWT_SECRET, ADMIN_PASSWORD
go run ./cmd/migrate up     # creates all tables + seeds roles/permissions/masters + first admin
go run ./cmd/api            # http://localhost:8080  (also auto-migrates when AUTO_MIGRATE=true)
```

`go run ./cmd/migrate status` lists migrations. Migrations are plain SQL in
`backend/migrations/NNNNNN_name.up.sql`, embedded into the binary and applied in order,
each in its own transaction. Never edit an applied migration; add a new file.

## Database conventions

- Every table has `id, is_active, created_at, created_by, updated_at, updated_by`.
  `updated_at` is maintained by a trigger.
- Delete = `is_active = false`. Unique indexes are partial (`WHERE is_active`), so values free up after deactivation.
- A user can hold **multiple roles** (`user_roles`). Permissions are `module.action` slugs (`placement.create`),
  granted to roles via `role_permissions`. The `admin` role always passes every check.
- Class incharge lives on `classes.class_incharge_id` (one class row per dept/year/section per academic year),
  and HOD on `departments.hod_id`.
- Parent ↔ student is `student_parents` (a parent may have several children, a student several guardians).
- `users.mobile` is intentionally not unique; a student and parent often share a number.

## Auth

| Endpoint | Purpose |
|---|---|
| `POST /api/v1/auth/login` | username/email + password |
| `POST /api/v1/auth/otp/request` → `/otp/verify` | OTP login by username or mobile |
| `POST /api/v1/auth/password/forgot` → `/password/reset` | reset password via OTP (signs out all devices) |
| `POST /api/v1/auth/refresh` | rotates the refresh token; a replayed old token revokes all sessions |
| `POST /api/v1/auth/logout`, `GET /auth/me`, `POST /auth/password/change` | |

- **Tokens:** the access token is a JWT that expires after 15 minutes. The refresh token is an opaque string, stored as a SHA-256 hash, and lasts 30 days.
- **OTP rules:** 6 digits, valid for 5 minutes, one resend per 60 seconds, locked after 5 wrong tries. The stored hash is an HMAC bound to the user and the purpose, so a password-reset OTP can't be used to log in.
- **Shared mobiles:** if two accounts share a mobile number, OTP requests by that number are rejected with 409, and the user must enter their username instead.
- **SMS:** `internal/sms` ships a `ConsoleSender` that only logs the message. Implement `sms.Sender` for a real gateway.
  `OTP_DEBUG=true` (dev only; refused in production) also returns the code in the API response.

## Users / roles / permissions

- `GET/POST /users`, `GET/PUT /users/:id`, `PATCH /users/:id/status`, `PUT /users/:id/roles`, `PUT /users/:id/password`
  (list filters: `search, role, department_id, status, page, page_size`)
- `GET/POST /roles`, `GET/PUT/DELETE /roles/:id`, `PUT /roles/:id/permissions`
- `GET /permissions` (grouped by module; `?flat=true` for a plain list)

**Guards:**
- Only an admin can assign the admin role.
- An admin can't remove their own admin role or deactivate themselves.
- System roles can't be deleted.
- A role that is still assigned to users can't be deleted.

## Phase 2 API

| Area | Endpoints |
|---|---|
| Academic masters | `/departments`, `/academic-years`, `/subjects`, `/exam-types` (list/get/create/update/`PATCH :id/status`/delete) · read-only `/year-levels`, `/semesters` |
| Curriculum | `GET /curriculum?department_id=&semester_id=`, `POST /curriculum {department_id, semester_id, subject_ids}`, `DELETE /curriculum/:id` |
| Classes | `/classes` (defaults to the current academic year) with `class_incharge_id`; one class per incharge per year |
| Staff | `/staff` (user + staff profile + staff/hod/placement_officer roles), `PATCH /staff/:id/status` |
| Students | `/students`, `/students/:id/parents` (link by existing parent id or name + mobile), `GET /parents?search=` |
| Bulk upload | `GET /bulk-upload/students/template`, `POST /bulk-upload/students` (multipart `file`, `dry_run`, `create_missing_classes`, `default_password`), `/bulk-upload/jobs[/:id[/errors.xlsx]]` |

- **Master CRUD:** simple lookup tables use the config-driven engine in `internal/modules/master`. Adding one is a `Resource` entry in `resources.go`.
- **Who sees which students:**
  - admin and placement officer: every student
  - HOD and staff: students in their own department
  - parent: only their linked children
  - student: only themselves
- **Parents:** a parent is matched by mobile number among existing parent accounts, so siblings share one parent login. New parents get the username `p<mobile>` and log in with OTP.
- **Bulk upload rows:** each row is processed in its own transaction, so a bad row is reported and skipped without affecting the rest. A dry run validates every row and saves nothing.

## Phase 3 API: marks

| Endpoint | Purpose |
|---|---|
| `GET /marks/my-subjects` | class × semester × subject combinations the user may enter marks for (current academic year) |
| `GET /marks/entry?class_id&semester_id&subject_id&exam_type_id&attempt_no` | mark-entry grid (roster, saved marks, stats, `can_edit`) |
| `PUT /marks/entry` | save the grid: `entries: [{student_id, marks_obtained, is_absent}]`; null + not absent clears an entry |
| `GET /marks/sheet?class_id&semester_id&exam_type_id` | class result sheet (every subject, every student, per-subject stats) |
| `GET /marks/students/:id` | a student's history by semester (SGPA, CGPA, backlogs, every exam and attempt), scoped like students |
| `/subject-allocations` | who teaches which subject to which class (the `staff_history` requirement) |
| `/grade-scales` | grade scale for final exams (O / A+ / A / B+ / B / C / U by default) |

- **Who can enter marks:**
  - an admin
  - the HOD of the class's department
  - the class incharge
  - staff allocated to that subject for that class and semester
- **Internal exams:** pass when the mark reaches the exam type's `pass_percent`.
- **Final exams:** graded with the grade scale, and the grade point is stored with the mark.
- **CGPA and backlogs:** CGPA = Σ credits × grade point ÷ Σ credits, over the latest attempt of each passed subject. Backlogs = subjects whose latest final attempt failed or was absent. Both are recalculated whenever final marks are saved.
- **Arrears:** entered as `attempt_no` 2 or higher. The roster lists only the students who failed the previous attempt.
- **Current semester:** each class has a `current_semester_id`, which defaults to the odd semester of its year. Mark entry and allocations use it by default.
- **Enrollment:** saving marks also records the student's enrollment (student × class × academic year × semester).

## Phase 4 API: skills, placement and the skill analyzer

| Endpoint | Purpose |
|---|---|
| `/skills`, `/companies` | masters (25 common skills are seeded) |
| `GET/PUT /students/:id/skills`, `DELETE /students/:id/skills/:skillId` | a student's skills (level 1–5, source). Only staff and admins write; access is scoped like students |
| `GET /student-skills/matrix?class_id=` | class × skill grid |
| `/job-roles` (+ `PATCH :id/status`) | drives: company, package, dates, min CGPA, max backlogs, batch, eligible departments, required skills (level, weight, mandatory) |
| `POST /job-roles/:id/analyze`, `GET /job-roles/:id/matches` | run the skill analyzer / read the cached ranking |
| `POST /job-roles/:id/shortlist`, `GET /job-roles/:id/applications`, `PATCH /applications/:id` | pipeline: shortlisted → applied → in_process → selected / rejected / withdrawn |
| `GET /placements`, `GET /placements/stats` | placement records and statistics (by department and company) |
| `GET /students/:id/opportunities` | the student / parent view: every open drive with eligibility, match % and missing skills |

**How the skill analyzer works** (`internal/modules/placement/analyzer.go`):
1. **Eligibility:** the student is checked against the role's departments, batch, minimum CGPA, maximum backlogs and mandatory skills (level ≥ required). A student already placed at a package ≥ this role's package is ineligible, since placed students may only take higher offers. Each failed check is listed as a reason.
2. **Skill score:** Σ weight × min(student level ÷ required level, 1) ÷ Σ weight × 100.
3. **Final score:** 0.7 × skill score + 0.3 × (CGPA × 10). Eligible students are ranked first, then by final score.
4. **Cache:** results go into `skill_match_results`. An HOD's run only replaces results for their own department.

- **Selecting a student** creates a placement record. The higher-package rule is checked again at that point. Moving an application out of "selected" withdraws the record.
- **Who sees what:** rankings, applications and placement lists are for staff only. Students and parents see only their own opportunities and skills.

## Phase 5 API: notifications

| Endpoint | Purpose |
|---|---|
| `GET /notifications?unread_only&type&page` | my inbox (+ `unread` count) |
| `GET /notifications/unread-count`, `POST /notifications/:id/read`, `POST /notifications/read-all`, `DELETE /notifications/:id` | badge, read, hide from my inbox |
| `POST /notifications` | send a notice to `all`, a `role`, a `department`, a `class` or one `user`, with `include_parents` |
| `GET /notifications/sent` | notices I sent (admins see everyone's), with read counts |
| `POST/DELETE /device-tokens` | register or unregister a phone's Expo push token |

- **Who can send to whom:** admins and placement officers can notify anyone. HODs and staff can only notify their own department, its classes or its students.
- **Automatic alerts** (sent through `internal/notify`, after the triggering change has been saved):
  - a drive opening for the first time goes to eligible students
  - shortlisted, next round, selected or rejected goes to the student and their parents
  - new or changed marks go to that student and their parents (one generic message, no scores)
  - a skill level being recorded or changed goes to the student
- **Push:** set `PUSH_ENABLED=true` to deliver through Expo's push service. It is off by default, so development never calls an outside service.

## Phase 6 API: year-end and student lifecycle

| Endpoint | Purpose |
|---|---|
| `POST /lifecycle/semester-change {class_ids, direction}` | move classes to the next or previous semester of their year and enrol their students. HODs are limited to their own department |
| `POST /lifecycle/promotion/preview {from_year_id, to_year_id}` | a dry run: per class, the target class (or "passed out") and its students with CGPA and backlogs |
| `POST /lifecycle/promotion` | run it: `detained_student_ids`, `carry_incharge`, `set_current`. One transaction; a year pair can only be promoted once |
| `GET /lifecycle/promotions` | promotion history with counts |
| `POST /students/:id/lifecycle {action: discontinue\|readmit, class_id, remarks}` | discontinue or re-admit a student |
| `GET /students/:id/history` | the student's semester-by-semester enrollment history, scoped like the profile |

- **What promotion does:**
  - Each class moves up a year into the same department and section in the new academic year (CSE II-A → CSE III-A). The new class is created if needed, starts in the odd semester, and can keep its incharge.
  - Detained students repeat their year in the same-level class of the new year.
  - Final-year students become alumni (`lifecycle_status = passed_out`, `passed_out_year`). They keep their login and their marks and placement history.
- **Enrollment history:** `student_enrollments` keeps every semester, marked studying, promoted, detained, passed out or discontinued.
- **Filtering:** student lists accept `lifecycle=studying|passed_out|discontinued`. The skill analyzer only ranks students who are currently studying.

## Phase 7 API: bulk tools and reports

**Excel uploads.** Every upload takes `dry_run=true`, is recorded in `bulk_upload_jobs` (`GET /bulk-upload/jobs?upload_type=`) and offers an error report (`/bulk-upload/jobs/:id/errors.xlsx`).

| Endpoint | Who | Notes |
|---|---|---|
| `GET /marks/entry/template?class_id=&semester_id=&subject_id=&exam_type_id=&attempt_no=` | staff who can enter the marks | roster pre-filled with existing marks; an Info sheet pins the file to that class · subject · exam |
| `POST /marks/entry/upload` (multipart: `file` + the same keys) | same | a number or `AB`; blank = unchanged. **All-or-nothing**: any bad row means nothing is saved. A template for another exam is refused. Grading, CGPA and notifications run as for the grid |
| `GET /bulk-upload/staff/template`, `POST /bulk-upload/staff` | `staff.create` | employee code = username; roles `staff,hod,placement_officer`; optional `default_password` |
| `GET /bulk-upload/skills/template?class_id=`, `POST /bulk-upload/skills` | `student_skill.create` | register no + skill + level 1–5; staff limited to their department; one combined notice per student |

**Exports** reuse the permission and data scope of what they export:

| Endpoint | File |
|---|---|
| `GET /marks/sheet.xlsx?class_id=&semester_id=&exam_type_id=` | class result sheet + per-subject summary |
| `GET /marks/students/:id/statement.pdf` | student mark statement. Students get their own and parents their children's. The college name comes from `COLLEGE_NAME` |
| `GET /students/export.xlsx` (list filters) | student list with primary parent (staff only) |
| `GET /placements.xlsx` (list filters) | placement records + by-company summary |
| `GET /job-roles/:id/matches.xlsx?eligible_only=` | analyzer ranking with reasons and skill gaps |

**Dashboard** (`GET /reports/dashboard?department_id=&exam_type_id=`, permission `report.view`, migration 000008) shows:
- headline numbers
- pass % by class for one exam (papers passed, and students who cleared every subject)
- CGPA spread by department
- skill gaps: for each skill the current drives ask for, the share of students who meet the highest level asked
- placement by batch, and offers per month over the last 12 months

HOD and staff always see their own department. Admins and placement officers can filter by department.

## Phase 8 API: file uploads

Files are uploaded first and attached second:
1. `POST /files` (multipart `file` + `category`) checks the real content, stores the file under `FILES_DIR` (default `backend/storage/`) and returns `{id, url, name, type, size}`.
2. The record then takes that `file_id`. A file can only be attached by the person who uploaded it, only once, and only to a slot of its category.

| Category | Allowed | Attached with |
|---|---|---|
| `profile_photo` | JPG/PNG/WebP ≤ 2 MB | `PUT /users/me/photo`, `PUT /users/:id/photo` (admin, or staff for students of their department) |
| `resume` | PDF ≤ 5 MB | `PUT /students/:id/resume` (the student or their department's staff) |
| `student_document` | PDF/image ≤ 5 MB | `POST /students/:id/documents {doc_type, title, file_id}` |
| `certificate` | PDF/image ≤ 5 MB | `PUT /students/:id/skills` with `certificate_file_id` (`remove_certificate: true` clears it) |
| `offer_letter` | PDF/image ≤ 5 MB | `PUT /placements/:id/offer-letter` |
| `company_logo` | image ≤ 1 MB | `PUT /companies/:id/logo` |
| `job_description` | PDF ≤ 5 MB | `PUT /job-roles/:id/jd` |
| `notification_attachment` | PDF/image ≤ 10 MB | `attachment_file_id` on `POST /notifications` |

Send `{file_id: null}` to a slot to remove its file.

- **Reading files:** records return a file as `{url, name, type, size}`. The `url` is relative to the API root, signed, and valid for 1–2 hours. `GET /files/:uuid?exp=&sig=` checks only the signature, so images and downloads work without a login header. Access is decided by the API that returned the link. Add `&download=1` to force a download.
- **Student documents:** ID proof, mark sheets, certificates and similar.
  - `GET /students/:id/documents` is scoped like the student profile, so parents can read their children's.
  - A student's own upload stays pending until staff verify it; staff uploads are verified straight away.
  - Staff use `PATCH …/documents/:docId {status, remarks}`; a rejection needs a reason, and the student and parents are notified.
  - The verification queue is `GET /documents/pending` (own department for HOD and staff).
  - Permissions `document.view|create|verify|delete` come from migration 000009.
- **Cleanup:** an hourly job removes uploads never attached within a day, and the bytes of replaced or removed files after 7 days.
- **Storage:** everything goes through a `files.Store` interface (local disk today), so an S3-style store can be added later.

## Tests & demo data

- `bash backend/scripts/e2e_auth.sh` runs the Phase 1 auth/RBAC checks (45). It needs a fresh DB.
- `python backend/scripts/e2e_phase2.py` runs the Phase 2 checks (97), including data scoping and the Excel import. It needs the admin and priya accounts, and can be re-run.
- `python backend/scripts/e2e_phase3.py` runs the Phase 3 checks (81): allocation rules, grading, CGPA and SGPA values, arrears, scoping and the result sheet. It can be re-run.
- `python backend/scripts/e2e_phase4.py` runs the Phase 4 checks (105): exact analyzer scores and ranking, eligibility reasons, the higher-package rule, shortlist and selection, placement stats, and student / parent views. It can be re-run.
- `python backend/scripts/e2e_phase5.py` runs the Phase 5 checks (74). They need the demo users and can be re-run.
- `python backend/scripts/e2e_phase6.py` runs the Phase 6 checks (76). They use their own far-future academic years, so a promotion never touches real data.
- `python backend/scripts/e2e_phase8.py` runs the Phase 8 checks (117): upload validation (HTML or SVG disguised as images, size limits), signed-link tampering and expiry, who may attach what, document verification, and every file slot. `go test ./internal/files/` unit-tests signing, name cleaning and path-traversal protection. Run a separate test API with `FILES_DIR=storage_test`.
- `python backend/scripts/e2e_phase7.py` runs the Phase 7 checks (136) for uploads, exports and the dashboard. They put back every mark and skill they change, and can be re-run.
- **Run the tests against a separate test instance so your demo data stays clean.** The scripts create their own departments and students, and every script reads `API_URL`:
  1. Create a test database (`CREATE DATABASE skills_analyzer_test`).
  2. Start a second API on it: `PORT=8090 DATABASE_URL=postgres://…/skills_analyzer_test go run ./cmd/api`.
  3. Load the demo data into it: `API_URL=http://localhost:8090/api/v1 python scripts/seed_demo.py`.
  4. Run the suites with the same `API_URL`.
- `python backend/scripts/seed_demo.py` fills a fresh DB with demo data (it also runs `seed_demo_marks.py` and `seed_demo_placement.py`):
  - 3 departments and 4 staff, with HODs and class incharges
  - 4 classes and a curriculum
  - 12 students with their parents
  - subject allocations and IA1 / IA2 / end-semester marks for CSE II-A
  - student skills, 3 companies with drives (Zoho, TCS, Infosys), an analyzer run and shortlists; Arun is placed at Zoho
  - demo logins: `priya`, `kavya` and `meena` with password `Staff@1234`; `25cs001` with `Student@123`; `p9200000001` with `Parent@123`

## Roadmap

1. **Done:** schema (34 tables), auth (password + OTP), RBAC, users, roles, plus the web and mobile apps for all user types.
2. **Done:** academic masters, curriculum, classes + incharge, staff and student profiles, parent links, **student bulk upload** (Excel), on web and mobile.
3. **Done:** subject allocation, mark entry (internal, end semester, arrears), grading, CGPA / SGPA / backlogs, class result sheets, student mark history, on web and mobile.
4. **Done:** skills, companies, job roles, **skill analyzer**, shortlisting, applications, placement records and statistics, and student skill-gap views, on web and mobile.
5. **Done:** notifications: in-app inbox and bell, sending notices with scope rules, automatic alerts for placement, marks and skills, and Expo push (turned on with `PUSH_ENABLED`).
6. **Done:** year-end: semester change, year promotion with detention and pass-out, alumni, discontinue / re-admit, and per-semester student history.
7. **Done:** bulk tools and reports: Excel upload for marks, staff and student skills; result sheet, mark statement (PDF), student list, placement report and ranking exports; and the analytics dashboard.
8. **Done:** file uploads: profile photos, resumes, student documents with staff verification, skill certificates, offer letters, company logos, job descriptions and notice attachments, on web and mobile.
9. **Next:** production: SMS gateway for OTP, deployment and app-store builds.
Each module ships its backend API together with its web and mobile screens, replacing the "Coming soon" pages.
