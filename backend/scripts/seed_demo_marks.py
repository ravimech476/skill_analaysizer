"""Add demo marks on top of seed_demo.py data: subject allocations + IA1/IA2/end-semester marks for CSE II-A (Sem 3).

Marks are entered as the class incharge (meena) through the real endpoint, so grading and CGPA run as in production.
Usage: python scripts/seed_demo_marks.py
"""
import os
import sys

import requests

B = os.environ.get("API_URL", "http://localhost:8080/api/v1")
ENV = os.path.join(os.path.dirname(__file__), "..", ".env")
ADMIN_PW = next(l.split("=", 1)[1].strip() for l in open(ENV) if l.startswith("ADMIN_PASSWORD="))


def login(u, p):
    r = requests.post(f"{B}/auth/login", json={"username": u, "password": p})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["data"]["access_token"]}


def call(h, method, path, body=None, **kw):
    r = requests.request(method, B + path, json=body, headers=h, **kw)
    if r.status_code >= 300:
        sys.exit(f"{method} {path} failed: {r.status_code} {r.text}")
    return r.json()["data"]


A = login("admin", ADMIN_PW)
MEENA = login("meena", "Staff@1234")

cls = next(c for c in call(A, "GET", "/classes") if c["label"] == "CSE II-A")
subjects = {s["code"]: s["id"] for s in call(A, "GET", "/subjects?all=true")}
staff = {s["username"]: s["id"] for s in call(A, "GET", "/staff?all=true")}
exams = {e["code"]: e["id"] for e in call(A, "GET", "/exam-types?all=true")}
students = {s["register_no"]: s["id"] for s in call(A, "GET", f"/students?class_id={cls['id']}&page_size=100")}

print("allocations")
for staff_user, code in [("priya", "CS3301"), ("kavya", "MA3301"), ("meena", "CS3311")]:
    r = requests.post(f"{B}/subject-allocations", json={"staff_id": staff[staff_user], "class_id": cls["id"], "subject_id": subjects[code]}, headers=A)
    print(f"  {staff_user} -> {code}: {r.status_code}")

# register_no -> {subject: (IA1/50, IA2/50, SEM/100)}; None = absent
MARKS = {
    "25CS001": {"CS3301": (46, 44, 94), "CS3311": (48, 47, 92), "MA3301": (41, 45, 88)},
    "25CS002": {"CS3301": (38, 40, 76), "CS3311": (45, 46, 85), "MA3301": (35, 39, 71)},
    "25CS003": {"CS3301": (30, 33, 63), "CS3311": (40, 42, 80), "MA3301": (28, None, 58)},
    "25CS004": {"CS3301": (26, 29, 55), "CS3311": (38, 41, 74), "MA3301": (18, 21, 38)},  # fails Discrete Maths
}
print("marks")
for code in ["CS3301", "CS3311", "MA3301"]:
    for i, exam in enumerate(["IA1", "IA2", "SEM"]):
        entries = []
        for reg, per in MARKS.items():
            v = per[code][i]
            entries.append({"student_id": students[reg], "marks_obtained": v, "is_absent": v is None})
        sheet = call(MEENA, "PUT", "/marks/entry", {"class_id": cls["id"], "semester_id": cls["current_semester_id"],
                                                    "subject_id": subjects[code], "exam_type_id": exams[exam], "attempt_no": 1, "entries": entries})
        print(f"  {code} {exam}: pass {sheet['stats']['pass_percent']}%  avg {sheet['stats']['average']}")

for reg in MARKS:
    s = call(A, "GET", f"/students/{students[reg]}")
    print(f"  {reg} {s['name']}: CGPA {s['cgpa']}, backlogs {s['backlog_count']}")
