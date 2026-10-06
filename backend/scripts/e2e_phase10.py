"""End-to-end test for Phase 10 (blended skill scores, subject -> skill mapping, certificate
verification, the career catalogue, career matches with gaps and courses, tunable weights).

Runs against the demo data (seed_demo.py + seed_demo_marks.py + seed_demo_placement.py) and puts
back every weight, mapping, certificate and career it touches, so it can be re-run.
  API_URL=http://localhost:8090/api/v1 python scripts/e2e_phase10.py
"""
import os
import random
import sys

import requests

B = os.environ.get("API_URL", "http://localhost:8080/api/v1")
ENV = os.path.join(os.path.dirname(__file__), "..", ".env")
ADMIN_PW = next(l.split("=", 1)[1].strip() for l in open(ENV) if l.startswith("ADMIN_PASSWORD="))
SFX = str(random.randint(1000, 9999))
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


def get(h, path, **kw):
    return requests.get(B + path, headers=h, **kw)


def data(h, path):
    r = get(h, path)
    if r.status_code != 200:
        sys.exit(f"GET {path}: {r.status_code} {r.text}")
    return r.json()["data"]


def put(h, path, body):
    return requests.put(B + path, headers=h, json=body)


def post(h, path, body=None):
    return requests.post(B + path, headers=h, json=body or {})


A = login("admin", ADMIN_PW)
MEENA = login("meena", "Staff@1234")    # staff, CSE, incharge CSE II-A
KAVYA = login("kavya", "Staff@1234")    # CSE HOD
SURESH = login("suresh", "Staff@1234")  # ECE HOD
ARUN = login("25cs001", "Student@123")  # 25CS001: Java 4, DSA 4, SQL 3, Communication 4, Aptitude 4
PARENT = login("p9200000001", "Parent@123")

students = {s["register_no"]: s for s in data(A, "/students?page_size=200")}
ARUN_ID = students["25CS001"]["id"]
EC_ID = students["25EC001"]["id"]
skills = {s["name"]: s["id"] for s in data(A, "/skills?all=true")}
subjects = {s["code"]: s["id"] for s in data(A, "/subjects?all=true")}
exams = {e["code"]: e["id"] for e in data(A, "/exam-types?all=true")}
cls = next(c for c in data(A, "/classes") if c["label"] == "CSE II-A")

# --------------------------------------------------------------- career catalogue
print("career catalogue (seeded)")
careers = check("admin lists careers", get(A, "/careers"), 200)
expect("the seeded catalogue is there", len(careers) >= 12, len(careers))
by_code = {c["code"]: c for c in careers}
expect("SDE is seeded with a domain and a package", by_code["SDE"]["domain"] == "IT / Software"
       and by_code["SDE"]["avg_package"] > 0, by_code.get("SDE"))
sde_skills = {s["skill_name"]: s for s in by_code["SDE"]["skills"]}
expect("SDE requires DSA at level 4 as a core skill",
       sde_skills["Data Structures & Algorithms"]["required_level"] == 4
       and sde_skills["Data Structures & Algorithms"]["is_core"] is True, sde_skills.get("Data Structures & Algorithms"))
expect("core skills are listed before optional ones", by_code["SDE"]["skills"][0]["is_core"] is True)
expect("careers count their courses", by_code["SDE"]["course_count"] > 0, by_code["SDE"]["course_count"])

domains = check("domains for the filter", get(A, "/careers/domains"), 200)
expect("domains are distinct", len(domains) == len(set(domains)) and "Data" in domains, domains)
expect("search narrows the list", len(data(A, "/careers?search=backend")) == 1, data(A, "/careers?search=backend"))
expect("domain filter works", all(c["domain"] == "Data" for c in data(A, "/careers?domain=Data")))
check("unknown career is a 404", get(A, "/careers/999999"), 404)

courses = check("courses for a career", get(A, "/careers/" + str(by_code["ML_ENG"]["id"]) + "/courses"), 200)
expect("ML courses cover Python and Machine Learning",
       {"Python", "Machine Learning"} <= {c["skill_name"] for c in courses}, [c["skill_name"] for c in courses])
expect("courses carry a provider", all(c["provider"] for c in courses), courses[:1])

