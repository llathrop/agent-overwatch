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

Writes, atomically (flock when available, mkdir-lock otherwise):

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
subject or body matches a secret pattern; only the line number is reported.

Exit codes: 0 written, 1 usage / IO error, 2 refused (secret pattern detected).
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
LOCK_DIR=""
cleanup() {
  rm -rf "$TMP"
  if [[ -n "$LOCK_DIR" ]]; then rmdir "$LOCK_DIR" 2>/dev/null || true; fi
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
# BUS_APPEND_NO_FLOCK=1 forces the mkdir-lock fallback (used by tests)
if [[ "${BUS_APPEND_NO_FLOCK:-0}" != 1 ]] && command -v flock >/dev/null 2>&1; then
  flock -x -w 30 9 || die "Timed out waiting for lock on $BUS"
  write_entry
else
  lock="${BUS}.lock.d"
  tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [[ "$tries" -lt 300 ]] || die "Timed out waiting for lock $lock (remove it if stale)"
    sleep 0.1
  done
  LOCK_DIR="$lock"
  write_entry
  rmdir "$LOCK_DIR" 2>/dev/null || true
  LOCK_DIR=""
fi
exec 9>&-

echo "$HEADER_WRITTEN"
