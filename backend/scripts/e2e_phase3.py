"""End-to-end test for Phase 3 (class semester, subject allocation, mark entry, grading, CGPA, history, sheet).

Builds its own department/classes/staff/students with a random suffix, so it can be re-run.
Needs the API on :8080 (OTP_DEBUG=true). Usage: python scripts/e2e_phase3.py
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
req = lambda m, p, body=None, h=A, **kw: requests.request(m, B + p, json=body, headers=h, **kw)

print("== setup")
dept = check("department", req("POST", "/departments", {"name": "Marks Dept " + SFX, "code": "MK" + SFX}), 201)
other_dept = check("other department", req("POST", "/departments", {"name": "Other Dept " + SFX, "code": "OT" + SFX}), 201)
sems = {s["sem_no"]: s["id"] for s in req("GET", "/semesters").json()["data"]}
levels = {l["level_no"]: l["id"] for l in req("GET", "/year-levels").json()["data"]}
exams = {e["code"]: e for e in req("GET", "/exam-types").json()["data"]}
year = next(y for y in req("GET", "/academic-years?all=true").json()["data"] if y["is_current"])
ds = check("subject DS (4 cr)", req("POST", "/subjects", {"code": "MKDS" + SFX, "name": "Data Structures", "credits": 4}), 201)
lab = check("subject Lab (2 cr)", req("POST", "/subjects", {"code": "MKLB" + SFX, "name": "DS Lab", "credits": 2, "subject_type": "lab"}), 201)
off = check("subject outside curriculum", req("POST", "/subjects", {"code": "MKOF" + SFX, "name": "Elsewhere", "credits": 3}), 201)
check("curriculum sem 3", req("POST", "/curriculum", {"department_id": dept["id"], "semester_id": sems[3], "subject_ids": [ds["id"], lab["id"]]}), 201)

mk_staff = lambda key, roles, d: check(f"staff {key}", req("POST", "/staff", {"name": f"{key} {SFX}", "employee_code": f"{key}{SFX}", "department_id": d,
                                                                           "roles": roles, "password": "Staff@1234"}), 201)
inc = mk_staff("INC", ["staff"], dept["id"])
alloc_staff = mk_staff("ALC", ["staff"], dept["id"])
nobody = mk_staff("NOB", ["staff"], dept["id"])
hod = mk_staff("HOD", ["staff", "hod"], dept["id"])
other_hod = mk_staff("OHD", ["staff", "hod"], other_dept["id"])

cls = check("class II-A", req("POST", "/classes", {"department_id": dept["id"], "academic_year_id": year["id"], "year_level_id": levels[2], "section": "A", "class_incharge_id": inc["id"]}), 201)
expect("current semester defaults to Sem 3", cls["current_sem_no"] == 3, cls.get("current_semester_name"))
base = {"department_id": dept["id"], "academic_year_id": year["id"], "year_level_id": levels[2], "section": "A", "class_incharge_id": inc["id"]}
check("semester of another year rejected", req("PUT", f"/classes/{cls['id']}", {**base, "current_semester_id": sems[5]}), 400)
c4 = check("move class to Sem 4", req("PUT", f"/classes/{cls['id']}", {**base, "current_semester_id": sems[4]}), 200)
expect("now Sem 4", c4["current_sem_no"] == 4)
check("back to Sem 3", req("PUT", f"/classes/{cls['id']}", {**base, "current_semester_id": sems[3]}), 200)

studs = []
for i, (n, pm) in enumerate([("S1", "9811100" + SFX), ("S2", "9822200" + SFX), ("S3", "9833300" + SFX)]):
    studs.append(check(f"student {n}", req("POST", "/students", {"name": f"{n} {SFX}", "register_no": f"MK{SFX}{i + 1:02d}", "department_id": dept["id"],
                                                                 "admission_year": 2025, "class_id": cls["id"], "password": "Student@123",
                                                                 "parents": [{"name": f"P{n} {SFX}", "mobile": pm, "relation": "father"}]}), 201))
s1, s2, s3 = studs

print("== subject allocation")
al = check("allocate DS to ALC", req("POST", "/subject-allocations", {"staff_id": alloc_staff["id"], "class_id": cls["id"], "subject_id": ds["id"]}), 201)
expect("semester defaulted to class's current", al["sem_no"] == 3)
check("duplicate allocation", req("POST", "/subject-allocations", {"staff_id": alloc_staff["id"], "class_id": cls["id"], "subject_id": ds["id"]}), 409)
check("subject not in curriculum", req("POST", "/subject-allocations", {"staff_id": alloc_staff["id"], "class_id": cls["id"], "subject_id": off["id"]}), 400)
check("student can't be allocated", req("POST", "/subject-allocations", {"staff_id": s1["id"], "class_id": cls["id"], "subject_id": lab["id"]}), 400)
OH = login(other_hod["username"], "Staff@1234")
check("HOD of another dept can't allocate here", req("POST", "/subject-allocations", {"staff_id": nobody["id"], "class_id": cls["id"], "subject_id": lab["id"]}, OH), 403)
lst = check("list allocations for class", req("GET", f"/subject-allocations?class_id={cls['id']}"), 200)
expect("1 allocation", len(lst) == 1)

ALC = login(alloc_staff["username"], "Staff@1234")
INC = login(inc["username"], "Staff@1234")
NOB = login(nobody["username"], "Staff@1234")
HOD = login(hod["username"], "Staff@1234")
mine = check("my-subjects (allocated)", req("GET", "/marks/my-subjects", h=ALC), 200)
expect("allocated staff: only DS", [(t["subject_id"], t["reason"]) for t in mine] == [(ds["id"], "allocated")], mine)
mine = check("my-subjects (incharge)", req("GET", "/marks/my-subjects", h=INC), 200)
expect("incharge: DS + Lab", sorted(t["subject_id"] for t in mine) == sorted([ds["id"], lab["id"]]))
expect("no access: nothing", check("my-subjects (none)", req("GET", "/marks/my-subjects", h=NOB), 200) == [])

print("== internal exam entry (IA1: max 50, pass 50%)")
ia1 = exams["IA1"]
key = lambda sub, ex, attempt=1: {"class_id": cls["id"], "semester_id": sems[3], "subject_id": sub, "exam_type_id": ex, "attempt_no": attempt}
sheet = check("load grid", req("GET", "/marks/entry", h=ALC, params=key(ds["id"], ia1["id"])), 200)
expect("3 students, editable", len(sheet["rows"]) == 3 and sheet["can_edit"])
expect("no-access staff sees read-only", check("load grid as other staff", req("GET", "/marks/entry", h=NOB, params=key(ds["id"], ia1["id"])), 200)["can_edit"] is False)
check("other staff can't save", req("PUT", "/marks/entry", {**key(ds["id"], ia1["id"]), "entries": [{"student_id": s1["id"], "marks_obtained": 40}]}, NOB), 403)
check("allocated staff can't enter Lab", req("PUT", "/marks/entry", {**key(lab["id"], ia1["id"]), "entries": [{"student_id": s1["id"], "marks_obtained": 40}]}, ALC), 403)
check("subject outside curriculum", req("GET", "/marks/entry", h=A, params=key(off["id"], ia1["id"])), 400)
check("marks above max", req("PUT", "/marks/entry", {**key(ds["id"], ia1["id"]), "entries": [{"student_id": s1["id"], "marks_obtained": 51}]}, ALC), 400)
check("student from another class", req("PUT", "/marks/entry", {**key(ds["id"], ia1["id"]), "entries": [{"student_id": inc["id"], "marks_obtained": 10}]}, ALC), 400)
g = check("save IA1", req("PUT", "/marks/entry", {**key(ds["id"], ia1["id"]), "entries": [
    {"student_id": s1["id"], "marks_obtained": 40}, {"student_id": s2["id"], "marks_obtained": 20}, {"student_id": s3["id"], "is_absent": True}]}, ALC), 200)
res = {r["student_id"]: r for r in g["rows"]}
expect("pass / fail / absent", (res[s1["id"]]["result"], res[s2["id"]]["result"], res[s3["id"]]["result"]) == ("pass", "fail", "absent"))
expect("internal exams have no grade", res[s1["id"]]["grade"] is None)
expect("stats", g["stats"]["entered"] == 2 and g["stats"]["absent"] == 1 and g["stats"]["average"] == 30 and g["stats"]["pass_percent"] == 33.33, g["stats"])
expect("internal marks don't touch CGPA", req("GET", f"/students/{s1['id']}").json()["data"]["cgpa"] == 0)

print("== end-semester entry (graded) + CGPA")
sem = exams["SEM"]
g = check("DS end-sem by allocated staff", req("PUT", "/marks/entry", {**key(ds["id"], sem["id"]), "entries": [
    {"student_id": s1["id"], "marks_obtained": 95}, {"student_id": s2["id"], "marks_obtained": 45}, {"student_id": s3["id"], "marks_obtained": 72}]}, ALC), 200)
grades = {r["student_id"]: r["grade"] for r in g["rows"]}
expect("grades O / U / A", (grades[s1["id"]], grades[s2["id"]], grades[s3["id"]]) == ("O", "U", "A"), grades)
g = check("Lab end-sem by class incharge", req("PUT", "/marks/entry", {**key(lab["id"], sem["id"]), "entries": [
    {"student_id": s1["id"], "marks_obtained": 85}, {"student_id": s2["id"], "marks_obtained": 60}, {"student_id": s3["id"], "is_absent": True}]}, INC), 200)
grades = {r["student_id"]: r["grade"] for r in g["rows"]}
expect("grades A+ / B / AB", (grades[s1["id"]], grades[s2["id"]], grades[s3["id"]]) == ("A+", "B", "AB"), grades)

prof = lambda s: req("GET", f"/students/{s['id']}").json()["data"]
p1, p2, p3 = prof(s1), prof(s2), prof(s3)
expect("S1 CGPA 9.67, 0 backlogs", (p1["cgpa"], p1["backlog_count"]) == (9.67, 0), (p1["cgpa"], p1["backlog_count"]))
expect("S2 CGPA 6.00, 1 backlog (DS)", (p2["cgpa"], p2["backlog_count"]) == (6.0, 1), (p2["cgpa"], p2["backlog_count"]))
expect("S3 CGPA 8.00, 1 backlog (Lab absent)", (p3["cgpa"], p3["backlog_count"]) == (8.0, 1), (p3["cgpa"], p3["backlog_count"]))

print("== arrear (attempt 2)")
g = check("arrear roster", req("GET", "/marks/entry", h=HOD, params=key(ds["id"], sem["id"], 2)), 200)
expect("only the failed student is listed", [r["student_id"] for r in g["rows"]] == [s2["id"]], [r["name"] for r in g["rows"]])
expect("HOD of the department can edit", g["can_edit"])
check("arrear pass by HOD", req("PUT", "/marks/entry", {**key(ds["id"], sem["id"], 2), "entries": [{"student_id": s2["id"], "marks_obtained": 65}]}, HOD), 200)
p2 = prof(s2)
expect("S2 CGPA 6.67 after clearing arrear, 0 backlogs", (p2["cgpa"], p2["backlog_count"]) == (6.67, 0), (p2["cgpa"], p2["backlog_count"]))
check("clear S3's lab entry", req("PUT", "/marks/entry", {**key(lab["id"], sem["id"]), "entries": [{"student_id": s3["id"], "marks_obtained": None}]}, INC), 200)
expect("S3 backlog removed", prof(s3)["backlog_count"] == 0)

print("== history & sheet")
h1 = check("S1 history (admin)", req("GET", f"/marks/students/{s1['id']}"), 200)
sem3 = h1["semesters"][0]
expect("one semester, SGPA 9.67, 6 credits", len(h1["semesters"]) == 1 and sem3["sgpa"] == 9.67 and sem3["credits_earned"] == 6, sem3.get("sgpa"))
ds_hist = next(s for s in sem3["subjects"] if s["subject_id"] == ds["id"])
expect("DS shows IA1 + SEM", [e["exam_code"] for e in ds_hist["exams"]] == ["IA1", "SEM"] and ds_hist["final_grade"] == "O")
expect("class recorded", sem3["class_label"] == cls["label"], sem3["class_label"])
h2 = req("GET", f"/marks/students/{s2['id']}").json()["data"]
ds2 = next(s for s in h2["semesters"][0]["subjects"] if s["subject_id"] == ds["id"])
expect("S2 DS shows both attempts, final = B+", [e["attempt_no"] for e in ds2["exams"] if e["exam_code"] == "SEM"] == [1, 2] and ds2["final_grade"] == "B+")
S1 = login(s1["username"], "Student@123")
check("student sees own history", req("GET", f"/marks/students/{s1['id']}", h=S1), 200)
check("student can't see classmate", req("GET", f"/marks/students/{s2['id']}", h=S1), 404)
sent = requests.post(f"{B}/auth/otp/request", json={"identifier": "p9811100" + SFX}).json()["data"]
PAR = {"Authorization": "Bearer " + requests.post(f"{B}/auth/otp/verify", json={"identifier": "p9811100" + SFX, "otp": sent["debug_otp"]}).json()["data"]["access_token"]}
check("parent sees child's history", req("GET", f"/marks/students/{s1['id']}", h=PAR), 200)
check("parent can't see other student", req("GET", f"/marks/students/{s2['id']}", h=PAR), 404)
sh = check("class result sheet", req("GET", "/marks/sheet", params={"class_id": cls["id"], "semester_id": sems[3], "exam_type_id": sem["id"]}), 200)
expect("2 subjects, 3 students", len(sh["subjects"]) == 2 and len(sh["rows"]) == 3)
dsst = next(s for s in sh["subjects"] if s["id"] == ds["id"])["stats"]
expect("DS pass 2 of 3 (attempt 1)", dsst["passed"] == 2 and dsst["failed"] == 1, dsst)
check("student can't open class sheet", req("GET", "/marks/sheet", h=S1, params={"class_id": cls["id"], "semester_id": sems[3], "exam_type_id": sem["id"]}), 403)
check("other-dept HOD can't open sheet", req("GET", "/marks/sheet", h=OH, params={"class_id": cls["id"], "semester_id": sems[3], "exam_type_id": sem["id"]}), 403)

print("== masters & revoking allocation")
gs = check("grade scale", req("GET", "/grade-scales"), 200)
expect("7 grades", len(gs) == 7)
expect("exam types expose pass_percent", "pass_percent" in exams["IA1"])
check("remove allocation", req("DELETE", f"/subject-allocations/{al['id']}"), 200)
check("ALC loses entry rights", req("PUT", "/marks/entry", {**key(ds["id"], ia1["id"]), "entries": [{"student_id": s1["id"], "marks_obtained": 41}]}, ALC), 403)

print(f"\nPASSED={PASS} FAILED={FAIL}")
sys.exit(1 if FAIL else 0)
