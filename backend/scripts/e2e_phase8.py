"""End-to-end test for Phase 8 (file uploads: photos, resumes, student documents, skill certificates,
company logos, job descriptions, offer letters, notification attachments, signed links).

Runs against the demo data (seed_demo.py) and removes every file it attaches, so it can be re-run.
  API_URL=http://localhost:8090/api/v1 python scripts/e2e_phase8.py
"""
import os
import struct
import sys
import zlib

import requests

B = os.environ.get("API_URL", "http://localhost:8080/api/v1")
ENV = os.path.join(os.path.dirname(__file__), "..", ".env")
ADMIN_PW = next(l.split("=", 1)[1].strip() for l in open(ENV) if l.startswith("ADMIN_PASSWORD="))
PASS = FAIL = 0


def check(name, resp, status):
    global PASS, FAIL
    ok = resp.status_code == status
    PASS += ok
    FAIL += not ok
    print(f"  {'ok  ' if ok else 'FAIL'} {name} ({resp.status_code}){'' if ok else ' ' + resp.text[:300]}")
    try:
        return resp.json().get("data")
    except ValueError:
        return None


def expect(name, cond, info=""):
    global PASS, FAIL
    PASS += bool(cond)
    FAIL += not cond
    print(f"  {'ok  ' if cond else 'FAIL'} {name} {info}")


def login(u, p):
    r = requests.post(f"{B}/auth/login", json={"username": u, "password": p})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["data"]["access_token"]}


def data(h, path):
    r = requests.get(B + path, headers=h)
    if r.status_code != 200:
        sys.exit(f"GET {path}: {r.status_code} {r.text}")
    return r.json()["data"]


def png(w=4, h=4, pad=0):
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    body = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    return body + b"\x00" * pad


PDF = b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"


def upload(h, category, content, name="file.bin"):
    return requests.post(f"{B}/files", headers=h, files={"file": (name, content)}, data={"category": category})


def fetch(link):
    return requests.get(B + link["url"])


A = login("admin", ADMIN_PW)
MEENA = login("meena", "Staff@1234")   # staff, CSE
SURESH = login("suresh", "Staff@1234")  # ECE HOD
PRIYA = login("priya", "Staff@1234")   # staff + placement officer
ARUN = login("25cs001", "Student@123")
PARENT = login("p9200000001", "Parent@123")
students = {s["register_no"]: s for s in data(A, "/students?page_size=200&status=all")}
arun, anjali, bharath, lakshmi = (students[r]["id"] for r in ("25CS001", "25CS002", "25CS003", "25EC001"))
arun_me = data(ARUN, "/auth/me")

# ---------------------------------------------------------------- upload + signed links
print("upload and signed links")
check("upload needs a login", requests.post(f"{B}/files", files={"file": ("a.png", png())}, data={"category": "profile_photo"}), 401)
photo = check("student uploads a photo", upload(ARUN, "profile_photo", png(), "me.png"), 201)
expect("upload returns id, url, type", photo and photo["id"] and photo["url"].startswith("/files/") and photo["type"] == "image/png", photo)
r = fetch(photo)
check("signed link serves the file without a login", r, 200)
expect("bytes and headers", r.content == png() and r.headers["Content-Type"] == "image/png" and r.headers.get("X-Content-Type-Options") == "nosniff",
       r.headers.get("Content-Type"))
