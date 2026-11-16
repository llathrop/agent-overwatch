#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal backticks and ${...} in single-quoted fixtures
# Tests for overwatch_watch.sh, coordinator_lease.sh and the init_workspace.sh
# additions. Pure bash, temp dirs only. Run: bash tests/test_watch_and_lease.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/skills/agent-overwatch/scripts"
WATCH="$SCRIPTS/overwatch_watch.sh"
LEASE="$SCRIPTS/coordinator_lease.sh"
INIT="$SCRIPTS/init_workspace.sh"

PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ao-test-watch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
nok()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }
check() { # desc, then a command; passes when the command succeeds
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else nok "$desc"; fi
}
contains()     { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
count_of()     { printf '%s\n' "$1" | grep -cF -- "$2"; }

# Fake credentials are assembled at runtime so this file never contains one.
FAKE_GH="gh""p_$(printf 'A%.0s' {1..36})"
FAKE_PW="Zq9""xTr4""LmW2vB"
SHA40="0123456789abcdef0123456789abcdef01234567"

# ---------------------------------------------------------------- watch: bus
W="$TMP/watch"; mkdir -p "$W"; cd "$W" || exit 1
cat > AGENT_BUS.md <<'EOF'
# AGENT_BUS

```markdown
### [YYYY-MM-DD HH:MM:SS UTC] <from> -> <to> | <TYPE> <subject>
```

### [2026-11-15 10:00:00 UTC] dev-1 -> qa-1 | RESULT first
- body
EOF
W_ARGS=(--once --state "$W/state" --allowlist "$W/allow" --bus "$W/AGENT_BUS.md")

out="$(bash "$WATCH" "${W_ARGS[@]}")"; rc=$?
check "watch exits 0" test "$rc" -eq 0
check "first header reported" contains "$out" "BUS: [2026-11-15 10:00:00 UTC] dev-1 -> qa-1 | RESULT first"
check "template example header not reported" not_contains "$out" "YYYY-MM-DD"

out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "--once prints nothing when nothing is new" test -z "$out"

cat >> AGENT_BUS.md <<'EOF'

### [2026-11-15 10:05:00 UTC] qa-1 -> dev-1 | QA HOLD feat/x@abcdef123456 second
- body
EOF
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "new header detected" contains "$out" "QA HOLD feat/x@abcdef123456 second"
check "old header not repeated" not_contains "$out" "RESULT first"
check "exactly one BUS line" test "$(count_of "$out" "BUS: ")" -eq 1
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "header detected once only" test -z "$out"

# Truncation: rewrite the bus shorter; watcher rescans instead of going silent.
printf '### [2026-11-15 11:00:00 UTC] coordinator -> all | STATUS reset\n' > AGENT_BUS.md
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "truncated bus is rescanned" contains "$out" "STATUS reset"

# --since-now on a fresh state skips history.
out="$(bash "$WATCH" --once --since-now --state "$W/state2" --bus "$W/AGENT_BUS.md")"
check "--since-now skips existing headers" test -z "$out"

# ------------------------------------------------------------- watch: secrets
printf '\n### [2026-11-15 12:00:00 UTC] dev-2 -> qa-1 | RESULT leak\n- token %s here\n- password = %s\n' \
  "$FAKE_GH" "$FAKE_PW" >> AGENT_BUS.md
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "GitHub PAT flagged" contains "$out" "GitHub Classic PAT"
check "generic assignment flagged" contains "$out" "Generic Credential Assignment"
check "secret line reported as file:line" contains "$out" "SECRET? $W/AGENT_BUS.md:4 GitHub Classic PAT"
check "PAT value never printed" not_contains "$out" "$FAKE_GH"
check "password value never printed" not_contains "$out" "$FAKE_PW"

# Secret in a header: header redacted, not printed.
printf '### [2026-11-15 12:01:00 UTC] dev-2 -> all | RESULT %s\n' "$FAKE_GH" >> AGENT_BUS.md
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "header containing a secret is redacted" contains "$out" "redacted: possible secret"
check "header secret value never printed" not_contains "$out" "$FAKE_GH"

# Allowlisted 40-hex SHA is not flagged; the same line without allowlist is.
printf '\n- commit_token: %s\n' "$SHA40" >> AGENT_BUS.md
cp "$W/state" "$W/state.bak"
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "un-allowlisted 40-hex token assignment is flagged" contains "$out" "SECRET? "
cp "$W/state.bak" "$W/state"
printf '# git SHAs\n\n^[0-9a-f]{40}$\n' > "$W/allow"
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "allowlisted 40-hex SHA not flagged" test -z "$out"

# Placeholders are not flagged.
printf -- '- api_key: <your-key-here>\n- token=${GITHUB_TOKEN}\n' >> AGENT_BUS.md
out="$(bash "$WATCH" "${W_ARGS[@]}")"
check "placeholder values not flagged" test -z "$out"

# No --check at all must not trip `set -u` on empty arrays (bash < 4.4).
out="$(bash "$WATCH" "${W_ARGS[@]}" 2>&1)"; rc=$?
check "watch with no --check exits 0 and prints nothing" test "$rc" -eq 0 -a -z "$out"

# An invalid allowlist regex warns on stderr and the valid ones still apply.
printf '\n- commit_token: %s\n' "$SHA40" >> AGENT_BUS.md
printf '([unclosed\n^[0-9a-f]{40}$\n' > "$W/allow"
err="$(bash "$WATCH" "${W_ARGS[@]}" 2>&1 >/dev/null)"
check "invalid allowlist regex warned on stderr" contains "$err" "invalid allowlist regex"
out="$(bash "$WATCH" "${W_ARGS[@]}" 2>/dev/null)"
check "valid allowlist entries still apply" test -z "$out"
printf '# git SHAs\n\n^[0-9a-f]{40}$\n' > "$W/allow"

# -------------------------------------------------------------- watch: checks
out="$(bash "$WATCH" "${W_ARGS[@]}" --check 'true' --check 'echo first; echo "db unreachable"; exit 3')"
check "failing --check reported with its index" contains "$out" "CHECK-FAIL 2: db unreachable"
check "passing --check is silent" not_contains "$out" "CHECK-FAIL 1"
long="$(printf 'x%.0s' {1..300})"
out="$(bash "$WATCH" "${W_ARGS[@]}" --check "echo $long; false")"
line="$(printf '%s\n' "$out" | grep '^CHECK-FAIL 1: ')"
check "check output truncated to 160 chars" test "${#line}" -eq $((14 + 160))
out="$(bash "$WATCH" "${W_ARGS[@]}" --check "echo $FAKE_GH; false")"
check "check output with a secret is redacted" not_contains "$out" "$FAKE_GH"

out="$(bash "$WATCH" --bogus 2>&1)"; rc=$?
check "unknown option exits 2" test "$rc" -eq 2

# --------------------------------------------------------------------- lease
L="$TMP/lease"; mkdir -p "$L"; cd "$L" || exit 1
printf '# AGENT_BUS\n' > AGENT_BUS.md
LF="$L/status/coordinator.lease"

out="$(bash "$LEASE" status --file "$LF" --id a)"; rc=$?
check "status with no lease exits 4" test "$rc" -eq 4
check "status does not create the lease" test ! -e "$LF"

bash "$LEASE" claim --id alpha --file "$LF" >/dev/null; rc=$?
check "claim by alpha exits 0" test "$rc" -eq 0
check "lease file written" grep -qx 'id=alpha' "$LF"
check "no temp files left behind" test -z "$(find "$L/status" -name '.coordinator.lease.*')"

bash "$LEASE" status --id alpha --file "$LF" >/dev/null; rc=$?
check "status by holder exits 0" test "$rc" -eq 0
bash "$LEASE" claim --id beta --file "$LF" >/dev/null 2>&1; rc=$?
check "claim by second id refused with exit 3" test "$rc" -eq 3
check "refused claim leaves holder unchanged" grep -qx 'id=alpha' "$LF"
bash "$LEASE" status --id beta --file "$LF" >/dev/null; rc=$?
check "status by other id exits 3" test "$rc" -eq 3
bash "$LEASE" renew --id beta --file "$LF" >/dev/null 2>&1; rc=$?
check "renew by non-holder exits 3" test "$rc" -eq 3
bash "$LEASE" release --id beta --file "$LF" >/dev/null 2>&1; rc=$?
check "release by non-holder exits 3" test "$rc" -eq 3

since_before="$(grep '^since=' "$LF")"
bash "$LEASE" renew --id alpha --ttl 0 --file "$LF" >/dev/null; rc=$?
check "renew by holder exits 0" test "$rc" -eq 0
check "renew keeps since" grep -qxF "$since_before" "$LF"
bash "$LEASE" status --id beta --file "$LF" >/dev/null; rc=$?
check "expired lease (--ttl 0) gives exit 4" test "$rc" -eq 4

out="$(bash "$WATCH" --once --bus "$L/AGENT_BUS.md" --state "$L/ws" --allowlist /dev/null)"
check "watch warns about stale lease" contains "$out" "LEASE stale: alpha last_seen "
out="$(bash "$WATCH" --once --bus "$L/AGENT_BUS.md" --state "$L/ws" --allowlist /dev/null)"
check "stale warning not repeated for the same lease" test -z "$out"

bash "$LEASE" claim --id beta --file "$LF" >/dev/null 2>&1; rc=$?
check "claim over expired lease without --takeover succeeds" test "$rc" -eq 0
check "no TAKEOVER written without --takeover" not_contains "$(cat AGENT_BUS.md)" "TAKEOVER"
out="$(bash "$WATCH" --once --bus "$L/AGENT_BUS.md" --state "$L/ws" --allowlist /dev/null)"
check "watch reports lease holder change" contains "$out" "LEASE holder changed: alpha -> beta"

# --takeover of a live lease, fallback path (no bus_append.sh beside the script)
bash "$LEASE" claim --id "gamma (session 2)" --takeover --file "$LF" --bus "$L/AGENT_BUS.md" >/dev/null; rc=$?
check "--takeover of live lease exits 0" test "$rc" -eq 0
check "--takeover moved the lease" grep -qx 'id=gamma (session 2)' "$LF"
check "TAKEOVER header written in spec format" \
  grep -qE '^### \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC\] gamma \(session 2\) -> all \| TAKEOVER coordinator lease$' "$L/AGENT_BUS.md"
check "TAKEOVER body names previous holder" grep -qF 'Previous holder: `beta`' "$L/AGENT_BUS.md"

# --takeover via bus_append.sh when present (stub records its arguments)
S="$TMP/stubdir"; mkdir -p "$S"; cp "$LEASE" "$S/"
cat > "$S/bus_append.sh" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:%s\n' "$*" >> "$STUB_LOG"; cat >> "$STUB_LOG"
EOF
export STUB_LOG="$TMP/stub.log"
bash "$S/coordinator_lease.sh" claim --id delta --takeover --file "$LF" --bus "$L/AGENT_BUS.md" >/dev/null; rc=$?
check "--takeover via bus_append.sh exits 0" test "$rc" -eq 0
check "bus_append.sh called with TAKEOVER args" grep -qF -- '--from delta --to all --type TAKEOVER --subject coordinator lease' "$STUB_LOG"
check "bus_append.sh received the body on stdin" grep -qF 'Previous holder: `gamma (session 2)`' "$STUB_LOG"
printf '#!/usr/bin/env bash\nexit 1\n' > "$S/bus_append.sh"
bash "$S/coordinator_lease.sh" claim --id eps --takeover --file "$LF" --bus "$L/AGENT_BUS.md" >/dev/null 2>&1; rc=$?
check "failing bus_append.sh surfaces exit 1" test "$rc" -eq 1

bash "$LEASE" release --id eps --file "$LF" >/dev/null; rc=$?
check "release by holder exits 0" test "$rc" -eq 0
check "release removed the lease" test ! -e "$LF"
AO_COORDINATOR_ID=envid bash "$LEASE" claim --file "$LF" >/dev/null
check "AO_COORDINATOR_ID is the default id" grep -qx 'id=envid' "$LF"
bash "$LEASE" claim --id 'bad|id' --file "$LF" >/dev/null 2>&1; rc=$?
check "id with '|' rejected (exit 2)" test "$rc" -eq 2
bash "$LEASE" claim --id x --ttl -1 --file "$LF" >/dev/null 2>&1; rc=$?
check "negative ttl rejected (exit 2)" test "$rc" -eq 2

# AO_LEASE_LOCK_WAIT cap (max 3600) and overflow safety
out="$(AO_LEASE_LOCK_WAIT=3601 bash "$LEASE" status --file "$L/status/none.lease" --id a 2>&1)"; rc=$?
check "AO_LEASE_LOCK_WAIT=3601 rejected (exit 2)" test "$rc" -eq 2
check "AO_LEASE_LOCK_WAIT=3601 message mentions non-negative integer" contains "$out" "must be a non-negative integer"

start=$(date -u +%s)
out="$(AO_LEASE_LOCK_WAIT=99999999999999999999 bash "$LEASE" status --file "$L/status/none.lease" --id a 2>&1)"; rc=$?
elapsed=$(( $(date -u +%s) - start ))
check "AO_LEASE_LOCK_WAIT overflow rejected (exit 2)" test "$rc" -eq 2
check "AO_LEASE_LOCK_WAIT overflow message mentions non-negative integer" contains "$out" "must be a non-negative integer"
check "AO_LEASE_LOCK_WAIT overflow fails immediately (${elapsed}s)" test "$elapsed" -le 2

out="$(AO_LEASE_LOCK_WAIT=3600 bash "$LEASE" status --file "$L/status/none.lease" --id a 2>&1)"; rc=$?
check "AO_LEASE_LOCK_WAIT=3600 accepted (status exit 4)" test "$rc" -eq 4

out="$(AO_LEASE_LOCK_WAIT=0010 bash "$LEASE" status --file "$L/status/none.lease" --id a 2>&1)"; rc=$?
check "AO_LEASE_LOCK_WAIT=0010 accepted (status exit 4)" test "$rc" -eq 4

# ------------------------------------------------- lease: hardening (HOLD fixes)
H="$TMP/hard"; mkdir -p "$H"; cd "$H" || exit 1
HF="$H/status/coordinator.lease"

bash "$LEASE" claim --id "$FAKE_GH" --file "$HF" >"$H/o" 2>&1; rc=$?
check "secret-looking id rejected (exit 2)" test "$rc" -eq 2
check "rejected id value not echoed" not_contains "$(cat "$H/o")" "$FAKE_GH"
check "rejected id writes no lease" test ! -e "$HF"

mkdir -p "$H/status"
printf 'id=%s\nsince=x\nlast_seen=2026-01-01 00:00:00 UTC\nttl_min=0\nlast_seen_epoch=1\n' "$FAKE_GH" > "$HF"
out="$(bash "$WATCH" --once --bus /dev/null --lease "$HF" --state "$H/ws" --allowlist /dev/null 2>/dev/null)"
check "watch redacts a secret-looking lease id" contains "$out" "LEASE stale: <redacted id: possible secret>"
check "watch never prints the lease id secret" not_contains "$out" "$FAKE_GH"

# CRLF lease written on another OS is still read as live.
printf 'id=alpha\r\nsince=x\r\nlast_seen=x\r\nttl_min=30\r\nlast_seen_epoch=%s\r\n' "$(date -u +%s)" > "$HF"
bash "$LEASE" status --id beta --file "$HF" >/dev/null; rc=$?
check "CRLF lease is read as live (exit 3)" test "$rc" -eq 3

# BRIEF-minimal keys (id/since/last_seen) are understood.
printf 'id=alpha\nsince=%s\nlast_seen=%s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$HF"
bash "$LEASE" status --id beta --file "$HF" >/dev/null; rc=$?
check "BRIEF-key lease with fresh last_seen is live (exit 3)" test "$rc" -eq 3
printf 'id=alpha\nsince=2020-01-01 00:00:00 UTC\nlast_seen=2020-01-01T00:00:00Z\n' > "$HF"
bash "$LEASE" status --id beta --file "$HF" >/dev/null; rc=$?
check "BRIEF-key lease with old last_seen is expired (exit 4)" test "$rc" -eq 4
out="$(bash "$WATCH" --once --bus /dev/null --lease "$HF" --state "$H/ws2" --allowlist /dev/null 2>/dev/null)"
check "watch flags a stale BRIEF-key lease" contains "$out" "LEASE stale: alpha last_seen 2020-01-01T00:00:00Z"
rm -f "$HF"

# PATH without flock, to exercise the exclusive-create lock fallback.
NOFLOCK="$TMP/noflock-bin"; mkdir -p "$NOFLOCK"
IFS=: read -r -a _pdirs <<< "$PATH"
for d in "${_pdirs[@]}"; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    [[ "$b" == flock || -e "$NOFLOCK/$b" || ! -x "$f" ]] && continue
    ln -s "$f" "$NOFLOCK/$b" 2>/dev/null
  done
done
check "flock hidden from the test PATH" test -z "$(PATH="$NOFLOCK" command -v flock)"

race() { # $1 = lease file, $2 = PATH to use -> prints number of winners
  local f="$1" p="$2" i
  rm -rf "$(dirname "$f")"; mkdir -p "$(dirname "$f")"
  for i in $(seq 1 20); do
    ( PATH="$p" bash "$LEASE" claim --id "racer-$i" --file "$f" >/dev/null 2>&1; echo $? > "$f.rc.$i" ) &
  done
  wait
  grep -lx 0 "$f".rc.* | wc -l | tr -d ' '
}
won="$(race "$H/r1/coordinator.lease" "$NOFLOCK")"
check "no-flock race: exactly 1 of 20 claims wins (got $won)" test "$won" -eq 1
check "no-flock race: losers exit 3" test "$(grep -lx 3 "$H/r1/coordinator.lease".rc.* | wc -l | tr -d ' ')" -eq 19
check "no-flock race: no errors (exit 1)" test -z "$(grep -lx 1 "$H/r1/coordinator.lease".rc.* 2>/dev/null)"
check "no-flock race: lock file released" test ! -e "$H/r1/coordinator.lease.excl.lock"
if command -v flock >/dev/null 2>&1; then
  won="$(race "$H/r2/coordinator.lease" "$PATH")"
  check "flock race: exactly 1 of 20 claims wins (got $won)" test "$won" -eq 1

  # A stuck holder of the flock must not hang claim/renew: bounded wait, exit 1.
  FL="$H/f/coordinator.lease"; mkdir -p "$H/f"
  hold_flock() { # $1 = file to lock; holds it in the background, prints the pid
    ( exec 7>>"$1"; flock -x 7; exec sleep 30 ) >/dev/null 2>&1 &
    echo $!
  }
  holder="$(hold_flock "$FL.lock")"; sleep 0.5
  start=$(date -u +%s)
  AO_LEASE_LOCK_WAIT=1 bash "$LEASE" claim --id stuck --file "$FL" >"$H/f/o" 2>&1; rc=$?
  elapsed=$(( $(date -u +%s) - start ))
  check "claim with a stuck flock holder exits 1" test "$rc" -eq 1
  check "flock wait is bounded (${elapsed}s)" test "$elapsed" -le 4
  check "flock timeout message is clear" grep -qF "timed out after 1s waiting for lock $FL.lock" "$H/f/o"
  check "timed-out claim wrote no lease" test ! -e "$FL"
  AO_LEASE_LOCK_WAIT=1 bash "$LEASE" renew --id stuck --file "$FL" >/dev/null 2>&1; rc=$?
  check "renew with a stuck flock holder exits 1" test "$rc" -eq 1
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  bash "$LEASE" claim --id stuck --file "$FL" >/dev/null 2>&1; rc=$?
  check "claim succeeds once the holder is gone" test "$rc" -eq 0

  # Fallback TAKEOVER append (no bus_append.sh beside the script) is bounded too.
  FB="$TMP/fb-only"; mkdir -p "$FB"; cp "$LEASE" "$FB/"
  printf '# AGENT_BUS\n' > "$H/f/AGENT_BUS.md"
  holder="$(hold_flock "$H/f/AGENT_BUS.md")"; sleep 0.5
  start=$(date -u +%s)
  AO_LEASE_LOCK_WAIT=1 bash "$FB/coordinator_lease.sh" claim --id taker --takeover \
    --file "$FL" --bus "$H/f/AGENT_BUS.md" >"$H/f/o2" 2>&1; rc=$?
  elapsed=$(( $(date -u +%s) - start ))
  check "fallback TAKEOVER with a stuck bus lock exits 1" test "$rc" -eq 1
  check "fallback TAKEOVER bus wait is bounded (${elapsed}s)" test "$elapsed" -le 4
  check "fallback TAKEOVER timeout message is clear" grep -qF "timed out after 1s waiting for the lock on $H/f/AGENT_BUS.md" "$H/f/o2"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
fi

# Stale exclusive lock (dead owner pid) is reaped; a live one times out.
SL="$H/s/coordinator.lease"; mkdir -p "$H/s"
bash -c 'exit 0' & deadpid=$!; wait "$deadpid"
printf '%s %s\n' "$deadpid" "$(date -u +%s)" > "$SL.excl.lock"
PATH="$NOFLOCK" bash "$LEASE" claim --id solo --file "$SL" >/dev/null 2>&1; rc=$?
check "stale lock from a dead pid is reaped (claim exit 0)" test "$rc" -eq 0
check "reaped lock is gone after claim" test ! -e "$SL.excl.lock"
printf '%s %s\n' "$$" "$(date -u +%s)" > "$SL.excl.lock"
start=$(date -u +%s)
AO_LEASE_LOCK_WAIT=1 PATH="$NOFLOCK" bash "$LEASE" renew --id solo --file "$SL" >/dev/null 2>&1; rc=$?
check "live lock held elsewhere times out with exit 1" test "$rc" -eq 1
check "lock wait is bounded" test $(( $(date -u +%s) - start )) -le 4
check "live lock is not removed by the waiter" test -f "$SL.excl.lock"
printf '%s %s\n' "$$" "1" > "$SL.excl.lock"
PATH="$NOFLOCK" bash "$LEASE" renew --id solo --file "$SL" >/dev/null 2>&1; rc=$?
check "lock older than the stale age is reaped even with a live pid" test "$rc" -eq 0
rm -f "$SL.excl.lock"

# ---------------------------------------------------------- init_workspace.sh
I="$TMP/init"
out="$(bash "$INIT" "$I/dry" --dry-run 2>&1)"; rc=$?
check "init --dry-run exits 0" test "$rc" -eq 0
check "init --dry-run writes nothing" test ! -e "$I/dry"
check "init --dry-run mentions .gitignore" contains "$out" ".gitignore"

bash "$INIT" "$I/root" >/dev/null 2>&1; rc=$?
check "init exits 0" test "$rc" -eq 0
check ".gitignore ignores AGENT_BUS.md" grep -qx 'AGENT_BUS.md' "$I/root/.gitignore"
check "init writes no .gitattributes union rule" test ! -e "$I/root/.gitattributes"
check "secret-allowlist created" test -f "$I/root/.overwatch/secret-allowlist"
check "secret-allowlist examples are all commented" \
  test -z "$(grep -vE '^[[:space:]]*(#|$)' "$I/root/.overwatch/secret-allowlist")"
check "no lease placeholder created" test ! -e "$I/root/status/coordinator.lease"
check "HANDOFF has Coordinator section" grep -q '^## Coordinator' "$I/root/HANDOFF.md"
check "HANDOFF has size-cap guidance" grep -qF 'keep each cell/bullet ≤ 200 chars' "$I/root/HANDOFF.md"
bash "$INIT" "$I/root" >/dev/null 2>&1
check "re-run does not duplicate .gitignore line" test "$(grep -c '^AGENT_BUS.md$' "$I/root/.gitignore")" -eq 1

mkdir -p "$I/pre"; printf '*.png' > "$I/pre/.gitignore"
bash "$INIT" "$I/pre" >/dev/null 2>&1
check "existing .gitignore kept and extended" \
  test "$(cat "$I/pre/.gitignore")" = "$(printf '*.png\nAGENT_BUS.md')"
mkdir -p "$I/nobus"
bash "$INIT" "$I/nobus" --no-bus >/dev/null 2>&1
check "--no-bus skips AGENT_BUS.md and its ignore line" test ! -e "$I/nobus/AGENT_BUS.md" -a ! -e "$I/nobus/.gitignore"
out="$(bash "$INIT" "$I/note" 2>&1)"
check "init prints local-bus note" contains "$out" "local coordination"

bash "$INIT" "$I/root/svc" --subdir >/dev/null 2>&1; rc=$?
check "init --subdir exits 0" test "$rc" -eq 0
check "subdir HANDOFF has Coordinator section" grep -q '^## Coordinator' "$I/root/svc/HANDOFF.md"
out="$(bash "$INIT" "$I/root/svc2" --subdir 2>&1)"
check "subdir lease hint points at the root lease" contains "$out" "--file $I/root/status/coordinator.lease "
check "subdir lease hint does not point inside the subdir" not_contains "$out" "$I/root/svc2/status/coordinator.lease"
printf 'changed\n' > "$I/root/.overwatch/secret-allowlist"
bash "$INIT" "$I/root" --force >/dev/null 2>&1
check "--force rewrites the allowlist" grep -qF 'Secret-scan allowlist' "$I/root/.overwatch/secret-allowlist"

# Fallback bus header (used when AGENT_BUS.template.md is not found) recommends bus_append.sh.
B="$TMP/busfb"; mkdir -p "$B/scripts"; cp "$INIT" "$B/scripts/"
bash "$B/scripts/init_workspace.sh" "$B/ws" >/dev/null 2>&1
check "fallback bus header recommends bus_append.sh" grep -qF 'append with `scripts/bus_append.sh`' "$B/ws/AGENT_BUS.md"
check "fallback bus header keeps heredoc only as fallback" grep -qF 'Only when that script is unavailable, fall back to a quoted heredoc' "$B/ws/AGENT_BUS.md"

# ---------------------------------------------------------------- link check
# Markdown link targets outside inline code spans, minus URLs and anchors.
link_targets() { # $1 = file
  sed -E 's/`[^`]*`//g' "$1" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' \
    | grep -vE '^(https?:|mailto:|$)' || true
}
links_resolve() { # $1 = file; every relative link must exist from the file's dir
  local f="$1" t bad=0
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    [[ -e "$(dirname "$f")/$t" ]] || { echo "       unresolved link in $f: $t"; bad=1; }
  done < <(link_targets "$f")
  return "$bad"
}
only_placeholder_links() { # raw templates: links may only target {{...}} placeholders
  local t bad=0
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    [[ "$t" =~ ^\{\{[A-Z_]+\}\}$ ]] || { echo "       non-placeholder link in $1: $t"; bad=1; }
  done < <(link_targets "$1")
  return "$bad"
}
TPL="$REPO_ROOT/skills/agent-overwatch/templates"
check "HANDOFF template links are placeholders only" only_placeholder_links "$TPL/HANDOFF.template.md"
check "SUBDIR_HANDOFF template links are placeholders only" only_placeholder_links "$TPL/SUBDIR_HANDOFF.template.md"
check "generated root HANDOFF links resolve" links_resolve "$I/root/HANDOFF.md"
check "generated subdir HANDOFF links resolve" links_resolve "$I/root/svc/HANDOFF.md"
check "generated subdir HANDOFF links to the parent" grep -qF '[Root HANDOFF.md](../HANDOFF.md)' "$I/root/svc/HANDOFF.md"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
