"""End-to-end test for Phase 5 (notifications): inbox, read/hide, sending notices with scope rules,
sent history, automatic alerts (drives, shortlist, status, marks, skills) and device tokens.

Run against a database seeded with scripts/seed_demo.py (uses its users), ideally a scratch one:
  API_URL=http://localhost:8090/api/v1 python scripts/e2e_phase5.py
"""
import os
import random
import sys

import requests

B = os.environ.get("API_URL", "http://localhost:8080/api/v1")
ENV = os.path.join(os.path.dirname(__file__), "..", ".env")
ADMIN_PW = next(l.split("=", 1)[1].strip() for l in open(ENV) if l.startswith("ADMIN_PASSWORD="))
SFX = str(random.randint(100, 999))
PASS = FAIL = 0


def check(name, resp, status):
    global PASS, FAIL
    ok = resp.status_code == status
    PASS += ok
    FAIL += not ok
    print(f"  {'ok  ' if ok else 'FAIL'} {name} ({resp.status_code}){'' if ok else ' ' + resp.text[:300]}")
    return resp.json() if resp.headers.get("content-type", "").startswith("application/json") else None


def expect(name, cond, info=""):
    global PASS, FAIL
    PASS += bool(cond)
    FAIL += not cond
    print(f"  {'ok  ' if cond else 'FAIL'} {name} {info}")


def login(u, p):
    r = requests.post(f"{B}/auth/login", json={"username": u, "password": p})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["data"]["access_token"]}


req = lambda m, p, body=None, h=None, **kw: requests.request(m, B + p, json=body, headers=h, **kw)
inbox = lambda h, q="": req("GET", "/notifications?page_size=200" + q, h=h).json()
titles = lambda h: [n["title"] for n in inbox(h)["data"]]

A = login("admin", ADMIN_PW)
PRIYA, KAVYA, MEENA = login("priya", "Staff@1234"), login("kavya", "Staff@1234"), login("meena", "Staff@1234")
ARUN, ANJALI = login("25cs001", "Student@123"), login("25cs002", "Student@123")
PARENT = login("p9200000001", "Parent@123")  # parent of Arun + Anjali
students = {s["register_no"]: s for s in req("GET", "/students?page_size=100", h=A).json()["data"]}
depts = {d["code"]: d["id"] for d in req("GET", "/departments?all=true", h=A).json()["data"]}
classes = {c["label"]: c for c in req("GET", "/classes", h=A).json()["data"]}

print("== automatic alerts created by the demo seed")
t = titles(ARUN)
expect("Arun: new drive", any(x.startswith("New drive: Zoho") for x in t), t[:3])
expect("Arun: shortlisted / next round / selected", all(any(x.startswith(p) for x in t) for p in ["Shortlisted: Zoho", "Zoho: moved to the next round", "Selected: Zoho"]))
expect("Arun: marks published", any(x == "End Semester marks: CS3301" for x in t))
expect("Arun: skill recorded", any(x == "Skill recorded: Java" for x in t))
pt = titles(PARENT)
expect("parent gets child's selection + marks", any(x.startswith("Selected: Zoho") for x in pt) and any("marks:" in x for x in pt))
expect("parent doesn't get skill alerts", not any(x.startswith("Skill recorded") for x in pt))
sel = next(n for n in inbox(PARENT)["data"] if n["title"].startswith("Selected"))
expect("body names the student", "Arun Kumar" in sel["body"] and sel["type"] == "placement" and sel["sender_name"] == "Priya Raman", sel["body"])