expect("inline with original name", 'inline; filename="me.png"' in r.headers.get("Content-Disposition", ""), r.headers.get("Content-Disposition"))
r = requests.get(B + photo["url"] + "&download=1")
expect("download=1 forces attachment", r.headers.get("Content-Disposition", "").startswith("attachment"))
base, q = photo["url"].split("?")
params = dict(p.split("=") for p in q.split("&"))
check("tampered signature refused", requests.get(f"{B}{base}?exp={params['exp']}&sig=AAAA{params['sig'][4:]}"), 403)
check("changed expiry refused", requests.get(f"{B}{base}?exp={int(params['exp']) + 3600}&sig={params['sig']}"), 403)
check("expired link refused", requests.get(f"{B}{base}?exp=1000&sig={params['sig']}"), 403)
check("signature is bound to the file", requests.get(f"{B}/files/00000000-0000-0000-0000-000000000000?exp={params['exp']}&sig={params['sig']}"), 403)
check("unknown category", upload(ARUN, "tax_return", png()), 400)
check("missing file field", requests.post(f"{B}/files", headers=ARUN, data={"category": "profile_photo"}), 400)
r = upload(ARUN, "profile_photo", b"<html><script>alert(1)</script></html>", "evil.png")
check("HTML renamed to .png is refused (content sniffed)", r, 400)
check("SVG refused", upload(ARUN, "profile_photo", b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "x.svg"), 400)
check("PDF is not a photo", upload(ARUN, "profile_photo", PDF, "cv.pdf"), 400)
check("image is not a resume", upload(ARUN, "resume", png(), "cv.png"), 400)
r = upload(ARUN, "profile_photo", png(pad=2 * 1024 * 1024 + 10), "big.png")
check("photo over 2 MB refused", r, 400)
expect("size message names the limit", "2 MB" in r.text, r.text[:100])
check("students cannot upload company logos", upload(ARUN, "company_logo", png()), 403)
check("students cannot upload notice attachments", upload(ARUN, "notification_attachment", PDF), 403)
pdf_up = check("PDF name gets the real extension", upload(ARUN, "resume", PDF, 'C:\\fakepath\\my "cv".txt'), 201)
expect("cleaned name", pdf_up and pdf_up["name"] == "my cv.pdf", pdf_up and pdf_up["name"])

# ---------------------------------------------------------------- profile photos
print("profile photos")
r = requests.put(f"{B}/users/me/photo", headers=ARUN, json={"file_id": photo["id"]})
res = check("student sets own photo", r, 200)
expect("photo link returned", res and res["photo"] and res["photo"]["name"] == "me.png")
me = data(ARUN, "/auth/me")
expect("/auth/me carries the photo", me.get("photo") and fetch(me["photo"]).status_code == 200)
st = data(A, f"/students/{arun}")
expect("student profile shows the photo", st.get("photo") and st["photo"]["name"] == "me.png")
expect("student list shows the photo", any(s["id"] == arun and s.get("photo") for s in data(A, "/students?search=25CS001")))
check("same file cannot be set as someone else's photo", requests.put(f"{B}/users/{anjali}/photo", headers=A, json={"file_id": photo["id"]}), 400)
other = check("anjali uploads", upload(login("25cs002", "Student@123"), "profile_photo", png(), "anj.png"), 201)
check("cannot attach a file someone else uploaded", requests.put(f"{B}/users/me/photo", headers=ARUN, json={"file_id": other["id"]}), 403)
check("category must match the slot", requests.put(f"{B}/students/{arun}/resume", headers=ARUN, json={"file_id": data(ARUN, "/auth/me")["id"] and photo["id"]}), 400)
photo2 = check("upload a replacement", upload(ARUN, "profile_photo", png(8, 8), "new.png"), 201)
old_link = me["photo"]
check("replace photo", requests.put(f"{B}/users/me/photo", headers=ARUN, json={"file_id": photo2["id"]}), 200)
check("old photo link stops working", fetch(old_link), 404)
check("student cannot set another user's photo", requests.put(f"{B}/users/{anjali}/photo", headers=ARUN, json={"file_id": None}), 403)
m_photo = check("staff uploads a photo", upload(MEENA, "profile_photo", png(), "anjali.png"), 201)
check("staff sets a photo for a student in their department", requests.put(f"{B}/users/{anjali}/photo", headers=MEENA, json={"file_id": m_photo["id"]}), 200)
check("staff cannot set a photo for another department's student", requests.put(f"{B}/users/{lakshmi}/photo", headers=MEENA, json={"file_id": None}), 404)
check("plain staff cannot set another staff member's photo", requests.put(f"{B}/users/{data(A, '/staff?search=priya')[0]['id']}/photo", headers=MEENA, json={"file_id": None}), 404)
a_photo = check("admin uploads", upload(A, "profile_photo", png(), "priya.png"), 201)
priya_id = data(A, "/staff?search=priya")[0]["id"]
check("admin sets a staff photo", requests.put(f"{B}/users/{priya_id}/photo", headers=A, json={"file_id": a_photo["id"]}), 200)
expect("staff list shows it", data(A, "/staff?search=priya")[0].get("photo") is not None)
expect("user list shows it", any(u["id"] == priya_id and u.get("photo") for u in data(A, "/users?search=priya")))
for uid in (arun, anjali, priya_id):
    requests.put(f"{B}/users/{uid}/photo", headers=A, json={"file_id": None})
