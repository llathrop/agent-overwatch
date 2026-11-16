#!/usr/bin/env bash
# Tests for skills/agent-overwatch/scripts/verify_atomic_branch.sh and bus_append.sh.
# Pure bash; builds throwaway git repos under mktemp -d.
# Usage: tests/test_verify_and_bus.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/skills/agent-overwatch/scripts/verify_atomic_branch.sh"
BUSAPP="$ROOT/skills/agent-overwatch/scripts/bus_append.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
nok()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/       | /' | tail -n 15; }

# Secret-shaped test values are assembled at runtime so this file never
# contains a literal that matches the scanners.
GH_TOKEN="gh""p_""Zq7XkP2mN9wR4tY6uB1cV3dF8gH0jL5s"
SLACK_TOKEN="xo""xb-""1234567890-abcdefghijkl"
SSH_HDR="-----BEGIN ""OPENSSH PRIVATE KEY-----"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# mkrepo DIR BRANCH: main with one commit, BRANCH with one more commit
mkrepo() {
  local d="$1" b="$2"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  echo "base" > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -q -m "base"
  git -C "$d" checkout -q -b "$b"
  echo "feature" > "$d/feature.txt"
  git -C "$d" add feature.txt
  git -C "$d" commit -q -m "feature"
}

commit_file() { # DIR FILE CONTENT MSG
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "$4"
}

head12() { git -C "$1" rev-parse HEAD | cut -c1-12; }

verdict() { # AUTHOR KIND BRANCH SHA
  printf '### [2026-11-16 00:00:00 UTC] %s -> coordinator | QA %s %s@%s review\nEvidence: tests ran.\n\n' "$1" "$2" "$3" "$4"
}

# run_verify OUTVAR args... ; sets RC and OUT
run_verify() {
  OUT="$("$VERIFY" "$@" 2>&1)"
  RC=$?
}

# ---------------------------------------------------------------------------
# verify_atomic_branch.sh
# ---------------------------------------------------------------------------

R="$WORK/r1"; mkrepo "$R" feat/x
LEDGER="$WORK/ledger1.md"

# 1. APPROVE for a different branch must not satisfy this branch
git -C "$R" branch feat/other
verdict qa-1 APPROVE feat/other "$(head12 "$R")" > "$LEDGER"
run_verify --repo "$R" --base main --qa-file "$LEDGER"
if [[ $RC -ne 0 && "$OUT" == *"No QA verdict bound to branch 'feat/x'"* ]]; then ok "wrong-branch APPROVE -> FAIL"; else nok "wrong-branch APPROVE -> FAIL" "$OUT"; fi

# 2. Matching branch@sha APPROVE by a qa role passes
verdict qa-1 APPROVE feat/x "$(head12 "$R")" >> "$LEDGER"
run_verify --repo "$R" --base main --qa-file "$LEDGER"
if [[ $RC -eq 0 && "$OUT" == *"[PASS] QA APPROVE for feat/x@"* ]]; then ok "matching APPROVE -> PASS"; else nok "matching APPROVE -> PASS" "$OUT"; fi

# 2b. 7-char prefix is accepted
verdict qa-1 APPROVE feat/x "$(git -C "$R" rev-parse HEAD | cut -c1-7)" > "$WORK/ledger1b.md"
run_verify --repo "$R" --base main --qa-file "$WORK/ledger1b.md"
if [[ $RC -eq 0 ]]; then ok "7-char sha prefix -> PASS"; else nok "7-char sha prefix -> PASS" "$OUT"; fi

# 2c. Same approve by a non-qa author is ignored
verdict coordinator APPROVE feat/x "$(head12 "$R")" > "$WORK/ledger1c.md"
run_verify --repo "$R" --base main --qa-file "$WORK/ledger1c.md"
if [[ $RC -ne 0 && "$OUT" == *"not a QA role"* ]]; then ok "non-qa author APPROVE -> FAIL"; else nok "non-qa author APPROVE -> FAIL" "$OUT"; fi