all_courses = check("course master lists the seeded courses", get(A, "/courses?all=true"), 200)
expect("every course names its skill", all(c["skill_name"] for c in all_courses), len(all_courses))

# --------------------------------------------------------------- weights
print("scoring weights")
cfg = check("admin reads the scoring config", get(A, "/config/scoring"), 200)
settings = {s["key"]: s["value"] for s in cfg["settings"]}
expect("both settings are seeded", set(settings) == {"skill_score_weights", "match_weights"}, list(settings))
expect("the four sources are named", cfg["skill_sources"] == ["declared", "test", "cert", "academic"], cfg["skill_sources"])
ORIGINAL_W = dict(settings["skill_score_weights"])
ORIGINAL_M = dict(settings["match_weights"])
expect("weights sum to 1", abs(sum(ORIGINAL_W.values()) - 1) < 1e-9, ORIGINAL_W)
check("a student cannot read the scoring config", get(ARUN, "/config/scoring"), 403)
check("an HOD can read it", get(KAVYA, "/config/scoring"), 200)
check("an HOD cannot change it", put(KAVYA, "/config/scoring", {"match_weights": {"skill": 1, "academic": 0}}), 403)
check("unknown weight key rejected", put(A, "/config/scoring", {"skill_score_weights": {"vibes": 1}}), 400)
check("all-zero weights rejected", put(A, "/config/scoring", {"skill_score_weights": {"declared": 0, "test": 0}}), 400)
check("out-of-range weight rejected", put(A, "/config/scoring", {"match_weights": {"skill": 7}}), 400)
check("empty body rejected", put(A, "/config/scoring", {}), 400)

# --------------------------------------------------------------- blended scores
print("blended skill scores")
check("recompute needs a target", post(A, "/skill-scores/recompute", {}), 400)
check("a class HOD cannot recompute everyone", post(KAVYA, "/skill-scores/recompute", {"all": True}), 403)
check("CSE staff cannot recompute an ECE student", post(MEENA, "/skill-scores/recompute", {"student_ids": [EC_ID]}), 404)
res = check("recompute one student", post(MEENA, "/skill-scores/recompute", {"student_ids": [ARUN_ID]}), 200)
expect("one student recomputed", res["students"] == 1, res)
res = check("recompute a whole class", post(A, "/skill-scores/recompute", {"class_id": cls["id"]}), 200)
expect("the class was recomputed", res["students"] >= 4, res)

sc = check("student reads their own scores", get(ARUN, f"/students/{ARUN_ID}/skill-scores"), 200)
expect("scores were computed", sc["computed_at"] is not None and len(sc["scores"]) == 5, len(sc["scores"]))
expect("scores come back highest first", [s["score"] for s in sc["scores"]] == sorted((s["score"] for s in sc["scores"]), reverse=True))
java = next(s for s in sc["scores"] if s["name"] == "Java")
expect("Java level 4 becomes a declared score of 80", java["sources"]["declared"] == 80, java["sources"])
expect("with only one source the blend equals it", java["score"] == 80, java)
expect("the 1-5 level round-trips", java["level"] == 4, java)
expect("the response repeats the weights in force", sc["weights"] == ORIGINAL_W, sc["weights"])
check("a parent sees their child's scores", get(PARENT, f"/students/{ARUN_ID}/skill-scores"), 200)
check("another department's HOD does not", get(SURESH, f"/students/{ARUN_ID}/skill-scores"), 404)

# --------------------------------------------------------------- subject -> skill mapping
print("subject to skill mapping")
maps = check("admin lists the subject mapping", get(A, "/subject-skills"), 200)
expect("every subject is listed", maps["total"] == len(subjects), (maps["total"], len(subjects)))
expect("nothing is mapped to begin with", maps["mapped"] == 0, maps["mapped"])
expect("the unmapped filter agrees", data(A, "/subject-skills?mapped=false")["total"] == maps["total"])
check("a student may read the mapping (it is just what a subject teaches)", get(ARUN, "/subject-skills"), 200)
check("but cannot change it", put(ARUN, f"/subjects/{subjects['CS3301']}/skills", {"skills": []}), 403)
check("duplicate skills rejected", put(A, f"/subjects/{subjects['CS3301']}/skills",
      {"skills": [{"skill_id": skills["Java"]}, {"skill_id": skills["Java"]}]}), 400)