print("== inbox actions")
req("POST", "/notifications", {"title": f"Throwaway {SFX}", "body": "x", "target_type": "user", "target_id": students["25CS001"]["id"]}, A)
uc = check("unread count", req("GET", "/notifications/unread-count", h=ARUN), 200)["data"]["unread"]
first = next(n for n in inbox(ARUN)["data"] if n["title"] == f"Throwaway {SFX}")
check("mark one read", req("POST", f"/notifications/{first['id']}/read", h=ARUN), 200)
expect("unread count dropped by 1", req("GET", "/notifications/unread-count", h=ARUN).json()["data"]["unread"] == uc - 1)
expect("is_read + read_at set", next(n for n in inbox(ARUN)["data"] if n["id"] == first["id"])["read_at"] is not None)
other = inbox(ANJALI)["data"][0]
check("can't mark someone else's", req("POST", f"/notifications/{other['id']}/read", h=ARUN) if other["id"] not in [n["id"] for n in inbox(ARUN)["data"]] else req("POST", "/notifications/999999/read", h=ARUN), 404)
f = inbox(ARUN, "&type=marks")
expect("filter by type", f["data"] and all(n["type"] == "marks" for n in f["data"]))
check("read all", req("POST", "/notifications/read-all", h=ARUN), 200)
expect("nothing unread", req("GET", "/notifications/unread-count", h=ARUN).json()["data"]["unread"] == 0 and inbox(ARUN, "&unread_only=true")["data"] == [])
check("hide one", req("DELETE", f"/notifications/{first['id']}", h=ARUN), 200)
expect("hidden from Arun only", first["id"] not in [n["id"] for n in inbox(ARUN)["data"]])
check("hide again 404", req("DELETE", f"/notifications/{first['id']}", h=ARUN), 404)

print("== sending notices (scope rules)")
body = lambda target, tid=None, parents=False, title=None: {"title": title or f"Notice {SFX}", "body": "Please read.", "target_type": target, "target_id": tid, "include_parents": parents}
users_total = req("GET", "/users?page_size=1", h=A).json()["meta"]["total"]
r = check("admin -> everyone", req("POST", "/notifications", body("all", title=f"All {SFX}"), A), 201)
expect("every active user", r["data"]["recipients"] == users_total, (r["data"]["recipients"], users_total))
roles = {x["slug"]: x["id"] for x in req("GET", "/roles", h=A).json()["data"]}
r = check("placement officer -> all students", req("POST", "/notifications", body("role", roles["student"], title=f"Students {SFX}"), PRIYA), 201)
n_students = req("GET", "/users?role=student&page_size=1", h=A).json()["meta"]["total"]
expect("every student", r["data"]["recipients"] == n_students, (r["data"]["recipients"], n_students))
r = check("HOD -> own department", req("POST", "/notifications", body("department", depts["CSE"]), KAVYA), 201)
check("HOD -> other department refused", req("POST", "/notifications", body("department", depts["ECE"]), KAVYA), 403)
cse2a = classes["CSE II-A"]
r = check("HOD -> CSE II-A with parents", req("POST", "/notifications", body("class", cse2a["id"], True, title=f"Class {SFX}"), KAVYA), 201)
expect("4 students + incharge + 3 parents = 8", r["data"]["recipients"] == 8, r["data"]["recipients"])
check("staff -> own class", req("POST", "/notifications", body("class", cse2a["id"]), MEENA), 201)
check("staff -> everyone refused", req("POST", "/notifications", body("all"), MEENA), 403)
check("staff -> a role refused", req("POST", "/notifications", body("role", roles["parent"]), MEENA), 403)
check("staff -> ECE student refused", req("POST", "/notifications", body("user", students["25EC001"]["id"]), MEENA), 403)
check("target id required", req("POST", "/notifications", body("class"), MEENA), 400)
check("student can't send", req("POST", "/notifications", body("user", students["25CS002"]["id"]), ARUN), 403)
check("empty title", req("POST", "/notifications", {**body("all"), "title": "  "}, A), 400)
n = next((x for x in inbox(ANJALI)["data"] if x["title"] == f"Class {SFX}"), None)
expect("Anjali received class notice from Kavya", n and n["sender_name"] == "Kavya Srinivasan")
expect("parent received class notice", any(x == f"Class {SFX}" for x in titles(PARENT)))
expect("ECE student didn't", f"Class {SFX}" not in titles(login("25ec001", "Student@123")))
sent = check("sent history (HOD)", req("GET", "/notifications/sent", h=KAVYA), 200)["data"]
mine = next(s for s in sent if s["title"] == f"Class {SFX}")
expect("target label + counts", mine["target_label"] == "CSE II-A" and mine["recipients"] == 8 and mine["read_count"] == 0, mine)
expect("HOD sees only own notices", all(s["sender_name"] == "Kavya Srinivasan" for s in sent))
expect("admin sees everyone's", {s["sender_name"] for s in req("GET", "/notifications/sent", h=A).json()["data"]} >= {"Kavya Srinivasan", "Priya Raman", "Meena Devi"})
expect("automatic alerts not in sent history", not any(s["title"].startswith("Selected") for s in req("GET", "/notifications/sent", h=A).json()["data"]))
check("student can't see sent history", req("GET", "/notifications/sent", h=ARUN), 403)