expect("photos removed", data(ARUN, "/auth/me").get("photo") is None)

# ---------------------------------------------------------------- resume
print("resume")
check("student sets own resume", requests.put(f"{B}/students/{arun}/resume", headers=ARUN, json={"file_id": pdf_up["id"]}), 200)
st = data(PARENT, f"/students/{arun}")
expect("parent sees the resume", st.get("resume") and fetch(st["resume"]).content == PDF)
check("student cannot set a classmate's resume", requests.put(f"{B}/students/{anjali}/resume", headers=ARUN, json={"file_id": None}), 403)
check("parent cannot change the resume", requests.put(f"{B}/students/{arun}/resume", headers=PARENT, json={"file_id": None}), 403)
check("ECE HOD cannot change a CSE student's resume", requests.put(f"{B}/students/{arun}/resume", headers=SURESH, json={"file_id": None}), 404)
check("remove resume", requests.put(f"{B}/students/{arun}/resume", headers=ARUN, json={"file_id": None}), 200)
expect("resume gone", data(A, f"/students/{arun}").get("resume") is None)

# ---------------------------------------------------------------- student documents
print("student documents")
f1 = check("student uploads a document file", upload(ARUN, "student_document", PDF, "10th.pdf"), 201)
d1 = check("student adds a document", requests.post(f"{B}/students/{arun}/documents", headers=ARUN, json={"doc_type": "marksheet_10", "file_id": f1["id"]}), 201)
expect("pending, titled from its type", d1 and d1["status"] == "pending" and d1["title"] == "10th mark sheet" and d1["file"], d1)
check("file cannot be reused for a second document", requests.post(f"{B}/students/{arun}/documents", headers=ARUN, json={"doc_type": "other", "file_id": f1["id"]}), 400)
f2 = check("upload second", upload(ARUN, "student_document", png(), "aadhaar.png"), 201)
check("unknown doc_type", requests.post(f"{B}/students/{arun}/documents", headers=ARUN, json={"doc_type": "passport_xyz", "file_id": f2["id"]}), 400)
d2 = check("student adds an image document", requests.post(f"{B}/students/{arun}/documents", headers=ARUN, json={"doc_type": "id_proof", "title": "Aadhaar", "file_id": f2["id"]}), 201)
check("student cannot add to a classmate", requests.post(f"{B}/students/{anjali}/documents", headers=ARUN, json={"doc_type": "other", "file_id": f2["id"]}), 403)
lst = check("parent lists documents", requests.get(f"{B}/students/{arun}/documents", headers=PARENT), 200)
expect("parent sees both with links", len(lst["documents"]) >= 2 and all(d["file"] for d in lst["documents"]) and "marksheet_10" in lst["types"])
check("parent cannot add documents", requests.post(f"{B}/students/{arun}/documents", headers=PARENT, json={"doc_type": "other", "file_id": f2["id"]}), 403)
check("ECE HOD cannot see CSE documents", requests.get(f"{B}/students/{arun}/documents", headers=SURESH), 404)
q = check("staff verification queue", requests.get(f"{B}/documents/pending", headers=MEENA), 200)
expect("queue has Arun's documents", any(d["id"] == d1["id"] for d in q), len(q))
q = check("ECE queue", requests.get(f"{B}/documents/pending", headers=SURESH), 200)
expect("ECE queue excludes CSE", all(d["id"] not in (d1["id"], d2["id"]) for d in q))
check("student cannot use the queue", requests.get(f"{B}/documents/pending", headers=ARUN), 403)
check("student cannot verify", requests.patch(f"{B}/students/{arun}/documents/{d1['id']}", headers=ARUN, json={"status": "verified"}), 403)
v = check("staff verifies", requests.patch(f"{B}/students/{arun}/documents/{d1['id']}", headers=MEENA, json={"status": "verified"}), 200)
expect("verified by meena", v and v["status"] == "verified" and v["verified_by"] == "Meena Devi" and v["verified_at"])
notes = data(ARUN, "/notifications?page_size=3")
expect("student told it was verified", notes and notes[0]["title"] == "Document verified", notes[0]["title"] if notes else None)
expect("parent told too", data(PARENT, "/notifications?page_size=3")[0]["title"] == "Document verified")
check("reject needs a reason", requests.patch(f"{B}/students/{arun}/documents/{d2['id']}", headers=MEENA, json={"status": "rejected"}), 400)
v = check("staff rejects with a reason", requests.patch(f"{B}/students/{arun}/documents/{d2['id']}", headers=MEENA, json={"status": "rejected", "remarks": "Image is blurred"}), 200)
expect("rejected + reason", v["status"] == "rejected" and v["remarks"] == "Image is blurred")
expect("rejection notice carries the reason", "blurred" in data(ARUN, "/notifications?page_size=1")[0]["body"])
check("student cannot delete a verified document", requests.delete(f"{B}/students/{arun}/documents/{d1['id']}", headers=ARUN), 409)
link2 = d2["file"]
check("student deletes the rejected one", requests.delete(f"{B}/students/{arun}/documents/{d2['id']}", headers=ARUN), 200)
check("its file link stops working", fetch(link2), 404)
f3 = check("staff uploads for a student", upload(MEENA, "student_document", PDF, "tc.pdf"), 201)
d3 = check("staff adds a document", requests.post(f"{B}/students/{arun}/documents", headers=MEENA, json={"doc_type": "transfer_certificate", "file_id": f3["id"]}), 201)
expect("staff uploads are verified straight away", d3["status"] == "verified" and d3["uploaded_by"] == "Meena Devi")
check("staff deletes a verified document", requests.delete(f"{B}/students/{arun}/documents/{d1['id']}", headers=MEENA), 200)
check("cleanup", requests.delete(f"{B}/students/{arun}/documents/{d3['id']}", headers=A), 200)
check("deleted document is gone", requests.delete(f"{B}/students/{arun}/documents/{d3['id']}", headers=A), 404)