check("unknown skill rejected", put(A, f"/subjects/{subjects['CS3301']}/skills", {"skills": [{"skill_id": 999999}]}), 400)
check("unknown subject is a 404", put(A, "/subjects/999999/skills", {"skills": []}), 404)
check("staff cannot change the mapping", put(MEENA, f"/subjects/{subjects['CS3301']}/skills", {"skills": []}), 403)

m = check("map CS3301 to Java and DSA", put(A, f"/subjects/{subjects['CS3301']}/skills",
         {"skills": [{"skill_id": skills["Java"], "weight": 2}, {"skill_id": skills["Data Structures & Algorithms"]}]}), 200)
expect("the mapping comes back", {s["name"] for s in m["skills"]} == {"Java", "Data Structures & Algorithms"}, m["skills"])
expect("the weight is kept", next(s for s in m["skills"] if s["name"] == "Java")["weight"] == 2, m["skills"])
expect("an omitted weight defaults to 1",
       next(s for s in m["skills"] if s["name"] != "Java")["weight"] == 1, m["skills"])
expect("heavier skills are listed first", m["skills"][0]["name"] == "Java", m["skills"])
expect("the overview counts it as mapped", data(A, "/subject-skills?mapped=true")["total"] == 1)

print("marks now reach the skill score")
sc = data(ARUN, f"/students/{ARUN_ID}/skill-scores")
java = next(s for s in sc["scores"] if s["name"] == "Java")
expect("mapping a subject added an academic source", "academic" in java["sources"], java["sources"])
expect("the academic score is a percentage", 0 <= java["sources"]["academic"] <= 100, java["sources"])
blend = sum(java["sources"][k] * ORIGINAL_W[k] for k in java["sources"]) / sum(ORIGINAL_W[k] for k in java["sources"])
expect("the blend is the renormalised weighted average", abs(java["score"] - round(blend, 2)) < 0.01,
       (java["score"], round(blend, 2), java["sources"]))
expect("declared alone no longer decides the score", java["score"] != 80, java["score"])
acad = next(p for p in java["breakdown"] if p["source"] == "academic")
expect("the breakdown names each source and its weight",
       {p["source"] for p in java["breakdown"]} == {"declared", "academic"}
       and acad["weight"] == ORIGINAL_W["academic"], java["breakdown"])
expect("the academic detail says which subjects were used",
       [s["subject_id"] for s in acad["detail"]["subjects"]] == [subjects["CS3301"]], acad["detail"])
expect("and at what percentage", acad["detail"]["subjects"][0]["percent"] == acad["score"], acad["detail"])
expect("declared evidence is the recorded proficiency",
       next(p for p in java["breakdown"] if p["source"] == "declared")["detail"]["proficiency"] == 4, java["breakdown"])

print("saving marks refreshes the score on its own")
# The academic score follows the final exam when there is one, so move the End Semester mark.
SEM_Q = "class_id=%d&semester_id=%d&subject_id=%d&exam_type_id=%d&attempt_no=1" % (
    cls["id"], cls["current_semester_id"], subjects["CS3301"], exams["SEM"])
SEM_KEY = {"class_id": cls["id"], "semester_id": cls["current_semester_id"], "subject_id": subjects["CS3301"],
           "exam_type_id": exams["SEM"], "attempt_no": 1}
before = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
entry = data(MEENA, "/marks/entry?" + SEM_Q)
arun_mark = {r["register_no"]: r["marks_obtained"] for r in entry["rows"]}["25CS001"]
expect("the demo student has an End Semester mark", arun_mark is not None, arun_mark)
expect("which is what the academic score is built from",
       abs(before["sources"]["academic"] - arun_mark) < 0.01, (before["sources"]["academic"], arun_mark))
check("staff saves a lower mark", put(MEENA, "/marks/entry",
      dict(SEM_KEY, entries=[{"student_id": ARUN_ID, "marks_obtained": arun_mark - 20}])), 200)
dropped = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
expect("the academic source moved with the mark", dropped["sources"]["academic"] < before["sources"]["academic"],
       (before["sources"]["academic"], dropped["sources"]["academic"]))