print("== automatic: new drive -> eligible students only, once")
LAK, MOHAN = login("25ec001", "Student@123"), login("25ec002", "Student@123")
skills = {s["name"]: s["id"] for s in req("GET", "/skills?all=true", h=A).json()["data"]}
co = check("company", req("POST", "/companies", {"name": f"Bosch {SFX}"}, PRIYA), 201)["data"]
rb = {"company_id": co["id"], "title": f"Embedded Engineer {SFX}", "package_lpa": 5, "min_cgpa": 0, "max_backlogs": 5, "status": "upcoming",
      "department_ids": [depts["ECE"]], "skills": [{"skill_id": skills["Embedded C"], "required_level": 3, "is_mandatory": True}]}
role = check("upcoming drive", req("POST", "/job-roles", rb, PRIYA), 200)["data"]
drive = f"New drive: Bosch {SFX} - Embedded Engineer {SFX}"
expect("upcoming: nobody notified yet", drive not in titles(LAK))
check("open the drive", req("PATCH", f"/job-roles/{role['id']}/status", {"status": "open"}, PRIYA), 200)
expect("eligible student notified", drive in titles(LAK))
expect("ineligible student not notified", drive not in titles(MOHAN))
req("PATCH", f"/job-roles/{role['id']}/status", {"status": "closed"}, PRIYA)
req("PATCH", f"/job-roles/{role['id']}/status", {"status": "open"}, PRIYA)
expect("re-opening doesn't notify twice", titles(LAK).count(drive) == 1)

print("== automatic: shortlist + status changes (student and parents)")
LPAR = login("p9200000010", "Parent@123") if req("POST", "/auth/login", {"username": "p9200000010", "password": "Parent@123"}).status_code == 200 else None
if LPAR is None:  # give Lakshmi's parent a password for the test
    pid = req("GET", "/parents?search=9200000010", h=A).json()["data"][0]["id"]
    req("PUT", f"/users/{pid}/password", {"password": "Parent@123"}, A)
    LPAR = login("p9200000010", "Parent@123")
check("shortlist Lakshmi", req("POST", f"/job-roles/{role['id']}/shortlist", {"student_ids": [students["25EC001"]["id"]]}, PRIYA), 200)
short = f"Shortlisted: Bosch {SFX} - Embedded Engineer {SFX}"
expect("student + parent told about shortlist", short in titles(LAK) and short in titles(LPAR))
app = req("GET", f"/job-roles/{role['id']}/applications", h=PRIYA).json()["data"][0]
before = len(titles(LAK))
check("-> applied", req("PATCH", f"/applications/{app['id']}", {"status": "applied"}, PRIYA), 200)
expect("'applied' sends nothing", len(titles(LAK)) == before)
check("-> in process", req("PATCH", f"/applications/{app['id']}", {"status": "in_process"}, PRIYA), 200)
check("-> in process again", req("PATCH", f"/applications/{app['id']}", {"status": "in_process", "remarks": "HR round"}, PRIYA), 200)
expect("next-round notice sent once", titles(LAK).count(f"Bosch {SFX}: moved to the next round") == 1)
check("-> selected", req("PATCH", f"/applications/{app['id']}", {"status": "selected"}, PRIYA), 200)
expect("parent told about selection", f"Selected: Bosch {SFX} - Embedded Engineer {SFX}" in titles(LPAR))
check("clean-up: withdraw selection", req("PATCH", f"/applications/{app['id']}", {"status": "withdrawn"}, PRIYA), 200)
req("PATCH", f"/job-roles/{role['id']}/status", {"status": "closed"}, PRIYA)

