"""End-to-end test for Phase 4 (skills, job roles, skill analyzer, shortlist, applications, placements).

Builds its own department, class, students (CGPA set through real end-semester marks) and job roles with a
random suffix, so it can be re-run. Needs the API on :8080 (OTP_DEBUG=true) and the demo staff user priya
(placement officer). Usage: python scripts/e2e_phase4.py
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
    return resp.json().get("data") if resp.headers.get("content-type", "").startswith("application/json") else None


def expect(name, cond, info=""):
    global PASS, FAIL
    PASS += bool(cond)
    FAIL += not cond
    print(f"  {'ok  ' if cond else 'FAIL'} {name} {info}")


def login(u, p):
    r = requests.post(f"{B}/auth/login", json={"username": u, "password": p})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["data"]["access_token"]}


A = login("admin", ADMIN_PW)
PO = login("priya", "Staff@1234")  # staff + placement officer
req = lambda m, p, body=None, h=A, **kw: requests.request(m, B + p, json=body, headers=h, **kw)

print("== setup: department, class, students with CGPA from real marks")
dept = check("department", req("POST", "/departments", {"name": "Placement Dept " + SFX, "code": "PL" + SFX}), 201)
other = check("other department", req("POST", "/departments", {"name": "Other Dept " + SFX, "code": "PO" + SFX}), 201)
sems = {s["sem_no"]: s["id"] for s in req("GET", "/semesters").json()["data"]}
levels = {l["level_no"]: l["id"] for l in req("GET", "/year-levels").json()["data"]}
exams = {e["code"]: e["id"] for e in req("GET", "/exam-types").json()["data"]}
year = next(y for y in req("GET", "/academic-years?all=true").json()["data"] if y["is_current"])
subj = check("subject", req("POST", "/subjects", {"code": "PL" + SFX, "name": "Placement Subject", "credits": 4}), 201)
req("POST", "/curriculum", {"department_id": dept["id"], "semester_id": sems[3], "subject_ids": [subj["id"]]})
cls = check("class", req("POST", "/classes", {"department_id": dept["id"], "academic_year_id": year["id"], "year_level_id": levels[2], "section": "A"}), 201)
st = {}
for key, pm in [("A", "01"), ("B", "02"), ("C", "03"), ("D", "04")]:
    st[key] = check(f"student {key}", req("POST", "/students", {"name": f"{key} {SFX}", "register_no": f"PL{SFX}{key}", "department_id": dept["id"],
                                                                "admission_year": 2025, "class_id": cls["id"], "password": "Student@123",
                                                                "parents": [{"name": f"P{key} {SFX}", "mobile": f"98700{SFX}{pm}", "relation": "father"}]}), 201)
st["E"] = check("student E (other dept)", req("POST", "/students", {"name": f"E {SFX}", "register_no": f"PO{SFX}E", "department_id": other["id"], "admission_year": 2025}), 201)
marks = {"A": 95, "B": 72, "C": 60, "D": 40}  # grades O / A / B / U -> CGPA 10 / 8 / 6 / 0 (+1 backlog)
check("end-semester marks", req("PUT", "/marks/entry", {"class_id": cls["id"], "semester_id": sems[3], "subject_id": subj["id"], "exam_type_id": exams["SEM"],
                                                        "attempt_no": 1, "entries": [{"student_id": st[k]["id"], "marks_obtained": v} for k, v in marks.items()]}), 200)
cg = {k: req("GET", f"/students/{st[k]['id']}").json()["data"] for k in "ABCD"}
expect("CGPAs 10 / 8 / 6 / 0", [cg[k]["cgpa"] for k in "ABCD"] == [10, 8, 6, 0], [cg[k]["cgpa"] for k in "ABCD"])

print("== skills")
skills = {s["name"]: s["id"] for s in check("skill master", req("GET", "/skills?all=true"), 200)}
expect("seeded skills present", {"Java", "SQL", "Communication", "Python"} <= set(skills), len(skills))
check("duplicate skill (case-insensitive)", req("POST", "/skills", {"name": "java"}), 409)
custom = check("new skill", req("POST", "/skills", {"name": "Kotlin " + SFX, "category": "programming"}), 201)
staff = check("dept staff", req("POST", "/staff", {"name": f"Stf {SFX}", "employee_code": f"PS{SFX}", "department_id": dept["id"], "password": "Staff@1234"}), 201)
ohod = check("other-dept HOD", req("POST", "/staff", {"name": f"Ohod {SFX}", "employee_code": f"PH{SFX}", "department_id": other["id"], "roles": ["staff", "hod"], "password": "Staff@1234"}), 201)
STF, OHOD = login(staff["username"], "Staff@1234"), login(ohod["username"], "Staff@1234")
SA = login(st["A"]["username"], "Student@123")
levels_of = {"A": {"Java": 4, "SQL": 3, "Communication": 3}, "B": {"Java": 5, "SQL": 4, "Communication": 4},
             "C": {"Java": 2, "SQL": 5}, "D": {"Java": 5, "SQL": 5, "Communication": 5}}
for k, sk in levels_of.items():
    for name, lvl in sk.items():
        r = req("PUT", f"/students/{st[k]['id']}/skills", {"skill_id": skills[name], "proficiency": lvl, "source": "assessment"}, STF)
        if r.status_code != 200:
            check(f"record {k} {name}", r, 200)
lst = check("student A skills", req("GET", f"/students/{st['A']['id']}/skills"), 200)
expect("3 skills, recorded_by staff", len(lst) == 3 and lst[0]["recorded_by"] == staff["name"])
check("update level (upsert)", req("PUT", f"/students/{st['A']['id']}/skills", {"skill_id": skills["Java"], "proficiency": 4, "source": "certification"}, STF), 200)
check("proficiency 6 rejected", req("PUT", f"/students/{st['A']['id']}/skills", {"skill_id": skills["Java"], "proficiency": 6}, STF), 400)
check("student can't record own skill", req("PUT", f"/students/{st['A']['id']}/skills", {"skill_id": skills["Go"], "proficiency": 5}, SA), 403)
check("other-dept HOD can't record", req("PUT", f"/students/{st['A']['id']}/skills", {"skill_id": skills["Go"], "proficiency": 3}, OHOD), 404)
check("student sees own skills", req("GET", f"/students/{st['A']['id']}/skills", h=SA), 200)
check("temp skill", req("PUT", f"/students/{st['B']['id']}/skills", {"skill_id": custom["id"], "proficiency": 2}, STF), 200)
check("remove skill", req("DELETE", f"/students/{st['B']['id']}/skills/{custom['id']}", h=STF), 200)
mx = check("class skill matrix", req("GET", f"/student-skills/matrix?class_id={cls['id']}", h=STF), 200)
expect("matrix 4 students x 3 skills", len(mx["rows"]) == 4 and len(mx["skills"]) == 3)
check("other-dept HOD can't open matrix", req("GET", f"/student-skills/matrix?class_id={cls['id']}", h=OHOD), 403)

print("== companies & job roles")
co = check("company", req("POST", "/companies", {"name": "Acme " + SFX, "industry": "IT Services", "location": "Chennai"}, PO), 201)
def role(title, pkg, **kw):
    body = {"company_id": co["id"], "title": title, "package_lpa": pkg, "min_cgpa": 7, "max_backlogs": 0, "status": "open",
            "department_ids": [dept["id"]], "drive_date": "2026-12-01", "last_apply_date": "2026-11-20",
            "skills": [{"skill_id": skills["Java"], "required_level": 4, "is_mandatory": True, "weight": 2},
                       {"skill_id": skills["SQL"], "required_level": 3, "weight": 1},
                       {"skill_id": skills["Communication"], "required_level": 3, "weight": 1}]}
    body.update(kw)
    return req("POST", "/job-roles", body, PO)
check("package 0 rejected", role("Bad", 0), 400)
check("apply date after drive rejected", role("Bad", 5, last_apply_date="2026-12-05"), 400)
check("unknown skill rejected", role("Bad", 5, skills=[{"skill_id": 999999, "required_level": 3}]), 400)
check("duplicate skill rejected", role("Bad", 5, skills=[{"skill_id": skills["SQL"], "required_level": 3}, {"skill_id": skills["SQL"], "required_level": 2}]), 400)
r1 = check("R1 Java Developer 6 LPA", role("Java Developer", 6), 200)
expect("role has 3 skills + 1 dept", len(r1["skills"]) == 3 and [d["id"] for d in r1["departments"]] == [dept["id"]])
check("student can view roles", req("GET", "/job-roles?status=open", h=SA), 200)
check("student can't create roles", role("X", 5) if False else req("POST", "/job-roles", {"company_id": co["id"], "title": "X", "package_lpa": 3}, SA), 403)
check("skill used by a role can't be deleted", req("DELETE", f"/skills/{skills['Java']}"), 409)

print("== skill analyzer")
res = check("analyze R1 (placement officer)", req("POST", f"/job-roles/{r1['id']}/analyze", h=PO), 200)
by = {m["student_id"]: m for m in res["matches"]}
order = [m["student_id"] for m in res["matches"] if m["student_id"] in {s["id"] for s in st.values()}]
expect("other-department student not ranked", st["E"]["id"] not in by)
expect("ranking A, B, D, C", order == [st[k]["id"] for k in "ABDC"], [next(k for k in st if st[k]["id"] == i) for i in order])
expect("A: skill 100, final 100, eligible", (by[st["A"]["id"]]["skill_score"], by[st["A"]["id"]]["final_score"], by[st["A"]["id"]]["is_eligible"]) == (100, 100, True))
expect("B: final 94", by[st["B"]["id"]]["final_score"] == 94, by[st["B"]["id"]]["final_score"])
c = by[st["C"]["id"]]
expect("C: skill 50, final 53, ineligible", (c["skill_score"], c["final_score"], c["is_eligible"]) == (50, 53, False), (c["skill_score"], c["final_score"]))
expect("C reasons: CGPA + Java", any("CGPA" in r for r in c["ineligible_reasons"]) and any("Java" in r for r in c["ineligible_reasons"]), c["ineligible_reasons"])
expect("C missing skills: Java, Communication", sorted(g["name"] for g in c["missing_skills"]) == ["Communication", "Java"])
d = by[st["D"]["id"]]
expect("D: skill 100 but ineligible (CGPA, backlogs)", d["skill_score"] == 100 and not d["is_eligible"] and any("backlog" in r for r in d["ineligible_reasons"]))
cached = check("cached ranking", req("GET", f"/job-roles/{r1['id']}/matches", h=PO), 200)
expect("cache matches live run", [m["student_id"] for m in cached["matches"]][:4] == order and cached["analyzed_at"])
el = check("eligible only", req("GET", f"/job-roles/{r1['id']}/matches?eligible_only=true", h=PO), 200)
expect("2 eligible", len([m for m in el["matches"] if m["student_id"] in by]) == 2)
check("student can't see ranking", req("GET", f"/job-roles/{r1['id']}/matches", h=SA), 403)
check("student can't run analyzer", req("POST", f"/job-roles/{r1['id']}/analyze", h=SA), 403)
oh = check("other-dept HOD analyzes (own dept only)", req("POST", f"/job-roles/{r1['id']}/analyze", h=OHOD), 200)
expect("HOD sees no students from other departments", all(m["student_id"] not in by for m in oh["matches"]))
still = req("GET", f"/job-roles/{r1['id']}/matches", h=PO).json()["data"]
expect("HOD run didn't wipe other departments' cache", st["A"]["id"] in [m["student_id"] for m in still["matches"]])

print("== shortlist, applications, placement rule")
staff_user = req("GET", "/users?search=priya").json()["data"][0]["id"]
sl = check("shortlist A, B, C, E, non-student", req("POST", f"/job-roles/{r1['id']}/shortlist", {"student_ids": [st[k]["id"] for k in "ABCE"] + [staff_user]}, PO), 200)
reasons = {s["student_id"]: s["reason"] for s in sl["skipped"]}
expect("added 2 (A, B)", sl["added"] == 2, sl)
expect("C skipped with reasons", "CGPA" in reasons.get(st["C"]["id"], ""))
expect("E skipped: department", "Department" in reasons.get(st["E"]["id"], ""))
expect("non-student skipped", "Not an active student" in reasons.get(staff_user, ""))
again = check("shortlist A again", req("POST", f"/job-roles/{r1['id']}/shortlist", {"student_ids": [st["A"]["id"]]}, PO), 200)
expect("A already shortlisted", again["added"] == 0 and "Already" in again["skipped"][0]["reason"])
apps = {a["student_id"]: a for a in check("applications", req("GET", f"/job-roles/{r1['id']}/applications", h=PO), 200)}
expect("2 applications with match score", len(apps) == 2 and apps[st["A"]["id"]]["match_score"] == 100)
check("student can't list applications", req("GET", f"/job-roles/{r1['id']}/applications", h=SA), 403)
check("invalid status", req("PATCH", f"/applications/{apps[st['A']['id']]['id']}", {"status": "hired"}, PO), 400)
check("A -> in process", req("PATCH", f"/applications/{apps[st['A']['id']]['id']}", {"status": "in_process", "remarks": "Round 2"}, PO), 200)
sel = check("A selected (6 LPA)", req("PATCH", f"/applications/{apps[st['A']['id']]['id']}", {"status": "selected"}, PO), 200)
expect("offer date set", sel["offer_date"] is not None)

r2 = check("R2 lower package 5 LPA", role("Support Engineer", 5), 200)
m2 = {m["student_id"]: m for m in req("POST", f"/job-roles/{r2['id']}/analyze", h=PO).json()["data"]["matches"]}
expect("A ineligible for a lower package", not m2[st["A"]["id"]]["is_eligible"] and any("Already placed" in r for r in m2[st["A"]["id"]]["ineligible_reasons"]))
expect("B still eligible", m2[st["B"]["id"]]["is_eligible"])
s2 = check("shortlist A for R2", req("POST", f"/job-roles/{r2['id']}/shortlist", {"student_ids": [st["A"]["id"], st["B"]["id"]]}, PO), 200)
expect("A refused, B added", s2["added"] == 1 and "Already placed" in s2["skipped"][0]["reason"])
b2 = next(a for a in req("GET", f"/job-roles/{r2['id']}/applications", h=PO).json()["data"] if a["student_id"] == st["B"]["id"])
check("B selected at 5 LPA", req("PATCH", f"/applications/{b2['id']}", {"status": "selected"}, PO), 200)
check("B selected at 6 LPA (higher) allowed", req("PATCH", f"/applications/{apps[st['B']['id']]['id']}", {"status": "selected"}, PO), 200)
check("selecting B back at 5 LPA refused", req("PATCH", f"/applications/{b2['id']}", {"status": "in_process"}, PO), 200)
check("…re-select lower package blocked", req("PATCH", f"/applications/{b2['id']}", {"status": "selected"}, PO), 409)

r3 = check("R3 higher package 9 LPA", role("Senior Developer", 9), 200)
s3 = check("shortlist A for R3", req("POST", f"/job-roles/{r3['id']}/shortlist", {"student_ids": [st["A"]["id"]]}, PO), 200)
expect("A allowed (higher package)", s3["added"] == 1)
a3 = req("GET", f"/job-roles/{r3['id']}/applications", h=PO).json()["data"][0]
check("A selected at 9 LPA", req("PATCH", f"/applications/{a3['id']}", {"status": "selected"}, PO), 200)
pl = check("placements list", req("GET", f"/placements?search=PL{SFX}", h=PO), 200)
expect("A has 2 offers, B has 1 active", sorted((p["register_no"], p["package_lpa"]) for p in pl) == sorted([(f"PL{SFX}A", 6), (f"PL{SFX}A", 9), (f"PL{SFX}B", 6)]), [(p["register_no"], p["package_lpa"]) for p in pl])
check("A rejected at R3 withdraws the offer", req("PATCH", f"/applications/{a3['id']}", {"status": "rejected"}, PO), 200)
pl = req("GET", f"/placements?search=PL{SFX}A", h=PO).json()["data"]
expect("A back to 1 offer", len(pl) == 1 and pl[0]["package_lpa"] == 6)
stats = check("placement stats", req("GET", f"/placements/stats?batch=2025-2029", h=PO), 200)
expect("stats have departments and companies", stats["placed_students"] >= 2 and any(d["code"] == "PL" + SFX for d in stats["by_department"]))
dstat = next(d for d in stats["by_department"] if d["code"] == "PL" + SFX)
expect("dept: 2 of 4 placed = 50%", (dstat["placed"], dstat["students"], dstat["percent"]) == (2, 4, 50), dstat)
check("student can't see placement list", req("GET", "/placements", h=SA), 403)

print("== student/parent view: opportunities & skill gap")
op = check("A opportunities (self)", req("GET", f"/students/{st['A']['id']}/opportunities", h=SA), 200)
mine = {o["job_role"]["id"]: o for o in op["opportunities"]}
expect("sees R1-R3", {r1["id"], r2["id"], r3["id"]} <= set(mine))
expect("R1 shows status selected", mine[r1["id"]]["application_status"] == "selected")
expect("R2 ineligible: already placed", not mine[r2["id"]]["is_eligible"])
expect("offers listed in applications", any(a["status"] == "selected" for a in op["applications"]))
SC = login(st["C"]["username"], "Student@123")
oc = {o["job_role"]["id"]: o for o in req("GET", f"/students/{st['C']['id']}/opportunities", h=SC).json()["data"]["opportunities"]}
expect("C's skill gap for R1: Java (has 2, needs 4)", any(g["name"] == "Java" and g["student_level"] == 2 and g["required_level"] == 4 for g in oc[r1["id"]]["missing_skills"]))
check("student can't see classmate's opportunities", req("GET", f"/students/{st['B']['id']}/opportunities", h=SA), 404)
sent = requests.post(f"{B}/auth/otp/request", json={"identifier": f"p98700{SFX}01"}).json()["data"]
PAR = {"Authorization": "Bearer " + requests.post(f"{B}/auth/otp/verify", json={"identifier": f"p98700{SFX}01", "otp": sent["debug_otp"]}).json()["data"]["access_token"]}
check("parent sees child's opportunities", req("GET", f"/students/{st['A']['id']}/opportunities", h=PAR), 200)
check("parent sees child's skills", req("GET", f"/students/{st['A']['id']}/skills", h=PAR), 200)

print("== lifecycle")
check("close R1", req("PATCH", f"/job-roles/{r1['id']}/status", {"status": "closed"}, PO), 200)
check("shortlist on closed role refused", req("POST", f"/job-roles/{r1['id']}/shortlist", {"student_ids": [st["D"]["id"]]}, PO), 409)
check("role with applications can't be deleted", req("DELETE", f"/job-roles/{r1['id']}", h=PO), 409)
check("company with roles can't be deleted", req("DELETE", f"/companies/{co['id']}", h=PO), 409)

print(f"\nPASSED={PASS} FAILED={FAIL}")
sys.exit(1 if FAIL else 0)
