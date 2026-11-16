#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch — Atomic, timestamped AGENT_BUS.md appender
# Usage: bus_append.sh --from ROLE --to LIST --type TYPE --subject TEXT
#                      [--ref auto|BRANCH@SHA] [--bus PATH] [--repo DIR] < body
# -----------------------------------------------------------------------------

FROM=""
TO=""
TYPE=""
SUBJECT=""
REF=""
BUS=""
REPO_DIR="."

VALID_TYPES=("TAKEOVER" "BRIEF" "ACTION" "RESULT" "CONCERN" "QA APPROVE" "QA HOLD" "STATUS" "USAGE")

show_help() {
  cat <<'EOF'
Agent Overwatch — append one entry to the coordination bus (AGENT_BUS.md)

Usage:
  bus_append.sh --from ROLE --to LIST --type TYPE --subject TEXT \
                [--ref auto|BRANCH@SHA] [--bus PATH] [--repo DIR] < body.txt

Writes, atomically (flock when available, else an O_EXCL <bus>.lock file whose
holder is recovered if its pid is dead or it is older than 60s):

  ### [YYYY-MM-DD HH:MM:SS UTC] <from> -> <to> | <TYPE> [<branch>@<sha>] <subject>
  <body read from stdin; may be empty>

Options:
  --from ROLE       Author role/id (QA verdicts require a role containing "qa")
  --to LIST         Recipient(s), e.g. "qa-1,coordinator" or "all"
  --type TYPE       One of: TAKEOVER BRIEF ACTION RESULT CONCERN "QA APPROVE"
                    "QA HOLD" STATUS USAGE
  --subject TEXT    One-line subject
  --ref REF         "auto" = current branch@12-char HEAD sha of --repo, or an
                    explicit BRANCH@SHA (sha >= 7 hex chars). Required for QA
                    APPROVE / QA HOLD.
  --bus PATH        Bus file (default: <repo toplevel>/AGENT_BUS.md). Must exist.
  --repo DIR        Git repo used for --ref auto and the default bus (default: .)
  -h, --help        Show this help

The UTC timestamp is stamped automatically. The entry is refused (exit 2) if the
subject or body matches a secret pattern (only the line number is reported), or
if a body line starts with a Markdown heading marker ("# ", "## ", "###...")
that could forge an entry header such as a QA verdict.

Environment: BUS_APPEND_LOCK_WAIT (default 30s), BUS_APPEND_LOCK_STALE (60s),
BUS_APPEND_NO_FLOCK=1 (force the lockfile fallback).

Exit codes: 0 written, 1 usage / IO / lock timeout, 2 refused (secret or
forged-header pattern detected).
EOF
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

need_arg() {
  local opt="$1"
  shift
  if [[ $# -lt 1 || -z "$1" || "$1" == --* ]]; then
    die "Option ${opt} requires a value. Run '$0 --help' for usage."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --from)    need_arg "$@"; FROM="$2"; shift 2 ;;
    --to)      need_arg "$@"; TO="$2"; shift 2 ;;
    --type)    need_arg "$@"; TYPE="$2"; shift 2 ;;
    --subject) need_arg "$@"; SUBJECT="$2"; shift 2 ;;
    --ref)     need_arg "$@"; REF="$2"; shift 2 ;;
    --bus)     need_arg "$@"; BUS="$2"; shift 2 ;;
    --repo)    need_arg "$@"; REPO_DIR="$2"; shift 2 ;;
    *) die "Unknown argument: $1. Run '$0 --help' for usage." ;;
  esac
done

[[ -n "$FROM" ]] || die "--from is required"
[[ -n "$TO" ]] || die "--to is required"
[[ -n "$TYPE" ]] || die "--type is required"
[[ -n "$SUBJECT" ]] || die "--subject is required"

for pair in "from:$FROM" "to:$TO" "type:$TYPE" "subject:$SUBJECT" "ref:$REF"; do
  if [[ "$pair" == *$'\n'* || "$pair" == *$'\r'* ]]; then
    die "--${pair%%:*} must be a single line"
  fi