# 3. Stale sha: new commit after APPROVE
commit_file "$R" more.txt "more" "more work"
run_verify --repo "$R" --base main --qa-file "$LEDGER"
if [[ $RC -ne 0 && "$OUT" == *"re-review needed for new commits"* ]]; then ok "stale sha APPROVE -> FAIL (re-review)"; else nok "stale sha APPROVE -> FAIL (re-review)" "$OUT"; fi

# 4. HOLD after APPROVE for the same branch blocks
verdict qa-1 APPROVE feat/x "$(head12 "$R")" >> "$LEDGER"
verdict qa-2 HOLD feat/x "$(head12 "$R")" >> "$LEDGER"
run_verify --repo "$R" --base main --qa-file "$LEDGER"
if [[ $RC -ne 0 && "$OUT" == *"is HOLD"* ]]; then ok "HOLD after APPROVE -> FAIL"; else nok "HOLD after APPROVE -> FAIL" "$OUT"; fi

# 4b. HOLD still blocks with --allow-external-qa
run_verify --repo "$R" --base main --qa-file "$LEDGER" --allow-external-qa
if [[ $RC -ne 0 ]]; then ok "HOLD blocks even with --allow-external-qa"; else nok "HOLD blocks even with --allow-external-qa" "$OUT"; fi

# 4c. A later APPROVE for HEAD after the HOLD clears it
verdict qa-2 APPROVE feat/x "$(head12 "$R")" >> "$LEDGER"
run_verify --repo "$R" --base main --qa-file "$LEDGER"
if [[ $RC -eq 0 ]]; then ok "APPROVE after HOLD -> PASS"; else nok "APPROVE after HOLD -> PASS" "$OUT"; fi

# 5. No ledger -> FAIL; --allow-external-qa -> WARN + pass; deprecated alias works
R2="$WORK/r2"; mkrepo "$R2" fix/y
run_verify --repo "$R2" --base main
if [[ $RC -ne 0 && "$OUT" == *"No QA ledger found"* ]]; then ok "no ledger -> FAIL"; else nok "no ledger -> FAIL" "$OUT"; fi
run_verify --repo "$R2" --base main --allow-external-qa
if [[ $RC -eq 0 && "$OUT" == *"[WARN]"* ]]; then ok "no ledger + --allow-external-qa -> WARN, pass"; else nok "no ledger + --allow-external-qa -> WARN, pass" "$OUT"; fi
run_verify --repo "$R2" --base main --allow-bus-only
if [[ $RC -eq 0 && "$OUT" == *"deprecated"* ]]; then ok "--allow-bus-only deprecated alias"; else nok "--allow-bus-only deprecated alias" "$OUT"; fi

# 5b. Ledger present but only legacy (unbound) verdicts -> FAIL
printf '### [2026-11-16 00:00 UTC] qa-1 -> all | QA APPROVE (Merge #9)\n' > "$WORK/legacy.md"
run_verify --repo "$R2" --base main --qa-file "$WORK/legacy.md"
if [[ $RC -ne 0 && "$OUT" == *"legacy verdict"* ]]; then ok "legacy unbound APPROVE -> FAIL"; else nok "legacy unbound APPROVE -> FAIL" "$OUT"; fi

# 5c. Explicit --qa-file that does not exist -> FAIL even with --allow-external-qa
run_verify --repo "$R2" --base main --qa-file "$WORK/nope.md" --allow-external-qa
if [[ $RC -ne 0 ]]; then ok "missing --qa-file -> FAIL"; else nok "missing --qa-file -> FAIL" "$OUT"; fi

# 6. Secret added then deleted on the branch -> FAIL, value never printed
R3="$WORK/r3"; mkrepo "$R3" feat/leak
commit_file "$R3" config.env "TOKEN=$GH_TOKEN" "add config"
commit_file "$R3" config.env "TOKEN=from-env" "remove token"
verdict qa-1 APPROVE feat/leak "$(head12 "$R3")" > "$WORK/ledger3.md"
run_verify --repo "$R3" --base main --qa-file "$WORK/ledger3.md"
LEAK_SHA="$(git -C "$R3" rev-parse HEAD~1 | cut -c1-12)"
if [[ $RC -ne 0 && "$OUT" == *"branch history: commit ${LEAK_SHA} file config.env (Pattern: GitHub Classic PAT)"* ]]; then
  ok "secret in branch history -> FAIL with commit/file/pattern"
