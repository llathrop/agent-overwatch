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

# ---------------------------------------------------------- init_workspace.sh
I="$TMP/init"
out="$(bash "$INIT" "$I/dry" --dry-run 2>&1)"; rc=$?
check "init --dry-run exits 0" test "$rc" -eq 0
check "init --dry-run writes nothing" test ! -e "$I/dry"
check "init --dry-run mentions .gitattributes" contains "$out" ".gitattributes"

bash "$INIT" "$I/root" >/dev/null 2>&1; rc=$?
check "init exits 0" test "$rc" -eq 0
check ".gitattributes has AGENT_BUS union" grep -qx 'AGENT_BUS.md merge=union' "$I/root/.gitattributes"
check ".gitattributes has QA_BUS union" grep -qx 'QA_BUS.md merge=union' "$I/root/.gitattributes"
check "secret-allowlist created" test -f "$I/root/.overwatch/secret-allowlist"
check "secret-allowlist examples are all commented" \
  test -z "$(grep -vE '^[[:space:]]*(#|$)' "$I/root/.overwatch/secret-allowlist")"
check "no lease placeholder created" test ! -e "$I/root/status/coordinator.lease"
check "HANDOFF has Coordinator section" grep -q '^## Coordinator' "$I/root/HANDOFF.md"
check "HANDOFF has size-cap guidance" grep -qF 'keep each cell/bullet ≤ 200 chars' "$I/root/HANDOFF.md"
bash "$INIT" "$I/root" >/dev/null 2>&1
check "re-run does not duplicate .gitattributes lines" test "$(grep -c 'merge=union' "$I/root/.gitattributes")" -eq 2

mkdir -p "$I/pre"; printf '*.png binary' > "$I/pre/.gitattributes"
bash "$INIT" "$I/pre" --no-bus >/dev/null 2>&1
check "existing .gitattributes kept and extended" \
  test "$(cat "$I/pre/.gitattributes")" = "$(printf '*.png binary\nAGENT_BUS.md merge=union\nQA_BUS.md merge=union')"
check "--no-bus still skips AGENT_BUS.md" test ! -e "$I/pre/AGENT_BUS.md"

bash "$INIT" "$I/root/svc" --subdir >/dev/null 2>&1; rc=$?
check "init --subdir exits 0" test "$rc" -eq 0
check "subdir HANDOFF has Coordinator section" grep -q '^## Coordinator' "$I/root/svc/HANDOFF.md"
printf 'changed\n' > "$I/root/.overwatch/secret-allowlist"
bash "$INIT" "$I/root" --force >/dev/null 2>&1
check "--force rewrites the allowlist" grep -qF 'Secret-scan allowlist' "$I/root/.overwatch/secret-allowlist"

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
