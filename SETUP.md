# Running Skills Analyzer on another machine

Three parts share one database: a Go API, a React web app and a Flutter phone app.
Start the API first — the other two only show connection errors without it.

## 1. Install the tools

| Need | Why | Check |
| --- | --- | --- |
| [Go 1.25+](https://go.dev/dl/) | the API | `go version` |
| [PostgreSQL 17+](https://www.postgresql.org/download/) | the database | `psql --version` |
| [Node 20+](https://nodejs.org/) | the web app | `node -v` |
| [Flutter 3.27+](https://docs.flutter.dev/get-started/install) | the phone app, optional | `flutter --version` |

Flutter also needs Android Studio for the Android SDK, and that part is only required
if you want the phone app. The API and the web app are enough to use the system.

## 2. Create the database

```bash
createdb -U postgres skills_analyzer
```

If `database.sql` came with this zip, load it — it carries the demo college, its
students, marks, skills and placement drives:

```bash
psql -U postgres -d skills_analyzer -f database.sql
```

Without it you still get a working but empty system: the API creates every table on
first start, and `backend/scripts/seed_demo.py` fills in demo data (needs Python and
`pip install requests`).

## 3. Configure the API

Secrets are not in this zip. Copy the template and fill it in:

```bash
cd backend
copy .env.example .env
```

Three lines matter:

```ini
DATABASE_URL=postgres://postgres:YOUR_PASSWORD@localhost:5432/skills_analyzer?sslmode=disable
JWT_SECRET=<any long random string — generate your own>
ADMIN_PASSWORD=<the password for the first admin>
```

`ADMIN_PASSWORD` only takes effect when no admin exists yet. If you loaded
`database.sql`, the admin account came with it and keeps **its original password** —
ask whoever sent you the zip. To reset it, delete the admin row and restart the API:

```bash
psql -U postgres -d skills_analyzer -c "UPDATE users SET is_active = false WHERE username = 'admin';"
```

## 4. Run it

Each of these holds its terminal, so use a separate one for each.

**API** — http://localhost:8080

```bash
cd backend
go run ./cmd/api
```

Tables are created and migrated automatically on start. Check it with
http://localhost:8080/health.

**Web app** — http://localhost:5180

```bash
cd web
npm install
npm run dev
```

The port is pinned in `vite.config.ts` and must stay 5180, because the API's
`CORS_ORIGINS` allows only that origin. On a different port the page loads and every
API call then fails.

**Phone app** — optional

```bash
cd mobile_flutter
flutter pub get
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_URL=http://localhost:8080/api/v1
```

`adb reverse` points the phone's own `localhost:8080` at the API on the computer, which
avoids hunting for its IP address and opening a firewall port. Re-run it each time the
phone reconnects. `mobile_flutter/README.md` covers wireless setup and release builds.

## Logging in

The demo accounts that come with `database.sql`:

| User | Password | Sees |
| --- | --- | --- |
| `priya` | `Staff@1234` | staff + placement officer |
| `kavya` | `Staff@1234` | HOD |
| `meena` | `Staff@1234` | staff, class incharge |
| `25cs001` | `Student@123` | one student |
| `p9200000001` | `Parent@123` | a parent |

## When something will not start

**`bind: Only one usage of each socket address`** — port 8080 is already taken, usually
by an API you started earlier.

```bash
netstat -ano | findstr :8080
taskkill /PID <the pid> /F
```

**The web app loads but every request fails** — it is not on port 5180, or the API is
not running. The browser console shows a CORS error in the first case.

**`password authentication failed`** — `DATABASE_URL` in `backend/.env` does not match
your Postgres password.

**Flutter: `Could not close incremental caches`** — the project and the pub cache are on
different drives. `android/gradle.properties` already sets `kotlin.incremental=false`
for this; if it still happens, put the project on the same drive as your pub cache.

## Repacking

From the project root:

```bash
powershell -ExecutionPolicy Bypass -File .\package-for-sharing.ps1
```

It drops `node_modules`, build output and compiled binaries — about 2.7 GB of the 2.7 GB
total — dumps the database alongside the source, and leaves secrets out.
