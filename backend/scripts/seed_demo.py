"""Seed a small, realistic demo dataset through the public API (run on a fresh database).

Creates 3 departments, subjects + curriculum, 4 staff (with HODs and class incharges),
classes for the current academic year, and 12 students with parents via the Excel bulk upload.
Usage: python scripts/seed_demo.py
"""
import io
import os
import runpy
import sys

import openpyxl
import requests

B = os.environ.get("API_URL", "http://localhost:8080/api/v1")
ENV = os.path.join(os.path.dirname(__file__), "..", ".env")
ADMIN_PW = next(l.split("=", 1)[1].strip() for l in open(ENV) if l.startswith("ADMIN_PASSWORD="))

r = requests.post(f"{B}/auth/login", json={"username": "admin", "password": ADMIN_PW})
r.raise_for_status()
H = {"Authorization": "Bearer " + r.json()["data"]["access_token"]}


def call(method, path, body=None):
    resp = requests.request(method, B + path, json=body, headers=H)
    if resp.status_code >= 300:
        sys.exit(f"{method} {path} failed: {resp.status_code} {resp.text}")
    return resp.json().get("data")


print("departments")
depts = {}
for code, name in [("CSE", "Computer Science and Engineering"), ("ECE", "Electronics and Communication Engineering"), ("MECH", "Mechanical Engineering")]:
    depts[code] = call("POST", "/departments", {"name": name, "code": code})["id"]

print("staff")
staff = {}
for key, body in {
    "priya": {"name": "Priya Raman", "username": "priya", "employee_code": "EMP001", "mobile": "9000000001", "department_id": depts["CSE"],
              "designation": "Assistant Professor", "roles": ["staff", "placement_officer"]},
    "kavya": {"name": "Kavya Srinivasan", "username": "kavya", "employee_code": "EMP002", "mobile": "9000000002", "department_id": depts["CSE"],
              "designation": "Professor & Head", "roles": ["staff", "hod"]},
    "meena": {"name": "Meena Devi", "username": "meena", "employee_code": "EMP003", "mobile": "9000000003", "department_id": depts["CSE"],
              "designation": "Assistant Professor", "roles": ["staff"]},
    "suresh": {"name": "Suresh Babu", "username": "suresh", "employee_code": "EMP004", "mobile": "9000000004", "department_id": depts["ECE"],
               "designation": "Professor & Head", "roles": ["staff", "hod"]},
}.items():
    staff[key] = call("POST", "/staff", {**body, "password": "Staff@1234", "qualification": "M.E., Ph.D.", "joined_on": "2015-06-01"})["id"]

call("PUT", f"/departments/{depts['CSE']}", {"name": "Computer Science and Engineering", "code": "CSE", "hod_id": staff["kavya"]})
call("PUT", f"/departments/{depts['ECE']}", {"name": "Electronics and Communication Engineering", "code": "ECE", "hod_id": staff["suresh"]})

print("subjects + curriculum")
subj = {}
for code, name, credits, typ in [
    ("CS3301", "Data Structures", 4, "theory"), ("CS3311", "Data Structures Lab", 2, "lab"), ("MA3301", "Discrete Mathematics", 4, "theory"),
    ("CS3401", "Operating Systems", 4, "theory"), ("CS3402", "Database Management Systems", 4, "theory"),
    ("CS3411", "DBMS Lab", 2, "lab"), ("EC3301", "Signals and Systems", 4, "theory"), ("EC3302", "Electronic Circuits", 4, "theory"),
]:
    subj[code] = call("POST", "/subjects", {"code": code, "name": name, "credits": credits, "subject_type": typ})["id"]
sems = {s["sem_no"]: s["id"] for s in call("GET", "/semesters")}
for dept, sem, codes in [("CSE", 3, ["CS3301", "CS3311", "MA3301"]), ("CSE", 4, ["CS3401", "CS3402", "CS3411"]), ("ECE", 3, ["EC3301", "EC3302", "MA3301"])]:
    call("POST", "/curriculum", {"department_id": depts[dept], "semester_id": sems[sem], "subject_ids": [subj[c] for c in codes]})