else
  nok "secret in branch history -> FAIL with commit/file/pattern" "$OUT"
fi
if [[ "$OUT" != *"$GH_TOKEN"* && "$OUT" != *"Zq7XkP2m"* ]]; then ok "secret value absent from verifier output"; else nok "secret value absent from verifier output"; fi

# 6b. New patterns: Slack token and OpenSSH key in final files
R4="$WORK/r4"; mkrepo "$R4" feat/keys
commit_file "$R4" slack.txt "hook=$SLACK_TOKEN" "slack"
commit_file "$R4" id_test "$SSH_HDR" "key"
run_verify --repo "$R4" --base main --allow-external-qa
if [[ $RC -ne 0 && "$OUT" == *"slack.txt:1 (Pattern: Slack Token)"* && "$OUT" == *"id_test:1 (Pattern: OpenSSH Private Key)"* && "$OUT" != *"$SLACK_TOKEN"* ]]; then
  ok "Slack token + OpenSSH key detected, value not printed"
else
  nok "Slack token + OpenSSH key detected, value not printed" "$OUT"
fi

# 7. Missing option arguments are validated (no 'unbound variable' crash)
for opt in --repo --base --qa-file --max-files; do
  run_verify "$opt"
  if [[ $RC -eq 1 && "$OUT" == *"requires a value"* && "$OUT" != *"unbound variable"* ]]; then ok "$opt without value -> clean error"; else nok "$opt without value -> clean error" "$OUT"; fi
done
run_verify --repo "$R" --max-files abc
if [[ $RC -eq 1 && "$OUT" == *"non-negative integer"* ]]; then ok "--max-files non-integer -> error"; else nok "--max-files non-integer -> error" "$OUT"; fi

# ---------------------------------------------------------------------------
# bus_append.sh
# ---------------------------------------------------------------------------
BUS="$WORK/bus.md"
printf '# bus\n' > "$BUS"

# 8. Header format, --ref auto, body from stdin
HDR="$(printf 'line one\nline two\n' | "$BUSAPP" --bus "$BUS" --repo "$R" --from dev-1 --to qa-1,coordinator --type RESULT --subject "ready" --ref auto)"
RC=$?
EXP_REF="feat/x@$(head12 "$R")"
if [[ $RC -eq 0 && "$HDR" =~ ^'### ['[0-9]{4}-[0-9]{2}-[0-9]{2}' '[0-9]{2}:[0-9]{2}:[0-9]{2}' UTC] dev-1 -> qa-1,coordinator | RESULT '"$EXP_REF"' ready'$ ]]; then
  ok "bus_append header format + --ref auto"
else
  nok "bus_append header format + --ref auto" "$HDR"
fi
if grep -qxF "$HDR" "$BUS" && grep -A2 -xF "$HDR" "$BUS" | tail -n 2 | tr '\n' '|' | grep -qx 'line one|line two|'; then
  ok "bus_append wrote header + body"
else
  nok "bus_append wrote header + body" "$(cat "$BUS")"
fi

# 8b. Empty body allowed
if HDR2="$("$BUSAPP" --bus "$BUS" --from coordinator --to all --type STATUS --subject "heartbeat" < /dev/null)" && grep -qxF "$HDR2" "$BUS"; then
  ok "empty body allowed"
else
  nok "empty body allowed" "$HDR2"
fi

# 8c. Round trip: QA verdict written by bus_append satisfies the verifier
"$BUSAPP" --bus "$BUS" --repo "$R" --from qa-1 --to coordinator --type "QA APPROVE" --subject "evidence: tests pass" --ref auto < /dev/null >/dev/null
run_verify --repo "$R" --base main --qa-file "$BUS"
if [[ $RC -eq 0 ]]; then ok "bus_append QA APPROVE --ref auto satisfies verifier"; else nok "bus_append QA APPROVE --ref auto satisfies verifier" "$OUT"; fi