done
[[ "$FROM" != *"->"* && "$FROM" != *"|"* ]] || die "--from must not contain '->' or '|'"
[[ "$TO" != *"|"* ]] || die "--to must not contain '|'"

type_ok=false
for t in "${VALID_TYPES[@]}"; do
  [[ "$TYPE" == "$t" ]] && type_ok=true
done
if [[ "$type_ok" != true ]]; then
  die "Invalid --type '$TYPE'. Valid: TAKEOVER, BRIEF, ACTION, RESULT, CONCERN, QA APPROVE, QA HOLD, STATUS, USAGE"
fi

if [[ "$TYPE" == QA\ * ]]; then
  [[ "${FROM,,}" == *qa* ]] || die "'$TYPE' must be written by a QA role (--from must contain 'qa'); QA writes its own verdicts."
  [[ -n "$REF" ]] || die "'$TYPE' requires --ref auto|BRANCH@SHA"
fi

# Resolve --ref
if [[ "$REF" == "auto" ]]; then
  [[ -d "$REPO_DIR" ]] || die "--repo directory does not exist: $REPO_DIR"
  branch="$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] || die "--ref auto: $REPO_DIR is not a git repo or HEAD is detached"
  sha="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$sha" ]] || die "--ref auto: cannot resolve HEAD in $REPO_DIR"
  REF="${branch}@${sha:0:12}"
elif [[ -n "$REF" ]]; then
  [[ "$REF" =~ ^[^[:space:]]+@[0-9a-fA-F]{7,40}$ ]] || die "--ref must be 'auto' or BRANCH@SHA (sha >= 7 hex chars): $REF"
fi

# Resolve bus path
if [[ -z "$BUS" ]]; then
  top="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  BUS="${top:-$REPO_DIR}/AGENT_BUS.md"
fi
[[ -f "$BUS" ]] || die "Bus file does not exist: $BUS"
[[ -w "$BUS" ]] || die "Bus file is not writable: $BUS"

# Body from stdin (a terminal on stdin means "no body")
BODY=""
if [[ ! -t 0 ]]; then
  BODY="$(cat)"
fi

# -----------------------------------------------------------------------------
# Secret refusal (same pattern library as verify_atomic_branch.sh).
# Only line numbers are reported, never content.
# -----------------------------------------------------------------------------
SECRET_REGEXES=(
  'BEGIN[[:space:]]+([A-Za-z0-9_-]+[[:space:]]+)?PRIVATE KEY'
  '-----BEGIN[[:space:]]OPENSSH[[:space:]]PRIVATE[[:space:]]KEY'
  'tskey-auth-[a-zA-Z0-9_-]+'
  'ghp_[a-zA-Z0-9]{20,}'
  'github_pat_[a-zA-Z0-9_]{20,}'
  'sk-[a-zA-Z0-9_-]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
)
PW_REGEX='(PASSWORD|PASSWD|SECRET_KEY|API_SECRET)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'' ]{8,}["'\'']'
PW_PLACEHOLDER='(\{\{|\}\}|<.*>|TODO|CHANGEME|example|placeholder|dummy|sample|your_|default|none|null|false|true)'

TMP="$(mktemp -d)"
LOCK_FILE=""
LOCK_TOKEN=""
# Remove the lockfile only if it still holds our token (never someone else's)
release_lock() {
  if [[ -n "$LOCK_FILE" && "$(cat -- "$LOCK_FILE" 2>/dev/null || true)" == "$LOCK_TOKEN" ]]; then
    rm -f -- "$LOCK_FILE"
  fi
  LOCK_FILE=""
}
BREAK_FILE=""
cleanup() {
  rm -rf "$TMP"
  release_lock
  if [[ -n "$BREAK_FILE" ]]; then rm -f -- "$BREAK_FILE"; fi
}
trap cleanup EXIT

