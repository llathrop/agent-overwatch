#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Agent Overwatch — Bus / Secret / Health Watcher
#
# Prints one line per event so a background watcher (any monitor, cron job or shell loop) can
# surface activity while QA and dev subagents are idle between turns.
#
#   BUS: <bus header>                       new "### [YYYY-MM-DD ...]" entry
#   SECRET? <file>:<line> <pattern-name>    possible secret (content NEVER shown)
#   CHECK-FAIL <n>: <last output line>      --check number <n> exited non-zero
#   LEASE stale: <id> last_seen <ts>        coordinator lease has expired
#   LEASE holder changed: <old> -> <new>    lease moved to a different id
#
# Exits 0 on every normal run (2 on usage errors). In --once mode it prints
# nothing when nothing is new.
# -----------------------------------------------------------------------------
set -uo pipefail

BUS="./AGENT_BUS.md"
STATE=".overwatch/watch.state"
ALLOWLIST=".overwatch/secret-allowlist"
LEASE=""
INTERVAL=120
ONCE=false
SINCE_NOW=false
CHECK_TIMEOUT=60
CHECKS=()

show_help() {
  cat <<'EOF'
Agent Overwatch — Bus / Secret / Health Watcher

Usage:
  overwatch_watch.sh [--bus PATH] [--state FILE] [--interval SEC] [--once]
                     [--check 'CMD']... [--allowlist FILE] [--lease FILE]
                     [--check-timeout SEC] [--since-now]

Options:
  --bus PATH          Bus file to follow (default: ./AGENT_BUS.md).
  --state FILE        Offset state file (default: .overwatch/watch.state).
                      Handles truncation/rewrite of the bus by rescanning.
  --interval SEC      Loop period in seconds (default: 120). Ignored with --once.
  --once              Run a single pass and exit (silent when nothing is new).
  --check 'CMD'       Health check run via 'bash -c' each pass (repeatable).
                      Non-zero exit prints: CHECK-FAIL <n>: <last line, 160 chars>
  --check-timeout SEC Per-check timeout when 'timeout' is available (default 60).
  --allowlist FILE    ERE patterns (one per line, '#' comments) whose matches
                      are not reported (default: .overwatch/secret-allowlist).
                      Each pattern is tested against the matched text and, for
                      key=value hits, against the value alone.
  --lease FILE        Coordinator lease (default: <bus dir>/status/coordinator.lease).
  --since-now         With no state yet, start at the current end of the bus
                      instead of reporting every existing header.
  -h, --help          Show this help.

Output prefixes: "BUS: ", "SECRET? ", "CHECK-FAIL ", "LEASE ".
Example (background watcher / plain loop):
  overwatch_watch.sh --interval 120 --check 'curl -fsS http://localhost:8080/health'
EOF
}

die_usage() { echo "[ERROR] $1" >&2; echo "Run '$0 --help' for usage." >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --once) ONCE=true; shift ;;
    --since-now) SINCE_NOW=true; shift ;;
    --bus|--state|--interval|--check|--allowlist|--lease|--check-timeout)
      [[ $# -ge 2 ]] || die_usage "$1 requires a value"
      case "$1" in
        --bus) BUS="$2" ;;
        --state) STATE="$2" ;;
        --interval) INTERVAL="$2" ;;
        --check) CHECKS+=("$2") ;;
        --allowlist) ALLOWLIST="$2" ;;
        --lease) LEASE="$2" ;;
        --check-timeout) CHECK_TIMEOUT="$2" ;;
      esac
      shift 2 ;;
    *) die_usage "Unknown argument: $1" ;;
  esac
done

[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -ge 1 ]] || die_usage "--interval must be a positive integer"
[[ "$CHECK_TIMEOUT" =~ ^[0-9]+$ && "$CHECK_TIMEOUT" -ge 1 ]] || die_usage "--check-timeout must be a positive integer"
[[ -n "$LEASE" ]] || LEASE="$(dirname "$BUS")/status/coordinator.lease"

