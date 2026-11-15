#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch — Pre-Merge Atomic Branch Gate
# Usage: verify_atomic_branch.sh [--repo DIR] [--base main|master] [--qa-file PATH] [--allow-bus-only] [--help]
# -----------------------------------------------------------------------------

REPO_DIR="."
BASE_BRANCH=""
QA_FILE=""
ALLOW_BUS_ONLY=false
MAX_FILES=25
ERRORS=0

show_help() {
  cat <<'EOF'
Agent Overwatch — Pre-Merge Atomic Branch Gate

Verifies that a git branch adheres to atomic branching discipline, has a clean
working tree, contains zero accidental secrets, and carries QA sign-off.

Usage:
  verify_atomic_branch.sh [OPTIONS]

Options:
  --repo DIR            Git repository root directory (default: ".")
  --base BRANCH         Target base branch for comparison (default: auto-detected main or master)
  --qa-file PATH        Path to coordination ledger / audit file to verify for QA approval
  --allow-bus-only      Accept bus log or external runtime message board for QA sign-off
  --max-files N         Threshold for changed files warning on atomic scope (default: 25)
  -h, --help            Show this help message and exit

Exit Codes:
  0: All hard pre-merge gates passed.
  1: Hard failure (on main/master, dirty working tree, secret scan match, or missing required QA).
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --repo)
      REPO_DIR="$2"
      shift 2
      ;;
    --base)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --qa-file)
      QA_FILE="$2"
      shift 2
      ;;
    --allow-bus-only)
      ALLOW_BUS_ONLY=true
      shift
      ;;
    --max-files)
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
if git -C "$REPO_DIR" rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null 2>&1; then
  MERGE_BASE="$(git -C "$REPO_DIR" merge-base HEAD "$BASE_BRANCH" 2>/dev/null || true)"
elif git -C "$REPO_DIR" rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  MERGE_BASE="$(git -C "$REPO_DIR" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null || true)"
fi

if [[ -z "$MERGE_BASE" ]]; then
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
# Gate 4: Secret Scanning on Changed Files
# -----------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "[SCAN] Scanning changed files for accidental secret patterns..."
SECRET_HITS=0

# Determine files to scan
FILES_TO_SCAN=()
if [[ -n "$CHANGED_FILES" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES_TO_SCAN+=("$f")
  done <<< "$CHANGED_FILES"
else
  # If no diff list, scan tracked files
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES_TO_SCAN+=("$f")
  done < <(git -C "$REPO_DIR" ls-files 2>/dev/null || true)
fi

# Patterns to scan with regex: NEVER output matched secret contents!
# Each pattern has a descriptive label
scan_file_for_secrets() {
  local rel_path="$1"
  local abs_path="$REPO_DIR/$rel_path"

  [[ ! -f "$abs_path" ]] && return 0

  # Check if binary file
  if file -b --mime-encoding "$abs_path" 2>/dev/null | grep -q "binary"; then
    return 0
  fi

  # 1. Private Key headers
  local line_match
  line_match="$(grep -n -E 'BEGIN[[:space:]]+([A-Za-z0-9_-]+[[:space:]]+)?PRIVATE KEY' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: Private Key Block)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 2. Tailscale auth keys
  line_match="$(grep -n -E 'tskey-auth-[a-zA-Z0-9_-]+' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: Tailscale Auth Key)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 3. GitHub Personal Access Tokens (classic)
  line_match="$(grep -n -E 'ghp_[a-zA-Z0-9]{20,}' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: GitHub Classic PAT)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 4. GitHub Fine-Grained Personal Access Tokens
  line_match="$(grep -n -E 'github_pat_[a-zA-Z0-9_]{20,}' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: GitHub Fine-Grained PAT)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 5. Standard AI/Cloud API keys (e.g. sk-...)
  line_match="$(grep -n -E 'sk-[a-zA-Z0-9_-]{20,}' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: OpenAI/Anthropic API Key)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 6. AWS Access Key IDs
  line_match="$(grep -n -E 'AKIA[0-9A-Z]{16}' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$line_match" ]]; then
    while IFS=: read -r lnum rest; do
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: AWS Access Key ID)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$line_match"
  fi

  # 7. Hardcoded password assignments with actual values (ignoring placeholders)
  local pw_matches
  pw_matches="$(grep -n -E '(PASSWORD|PASSWD|SECRET_KEY|API_SECRET)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'' ]{8,}["'\'']' "$abs_path" 2>/dev/null || true)"
  if [[ -n "$pw_matches" ]]; then
    while IFS= read -r line; do
      # Ignore common placeholders, documentation tokens, template variables
      if echo "$line" | grep -qiE '(\{\{|\}\}|<.*>|TODO|CHANGEME|example|placeholder|dummy|sample|your_|default|none|null|false|true)'; then
        continue
      fi
      local lnum
      lnum="$(echo "$line" | cut -d: -f1)"
      echo "[FAIL] Secret pattern matched: ${rel_path}:${lnum} (Pattern: Hardcoded Password/Secret Assignment)" >&2
      SECRET_HITS=$((SECRET_HITS + 1))
    done <<< "$pw_matches"
  fi
}

