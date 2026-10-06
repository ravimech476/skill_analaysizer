"""End-to-end test for Phase 6 (semester change, year promotion, detention, pass-out, discontinue/re-admit, history).

Creates its own department and two far-future academic years, so promotions never touch real data and the
test can be re-run. Needs the demo users (seed_demo.py). Usage:
  API_URL=http://localhost:8090/api/v1 python scripts/e2e_phase6.py
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
KAVYA = login("kavya", "Staff@1234")  # HOD of another department (CSE)
req = lambda m, p, body=None, h=A, **kw: requests.request(m, B + p, json=body, headers=h, **kw)
levels = {l["level_no"]: l["id"] for l in req("GET", "/year-levels").json()["data"]}
sems = {s["sem_no"]: s for s in req("GET", "/semesters").json()["data"]}
current_year = next(y for y in req("GET", "/academic-years?all=true").json()["data"] if y["is_current"])

print("== setup: department, two future academic years, classes, students")
dept = check("department", req("POST", "/departments", {"name": "Lifecycle Dept " + SFX, "code": "LC" + SFX}), 201)
y0 = 3000 + int(SFX)
F = check("from year", req("POST", "/academic-years", {"name": f"F{SFX}", "start_date": f"{y0}-06-01", "end_date": f"{y0 + 1}-05-31"}), 201)
T = check("to year", req("POST", "/academic-years", {"name": f"T{SFX}", "start_date": f"{y0 + 1}-06-01", "end_date": f"{y0 + 2}-05-31"}), 201)
inc = check("incharge staff", req("POST", "/staff", {"name": f"Inc {SFX}", "employee_code": f"LI{SFX}", "department_id": dept["id"], "password": "Staff@1234"}), 201)
mk_class = lambda level, section, incharge=None, year=F: check(f"class {level}-{section}", req("POST", "/classes", {
    "department_id": dept["id"], "academic_year_id": year["id"], "year_level_id": levels[level], "section": section, "class_incharge_id": incharge}), 201)
c1a = mk_class(1, "A", inc["id"])
c1b = mk_class(1, "B")
c2a = mk_class(2, "A")
c4a = mk_class(4, "A")
st = {}
for key, cls in [("s1", c1a), ("s2", c1a), ("s3", c2a), ("s4", c4a), ("s5", c4a)]:
    st[key] = check(f"student {key}", req("POST", "/students", {"name": f"{key} {SFX}", "register_no": f"LC{SFX}{key}", "department_id": dept["id"],
                                                               "admission_year": 2025, "class_id": cls["id"], "password": "Student@123"}), 201)
S1 = login(st["s1"]["username"], "Student@123")

print("== semester change")
r = check("I-A: next semester", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"]]}), 200)
expect("Semester 1 -> Semester 2", r["changed"] and r["changed"][0]["from"] == "Semester 1" and r["changed"][0]["to"] == "Semester 2", r)
r = check("I-A: next again", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"]]}), 200)
expect("skipped: already last semester of the year", not r["changed"] and "year promotion" in r["skipped"][0]["reason"])
r = check("I-A: previous", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"]], "direction": "previous"}), 200)
expect("back to Semester 1", r["changed"][0]["to"] == "Semester 1")
r = check("several classes at once", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"], c1b["id"], c2a["id"], c4a["id"]]}), 200)
expect("4 classes moved to even semesters", len(r["changed"]) == 4 and {x["to"] for x in r["changed"]} == {"Semester 2", "Semester 4", "Semester 8"}, [x["to"] for x in r["changed"]])
r = check("other-dept HOD", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"]]}, KAVYA), 200)
expect("skipped: other department", not r["changed"] and "another department" in r["skipped"][0]["reason"])
check("student can't change semesters", req("POST", "/lifecycle/semester-change", {"class_ids": [c1a["id"]]}, S1), 403)
hist = check("student history", req("GET", f"/students/{st['s1']['id']}/history"), 200)
expect("history has Sem 1 and Sem 2 in F year", [(h["academic_year"], h["sem_no"]) for h in hist] == [(f"F{SFX}", 1), (f"F{SFX}", 2)], hist)
check("student can read own history", req("GET", f"/students/{st['s1']['id']}/history", h=S1), 200)
check("student can't read another's history", req("GET", f"/students/{st['s2']['id']}/history", h=S1), 404)

print("== promotion preview")
check("same year refused", req("POST", "/lifecycle/promotion/preview", {"from_year_id": F["id"], "to_year_id": F["id"]}), 400)
check("backwards refused", req("POST", "/lifecycle/promotion/preview", {"from_year_id": T["id"], "to_year_id": F["id"]}), 400)
pv = check("preview F -> T", req("POST", "/lifecycle/promotion/preview", {"from_year_id": F["id"], "to_year_id": T["id"]}), 200)
plans = {p["label"]: p for p in pv["classes"]}
expect("4 classes, final year passes out", len(plans) == 4 and plans[f"LC{SFX} IV-A"]["action"] == "pass_out", [(k, v["action"]) for k, v in plans.items()])
expect("target labels", plans[f"LC{SFX} I-A"]["target_label"] == f"LC{SFX} II-A" and not plans[f"LC{SFX} I-A"]["target_exists"])
expect("totals: 3 to promote, 2 to pass out", pv["totals"]["to_promote"] == 3 and pv["totals"]["to_pass_out"] == 2, pv["totals"])
expect("not run yet", pv["already_run"] is False)
check("staff can't preview", req("POST", "/lifecycle/promotion/preview", {"from_year_id": F["id"], "to_year_id": T["id"]}, S1), 403)

print("== promotion")
check("student can't promote", req("POST", "/lifecycle/promotion", {"from_year_id": F["id"], "to_year_id": T["id"]}, S1), 403)
res = check("promote (detain s2 + s5, carry incharge)", req("POST", "/lifecycle/promotion", {
    "from_year_id": F["id"], "to_year_id": T["id"], "detained_student_ids": [st["s2"]["id"], st["s5"]["id"]],
    "carry_incharge": True, "set_current": False}), 201)
expect("promoted 2, detained 2, passed out 1", (res["promoted"], res["detained"], res["passed_out"]) == (2, 2, 1), res)
expect("5 classes created (II-A, I-A repeat, III-A, IV-A repeat, II-B)", res["classes_created"] == 5, res["classes_created"])
prof = lambda k: req("GET", f"/students/{st[k]['id']}").json()["data"]
expect("s1 now in II-A", prof("s1")["class_label"] == f"LC{SFX} II-A")
expect("s2 detained: repeats I-A", prof("s2")["class_label"] == f"LC{SFX} I-A" and prof("s2")["lifecycle_status"] == "studying")
expect("s3 now in III-A", prof("s3")["class_label"] == f"LC{SFX} III-A")
p4 = prof("s4")
expect("s4 passed out", p4["lifecycle_status"] == "passed_out" and p4["class_id"] is None and p4["passed_out_year"] == y0 + 1, (p4["lifecycle_status"], p4["passed_out_year"]))
expect("s5 detained in final year: repeats IV-A", prof("s5")["class_label"] == f"LC{SFX} IV-A")
t_classes = {c["label"]: c for c in req("GET", f"/classes?academic_year_id={T['id']}").json()["data"]}
expect("incharge carried to II-A", t_classes[f"LC{SFX} II-A"]["class_incharge_name"] == inc["name"])
expect("new classes start in the odd semester", t_classes[f"LC{SFX} II-A"]["current_sem_no"] == 3 and t_classes[f"LC{SFX} III-A"]["current_sem_no"] == 5)
h1 = req("GET", f"/students/{st['s1']['id']}/history").json()["data"]
expect("s1 history: F sem 1-2 promoted, T sem 3 studying", [(h["academic_year"], h["sem_no"], h["status"]) for h in h1] ==
       [(f"F{SFX}", 1, "promoted"), (f"F{SFX}", 2, "promoted"), (f"T{SFX}", 3, "studying")], [(h["sem_no"], h["status"]) for h in h1])
h2 = req("GET", f"/students/{st['s2']['id']}/history").json()["data"]
expect("s2 history: detained, then Sem 1 again", [h["status"] for h in h2 if h["academic_year"] == f"F{SFX}"] == ["detained", "detained"] and h2[-1]["sem_no"] == 1)
expect("s4 history: passed out", all(h["status"] == "passed_out" for h in req("GET", f"/students/{st['s4']['id']}/history").json()["data"]))
check("running the same promotion again", req("POST", "/lifecycle/promotion", {"from_year_id": F["id"], "to_year_id": T["id"]}), 409)
expect("preview now says already run", req("POST", "/lifecycle/promotion/preview", {"from_year_id": F["id"], "to_year_id": T["id"]}).json()["data"]["already_run"])
run = next(r for r in check("promotion history", req("GET", "/lifecycle/promotions"), 200) if r["from_year"] == f"F{SFX}")
expect("history counts", (run["promoted_count"], run["detained_count"], run["passed_out_count"], run["classes_created"]) == (2, 2, 1, 5))
expect("current year unchanged (set_current=false)", next(y for y in req("GET", "/academic-years?all=true").json()["data"] if y["is_current"])["id"] == current_year["id"])

print("== alumni & placement")
al = check("alumni list", req("GET", f"/students?lifecycle=passed_out&search=LC{SFX}"), 200)
expect("only s4", [s["register_no"] for s in al] == [f"LC{SFX}S4"], [s["register_no"] for s in al])
cur = req("GET", f"/students?lifecycle=studying&search=LC{SFX}").json()["data"]
expect("studying list excludes alumni", f"LC{SFX}S4" not in [s["register_no"] for s in cur] and len(cur) == 4)
co = check("company", req("POST", "/companies", {"name": f"Lifecycle Co {SFX}"}), 201)
role = check("drive for the department", req("POST", "/job-roles", {"company_id": co["id"], "title": "Trainee", "package_lpa": 3, "min_cgpa": 0, "max_backlogs": 5,
                                                                     "status": "upcoming", "department_ids": [dept["id"]], "skills": []}), 200)
rank = check("analyze", req("POST", f"/job-roles/{role['id']}/analyze"), 200)
ranked = {m["student_id"] for m in rank["matches"]}
expect("alumni not ranked, current students are", st["s4"]["id"] not in ranked and st["s1"]["id"] in ranked)
S4 = login(st["s4"]["username"], "Student@123")
op = next(o for o in req("GET", f"/students/{st['s4']['id']}/opportunities", h=S4).json()["data"]["opportunities"] if o["job_role"]["id"] == role["id"])
expect("alumnus sees why they're not eligible", not op["is_eligible"] and any("Not a current student" in r for r in op["ineligible_reasons"]), op["ineligible_reasons"])
check("alumnus can still log in and see marks history", req("GET", f"/marks/students/{st['s4']['id']}", h=S4), 200)

print("== discontinue / re-admit")
check("discontinue s3", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "discontinue", "remarks": "Moved to another college"}), 200)
p3 = prof("s3")
expect("s3 discontinued, no class, remarks kept", p3["lifecycle_status"] == "discontinued" and p3["class_id"] is None and p3["status_remarks"] == "Moved to another college")
check("discontinue again refused", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "discontinue"}), 409)
check("re-admit needs a class", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "readmit"}), 400)
check("re-admit into a non-current year refused", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "readmit", "class_id": t_classes[f"LC{SFX} III-A"]["id"]}), 400)
now_class = mk_class(3, "A", year=current_year)
other_dept_class = next(c for c in req("GET", "/classes").json()["data"] if c["department_id"] != dept["id"])
check("re-admit into another department refused", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "readmit", "class_id": other_dept_class["id"]}), 400)
check("re-admit", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "readmit", "class_id": now_class["id"], "remarks": "Returned"}), 200)
expect("s3 studying again", prof("s3")["lifecycle_status"] == "studying" and prof("s3")["class_id"] == now_class["id"])
check("re-admit a studying student refused", req("POST", f"/students/{st['s3']['id']}/lifecycle", {"action": "readmit", "class_id": now_class["id"]}), 409)
check("student can't discontinue", req("POST", f"/students/{st['s1']['id']}/lifecycle", {"action": "discontinue"}, S1), 403)
check("bad action", req("POST", f"/students/{st['s1']['id']}/lifecycle", {"action": "expel"}), 400)

print(f"\nPASSED={PASS} FAILED={FAIL}")
sys.exit(1 if FAIL else 0)
