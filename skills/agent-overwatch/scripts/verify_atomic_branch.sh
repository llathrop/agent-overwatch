#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch — Pre-Merge Atomic Branch Gate
# Usage: verify_atomic_branch.sh [--repo DIR] [--base main|master] [--qa-file PATH]
#        [--allow-external-qa] [--max-files N] [--help]
# -----------------------------------------------------------------------------

REPO_DIR="."
BASE_BRANCH=""
QA_FILE=""
ALLOW_EXTERNAL_QA=false
MAX_FILES=25
ERRORS=0

show_help() {
  cat <<'EOF'
Agent Overwatch — Pre-Merge Atomic Branch Gate

Verifies that a git branch adheres to atomic branching discipline, has a clean
working tree, contains zero accidental secrets (in the final files AND in the
lines added by every commit on the branch), and carries a QA APPROVE verdict
bound to the current branch and HEAD commit.

QA verdict format (one header line in the ledger, written by QA via bus_append.sh):
  ### [YYYY-MM-DD HH:MM:SS UTC] <qa-role> -> <to> | QA APPROVE <branch>@<sha12> <subject>
  ### [YYYY-MM-DD HH:MM:SS UTC] <qa-role> -> <to> | QA HOLD <branch>@<sha12> <subject>
The author (<qa-role>) must contain "qa". The latest verdict for the current
branch wins; its SHA (prefix >= 7 chars) must match HEAD.

Usage:
  verify_atomic_branch.sh [OPTIONS]

Options:
  --repo DIR            Git repository root directory (default: ".")
  --base BRANCH         Target base branch for comparison (default: auto-detected main or master)
  --qa-file PATH        Path to coordination ledger / audit file to verify for QA approval
  --allow-external-qa   QA sign-off lives outside the ledger (native board / PR review):
                        a missing ledger or missing matching verdict is a WARN, not a FAIL.
                        A HOLD or stale verdict for this branch in the ledger still FAILs.
  --allow-bus-only      Deprecated alias for --allow-external-qa
  --max-files N         Threshold for changed files warning on atomic scope (default: 25)
  -h, --help            Show this help message and exit

Exit Codes:
  0: All hard pre-merge gates passed.
  1: Hard failure (on main/master, dirty working tree, secret scan match,
     missing/stale/HOLD QA verdict, or bad arguments).
EOF
}

# Require a non-empty value for options that take an argument (safe under set -u)
need_arg() {
  local opt="$1"
  shift
  if [[ $# -lt 1 || -z "$1" || "$1" == --* ]]; then
    echo "[ERROR] Option ${opt} requires a value." >&2
    echo "Run '$0 --help' for usage." >&2
    exit 1
  fi
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --repo)
      need_arg "$@"
      REPO_DIR="$2"
      shift 2
      ;;
    --base)
      need_arg "$@"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --qa-file)
      need_arg "$@"
      QA_FILE="$2"
      shift 2
      ;;
    --allow-external-qa)
      ALLOW_EXTERNAL_QA=true
      shift
      ;;
    --allow-bus-only)
      echo "[WARN] --allow-bus-only is deprecated; use --allow-external-qa." >&2
      ALLOW_EXTERNAL_QA=true
      shift
      ;;
    --max-files)
      need_arg "$@"
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] --max-files requires a non-negative integer (got: $2)" >&2
        exit 1
      fi
      MAX_FILES="$2"
      shift 2
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
    *)
      echo "[ERROR] Unexpected positional argument: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
  esac
done

# Resolve absolute repo directory
if [[ ! -d "$REPO_DIR" ]]; then
  echo "[FAIL] Repository directory does not exist: $REPO_DIR" >&2
  exit 1
fi
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

echo "================================================================="
echo "Agent Overwatch — Verifying Atomic Branch Pre-Merge Gates"
echo "  Repository:  ${REPO_DIR}"
echo "================================================================="

# -----------------------------------------------------------------------------
# Gate 1: Git Repository & Branch Refusal
# -----------------------------------------------------------------------------
if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[FAIL] Not inside a valid Git work tree: ${REPO_DIR}" >&2
  exit 1
fi

CURRENT_BRANCH="$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"

if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "[FAIL] Git repository is in detached HEAD state. Please switch to an atomic branch." >&2
  ERRORS=$((ERRORS + 1))