expect("the blended score moved with it", dropped["score"] < before["score"], (before["score"], dropped["score"]))
check("mark restored", put(MEENA, "/marks/entry",
      dict(SEM_KEY, entries=[{"student_id": ARUN_ID, "marks_obtained": arun_mark}])), 200)
after = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
expect("and back again once the mark is put back", abs(after["score"] - before["score"]) < 0.01,
       (before["score"], after["score"]))

# --------------------------------------------------------------- certificate verification
print("certificate verification")
check("verifying an unrecorded skill is a 404", put(MEENA, f"/students/{ARUN_ID}/skills/{skills['Docker']}/verify", {"verified": True}), 404)
check("verifying without a certificate is refused", put(MEENA, f"/students/{ARUN_ID}/skills/{skills['SQL']}/verify", {"verified": True}), 400)
check("verified is required", put(MEENA, f"/students/{ARUN_ID}/skills/{skills['SQL']}/verify", {}), 400)
check("a student cannot verify their own certificate", put(ARUN, f"/students/{ARUN_ID}/skills/{skills['SQL']}/verify", {"verified": True}), 403)
check("attach a certificate to SQL", put(MEENA, f"/students/{ARUN_ID}/skills",
      {"skill_id": skills["SQL"], "proficiency": 3, "source": "certification",
       "certificate_url": "https://example.com/sql-cert"}), 200)
sql_before = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "SQL")
expect("an unverified certificate adds nothing", "cert" not in sql_before["sources"], sql_before["sources"])
lst = check("staff verifies it", put(MEENA, f"/students/{ARUN_ID}/skills/{skills['SQL']}/verify", {"verified": True}), 200)
sql_row = next(s for s in lst if s["name"] == "SQL")
expect("the skill is flagged verified", sql_row["certificate_verified"] is True, sql_row)
expect("who verified it is recorded", sql_row["certificate_verified_by"] == "Meena Devi"
       and sql_row["certificate_verified_at"], sql_row)
sql_after = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "SQL")
expect("verification adds a cert source", sql_after["sources"].get("cert") == 60, sql_after["sources"])
expect("the skill list carries the blended score", abs(sql_row["score"] - sql_after["score"]) < 0.01, (sql_row["score"], sql_after["score"]))
lst = check("verification can be withdrawn", put(MEENA, f"/students/{ARUN_ID}/skills/{skills['SQL']}/verify", {"verified": False}), 200)
expect("the flag is cleared", next(s for s in lst if s["name"] == "SQL")["certificate_verified"] is False)
sql_clear = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "SQL")
expect("the cert source goes away with it", "cert" not in sql_clear["sources"], sql_clear["sources"])
check("SQL skill restored", put(MEENA, f"/students/{ARUN_ID}/skills",
      {"skill_id": skills["SQL"], "proficiency": 3, "source": "assessment", "remove_certificate": True}), 200)

# --------------------------------------------------------------- career matches
print("career matches")
check("CSE staff cannot run matches for an ECE student", post(MEENA, f"/students/{EC_ID}/career-matches"), 404)
check("a student cannot run the matcher", post(ARUN, f"/students/{ARUN_ID}/career-matches"), 403)
run = check("staff runs the matcher", post(MEENA, f"/students/{ARUN_ID}/career-matches"), 200)
expect("every career is ranked", run["total"] == len(careers), (run["total"], len(careers)))
expect("ranks are 1..n in score order", [m["rank"] for m in run["matches"]] == list(range(1, len(run["matches"]) + 1)))
expect("scores descend", all(run["matches"][i]["final_score"] >= run["matches"][i + 1]["final_score"]
       for i in range(len(run["matches"]) - 1)))
expect("a fresh run is not stale", run["is_stale"] is False, run["is_stale"])
expect("readiness is counted", sum(run["counts"].values()) == run["total"], run["counts"])
top = run["matches"][0]
expect("the top match explains itself", len(top["explanation"]) > 30 and top["explanation"].endswith("."), top["explanation"])
expect("the top match names its skill and academic parts",
       0 <= top["skill_score"] <= 100 and 0 <= top["academic_score"] <= 100, (top["skill_score"], top["academic_score"]))