# Line 1 = subject, line N+1 = body line N
{ printf '%s\n' "$SUBJECT"; [[ -n "$BODY" ]] && printf '%s\n' "$BODY"; } > "$TMP/check.txt"
hits="$(
  {
    for re in "${SECRET_REGEXES[@]}"; do
      grep -n -E -e "$re" -- "$TMP/check.txt" 2>/dev/null | cut -d: -f1 || true
    done
    grep -n -E -e "$PW_REGEX" -- "$TMP/check.txt" 2>/dev/null | grep -viE -e "$PW_PLACEHOLDER" | cut -d: -f1 || true
  } | sort -n -u
)"
if [[ -n "$hits" ]]; then
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if [[ "$n" -eq 1 ]]; then
      echo "[REFUSED] Secret pattern detected in subject" >&2
    else
      echo "[REFUSED] Secret pattern detected in body line $((n - 1))" >&2
    fi
  done <<< "$hits"
  echo "[REFUSED] Nothing was written to $BUS. Reference variable names or file paths instead of values." >&2
  exit 2
fi

# -----------------------------------------------------------------------------
# Header-injection refusal: a body line that looks like a Markdown heading
# (^#{1,6} + space, or anything starting "###") could be parsed as a bus entry
# header, e.g. a STATUS that pastes a forged "| QA APPROVE <branch>@<sha>" line.
# -----------------------------------------------------------------------------
if [[ -n "$BODY" ]]; then
  hdr_hits="$(printf '%s\n' "$BODY" | grep -n -E -e '^(#{1,6}([[:space:]]|$)|###)' | cut -d: -f1 || true)"
  if [[ -n "$hdr_hits" ]]; then
    while IFS= read -r n; do
      [[ -n "$n" ]] && echo "[REFUSED] Body line ${n} starts with a Markdown heading marker ('#'); it could forge a bus entry header." >&2
    done <<< "$hdr_hits"
    echo "[REFUSED] Nothing was written to $BUS. Indent the line, quote it in backticks, or drop the leading '#'." >&2
    exit 2
  fi
fi

# -----------------------------------------------------------------------------
# Atomic append (timestamp taken inside the lock so entries are ordered)
# -----------------------------------------------------------------------------
write_entry() {
  local ts header lead=""
  ts="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  header="### [${ts}] ${FROM} -> ${TO} | ${TYPE}"
  [[ -n "$REF" ]] && header+=" ${REF}"
  header+=" ${SUBJECT}"
  # Keep entries separated even if the file lacks a trailing newline
  if [[ -s "$BUS" && -n "$(tail -c 1 "$BUS")" ]]; then
    lead=$'\n'
  fi
  local entry="${lead}"$'\n'"${header}"$'\n'
  [[ -n "$BODY" ]] && entry+="${BODY}"$'\n'
  printf '%s' "$entry" >&9
  HEADER_WRITTEN="$header"
}

HEADER_WRITTEN=""
exec 9>>"$BUS"
# BUS_APPEND_NO_FLOCK=1 forces the lockfile fallback (used by tests)
if [[ "${BUS_APPEND_NO_FLOCK:-0}" != 1 ]] && command -v flock >/dev/null 2>&1; then
  flock -x -w "${BUS_APPEND_LOCK_WAIT:-30}" 9 || die "Timed out waiting for lock on $BUS"
  write_entry