print("== automatic: marks (only changed students) and skills (only when level changes)")
subj = {s["code"]: s["id"] for s in req("GET", "/subjects?all=true", h=A).json()["data"]}
exams = {e["code"]: e["id"] for e in req("GET", "/exam-types", h=A).json()["data"]}
k = {"class_id": cse2a["id"], "semester_id": cse2a["current_semester_id"], "subject_id": subj["CS3301"], "exam_type_id": exams["IA1"], "attempt_no": 1}
grid = req("GET", "/marks/entry", h=MEENA, params=k).json()["data"]["rows"]
same = [{"student_id": r["student_id"], "marks_obtained": r["marks_obtained"], "is_absent": r["is_absent"]} for r in grid]
BHA, DIV = login("25cs003", "Student@123"), login("25cs004", "Student@123")
count = lambda h: titles(h).count("Internal Assessment 1 marks: CS3301")
b0, d0 = count(BHA), count(DIV)
check("re-save identical marks", req("PUT", "/marks/entry", {**k, "entries": same}, MEENA), 200)
expect("no new marks notice", count(BHA) == b0 and count(DIV) == d0)
changed = [dict(e, marks_obtained=(e["marks_obtained"] or 0) + 1) if e["student_id"] == students["25CS003"]["id"] else e for e in same]
check("change Bharath's mark", req("PUT", "/marks/entry", {**k, "entries": changed}, MEENA), 200)
expect("only Bharath notified", count(BHA) == b0 + 1 and count(DIV) == d0)
check("restore", req("PUT", "/marks/entry", {**k, "entries": same}, MEENA), 200)
java = lambda h: titles(h).count("Skill recorded: Java")
j0 = java(DIV)
cur = next(x["proficiency"] for x in req("GET", f"/students/{students['25CS004']['id']}/skills", h=MEENA).json()["data"] if x["name"] == "Java")
nxt = 3 if cur != 3 else 4
check("same skill level again", req("PUT", f"/students/{students['25CS004']['id']}/skills", {"skill_id": skills["Java"], "proficiency": cur}, MEENA), 200)
expect("no notice for unchanged level", java(DIV) == j0)
check("change skill level", req("PUT", f"/students/{students['25CS004']['id']}/skills", {"skill_id": skills["Java"], "proficiency": nxt}, MEENA), 200)
names = {3: "Intermediate", 4: "Advanced"}
expect("student notified of new level", java(DIV) == j0 + 1 and f"level {nxt} of 5 ({names[nxt]})" in next(n["body"] for n in inbox(DIV)["data"] if n["title"] == "Skill recorded: Java"))

print("== device tokens")
tok = f"ExponentPushToken[test-{SFX}]"
check("register token (Arun)", req("POST", "/device-tokens", {"token": tok, "platform": "android"}, ARUN), 200)
check("same device, Anjali signs in", req("POST", "/device-tokens", {"token": tok, "platform": "android"}, ANJALI), 200)
check("Arun can't remove a token now owned by Anjali (no-op)", req("DELETE", "/device-tokens", {"token": tok}, ARUN), 200)
check("Anjali removes it", req("DELETE", "/device-tokens", {"token": tok}, ANJALI), 200)
check("token required", req("POST", "/device-tokens", {"platform": "ios"}, ARUN), 400)
check("no token -> 401", req("GET", "/notifications"), 401)

print(f"\nPASSED={PASS} FAILED={FAIL}")
sys.exit(1 if FAIL else 0)