SK_W, AC_W = ORIGINAL_M["skill"], ORIGINAL_M["academic"]
expect("final score is the configured blend of the two",
       abs(top["final_score"] - round(SK_W * top["skill_score"] + AC_W * top["academic_score"], 2)) < 0.02,
       (top["final_score"], top["skill_score"], top["academic_score"]))
expect("strengths and gaps cover the requirements",
       all(len(m["strengths"]) + len(m["gaps"]) == len(by_code[m["code"]]["skills"]) for m in run["matches"]))
expect("a met requirement has no gap", all(s["gap"] == 0 for s in top["strengths"]), top["strengths"][:1])
expect("a missing requirement reports how far off it is",
       all(g["gap"] > 0 and g["score"] < g["required_score"] for m in run["matches"] for g in m["gaps"]))
expect("gaps list core requirements first",
       all(not (m["gaps"][i]["is_core"] is False and m["gaps"][i + 1]["is_core"] is True)
           for m in run["matches"] for i in range(len(m["gaps"]) - 1)))
with_courses = [g for m in run["matches"] for g in m["gaps"] if g.get("courses")]
expect("gaps come with something to study", len(with_courses) > 0, len(with_courses))
expect("suggested courses carry a title", all(c["title"] for g in with_courses for c in g["courses"]))
expect("at most three courses per gap", all(len(g["courses"]) <= 3 for g in with_courses))

backend = next(m for m in run["matches"] if m["code"] == "BACKEND")
expect("25CS001 (Java 4) counts Java as a backend strength",
       "Java" in {s["name"] for s in backend["strengths"]}, backend["strengths"])
expect("Spring Boot, which the student has not recorded, is a gap with level 0",
       next(g for g in backend["gaps"] if g["name"] == "Spring Boot")["level"] == 0, backend["gaps"])

print("students and parents read the stored ranking")
mine = check("the student reads their own matches", get(ARUN, f"/students/{ARUN_ID}/career-matches"), 200)
expect("they see the same ranking", [m["career_id"] for m in mine["matches"]] == [m["career_id"] for m in run["matches"]])
check("a parent sees their child's matches", get(PARENT, f"/students/{ARUN_ID}/career-matches"), 200)
check("an unrelated department's HOD does not", get(SURESH, f"/students/{ARUN_ID}/career-matches"), 404)
ready = data(ARUN, f"/students/{ARUN_ID}/career-matches?readiness=explore")
expect("readiness filters the list", all(m["readiness"] == "explore" for m in ready["matches"])
       and ready["total"] == run["total"], len(ready["matches"]))
expect("limit trims the list", len(data(ARUN, f"/students/{ARUN_ID}/career-matches?limit=3")["matches"]) == 3)

print("a ranking goes stale when the scores move")
check("record Spring Boot at level 4", put(MEENA, f"/students/{ARUN_ID}/skills",
      {"skill_id": skills["Spring Boot"], "proficiency": 4, "source": "assessment"}), 200)
stale = data(ARUN, f"/students/{ARUN_ID}/career-matches")
expect("the stored ranking is flagged stale", stale["is_stale"] is True)
expect("every row is flagged", all(m["is_stale"] for m in stale["matches"]))
fresh = data(ARUN, f"/students/{ARUN_ID}/career-matches?refresh=true")
expect("refreshing clears the flag", fresh["is_stale"] is False)
backend2 = next(m for m in fresh["matches"] if m["code"] == "BACKEND")
expect("the new skill became a strength", "Spring Boot" in {s["name"] for s in backend2["strengths"]},
       backend2["strengths"])
expect("the backend match score went up", backend2["skill_score"] > backend["skill_score"],
       (backend["skill_score"], backend2["skill_score"]))
check("remove the test skill", requests.delete(B + f"/students/{ARUN_ID}/skills/{skills['Spring Boot']}", headers=MEENA), 200)

print("feedback")
check("rating is required", post(ARUN, f"/students/{ARUN_ID}/career-matches/{by_code['SDE']['id']}/feedback", {}), 400)
check("rating must be 1-5", post(ARUN, f"/students/{ARUN_ID}/career-matches/{by_code['SDE']['id']}/feedback", {"rating": 9}), 400)
check("feedback on an unknown career is a 404", post(ARUN, f"/students/{ARUN_ID}/career-matches/999999/feedback", {"rating": 4}), 404)
check("another student's feedback is refused", post(ARUN, f"/students/{EC_ID}/career-matches/{by_code['SDE']['id']}/feedback", {"rating": 4}), 404)
fb = check("the student rates a suggestion", post(ARUN, f"/students/{ARUN_ID}/career-matches/{by_code['SDE']['id']}/feedback",
          {"rating": 5, "comment": "This is what I want to do"}), 200)