# ---------------------------------------------------------------- skill certificates
print("skill certificates")
have = {s["skill_id"] for s in data(A, f"/students/{arun}/skills")}
skill = next(s for s in data(A, "/skills?all=true") if s["id"] not in have)
cert = check("staff uploads a certificate", upload(MEENA, "certificate", PDF, "aws.pdf"), 201)
res = check("record a skill with its certificate", requests.put(f"{B}/students/{arun}/skills", headers=MEENA,
                                                                  json={"skill_id": skill["id"], "proficiency": 3, "source": "certification", "certificate_file_id": cert["id"]}), 200)
row = next(s for s in res if s["skill_id"] == skill["id"])
expect("certificate link on the skill", row["certificate"] and fetch(row["certificate"]).status_code == 200)
res = requests.put(f"{B}/students/{arun}/skills", headers=MEENA, json={"skill_id": skill["id"], "proficiency": 4, "source": "certification"}).json()["data"]
expect("updating the level keeps the certificate", next(s for s in res if s["skill_id"] == skill["id"])["certificate"] is not None)
expect("student sees the certificate", next(s for s in data(ARUN, f"/students/{arun}/skills") if s["skill_id"] == skill["id"])["certificate"])
res = requests.put(f"{B}/students/{arun}/skills", headers=MEENA, json={"skill_id": skill["id"], "proficiency": 4, "remove_certificate": True}).json()["data"]
expect("remove_certificate clears it", next(s for s in res if s["skill_id"] == skill["id"])["certificate"] is None)
check("certificate link dead after removal", fetch(row["certificate"]), 404)
check("cleanup skill", requests.delete(f"{B}/students/{arun}/skills/{skill['id']}", headers=MEENA), 200)