elif [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "[FAIL] Current branch is '${CURRENT_BRANCH}'. Direct commits or unbranched work on protected base branch are forbidden!" >&2
  echo "[INFO] Create and checkout an atomic feature/fix branch: git checkout -b feat/<topic>" >&2
  ERRORS=$((ERRORS + 1))
else
  echo "[PASS] Active branch: '${CURRENT_BRANCH}' (branching isolation confirmed)"
fi

# -----------------------------------------------------------------------------
# Gate 2: Clean Working Tree
# -----------------------------------------------------------------------------
STATUS_DIRTY="$(git -C "$REPO_DIR" status --porcelain 2>/dev/null || true)"
if [[ -n "$STATUS_DIRTY" ]]; then
  echo "[FAIL] Working tree is dirty. Uncommitted changes detected:" >&2
  git -C "$REPO_DIR" status --short >&2
  echo "[INFO] Commit or stash all changes before running pre-merge verification." >&2
  ERRORS=$((ERRORS + 1))
else
  echo "[PASS] Working tree is clean (no uncommitted or untracked changes)"
fi

# -----------------------------------------------------------------------------
# Gate 3: Base Branch Detection & Diff Size / Commit Count
# -----------------------------------------------------------------------------
if [[ -z "$BASE_BRANCH" ]]; then
  if git -C "$REPO_DIR" show-ref --verify --quiet refs/heads/main || git -C "$REPO_DIR" show-ref --verify --quiet refs/remotes/origin/main; then
    BASE_BRANCH="main"
  elif git -C "$REPO_DIR" show-ref --verify --quiet refs/heads/master || git -C "$REPO_DIR" show-ref --verify --quiet refs/remotes/origin/master; then
    BASE_BRANCH="master"
  else
    BASE_BRANCH="main"
  fi
fi

# Check if current branch equals base branch
if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  echo "[FAIL] Current branch cannot be identical to target base branch '${BASE_BRANCH}'." >&2
  ERRORS=$((ERRORS + 1))
fi

# Resolve merge base
MERGE_BASE=""
BASE_FOUND=false
if git -C "$REPO_DIR" rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null 2>&1; then
  MERGE_BASE="$(git -C "$REPO_DIR" merge-base HEAD "$BASE_BRANCH" 2>/dev/null || true)"
elif git -C "$REPO_DIR" rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  MERGE_BASE="$(git -C "$REPO_DIR" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null || true)"
fi

if [[ -n "$MERGE_BASE" ]]; then
  BASE_FOUND=true
else
  # Fallback: if base branch doesn't exist yet, compare with root commit
  MERGE_BASE="$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD 2>/dev/null | head -n 1 || true)"
fi

COMMIT_COUNT=0
DIFF_SUMMARY=""
CHANGED_FILES=""
FILE_COUNT=0

if [[ -n "$MERGE_BASE" ]]; then
  COMMIT_COUNT="$(git -C "$REPO_DIR" rev-list --count "${MERGE_BASE}..HEAD" 2>/dev/null || echo "0")"
  DIFF_SUMMARY="$(git -C "$REPO_DIR" diff --shortstat "${MERGE_BASE}"...HEAD 2>/dev/null || echo "")"
  CHANGED_FILES="$(git -C "$REPO_DIR" diff --name-only --diff-filter=ACMRT "${MERGE_BASE}"...HEAD 2>/dev/null || true)"
  if [[ -n "$CHANGED_FILES" ]]; then
    FILE_COUNT="$(echo "$CHANGED_FILES" | grep -c . || echo "0")"
  fi
fi

echo "[INFO] Base branch: '${BASE_BRANCH}' (merge-base: ${MERGE_BASE:-none})"
echo "[INFO] Commits on branch: ${COMMIT_COUNT}"
echo "[INFO] Diff summary: ${DIFF_SUMMARY:-no file modifications}"
echo "[INFO] Files modified: ${FILE_COUNT}"

if [[ "$FILE_COUNT" -gt "$MAX_FILES" ]]; then
  echo "[WARN] Branch modifies ${FILE_COUNT} files, exceeding atomic threshold (${MAX_FILES})."
  echo "       Consider breaking this branch into smaller, independently testable slices."
elif [[ "$FILE_COUNT" -eq 0 && "$COMMIT_COUNT" -gt 0 ]]; then
  echo "[WARN] Commits exist on branch but no file diff against base '${BASE_BRANCH}'."
else
  echo "[PASS] Branch diff scope is within atomic limits (${FILE_COUNT} files)."
fi

# -----------------------------------------------------------------------------
# Secret pattern library (shared shape with bus_append.sh).
# Matched CONTENT is NEVER printed: only locations and pattern names.
# Regexes are written so this file does not match itself.
# -----------------------------------------------------------------------------
SECRET_NAMES=(
  "Private Key Block"
  "OpenSSH Private Key"
  "Tailscale Auth Key"
  "GitHub Classic PAT"
  "GitHub Fine-Grained PAT"
  "OpenAI/Anthropic API Key"
  "AWS Access Key ID"
  "Slack Token"
)
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
PW_NAME="Hardcoded Password/Secret Assignment"
PW_REGEX='(PASSWORD|PASSWD|SECRET_KEY|API_SECRET)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'' ]{8,}["'\'']'
PW_PLACEHOLDER='(\{\{|\}\}|<.*>|TODO|CHANGEME|example|placeholder|dummy|sample|your_|default|none|null|false|true)'