sde = next(m for m in fb["matches"] if m["code"] == "SDE")
expect("the rating is attached to the match", sde["feedback"]["rating"] == 5, sde["feedback"])
expect("a high rating counts as useful", sde["feedback"]["is_useful"] is True, sde["feedback"])
expect("the comment is kept", sde["feedback"]["comment"] == "This is what I want to do", sde["feedback"])
fb = check("rating again replaces it", post(ARUN, f"/students/{ARUN_ID}/career-matches/{by_code['SDE']['id']}/feedback",
          {"rating": 2, "is_useful": False}), 200)
sde = next(m for m in fb["matches"] if m["code"] == "SDE")
expect("the new rating wins", sde["feedback"]["rating"] == 2 and sde["feedback"]["is_useful"] is False, sde["feedback"])
expect("other careers have no feedback", all(m["feedback"] is None for m in fb["matches"] if m["code"] != "SDE"))

# --------------------------------------------------------------- the analyzer reads the blend
print("the placement analyzer uses the blended scores")
roles = data(A, "/job-roles")
role = next(r for r in roles if "Java" in {s["skill_name"] for s in r["skills"]})
rank = check("run the analyzer", post(A, f"/job-roles/{role['id']}/analyze"), 200)
expect("a fresh ranking has nothing stale", rank["stale"] == 0, rank["stale"])
arun = next(m for m in rank["matches"] if m["student_id"] == ARUN_ID)
gaps = arun["matched_skills"] + arun["missing_skills"]
expect("each requirement carries the blended score and the score needed",
       all("student_score" in g and g["required_score"] == g["required_level"] * 20 for g in gaps), gaps[:1])
java_req = next((g for g in gaps if g["name"] == "Java"), None)
expect("Java is scored from the blend, not the typed level",
       java_req is not None and abs(java_req["student_score"] - after["score"]) < 0.01,
       (java_req or {}).get("student_score"))
expect("the 1-5 level still comes through", all(0 <= g["student_level"] <= 5 for g in gaps))
check("record a skill to age the ranking", put(MEENA, f"/students/{ARUN_ID}/skills",
      {"skill_id": skills["Docker"], "proficiency": 3, "source": "assessment"}), 200)
cached = data(A, f"/job-roles/{role['id']}/matches")
expect("the cached ranking knows it is behind", cached["stale"] >= 1, cached["stale"])
expect("the affected student is the one flagged",
       next(m for m in cached["matches"] if m["student_id"] == ARUN_ID)["is_stale"] is True)
check("remove the test skill", requests.delete(B + f"/students/{ARUN_ID}/skills/{skills['Docker']}", headers=MEENA), 200)
check("re-run the analyzer to leave it fresh", post(A, f"/job-roles/{role['id']}/analyze"), 200)

# --------------------------------------------------------------- weight change
print("changing the weights changes the scores")
check("admin puts everything on the declared level", put(A, "/config/scoring", {"skill_score_weights":
      {"declared": 1, "test": 0, "cert": 0, "academic": 0}}), 200)
check("recompute with the new weights", post(A, "/skill-scores/recompute", {"student_ids": [ARUN_ID]}), 200)
java_only = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
expect("Java is back to the declared 80 alone", java_only["score"] == 80, java_only)
check("weights restored", put(A, "/config/scoring", {"skill_score_weights": ORIGINAL_W, "match_weights": ORIGINAL_M}), 200)
check("recompute with the original weights", post(A, "/skill-scores/recompute", {"student_ids": [ARUN_ID]}), 200)
restored = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
expect("the original blend is back", abs(restored["score"] - after["score"]) < 0.01, (restored["score"], after["score"]))