# ---------------------------------------------------------------- placement files
print("company logo, job description, offer letter")
roles = data(A, "/job-roles")
role = next(r for r in roles if r["company_name"] == "Zoho")
logo = check("placement officer uploads a logo", upload(PRIYA, "company_logo", png(), "zoho.png"), 201)
check("staff without company.update cannot set it", requests.put(f"{B}/companies/{role['company_id']}/logo", headers=MEENA, json={"file_id": logo["id"]}), 403)
check("placement officer sets the logo", requests.put(f"{B}/companies/{role['company_id']}/logo", headers=PRIYA, json={"file_id": logo["id"]}), 200)
jd = check("upload a JD", upload(PRIYA, "job_description", PDF, "zoho-jd.pdf"), 201)
check("JD must be a PDF", upload(PRIYA, "job_description", png()), 400)
check("set the JD", requests.put(f"{B}/job-roles/{role['id']}/jd", headers=PRIYA, json={"file_id": jd["id"]}), 200)
r = data(ARUN, f"/job-roles/{role['id']}")
expect("student sees logo and JD on the drive", r["company_logo"] and r["jd"] and fetch(r["jd"]).content == PDF)
check("unknown job role", requests.put(f"{B}/job-roles/999999/jd", headers=PRIYA, json={"file_id": None}), 404)
placement = next(p for p in data(A, "/placements") if p["register_no"] == "25CS001")
offer = check("upload an offer letter", upload(PRIYA, "offer_letter", PDF, "offer.pdf"), 201)
check("student cannot set an offer letter", requests.put(f"{B}/placements/{placement['id']}/offer-letter", headers=ARUN, json={"file_id": None}), 403)
check("ECE HOD cannot set a CSE offer letter", requests.put(f"{B}/placements/{placement['id']}/offer-letter", headers=SURESH, json={"file_id": None}), 403)
check("placement officer sets it", requests.put(f"{B}/placements/{placement['id']}/offer-letter", headers=PRIYA, json={"file_id": offer["id"]}), 200)
p2 = next(p for p in data(A, "/placements") if p["id"] == placement["id"])
expect("placement list shows the offer letter", p2["offer_letter"] and p2["offer_letter"]["name"] == "offer.pdf")
for path in (f"/companies/{role['company_id']}/logo", f"/job-roles/{role['id']}/jd", f"/placements/{placement['id']}/offer-letter"):
    requests.put(B + path, headers=A, json={"file_id": None})
r = data(A, f"/job-roles/{role['id']}")
expect("placement files removed", r["company_logo"] is None and r["jd"] is None)

# ---------------------------------------------------------------- notification attachments
print("notification attachments")
att = check("admin uploads an attachment", upload(A, "notification_attachment", PDF, "timetable.pdf"), 201)
res = check("send with attachment", requests.post(f"{B}/notifications", headers=A, json={"title": "Timetable", "body": "See attached", "target_type": "user",
                                                                                   "target_id": arun, "attachment_file_id": att["id"]}), 201)
n = data(ARUN, "/notifications?page_size=1")[0]
expect("recipient gets the attachment", n["title"] == "Timetable" and n["attachment"] and fetch(n["attachment"]).content == PDF)
sent = data(A, "/notifications/sent")
expect("sent list shows it", sent[0]["attachment"] and sent[0]["attachment"]["name"] == "timetable.pdf")
m_att = check("staff uploads an attachment", upload(MEENA, "notification_attachment", PDF), 201)
before = len(data(ARUN, "/notifications?page_size=100"))
check("cannot send someone else's upload", requests.post(f"{B}/notifications", headers=A, json={"title": "X", "body": "Y", "target_type": "user",
                                                                                             "target_id": arun, "attachment_file_id": m_att["id"]}), 403)
expect("nothing was sent", len(data(ARUN, "/notifications?page_size=100")) == before)
check("attachment already used", requests.post(f"{B}/notifications", headers=A, json={"title": "X", "body": "Y", "target_type": "user", "target_id": arun,
                                                                                   "attachment_file_id": att["id"]}), 400)
requests.delete(f"{B}/notifications/{n['id']}", headers=ARUN)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