for f in "${FILES_TO_SCAN[@]}"; do
  scan_file_for_secrets "$f"
done

if [[ "$SECRET_HITS" -gt 0 ]]; then
  echo "[FAIL] Secret scan detected ${SECRET_HITS} potential credential leak(s)!" >&2
  echo "[INFO] Strip all credentials, use environment variables or secret vaults, and amend commits." >&2
  ERRORS=$((ERRORS + 1))
else
  echo "[PASS] Secret hygiene clean: no credential patterns detected in changed files."
fi

# -----------------------------------------------------------------------------
# Gate 5: QA Approval Check
# -----------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "[QA] Checking for QA sign-off..."

TARGET_QA_FILE=""
if [[ -n "$QA_FILE" ]]; then
  if [[ -f "$QA_FILE" ]]; then
    TARGET_QA_FILE="$QA_FILE"
  elif [[ -f "$REPO_DIR/$QA_FILE" ]]; then
    TARGET_QA_FILE="$REPO_DIR/$QA_FILE"
  else
    echo "[FAIL] Specified QA file does not exist: $QA_FILE" >&2
    ERRORS=$((ERRORS + 1))
  fi
elif [[ -f "$REPO_DIR/QA_BUS.md" ]]; then
  TARGET_QA_FILE="$REPO_DIR/QA_BUS.md"
elif [[ -f "$REPO_DIR/AGENT_BUS.md" ]]; then
  TARGET_QA_FILE="$REPO_DIR/AGENT_BUS.md"
fi

if [[ -n "$TARGET_QA_FILE" && -f "$TARGET_QA_FILE" ]]; then
  # Inspect the latest actual QA verdict line (ignore legend/placeholder lines; POSIX-ERE portable)
  LATEST_VERDICT_LINE="$(grep -Eni '^(###[[:space:]].*\|[[:space:]]*(QA[[:space:]]+)?(APPROVE|APPROVED|HOLD)([[:space:]]|$)|###[[:space:]].*\[QA[[:space:]]+(APPROVE|APPROVED|HOLD)\]|(Overall Decision|QA VERDICT|Decision):[[:space:]]*(APPROVE|APPROVED|HOLD)([[:space:]]|$))' "$TARGET_QA_FILE" | tail -n 1 || true)"

  if [[ -n "$LATEST_VERDICT_LINE" ]]; then
    LATEST_LINE_NUM="${LATEST_VERDICT_LINE%%:*}"
    LATEST_LINE_TEXT="${LATEST_VERDICT_LINE#*:}"
    if echo "$LATEST_LINE_TEXT" | grep -Eiq '(^|[[:space:]\[])HOLD([[:space:]\]]|$)'; then
      echo "[FAIL] Latest QA verdict in $(basename "$TARGET_QA_FILE"):${LATEST_LINE_NUM} is HOLD: ${LATEST_LINE_TEXT}" >&2
      echo "       Merge blocked until defects are resolved and QA emits APPROVE." >&2
      ERRORS=$((ERRORS + 1))
    else
      echo "[PASS] Latest QA verdict in $(basename "$TARGET_QA_FILE"):${LATEST_LINE_NUM} is APPROVE: ${LATEST_LINE_TEXT}"
      LATER_RESULT_LINE="$(awk -v start="$LATEST_LINE_NUM" 'NR > start && /^###[[:space:]].*\|[[:space:]]*RESULT([[:space:]]|$)/ { print NR ":" $0; exit }' "$TARGET_QA_FILE" || true)"
      if [[ -n "$LATER_RESULT_LINE" ]]; then
        echo "[INFO] Note: newer RESULT entry appears at line ${LATER_RESULT_LINE%%:*} after the latest QA APPROVE; verify this sign-off covers branch '${CURRENT_BRANCH}'."
      fi
    fi
  else
    if [[ "$ALLOW_BUS_ONLY" == true || -z "$QA_FILE" ]]; then
      echo "[WARN] No explicit QA APPROVE/HOLD verdict entry found in $(basename "$TARGET_QA_FILE")."
      echo "[INFO] Verified bus presence. If sign-off was delivered via native runtime board, confirm before merge."
    else
      echo "[FAIL] No QA APPROVE verdict found in $(basename "$TARGET_QA_FILE")." >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  if [[ "$ALLOW_BUS_ONLY" == true ]]; then
    echo "[INFO] No local QA ledger found. External or built-in tool board holds QA sign-off."
  else
    echo "[INFO] No AGENT_BUS.md or QA_BUS.md found in workspace."
    echo "[INFO] Assuming native runtime messaging board or PR review holds QA sign-off."
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
