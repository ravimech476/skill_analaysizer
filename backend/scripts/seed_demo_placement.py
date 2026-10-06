"""Add demo placement data on top of seed_demo.py + seed_demo_marks.py: student skills, companies,
job roles, an analyzer run, a shortlist and one placement. Usage: python scripts/seed_demo_placement.py
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


def call(h, method, path, body=None):
    r = requests.request(method, B + path, json=body, headers=h)
    if r.status_code >= 300:
        sys.exit(f"{method} {path} failed: {r.status_code} {r.text}")
    return r.json()["data"]


A = login("admin", ADMIN_PW)
MEENA, SURESH, PRIYA = login("meena", "Staff@1234"), login("suresh", "Staff@1234"), login("priya", "Staff@1234")
skills = {s["name"]: s["id"] for s in call(A, "GET", "/skills?all=true")}
students = {s["register_no"]: s for s in call(A, "GET", "/students?page_size=100")}
depts = {d["code"]: d["id"] for d in call(A, "GET", "/departments?all=true")}

print("student skills")
LEVELS = {
    "25CS001": {"Java": 4, "Data Structures & Algorithms": 4, "SQL": 3, "Communication": 4, "Aptitude": 4},
    "25CS002": {"Python": 4, "SQL": 4, "Data Structures & Algorithms": 3, "Communication": 5, "Aptitude": 4},
    "25CS003": {"Java": 3, "HTML/CSS": 4, "JavaScript": 3, "Communication": 3, "Aptitude": 3},
    "25CS004": {"Java": 2, "SQL": 2, "Communication": 3, "Aptitude": 2},
    "25CS005": {"Java": 4, "Spring Boot": 3, "SQL": 3, "Aptitude": 3},
    "25CS006": {"Python": 3, "Machine Learning": 2, "Communication": 4, "Aptitude": 4},
    "25EC001": {"Embedded C": 4, "C": 4, "MATLAB": 3, "Communication": 3, "Aptitude": 4},
    "25EC002": {"C": 3, "Embedded C": 2, "Aptitude": 3},
}
for reg, lv in LEVELS.items():
    who = SURESH if reg.startswith("25EC") else MEENA
    for name, level in lv.items():
        call(who, "PUT", f"/students/{students[reg]['id']}/skills", {"skill_id": skills[name], "proficiency": level, "source": "assessment"})
print(f"  recorded skills for {len(LEVELS)} students")

print("companies + drives")
co = {}
for name, industry, loc in [("Zoho", "Product / SaaS", "Chennai"), ("TCS", "IT Services", "Chennai"), ("Infosys", "IT Services", "Bengaluru")]:
    co[name] = call(PRIYA, "POST", "/companies", {"name": name, "industry": industry, "location": loc})["id"]
S = lambda name, lvl, must=False, w=1: {"skill_id": skills[name], "required_level": lvl, "is_mandatory": must, "weight": w}
roles = {
    "zoho": call(PRIYA, "POST", "/job-roles", {"company_id": co["Zoho"], "title": "Software Developer", "package_lpa": 8.4, "min_cgpa": 7, "max_backlogs": 0,
                                               "status": "open", "department_ids": [depts["CSE"]], "drive_date": "2026-11-15", "last_apply_date": "2026-11-05",
                                               "skills": [S("Java", 4, True, 2), S("Data Structures & Algorithms", 3, True, 2), S("SQL", 3), S("Communication", 3)]})["id"],
    "tcs": call(PRIYA, "POST", "/job-roles", {"company_id": co["TCS"], "title": "Ninja - Assistant System Engineer", "package_lpa": 3.6, "min_cgpa": 6, "max_backlogs": 1,
                                              "status": "open", "drive_date": "2026-10-20", "last_apply_date": "2026-10-10",
                                              "skills": [S("Aptitude", 3, True, 2), S("Communication", 3), S("Java", 2)]})["id"],
    "infosys": call(PRIYA, "POST", "/job-roles", {"company_id": co["Infosys"], "title": "Systems Engineer", "package_lpa": 4.5, "min_cgpa": 6.5, "max_backlogs": 0,
                                                  "status": "upcoming", "drive_date": "2026-12-10",
                                                  "skills": [S("Python", 3), S("SQL", 3, True), S("Aptitude", 3, True), S("Communication", 4)]})["id"],
}

print("analyzer + shortlist")
for key, rid in roles.items():
    r = call(PRIYA, "POST", f"/job-roles/{rid}/analyze")
    print(f"  {key}: {r['eligible']} of {r['total']} eligible; top: {', '.join(m['name'] for m in r['matches'][:3])}")
zoho = call(PRIYA, "GET", f"/job-roles/{roles['zoho']}/matches")
top = [m["student_id"] for m in zoho["matches"] if m["is_eligible"]]
call(PRIYA, "POST", f"/job-roles/{roles['zoho']}/shortlist", {"student_ids": top})
tcs = [m["student_id"] for m in call(PRIYA, "GET", f"/job-roles/{roles['tcs']}/matches")["matches"] if m["is_eligible"]][:4]
call(PRIYA, "POST", f"/job-roles/{roles['tcs']}/shortlist", {"student_ids": tcs})
apps = call(PRIYA, "GET", f"/job-roles/{roles['zoho']}/applications")
arun = next((a for a in apps if a["register_no"] == "25CS001"), None)
if arun:
    call(PRIYA, "PATCH", f"/applications/{arun['id']}", {"status": "in_process", "remarks": "Cleared technical round"})
    call(PRIYA, "PATCH", f"/applications/{arun['id']}", {"status": "selected"})
    print("  Arun Kumar selected at Zoho (8.4 LPA)")
for a in call(PRIYA, "GET", f"/job-roles/{roles['tcs']}/applications")[:2]:
    call(PRIYA, "PATCH", f"/applications/{a['id']}", {"status": "applied"})
stats = call(PRIYA, "GET", "/placements/stats")
print(f"  placed {stats['placed_students']}/{stats['total_students']} students, highest {stats['highest_package']} LPA")