# --------------------------------------------------------------- career CRUD
print("career CRUD")
body = {"code": "TEST" + SFX, "name": "Test Career " + SFX, "domain": "QA / Test", "min_cgpa": 7.5,
        "avg_package": 9.25, "description": "Created by the Phase 10 test",
        "skills": [{"skill_id": skills["Python"], "required_level": 3, "weight": 2, "is_core": True},
                   {"skill_id": skills["Git"], "required_level": 2}]}
check("a student cannot create a career", post(ARUN, "/careers", body), 403)
check("an HOD can", post(KAVYA, "/careers", dict(body, code="HOD" + SFX, name="HOD career " + SFX)), 200)
new = check("admin creates a career", post(A, "/careers", body), 200)
expect("it comes back with its skills", len(new["skills"]) == 2 and new["min_cgpa"] == 7.5, new)
expect("the code is upper-cased", new["code"] == ("TEST" + SFX).upper(), new["code"])
expect("an omitted weight defaults to 1", next(s for s in new["skills"] if s["skill_name"] == "Git")["weight"] == 1)
check("a duplicate code is a conflict", post(A, "/careers", body), 409)
check("a duplicate skill is rejected", post(A, "/careers", dict(body, code="DUP" + SFX, skills=[
      {"skill_id": skills["Python"], "required_level": 3}, {"skill_id": skills["Python"], "required_level": 4}])), 400)
check("an unknown skill is rejected", post(A, "/careers", dict(body, code="BAD" + SFX,
      skills=[{"skill_id": 999999, "required_level": 3}])), 400)
check("required_level must be 1-5", post(A, "/careers", dict(body, code="LVL" + SFX,
      skills=[{"skill_id": skills["Python"], "required_level": 9}])), 400)
up = check("admin edits it", put(A, f"/careers/{new['id']}", dict(body, name="Renamed " + SFX,
          skills=[{"skill_id": skills["Python"], "required_level": 5, "is_core": True}])), 200)
expect("the edit replaced the skills", len(up["skills"]) == 1 and up["skills"][0]["required_level"] == 5, up["skills"])
expect("the new career appears in a student's matches",
       new["id"] in {m["career_id"] for m in data(ARUN, f"/students/{ARUN_ID}/career-matches?refresh=true")["matches"]})
check("a student cannot delete a career", requests.delete(B + f"/careers/{new['id']}", headers=ARUN), 403)
check("admin deletes it", requests.delete(B + f"/careers/{new['id']}", headers=A), 200)
check("it is gone", get(A, f"/careers/{new['id']}"), 404)
expect("and gone from the stored matches too",
       new["id"] not in {m["career_id"] for m in data(ARUN, f"/students/{ARUN_ID}/career-matches")["matches"]})
hodc = next(c for c in data(A, "/careers") if c["code"] == ("HOD" + SFX).upper())
check("clean up the HOD's career", requests.delete(B + f"/careers/{hodc['id']}", headers=A), 200)

print("course CRUD")
co = check("admin adds a course", post(A, "/courses", {"skill_id": skills["Git"], "title": "Git Deep Dive " + SFX,
          "provider": "Internal", "level": 4, "duration_hours": 12, "is_certification": True, "is_free": False}), 201)
expect("it names its skill", co["skill_name"] == "Git", co)
check("a student cannot add a course", post(ARUN, "/courses", {"skill_id": skills["Git"], "title": "x"}), 403)
check("a course needs a skill", post(A, "/courses", {"title": "No skill"}), 400)
check("admin deletes the course", requests.delete(B + f"/courses/{co['id']}", headers=A), 200)

print("a skill in use cannot be deleted")
check("a mapped skill is protected", requests.delete(B + f"/skills/{skills['Java']}", headers=A), 409)

# --------------------------------------------------------------- put the mapping back
print("cleanup")
check("CS3301 mapping removed", put(A, f"/subjects/{subjects['CS3301']}/skills", {"skills": []}), 200)
expect("nothing is mapped again", data(A, "/subject-skills")["mapped"] == 0)
check("scores recomputed without it", post(A, "/skill-scores/recompute", {"class_id": cls["id"]}), 200)
final = next(s for s in data(A, f"/students/{ARUN_ID}/skill-scores")["scores"] if s["name"] == "Java")
expect("Java is back to the declared level alone", final["score"] == 80 and "academic" not in final["sources"], final)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