# -----------------------------------------------------------------------------
# Secret patterns: "name|flags|ERE". Same family as verify_atomic_branch.sh,
# plus a generic key=value credential assignment. flags: i = case-insensitive,
# v = key=value pattern (allowlist also tested against the value part).
# -----------------------------------------------------------------------------
SECRET_PATTERNS=(
  'Private Key Block||BEGIN[[:space:]]+([A-Za-z0-9_-]+[[:space:]]+)?PRIVATE KEY'
  'Tailscale Auth Key||tskey-auth-[a-zA-Z0-9_-]+'
  'GitHub Classic PAT||ghp_[a-zA-Z0-9]{20,}'
  'GitHub Fine-Grained PAT||github_pat_[a-zA-Z0-9_]{20,}'
  'OpenAI/Anthropic API Key||sk-[a-zA-Z0-9_-]{20,}'
  'AWS Access Key ID||AKIA[0-9A-Z]{16}'
  "Hardcoded Password/Secret Assignment|v|(PASSWORD|PASSWD|SECRET_KEY|API_SECRET)[[:space:]]*[:=][[:space:]]*[\"'][^\"' ]{8,}[\"']"
  'Generic Credential Assignment|iv|(password|token|secret|api_?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}'
)

# Values that are obviously placeholders, not credentials.
PLACEHOLDER_RE='^["'\''`]?(<|\{\{|\$\{|\$[A-Za-z_]|\*\*\*|xxx)|REDACTED|CHANGEME|placeholder|example|your_|dummy'

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ao-watch.XXXXXX")" || exit 0
trap 'rm -rf "$WORK_DIR"' EXIT
ALLOW_CLEAN="$WORK_DIR/allow"

# Keep valid patterns only; an invalid ERE is dropped with a warning instead of
# silently breaking every other allowlist entry.
load_allowlist() {
  : > "$ALLOW_CLEAN"
  [[ -f "$ALLOWLIST" ]] || return 0
  local pat n=0 rc
  while IFS= read -r pat || [[ -n "$pat" ]]; do
    n=$((n + 1))
    pat="${pat%$'\r'}"
    [[ "$pat" =~ ^[[:space:]]*(#|$) ]] && continue
    # Non-empty input: busybox grep only compiles the regex once it reads a line.
    printf 'x\n' | grep -qE -- "$pat" 2>/dev/null; rc=$?
    if (( rc == 2 )); then
      echo "[WARN] ignoring invalid allowlist regex at ${ALLOWLIST}:${n}" >&2
      continue
    fi
    printf '%s\n' "$pat" >> "$ALLOW_CLEAN"
  done < "$ALLOWLIST"
}

allowlisted() { # $1 = text
  [[ -s "$ALLOW_CLEAN" ]] || return 1
  printf '%s\n' "$1" | grep -qE -f "$ALLOW_CLEAN" 2>/dev/null
}

# Scan a file; print "SECRET? <label>:<line+base> <name>" per non-allowlisted hit.
# Also records hit line numbers in $WORK_DIR/hitlines for header redaction.
scan_secrets() { # $1=file $2=label $3=line-number base
  local file="$1" label="$2" base="$3" entry name flags re gflags hits l lnum match value
  for entry in "${SECRET_PATTERNS[@]}"; do
    name="${entry%%|*}"; entry="${entry#*|}"
    flags="${entry%%|*}"; re="${entry#*|}"
    gflags="-noE"; [[ "$flags" == *i* ]] && gflags="-noiE"
    hits="$(grep "$gflags" -- "$re" "$file" 2>/dev/null || true)"
    [[ -n "$hits" ]] || continue
    while IFS= read -r l; do
      lnum="${l%%:*}"; match="${l#*:}"
      if [[ "$flags" == *v* ]]; then
        value="$(printf '%s' "$match" | sed -E 's/^[^:=]*[:=][[:space:]]*//')"
        if printf '%s\n' "$value" | grep -qiE "$PLACEHOLDER_RE"; then continue; fi
        if allowlisted "$value"; then continue; fi
      fi
      if allowlisted "$match"; then continue; fi
      echo "SECRET? ${label}:$((lnum + base)) ${name}"
      echo "$lnum" >> "$WORK_DIR/hitlines"
    done <<< "$hits"
  done
}

# Contains a secret? (used to redact check output before printing)
has_secret() {
  local entry flags re gflags
  for entry in "${SECRET_PATTERNS[@]}"; do
    entry="${entry#*|}"; flags="${entry%%|*}"; re="${entry#*|}"
    gflags="-qE"; [[ "$flags" == *i* ]] && gflags="-qiE"
    if printf '%s\n' "$1" | grep "$gflags" -- "$re" 2>/dev/null; then return 0; fi
  done
  return 1
}

# ---------------------------- state (key=value) ------------------------------
# Plain variables (no associative arrays) so this runs on bash 3.2 as well.
S_OFFSET=""; S_OFFSET_HASH=""; S_LEASE_ID=""; S_LEASE_WARNED=""
read_state() {
  S_OFFSET=""; S_OFFSET_HASH=""; S_LEASE_ID=""; S_LEASE_WARNED=""
  [[ -f "$STATE" ]] || return 0
  local k v
  while IFS='=' read -r k v; do
    v="${v%$'\r'}"
    case "$k" in
      offset) S_OFFSET="$v" ;;
      offset_hash) S_OFFSET_HASH="$v" ;;
      lease_id) S_LEASE_ID="$v" ;;
      lease_warned) S_LEASE_WARNED="$v" ;;
    esac
  done < "$STATE"
}
write_state() {
  local dir tmp
  dir="$(dirname "$STATE")"
  mkdir -p "$dir" 2>/dev/null || { echo "[WARN] cannot create $dir" >&2; return 0; }
  tmp="$(mktemp "$dir/.watch.state.XXXXXX")" || return 0
  printf 'offset=%s\noffset_hash=%s\nlease_id=%s\nlease_warned=%s\n' \
    "$S_OFFSET" "$S_OFFSET_HASH" "$S_LEASE_ID" "$S_LEASE_WARNED" > "$tmp"
  mv -f "$tmp" "$STATE"
}

prefix_hash() { # $1=file $2=line count -> hash of the first N lines
  head -n "$2" "$1" | cksum | cut -d' ' -f1
}

# ------------------------------- bus pass ------------------------------------
check_bus() {
  if [[ ! -f "$BUS" ]]; then
    echo "[WARN] bus not found: $BUS" >&2
    return 0
  fi
  local total offset start new hdr lnum text
  total="$(wc -l < "$BUS" | tr -d ' ')"
  # Count a final line without trailing newline too.
  if [[ -s "$BUS" && -n "$(tail -c 1 "$BUS")" ]]; then total=$((total + 1)); fi

  if [[ -z "$S_OFFSET" ]]; then
    if [[ "$SINCE_NOW" == true ]]; then
      S_OFFSET="$total"; S_OFFSET_HASH="$( [[ $total -gt 0 ]] && prefix_hash "$BUS" "$total" )"
      return 0
    fi
    offset=0
  else
    offset="$S_OFFSET"
    [[ "$offset" =~ ^[0-9]+$ ]] || offset=0
    if (( offset > total )); then
      echo "BUS: (bus shrank from $offset to $total lines; rescanning from the top)"
      offset=0
    elif (( offset > 0 )) && [[ "$(prefix_hash "$BUS" "$offset")" != "$S_OFFSET_HASH" ]]; then
      echo "BUS: (bus rewritten within its first $offset lines; rescanning from the top)"
      offset=0
    fi
  fi

  if (( total > offset )); then
    start=$((offset + 1))
    new="$WORK_DIR/new"
    tail -n "+$start" "$BUS" > "$new"
    : > "$WORK_DIR/hitlines"
    scan_secrets "$new" "$BUS" "$offset"
    hdr="$(grep -nE '^### \[[0-9]{4}-' "$new" || true)"
    if [[ -n "$hdr" ]]; then
      while IFS= read -r l; do
        lnum="${l%%:*}"; text="${l#*:}"; text="${text#\#\#\# }"
        if grep -qx "$lnum" "$WORK_DIR/hitlines"; then
          echo "BUS: <header at line $((lnum + offset)) redacted: possible secret>"
        else
          echo "BUS: ${text:0:240}"
        fi
      done <<< "$hdr"
    fi
  fi
  S_OFFSET="$total"
  S_OFFSET_HASH="$( (( total > 0 )) && prefix_hash "$BUS" "$total" )"
}

# ------------------------------ checks ---------------------------------------
run_checks() {
  local i=0 cmd out rc last
  for cmd in ${CHECKS[@]+"${CHECKS[@]}"}; do
    i=$((i + 1))
    if command -v timeout >/dev/null 2>&1; then
      out="$(timeout "$CHECK_TIMEOUT" bash -c "$cmd" 2>&1 < /dev/null)"; rc=$?
    else
      out="$(bash -c "$cmd" 2>&1 < /dev/null)"; rc=$?
    fi
    if (( rc != 0 )); then
      last="$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | tr -d '\r')"
      [[ -n "$last" ]] || last="(exit $rc, no output)"
      (( rc == 124 )) && last="(timed out after ${CHECK_TIMEOUT}s) $last"
      if has_secret "$last"; then last="(exit $rc; output redacted: possible secret)"; fi
      echo "CHECK-FAIL ${i}: ${last:0:160}"
    fi
  done
}

# ------------------------------ lease ----------------------------------------
# "YYYY-MM-DD HH:MM:SS UTC" or ISO "YYYY-MM-DDTHH:MM:SSZ" -> epoch (GNU/busybox/BSD date)
ts_to_epoch() {
  local t="${1% UTC}"; t="${t%Z}"; t="${t/T/ }"
  local re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$'
  [[ "$t" =~ $re ]] || return 1
  [[ ${#t} -eq 16 ]] && t="$t:00"
  date -u -d "$t" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$t" +%s 2>/dev/null
}

check_lease() {
  [[ -f "$LEASE" ]] || return 0
  local k v id="" last_seen="" epoch="" ttl="" now key
  while IFS='=' read -r k v; do
    v="${v%$'\r'}"
    case "$k" in
      id) id="$v" ;; last_seen) last_seen="$v" ;;
      last_seen_epoch) epoch="$v" ;; ttl_min) ttl="$v" ;;
    esac
  done < "$LEASE"
  [[ -n "$id" ]] || return 0
  # Never echo lease fields that look like credentials (a hand-edited file).
  if has_secret "$id"; then id="<redacted id: possible secret>"; fi
  if has_secret "$last_seen"; then last_seen="<redacted>"; fi
  if [[ -n "$S_LEASE_ID" && "$S_LEASE_ID" != "$id" ]]; then
    echo "LEASE holder changed: $S_LEASE_ID -> ${id}"
  fi
  S_LEASE_ID="$id"
  # BRIEF-minimal leases (id/since/last_seen only): derive epoch, default ttl 30.
  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch="$(ts_to_epoch "$last_seen" || true)"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=30
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 0
  now="$(date -u +%s)"
  if (( now >= epoch + ttl * 60 )); then
    key="${id}|${epoch}"
    if [[ "$S_LEASE_WARNED" != "$key" ]]; then
      echo "LEASE stale: ${id} last_seen ${last_seen}"
      S_LEASE_WARNED="$key"
    fi
  fi
}

run_pass() {
  read_state
  load_allowlist
  check_bus
  run_checks
  check_lease
  write_state
}

if [[ "$ONCE" == true ]]; then
  run_pass
  exit 0
fi

while true; do
  run_pass
  sleep "$INTERVAL"
done