print("classes")
year = next(y for y in call("GET", "/academic-years?all=true") if y["is_current"])["id"]
levels = {l["level_no"]: l["id"] for l in call("GET", "/year-levels")}
for dept, level, section, incharge in [("CSE", 2, "A", "meena"), ("CSE", 2, "B", "priya"), ("CSE", 3, "A", "kavya"), ("ECE", 2, "A", "suresh")]:
    call("POST", "/classes", {"department_id": depts[dept], "academic_year_id": year, "year_level_id": levels[level], "section": section, "class_incharge_id": staff[incharge]})

print("students (bulk upload)")
wb = openpyxl.Workbook()
ws = wb.active
ws.append(["register_no", "name", "department_code", "admission_year", "year", "section", "gender", "dob", "mobile", "email",
           "blood_group", "parent_name", "parent_mobile", "parent_relation"])
rows = [
    ("25CS001", "Arun Kumar", "CSE", 2025, 2, "A", "male", "2007-03-12", "9100000001", "Kumar Ramasamy", "9200000001", "father"),
    ("25CS002", "Anjali Kumar", "CSE", 2025, 2, "A", "female", "2007-08-21", "9100000002", "Kumar Ramasamy", "9200000001", "father"),  # sibling of Arun
    ("25CS003", "Bharath S", "CSE", 2025, 2, "A", "male", "2007-01-05", "9100000003", "Sankar V", "9200000003", "father"),
    ("25CS004", "Divya R", "CSE", 2025, 2, "A", "female", "2007-11-30", "9100000004", "Revathi R", "9200000004", "mother"),
    ("25CS005", "Farhan Ali", "CSE", 2025, 2, "B", "male", "2007-05-17", "9100000005", "Imran Ali", "9200000005", "father"),
    ("25CS006", "Gayathri M", "CSE", 2025, 2, "B", "female", "2007-07-09", "9100000006", "Murugan K", "9200000006", "father"),
    ("25CS007", "Harish P", "CSE", 2025, 2, "B", "male", "2007-02-14", "9100000007", "Padma P", "9200000007", "mother"),
    ("24CS001", "Ishwarya N", "CSE", 2024, 3, "A", "female", "2006-04-02", "9100000008", "Natarajan S", "9200000008", "father"),
    ("24CS002", "Karthik V", "CSE", 2024, 3, "A", "male", "2006-09-25", "9100000009", "Vijaya L", "9200000009", "mother"),
    ("25EC001", "Lakshmi T", "ECE", 2025, 2, "A", "female", "2007-06-18", "9100000010", "Thangaraj M", "9200000010", "father"),
    ("25EC002", "Mohan Raj", "ECE", 2025, 2, "A", "male", "2007-12-01", "9100000011", "Raj Kumar", "9200000011", "father"),
    ("25EC003", "Nandhini S", "ECE", 2025, 2, "A", "female", "2007-10-10", "9100000012", "Sundari S", "9200000012", "mother"),
]
for reg, name, dept, adm, yr, sec, gender, dob, mobile, pname, pmobile, rel in rows:
    ws.append([reg, name, dept, adm, yr, sec, gender, dob, mobile, f"{reg.lower()}@college.edu", "O+", pname, pmobile, rel])
buf = io.BytesIO()
wb.save(buf)
resp = requests.post(f"{B}/bulk-upload/students", headers=H, files={"file": ("demo_students.xlsx", buf.getvalue())},
                     data={"default_password": "Student@123"})
job = resp.json()["data"]
print(f"  uploaded {job['success_rows']}/{job['total_rows']} students", job["errors"] or "")

# Give one parent a password so the parent view can be tried without OTP.
parent = call("GET", "/parents?search=9200000001")[0]
call("PUT", f"/users/{parent['id']}/password", {"password": "Parent@123"})

print("marks")
runpy.run_path(os.path.join(os.path.dirname(__file__), "seed_demo_marks.py"))
print("placement")
runpy.run_path(os.path.join(os.path.dirname(__file__), "seed_demo_placement.py"))

print("\nDemo logins (password):")
print("  admin              -> ADMIN_PASSWORD in backend/.env")
print("  priya  Staff@1234  -> staff + placement officer (incharge CSE II-B)")
print("  kavya  Staff@1234  -> CSE HOD (incharge CSE III-A)")
print("  meena  Staff@1234  -> staff (incharge CSE II-A)")
print("  25cs001 Student@123 -> student Arun Kumar")
print(f"  {parent['username']} Parent@123 -> parent of Arun + Anjali (others log in with OTP)")
