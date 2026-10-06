# End-to-end smoke test for auth/users/roles. Needs the API running on :8080 against a FRESH database
# (it creates users priya/arun/ravi). Usage: bash scripts/e2e_auth.sh
B=http://localhost:8080/api/v1
PASS=0; FAIL=0
j() { python -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }
call() { # method path token body -> sets CODE, BODY
  local out; out=$(curl -s -w '\n%{http_code}' -X "$1" "$B$2" -H "Content-Type: application/json" ${3:+-H "Authorization: Bearer $3"} ${4:+-d "$4"})
  CODE=$(echo "$out" | tail -1); BODY=$(echo "$out" | sed '$d'); }
check() { if [ "$CODE" = "$2" ]; then PASS=$((PASS+1)); echo "  ok   $1 ($CODE)"; else FAIL=$((FAIL+1)); echo "  FAIL $1 expected $2 got $CODE: $BODY"; fi; }
ADMINPW=$(grep ADMIN_PASSWORD= "$(dirname "$0")/../.env" | cut -d= -f2)

echo "== health"; curl -s localhost:8080/health; echo
echo "== password login"
call POST /auth/login "" '{"username":"admin","password":"wrong-pass"}'; check "wrong password" 401
call POST /auth/login "" '{"username":"nobody","password":"wrong-pass"}'; check "unknown user" 401
call POST /auth/login "" "{\"username\":\"admin\",\"password\":\"$ADMINPW\"}"; check "admin login" 200
AT=$(echo "$BODY" | j "d['data']['access_token']")
call GET /auth/me "$AT"; check "me" 200; echo "     roles=$(echo "$BODY"|j "d['data']['roles']") perms=$(echo "$BODY"|j "len(d['data']['permissions'])")"
call GET /users ""; check "no token" 401
call GET /users "garbage.token.x"; check "bad token" 401

echo "== permissions & roles"
call GET /permissions "$AT"; check "permission groups" 200; echo "     modules=$(echo "$BODY"|j "len(d['data'])")"
call GET /roles "$AT"; check "list roles" 200
rid() { echo "$BODY" | python -c "import sys,json;print({r['slug']:r['id'] for r in json.load(sys.stdin)['data']}['$1'])"; }
STAFF=$(rid staff); PO=$(rid placement_officer); STUDENT=$(rid student); PARENT=$(rid parent); ADMIN=$(rid admin)
call POST /roles "$AT" '{"name":"Lab Assistant","permission_ids":[1,2]}'; check "create custom role" 201
CR=$(echo "$BODY"|j "d['data']['id']"); echo "     slug=$(echo "$BODY"|j "d['data']['slug']") perms=$(echo "$BODY"|j "d['data']['permission_ids']")"
call PUT /roles/$CR/permissions "$AT" '{"permission_ids":[]}'; check "clear role perms" 200; echo "     perms after clear=$(echo "$BODY"|j "d['data']['permission_count']")"
call PUT /roles/$CR/permissions "$AT" '{"permission_ids":[999999]}'; check "invalid perm id" 400
call DELETE /roles/$STAFF "$AT"; check "delete system role blocked" 409
call DELETE /roles/$CR "$AT"; check "delete custom role" 200
call PUT /roles/$ADMIN/permissions "$AT" '{"permission_ids":[1]}'; check "admin perms locked" 409

echo "== users (multi-role)"
call POST /users "$AT" "{\"name\":\"Priya Staff\",\"username\":\"priya\",\"password\":\"Staff@1234\",\"mobile\":\"9000000001\",\"reference_number\":\"EMP001\",\"role_ids\":[$STAFF,$PO]}"; check "create staff+PO user" 201
echo "     roles=$(echo "$BODY"|j "[r['slug'] for r in d['data']['roles']]")"
call POST /users "$AT" "{\"name\":\"Dup\",\"username\":\"PRIYA\",\"role_ids\":[$STAFF]}"; check "duplicate username (case-insensitive)" 409
call POST /users "$AT" "{\"name\":\"Bad\",\"username\":\"bad1\",\"mobile\":\"12345\",\"role_ids\":[$STAFF]}"; check "invalid mobile" 400
call POST /users "$AT" "{\"name\":\"Bad\",\"username\":\"bad2\"}"; check "missing roles" 400
call POST /users "$AT" "{\"name\":\"Arun Student\",\"username\":\"arun\",\"password\":\"Stud@1234\",\"mobile\":\"9000000002\",\"reference_number\":\"21CS001\",\"role_ids\":[$STUDENT]}"; check "create student" 201
SID=$(echo "$BODY"|j "d['data']['id']")
call POST /users "$AT" "{\"name\":\"Ravi Parent\",\"username\":\"ravi\",\"mobile\":\"9000000002\",\"role_ids\":[$PARENT]}"; check "create parent, same mobile, no password" 201
echo "     has_password=$(echo "$BODY"|j "d['data']['has_password']")"
call GET "/users?role=student&search=arun" "$AT"; check "filter users" 200; echo "     total=$(echo "$BODY"|j "d['meta']['total']")"
call PUT /users/1/roles "$AT" "{\"role_ids\":[$STAFF]}"; check "admin can't drop own admin" 409
call PATCH /users/1/status "$AT" '{"is_active":false}'; check "admin can't deactivate self" 409