# 9. Refuses a secret (exit 2), reports line number only, writes nothing
BEFORE="$(cksum < "$BUS")"
ERR="$(printf 'fine\ntoken is %s\n' "$GH_TOKEN" | "$BUSAPP" --bus "$BUS" --from dev-1 --to all --type RESULT --subject "x" 2>&1)"
RC=$?
if [[ $RC -eq 2 && "$ERR" == *"body line 2"* && "$ERR" != *"$GH_TOKEN"* && "$(cksum < "$BUS")" == "$BEFORE" ]]; then
  ok "secret in body -> exit 2, line number only, bus unchanged"
else
  nok "secret in body -> exit 2, line number only, bus unchanged" "$ERR"
fi
ERR="$("$BUSAPP" --bus "$BUS" --from dev-1 --to all --type RESULT --subject "key $SLACK_TOKEN" < /dev/null 2>&1)"
RC=$?
if [[ $RC -eq 2 && "$ERR" == *"in subject"* && "$ERR" != *"$SLACK_TOKEN"* ]]; then ok "secret in subject -> exit 2"; else nok "secret in subject -> exit 2" "$ERR"; fi

# 10. Validation
ERR="$("$BUSAPP" --bus "$BUS" --from dev-1 --to all --type APPROVE --subject "x" < /dev/null 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"Invalid --type"* ]]; then ok "invalid type rejected"; else nok "invalid type rejected" "$ERR"; fi
ERR="$("$BUSAPP" --bus "$BUS" --from coordinator --to all --type "QA APPROVE" --subject "x" --ref "feat/x@abcdef1" < /dev/null 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"QA role"* ]]; then ok "QA verdict from non-qa role rejected"; else nok "QA verdict from non-qa role rejected" "$ERR"; fi
ERR="$("$BUSAPP" --bus "$BUS" --from qa-1 --to all --type "QA HOLD" --subject "x" < /dev/null 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"requires --ref"* ]]; then ok "QA verdict without --ref rejected"; else nok "QA verdict without --ref rejected" "$ERR"; fi
ERR="$("$BUSAPP" --bus "$BUS" --from dev-1 --to all --type RESULT --subject "x" --ref "nobranch" < /dev/null 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"BRANCH@SHA"* ]]; then ok "malformed --ref rejected"; else nok "malformed --ref rejected" "$ERR"; fi
ERR="$("$BUSAPP" --bus "$WORK/missing.md" --from dev-1 --to all --type RESULT --subject "x" < /dev/null 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"does not exist"* ]]; then ok "missing bus file rejected"; else nok "missing bus file rejected" "$ERR"; fi
ERR="$("$BUSAPP" --bus 2>&1)"; RC=$?
if [[ $RC -eq 1 && "$ERR" == *"requires a value"* ]]; then ok "bus_append missing option value rejected"; else nok "bus_append missing option value rejected" "$ERR"; fi

# 11. Concurrent appends do not interleave (flock and O_EXCL lockfile fallback)
check_concurrent() { # LABEL ENVPREFIX
  local label="$1" cbus="$WORK/cbus-$1.md" i
  printf '# concurrent\n' > "$cbus"
  for i in $(seq 1 20); do
    ( body=""
      for j in 1 2 3 4 5; do body+="w${i} line ${j} $(printf '%0200d' 0)"$'\n'; done
      printf '%s' "$body" | env "$2" "$BUSAPP" --bus "$cbus" --from "dev-$i" --to all --type STATUS --subject "w${i}" >/dev/null ) &
  done
  wait
  local headers bad=0
  headers="$(grep -c '^### \[' "$cbus")"
  for i in $(seq 1 20); do
    # header for worker i must be followed by exactly its 5 body lines
    if ! grep -A5 -E "^### \[.*\] dev-${i} -> all \| STATUS w${i}$" "$cbus" | tail -n 5 \
         | awk -v w="w${i}" 'BEGIN{n=0} $1==w && $2=="line" {n++} END{exit (n==5)?0:1}'; then
      bad=$((bad + 1))
    fi
  done
  if [[ "$headers" -eq 20 && "$bad" -eq 0 ]]; then ok "20 parallel appends, no interleaving ($label)"; else nok "20 parallel appends, no interleaving ($label)" "headers=$headers bad=$bad"; fi
}
check_concurrent flock BUS_APPEND_NO_FLOCK=0
check_concurrent lockfile BUS_APPEND_NO_FLOCK=1

echo "-----------------------------------------------------------------"
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