else
  # Fallback: O_EXCL lockfile created by bash noclobber (open(2) O_CREAT|O_EXCL),
  # holding "<pid> <epoch> <nonce>". This deliberately avoids the external
  # mkdir(1) binary: mkdir(2) is atomic, but the uutils coreutils 0.10.0 mkdir
  # binary (installed as the system coreutils on some hosts) was observed to let
  # several racing callers "succeed", admitting multiple lock holders. Do not
  # revert to `mkdir "$lock"` without re-running the concurrency tests.
  #
  # A lock whose pid is dead, or that is older than BUS_APPEND_LOCK_STALE
  # seconds (default 60), or that stays empty/malformed for ~2s, is broken by
  # an atomic rename (mv -> rename(2)) and re-checked before deletion.
  # Known limit: breaking a live holder that is merely older than the stale
  # threshold can race with its own release in a microsecond window.
  lock="${BUS}.lock"
  stale_secs="${BUS_APPEND_LOCK_STALE:-60}"
  wait_secs="${BUS_APPEND_LOCK_WAIT:-30}"
  [[ "$stale_secs" =~ ^[0-9]+$ && "$wait_secs" =~ ^[0-9]+$ ]] || die "BUS_APPEND_LOCK_STALE / BUS_APPEND_LOCK_WAIT must be integers"
  max_tries=$((wait_secs * 10))

  pid_alive() {
    kill -0 "$1" 2>/dev/null && return 0
    # kill -0 also fails with EPERM for another user's live process
    command -v ps >/dev/null 2>&1 && ps -p "$1" >/dev/null 2>&1 && return 0
    return 1
  }
  # Breakers are serialized by "<lock>.break" (also O_EXCL) and re-read the lock
  # immediately before renaming it, so a waiter acting on an old view cannot
  # steal a lock that a live process has just acquired.
  break_stale_lock() { # $1 = content we judged stale
    local brk="${lock}.break" moved="${lock}.stale.$$" bpid
    if ! ( set -o noclobber; printf '%s\n' "$$" > "$brk" ) 2>/dev/null; then
      # Another breaker is active; clear it only if that breaker died
      bpid="$(cat -- "$brk" 2>/dev/null || true)"
      if [[ "$bpid" =~ ^[0-9]+$ ]] && ! pid_alive "$bpid"; then rm -f -- "$brk"; fi
      return 0
    fi
    BREAK_FILE="$brk"
    if [[ "$(cat -- "$lock" 2>/dev/null || true)" == "$1" ]] && mv -f -- "$lock" "$moved" 2>/dev/null; then
      if [[ "$(cat -- "$moved" 2>/dev/null || true)" == "$1" ]]; then
        echo "[WARN] Broke stale lock $lock (holder: ${1:-<empty>})" >&2
      else
        # Lost a microsecond race: put the fresh lock back if the slot is free
        ( set -o noclobber; cat -- "$moved" > "$lock" ) 2>/dev/null || true
      fi
      rm -f -- "$moved"
    fi
    rm -f -- "$brk"
    BREAK_FILE=""
  }

  tries=0
  same_bad=0
  last_bad=""
  while :; do
    LOCK_TOKEN="$$ $(date +%s) ${RANDOM}${RANDOM}"
    if ( set -o noclobber; printf '%s\n' "$LOCK_TOKEN" > "$lock" ) 2>/dev/null; then
      break
    fi
    tries=$((tries + 1))
    [[ "$tries" -le "$max_tries" ]] || die "Timed out after ${wait_secs}s waiting for lock $lock (holder: $(cat -- "$lock" 2>/dev/null || echo '?'))"
    content="$(cat -- "$lock" 2>/dev/null || true)"
    if [[ "$content" =~ ^([0-9]+)\ ([0-9]+)(\ |$) ]]; then
      same_bad=0
      holder_pid="${BASH_REMATCH[1]}"
      holder_ts="${BASH_REMATCH[2]}"
      if ! pid_alive "$holder_pid" || (( $(date +%s) - holder_ts > stale_secs )); then
        break_stale_lock "$content"
        continue
      fi
    elif [[ -e "$lock" ]]; then
      # Empty or malformed: the holder may be mid-write; break only if it persists
      if [[ "$content" == "$last_bad" ]]; then same_bad=$((same_bad + 1)); else same_bad=0; fi
      last_bad="$content"
      if [[ "$same_bad" -ge 20 ]]; then
        break_stale_lock "$content"
        same_bad=0
        continue
      fi
    fi
    sleep 0.1
  done
  LOCK_FILE="$lock"
  write_entry
  release_lock
fi
exec 9>&-

echo "$HEADER_WRITTEN"