echo "== staff login: union of staff + placement_officer perms"
call POST /auth/login "" '{"username":"priya","password":"Staff@1234"}'; check "staff login" 200
ST=$(echo "$BODY"|j "d['data']['access_token']"); echo "     roles=$(echo "$BODY"|j "d['data']['user']['roles']") has company.create=$(echo "$BODY"|j "'company.create' in d['data']['user']['permissions']")"
call GET /users "$ST"; check "staff cannot list users" 403

echo "== OTP login"
call POST /auth/otp/request "" '{"identifier":"9000000002"}'; check "shared mobile is ambiguous" 409
call POST /auth/otp/request "" '{"identifier":"ghost_user"}'; check "unknown user gets generic reply" 200
call POST /auth/otp/request "" '{"identifier":"ravi"}'; check "parent requests OTP by username" 200
OTP=$(echo "$BODY"|j "d['data']['debug_otp']"); echo "     masked=$(echo "$BODY"|j "d['data']['masked_mobile']")"
call POST /auth/otp/request "" '{"identifier":"ravi"}'; check "resend throttled" 429
if [ "$OTP" != "000000" ]; then call POST /auth/otp/verify "" '{"identifier":"ravi","otp":"000000"}'; check "wrong OTP" 401; fi
call POST /auth/otp/verify "" "{\"identifier\":\"ravi\",\"otp\":\"$OTP\"}"; check "correct OTP -> tokens" 200
PRT=$(echo "$BODY"|j "d['data']['refresh_token']"); echo "     roles=$(echo "$BODY"|j "d['data']['user']['roles']")"
call POST /auth/otp/verify "" "{\"identifier\":\"ravi\",\"otp\":\"$OTP\"}"; check "OTP single-use" 401
call POST /auth/otp/request "" '{"identifier":"priya"}'; OTP2=$(echo "$BODY"|j "d['data']['debug_otp']")
WRONG=111111; [ "$OTP2" = "111111" ] && WRONG=222222
for i in 1 2 3 4 5; do call POST /auth/otp/verify "" "{\"identifier\":\"priya\",\"otp\":\"$WRONG\"}"; done
call POST /auth/otp/verify "" "{\"identifier\":\"priya\",\"otp\":\"$OTP2\"}"; check "locked after 5 wrong attempts" 429

echo "== refresh rotation & reuse detection"
call POST /auth/refresh "" "{\"refresh_token\":\"$PRT\"}"; check "refresh" 200
NRT=$(echo "$BODY"|j "d['data']['refresh_token']")
call POST /auth/refresh "" "{\"refresh_token\":\"$PRT\"}"; check "old refresh token replayed" 401
call POST /auth/refresh "" "{\"refresh_token\":\"$NRT\"}"; check "replay revoked the whole family" 401

echo "== forgot / reset password"
call POST /auth/password/forgot "" '{"identifier":"arun"}'; check "reset OTP" 200
ROTP=$(echo "$BODY"|j "d['data']['debug_otp']")
call POST /auth/otp/verify "" "{\"identifier\":\"arun\",\"otp\":\"$ROTP\"}"; check "reset OTP can't be used to log in" 401
call POST /auth/password/reset "" "{\"identifier\":\"arun\",\"otp\":\"$ROTP\",\"new_password\":\"NewPass@99\"}"; check "reset password" 200
call POST /auth/login "" '{"username":"arun","password":"Stud@1234"}'; check "old password rejected" 401
call POST /auth/login "" '{"username":"arun","password":"NewPass@99"}'; check "new password works" 200
SAT=$(echo "$BODY"|j "d['data']['access_token']")
call POST /auth/password/change "$SAT" '{"current_password":"wrong","new_password":"Another@99"}'; check "change pw wrong current" 400

echo "== deactivate"
call PATCH /users/$SID/status "$AT" '{"is_active":false}'; check "deactivate student" 200
call POST /auth/login "" '{"username":"arun","password":"NewPass@99"}'; check "inactive user can't log in" 401
call PATCH /users/$SID/status "$AT" '{"is_active":true}'; check "reactivate" 200

echo; echo "PASSED=$PASS FAILED=$FAIL"