# secret_hits FILE -> prints "<line>\t<pattern name>" for every hit (never content)
secret_hits() {
  local f="$1" i n
  for i in "${!SECRET_REGEXES[@]}"; do
    while IFS= read -r n; do
      [[ -n "$n" ]] && printf '%s\t%s\n' "$n" "${SECRET_NAMES[$i]}"
    done < <(grep -I -n -E -e "${SECRET_REGEXES[$i]}" -- "$f" 2>/dev/null | cut -d: -f1 || true)
  done
  while IFS= read -r n; do
    [[ -n "$n" ]] && printf '%s\t%s\n' "$n" "$PW_NAME"
  done < <(grep -I -n -E -e "$PW_REGEX" -- "$f" 2>/dev/null | grep -viE -e "$PW_PLACEHOLDER" | cut -d: -f1 || true)
}

SCAN_TMP="$(mktemp -d)"
trap 'rm -rf "$SCAN_TMP"' EXIT

# -----------------------------------------------------------------------------
# Gate 4: Secret Scanning (final changed files + every commit's added lines)
# -----------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "[SCAN] Scanning changed files and branch history for accidental secret patterns..."
SECRET_HITS=0

# 4a. Final contents of changed files (or all tracked files if no diff list)
FILES_TO_SCAN=()
if [[ -n "$CHANGED_FILES" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES_TO_SCAN+=("$f")
  done <<< "$CHANGED_FILES"
else
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES_TO_SCAN+=("$f")
  done < <(git -C "$REPO_DIR" ls-files 2>/dev/null || true)
fi

for f in "${FILES_TO_SCAN[@]+"${FILES_TO_SCAN[@]}"}"; do
  [[ -f "$REPO_DIR/$f" ]] || continue
  while IFS=$'\t' read -r lnum pname; do
    [[ -n "$lnum" ]] || continue
    echo "[FAIL] Secret pattern matched: ${f}:${lnum} (Pattern: ${pname})" >&2
    SECRET_HITS=$((SECRET_HITS + 1))
  done < <(secret_hits "$REPO_DIR/$f")
done

# 4b. Lines added by every commit on the branch (catches add-then-delete)
if [[ "$BASE_FOUND" == true ]]; then
  HISTORY_RANGE="${MERGE_BASE}..HEAD"
else
  HISTORY_RANGE="HEAD"
fi
HISTORY_COMMITS="$(git -C "$REPO_DIR" rev-list --reverse "$HISTORY_RANGE" 2>/dev/null || true)"
HISTORY_COUNT=0
while IFS= read -r sha; do
  [[ -n "$sha" ]] || continue
  HISTORY_COUNT=$((HISTORY_COUNT + 1))
  content="$SCAN_TMP/added.txt"
  names="$SCAN_TMP/added.files"
  : > "$content"
  : > "$names"
  git -C "$REPO_DIR" show --format= -p --unified=0 --no-color --no-ext-diff --no-textconv \
      -m --first-parent "$sha" 2>/dev/null \
    | awk -v cf="$content" -v ff="$names" '
        /^diff --git / { hdr = 1; file = ""; next }
        hdr && /^\+\+\+ / { f = substr($0, 5); if (f ~ /^b\//) f = substr(f, 3); file = f; hdr = 0; next }
        /^@@/ { hdr = 0; next }
        !hdr && /^\+/ { print substr($0, 2) > cf; print file > ff }
      ' || true
  [[ -s "$content" ]] || continue
  while IFS=$'\t' read -r hfile pname; do
    [[ -n "$pname" ]] || continue
    echo "[FAIL] Secret pattern in branch history: commit ${sha:0:12} file ${hfile} (Pattern: ${pname})" >&2
    SECRET_HITS=$((SECRET_HITS + 1))
  done < <(
    secret_hits "$content" | while IFS=$'\t' read -r lnum pname; do
      printf '%s\t%s\n' "$(sed -n "${lnum}p" "$names")" "$pname"
    done | sort -u
  )
done <<< "$HISTORY_COMMITS"
echo "[INFO] History scan covered ${HISTORY_COUNT} commit(s) in ${HISTORY_RANGE}"

if [[ "$SECRET_HITS" -gt 0 ]]; then
  echo "[FAIL] Secret scan detected ${SECRET_HITS} potential credential leak(s)!" >&2
  echo "[INFO] Strip all credentials, rotate any exposed secret, and rewrite the branch history (deleting the line in a later commit is NOT enough)." >&2
  ERRORS=$((ERRORS + 1))
else
  echo "[PASS] Secret hygiene clean: no credential patterns in changed files or branch history."
fi

# -----------------------------------------------------------------------------
# Gate 5: QA Approval Check (verdict bound to <branch>@<sha>)
# -----------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "[QA] Checking for a QA verdict bound to '${CURRENT_BRANCH}' at HEAD..."

HEAD_SHA="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")"

qa_missing() {
  # $1 = reason. FAIL unless --allow-external-qa was given explicitly.
  if [[ "$ALLOW_EXTERNAL_QA" == true ]]; then
    echo "[WARN] $1"
    echo "[WARN] --allow-external-qa given: QA sign-off is assumed to live on an external board / PR review. Confirm it covers ${CURRENT_BRANCH}@${HEAD_SHA:0:12} before merge."
  else
    echo "[FAIL] $1" >&2
    echo "       QA must append: QA APPROVE ${CURRENT_BRANCH}@${HEAD_SHA:0:12} (via bus_append.sh), or pass --allow-external-qa if sign-off lives elsewhere." >&2
    ERRORS=$((ERRORS + 1))
  fi
}

TARGET_QA_FILE=""
QA_FILE_ERROR=false
if [[ -n "$QA_FILE" ]]; then
  if [[ -f "$QA_FILE" ]]; then
    TARGET_QA_FILE="$QA_FILE"
  elif [[ -f "$REPO_DIR/$QA_FILE" ]]; then
    TARGET_QA_FILE="$REPO_DIR/$QA_FILE"
  else
    echo "[FAIL] Specified QA file does not exist: $QA_FILE" >&2
    ERRORS=$((ERRORS + 1))
    QA_FILE_ERROR=true
  fi
elif [[ -f "$REPO_DIR/QA_BUS.md" ]]; then
  TARGET_QA_FILE="$REPO_DIR/QA_BUS.md"
elif [[ -f "$REPO_DIR/AGENT_BUS.md" ]]; then
  TARGET_QA_FILE="$REPO_DIR/AGENT_BUS.md"
fi

VERDICT_RE='^###[[:space:]]+\[[^]]*\][[:space:]]+([^>|]+)[[:space:]]+->[^|]*\|[[:space:]]*QA[[:space:]]+(APPROVE|HOLD)[[:space:]]+([^[:space:]]+)@([0-9a-fA-F]{7,40})([[:space:]]|$)'
LEGACY_RE='^###[[:space:]].*\|[[:space:]]*(QA[[:space:]]+)?(APPROVE|APPROVED|HOLD)([[:space:]]|$)'

if [[ "$QA_FILE_ERROR" == true ]]; then
  :
elif [[ -z "$TARGET_QA_FILE" ]]; then
  qa_missing "No QA ledger found (no --qa-file, QA_BUS.md or AGENT_BUS.md)."
else
  QA_BASENAME="$(basename "$TARGET_QA_FILE")"
  LAST_KIND=""
  LAST_SHA=""
  LAST_LINE=""
  LAST_AUTHOR=""
  IGNORED_NON_QA=0
  LEGACY_COUNT=0
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ "$line" == "###"* ]] || continue
    if [[ "$line" =~ $VERDICT_RE ]]; then
      author="${BASH_REMATCH[1]}"
      author="${author%"${author##*[![:space:]]}"}"
      kind="${BASH_REMATCH[2]}"
      vbranch="${BASH_REMATCH[3]}"
      vsha="${BASH_REMATCH[4]}"
      [[ "$vbranch" == "$CURRENT_BRANCH" ]] || continue
      if [[ "${author,,}" != *qa* ]]; then
        IGNORED_NON_QA=$((IGNORED_NON_QA + 1))
        echo "[WARN] Ignoring ${QA_BASENAME}:${lineno}: verdict author '${author}' is not a QA role (must contain 'qa')."
        continue
      fi
      LAST_KIND="$kind"
      LAST_SHA="${vsha,,}"
      LAST_LINE="$lineno"
      LAST_AUTHOR="$author"
    elif [[ "$line" =~ $LEGACY_RE ]]; then
      LEGACY_COUNT=$((LEGACY_COUNT + 1))
    fi
  done < "$TARGET_QA_FILE"

  if [[ "$LEGACY_COUNT" -gt 0 ]]; then
    echo "[INFO] ${LEGACY_COUNT} legacy verdict line(s) without <branch>@<sha> in ${QA_BASENAME} were ignored."
  fi

  if [[ -z "$LAST_KIND" ]]; then
    qa_missing "No QA verdict bound to branch '${CURRENT_BRANCH}' found in ${QA_BASENAME}."
  elif [[ "$LAST_KIND" == "HOLD" ]]; then
    echo "[FAIL] Latest QA verdict for '${CURRENT_BRANCH}' (${QA_BASENAME}:${LAST_LINE}, by ${LAST_AUTHOR}) is HOLD @${LAST_SHA}." >&2
    echo "       Merge blocked until defects are resolved and QA emits a new APPROVE for HEAD." >&2
    ERRORS=$((ERRORS + 1))
  elif [[ -n "$HEAD_SHA" && "$HEAD_SHA" == "$LAST_SHA"* ]]; then
    echo "[PASS] QA APPROVE for ${CURRENT_BRANCH}@${LAST_SHA} matches HEAD (${QA_BASENAME}:${LAST_LINE}, by ${LAST_AUTHOR})."
  else
    if git -C "$REPO_DIR" merge-base --is-ancestor "$LAST_SHA" HEAD >/dev/null 2>&1; then
      NEW_COMMITS="$(git -C "$REPO_DIR" rev-list --count "${LAST_SHA}..HEAD" 2>/dev/null || echo "?")"
      echo "[FAIL] QA APPROVE (${QA_BASENAME}:${LAST_LINE}) covers ${CURRENT_BRANCH}@${LAST_SHA}, but HEAD is ${HEAD_SHA:0:12} (${NEW_COMMITS} newer commit(s)): re-review needed for new commits." >&2
    else
      echo "[FAIL] QA APPROVE (${QA_BASENAME}:${LAST_LINE}) covers ${CURRENT_BRANCH}@${LAST_SHA}, which is not an ancestor of HEAD ${HEAD_SHA:0:12} (history rewritten?): re-review needed for new commits." >&2
    fi
    ERRORS=$((ERRORS + 1))
  fi
fi

# -----------------------------------------------------------------------------
# Summary and Final Verdict
# -----------------------------------------------------------------------------
echo "================================================================="
if [[ "$ERRORS" -eq 0 ]]; then
  echo "[ALL CHECKS PASSED] Branch '${CURRENT_BRANCH}' is verified and ready for merge."
  echo "================================================================="
  exit 0
else
  echo "[VERIFICATION FAILED] ${ERRORS} check(s) failed. Fix issues before merge." >&2
  echo "================================================================="
  exit 1
fi
