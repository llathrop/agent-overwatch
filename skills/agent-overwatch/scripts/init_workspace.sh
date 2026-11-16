#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch — Workspace Initializer
# Usage: init_workspace.sh [TARGET_DIR] [--subdir] [--no-bus] [--force] [--dry-run] [--help]
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configurations
TARGET_DIR=""
IS_SUBDIR=false
NO_BUS=false
FORCE=false
DRY_RUN=false

show_help() {
  cat <<'EOF'
Agent Overwatch — Workspace Initializer

Usage:
  init_workspace.sh [TARGET_DIR] [OPTIONS]

Arguments:
  TARGET_DIR       Target directory to initialize (default: current directory ".")

Options:
  --subdir         Initialize as a child/subproject workspace.
                   Uses child subproject handoff format linking back to the parent
                   HANDOFF.md, and prints a reminder to update the parent index.
  --no-bus         Skip scaffolding AGENT_BUS.md (used when native agent messaging,
                   e.g., a swarm or host message board, supersedes file-bus).
  --force          Overwrite existing files if they already exist (default: skip safely).
  --dry-run        Print planned actions safely without creating or modifying any files.
  -h, --help       Show this help message and exit.

Creates (skipping existing files unless --force):
  HANDOFF.md, AGENT_BUS.md (unless --no-bus), status/, .overwatch/secret-allowlist,
  and an AGENT_BUS.md entry in .gitignore (added if missing; the bus is local,
  never committed). status/coordinator.lease is NOT pre-created; use coordinator_lease.sh.

Examples:
  init_workspace.sh
  init_workspace.sh ./my-new-project
  init_workspace.sh ./services/auth --subdir
  init_workspace.sh --no-bus --dry-run
  init_workspace.sh ./backend --subdir --no-bus --force
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --subdir)
      IS_SUBDIR=true
      shift
      ;;
    --no-bus)
      NO_BUS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
      else
        echo "[ERROR] Unexpected argument: $1" >&2
        echo "Run '$0 --help' for usage." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-.}"

# Resolve target directory path
if [[ "$DRY_RUN" == true ]]; then
  # Avoid creating dir in dry-run if not existing
  if [[ "$TARGET_DIR" = /* ]]; then
    TARGET_ABS="$TARGET_DIR"
  elif [[ -d "$TARGET_DIR" ]]; then
    TARGET_ABS="$(cd "$TARGET_DIR" && pwd)"
  else
    TARGET_ABS="$(pwd)/$TARGET_DIR"
  fi
else
  mkdir -p "$TARGET_DIR"
  TARGET_ABS="$(cd "$TARGET_DIR" && pwd)"
fi

PROJECT_NAME="$(basename "$TARGET_ABS")"

# -----------------------------------------------------------------------------
# Template Discovery with Resilient Fallbacks
# -----------------------------------------------------------------------------
find_template() {
  local template_name="$1"
  local candidate_dirs=(
    "$SCRIPT_DIR/../templates"
    "$SCRIPT_DIR/../../templates"
    "$SCRIPT_DIR/../../../templates"
  )

  for dir in "${candidate_dirs[@]}"; do
    if [[ -f "$dir/$template_name" ]]; then
      echo "$dir/$template_name"
      return 0
    fi
  done
  return 1
}

# Minimal built-in fallback templates if copied standalone
get_fallback_handoff() {
  cat <<'EOF'
# HANDOFF — {{PROJECT_NAME}}

> **Size caps:** keep each cell/bullet ≤ 200 chars; push detail to AGENT_BUS.md; whole file ≤ ~150 lines.

## Coordinator
- **Lease file:** `status/coordinator.lease`; check with `coordinator_lease.sh status` (0 = mine, 3 = another live holder, 4 = expired/none).
- **Takeover rule:** only `coordinator_lease.sh claim --takeover` (posts a TAKEOVER bus entry) when the holder is known to be gone.

## 1. Purpose & Architecture
{{PROJECT_PURPOSE}}

- **Repository Root:** `{{PROJECT_ROOT}}`
- **Active Branch:** `{{ACTIVE_BRANCH}}`

## 2. Current State
- **Active Branch:** `{{ACTIVE_BRANCH}}`
- **Completed:** Workspace initialized with `agent-overwatch`.
- **In Progress:** Step 1 planning and roadmap breakdown.
- **Blockers / Holds:** None.

## 3. Planned Atomic Roadmap
1. **Step 1 (`feat/<topic-1>`):** <Scope description and atomic deliverables> — merge after QA APPROVE.
2. **Step 2 (`feat/<topic-2>`):** <Scope description and atomic deliverables> — merge after QA APPROVE.
3. **Step 3 (`feat/<topic-3>`):** <Scope description and atomic deliverables> — merge after QA APPROVE.

## 4. Repo Conventions & Coordination Rules
- **Never Commit Secrets:** `.gitignore` blocks `.env*`, credentials, tokens, and keys.
- **Atomic Branches + QA Gate:** Short-lived branches, read-only QA review, binary APPROVE/HOLD verdict.
- **Inter-Agent Coordination:** Native messaging tool or atomic append to `AGENT_BUS.md`.
- **Subprojects:** Child subprojects maintain their own `<subdir>/HANDOFF.md` linked back to this root.
EOF
}

get_fallback_subdir_handoff() {
  cat <<'EOF'
# SUBPROJECT HANDOFF — {{SUBDIR_NAME}}

> **Parent Workspace:** [Parent HANDOFF]({{PARENT_HANDOFF_PATH}})
> **Coordinator Action Required:** Ensure this child subproject is indexed in parent `HANDOFF.md` under Section 2 (Active Subprojects) and Section 3 (Roadmap)!
>
> **Size caps:** keep each cell/bullet ≤ 200 chars; push detail to AGENT_BUS.md; whole file ≤ ~150 lines.

## Coordinator
- **Lease:** the root `status/coordinator.lease` governs this subproject; check with `coordinator_lease.sh status --file <lease-path>`.
- **Takeover rule:** only `coordinator_lease.sh claim --takeover` (posts a TAKEOVER bus entry) when the holder is known to be gone.

## 1. Subproject Purpose & Scope
{{SUBDIR_PURPOSE}}

- **Subproject Directory:** `{{SUBDIR_PATH}}`
- **Parent Workspace Root:** `{{PARENT_HANDOFF_PATH}}`

## 2. Current State
- **Active Branch / Worktree:** `{{ACTIVE_BRANCH}}`
- **Completed:** Subproject workspace initialized.
- **In Progress:** Local planning and isolated implementation.
- **Blockers / Holds:** None.

## 3. Subproject Roadmap & Dependencies
1. **Sub-task 1 (`feat/<sub-topic-1>`):** <Scope description> — QA gated.
2. **Sub-task 2 (`feat/<sub-topic-2>`):** <Scope description> — QA gated.
- **Shared Dependencies & Interfaces:** <APIs, shared libs, or data schemas shared with parent or sibling services>

## 4. Subproject Local Conventions
- **Scope Discipline:** All edits must remain strictly within `{{SUBDIR_PATH}}`.
- **Coordination:** Local updates are logged here. Update parent `HANDOFF.md` only when cross-cutting interfaces, shared dependencies, or milestone releases change.
- **QA Verification:** Child increments require independent `qa-agent` approval prior to merge.
EOF
}

get_fallback_agent_bus() {
  cat <<'EOF'
# AGENT_BUS — Inter-Agent Coordination Log

> **Supersession Rule:** When your runtime provides a built-in message board or native agent-to-agent messaging tool (for example a swarm message board, a `send_message` tool, or agent teams), use that native channel for live coordination. Use `AGENT_BUS.md` when no native board exists or when a local file-based log is needed. This file is git-ignored local coordination, not committed; use HANDOFF.md for tracked cross-machine handoff.
>
> **Append-Only Discipline:** Read the tail before writing, then append with `scripts/bus_append.sh` (for example `echo '- body' | bus_append.sh --from dev-1 --to qa-1 --type RESULT --subject 'feat/x ready' --ref auto`). It stamps the UTC time, appends atomically and refuses bodies that match secret patterns. Only when that script is unavailable, fall back to a quoted heredoc (`cat <<'EOF' >> AGENT_BUS.md`), so parallel agents never clobber concurrent entries.
>
> **Secret Hygiene:** Never write tokens, passwords, private keys, API keys, PII, or credential strings into `AGENT_BUS.md` (or any file).

## Entry Format

```markdown
### [YYYY-MM-DD HH:MM:SS UTC] <from> -> <to> | <TYPE> <short subject>
- Concise scope, file paths, verification output, or blocker.
```

Standard `<TYPE>` tags: `TAKEOVER`, `BRIEF`, `ACTION`, `RESULT`, `CONCERN`, `QA APPROVE`, `QA HOLD`, `STATUS`.

---
EOF
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
find_parent_handoff() {
  local current_dir="$1"
  local check_dir
  check_dir="$(cd "$current_dir/.." 2>/dev/null && pwd || echo "")"

  while [[ -n "$check_dir" && "$check_dir" != "/" ]]; do
    if [[ -f "$check_dir/HANDOFF.md" ]]; then
      # Compute relative path from current_dir to parent HANDOFF.md
      if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os.path, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$check_dir/HANDOFF.md" "$current_dir"
      else
        echo "../HANDOFF.md"
      fi
      return 0
    fi
    local next_dir
    next_dir="$(cd "$check_dir/.." 2>/dev/null && pwd || echo "")"
    if [[ "$next_dir" == "$check_dir" ]]; then
      break
    fi
    check_dir="$next_dir"
  done

  echo "../HANDOFF.md"
  return 0
}

write_file_safe() {
  local target_file="$1"
  local content="$2"
  local label="$3"

  if [[ -f "$target_file" && "$FORCE" != true ]]; then
    echo "[SKIP] ${target_file} already exists (use --force to overwrite)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would write ${label}: ${target_file}"
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "$target_file")"
  mkdir -p "$parent_dir"
  printf '%s\n' "$content" > "$target_file"
  echo "[OK] Scaffolding ${label}: ${target_file}"
}

create_dir_safe() {
  local dir_path="$1"
  local label="$2"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would create directory for ${label}: ${dir_path}"
    return 0
  fi

  if [[ ! -d "$dir_path" ]]; then
    mkdir -p "$dir_path"
    echo "[OK] Created directory for ${label}: ${dir_path}"
  fi
}

# -----------------------------------------------------------------------------
# Main Execution Logic
# -----------------------------------------------------------------------------

echo "================================================================="
echo "Agent Overwatch — Initializing Workspace"
echo "  Target:   ${TARGET_ABS}"
echo "  Mode:     $([ "$IS_SUBDIR" = true ] && echo "Child Subproject (--subdir)" || echo "Root Workspace")"
echo "  Bus:      $([ "$NO_BUS" = true ] && echo "Skipped (--no-bus)" || echo "AGENT_BUS.md")"
echo "  Dry Run:  ${DRY_RUN}"
echo "  Force:    ${FORCE}"
echo "================================================================="

# Detect active branch if git is present
ACTIVE_BRANCH="main"
if git -C "$TARGET_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ACTIVE_BRANCH="$(git -C "$TARGET_ABS" symbolic-ref --short HEAD 2>/dev/null || git -C "$TARGET_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
fi

# 1. Scaffolding HANDOFF
if [[ "$IS_SUBDIR" == true ]]; then
  PARENT_HANDOFF_REL="$(find_parent_handoff "$TARGET_ABS")"
  SUBDIR_NAME="$PROJECT_NAME"
  SUBDIR_PURPOSE="Dedicated subproject service and isolated execution domain for ${SUBDIR_NAME}."
  SUBDIR_PATH="${TARGET_DIR}"

  TEMPLATE_FILE="$(find_template "SUBDIR_HANDOFF.template.md" || true)"
  if [[ -n "$TEMPLATE_FILE" && -f "$TEMPLATE_FILE" ]]; then
    HANDOFF_CONTENT="$(cat "$TEMPLATE_FILE")"
  else
    HANDOFF_CONTENT="$(get_fallback_subdir_handoff)"
  fi

  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{SUBDIR_NAME\}\}/$SUBDIR_NAME}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{SUBDIR_PURPOSE\}\}/$SUBDIR_PURPOSE}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{SUBDIR_PATH\}\}/$SUBDIR_PATH}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{PARENT_HANDOFF_PATH\}\}/$PARENT_HANDOFF_REL}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{ACTIVE_BRANCH\}\}/$ACTIVE_BRANCH}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//<SUBDIR_NAME>/$SUBDIR_NAME}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//<SUBDIR_PATH>/$SUBDIR_PATH}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//<branch-name>/$ACTIVE_BRANCH}"

  write_file_safe "$TARGET_ABS/HANDOFF.md" "$HANDOFF_CONTENT" "Subproject HANDOFF.md"
  
  # Also scaffold SUBDIR_HANDOFF.md as a mirror or secondary pointer if requested
  write_file_safe "$TARGET_ABS/SUBDIR_HANDOFF.md" "$HANDOFF_CONTENT" "Subproject SUBDIR_HANDOFF.md"

  echo ""
  echo "-----------------------------------------------------------------"
  echo "[NOTE] SUBPROJECT SCAFFOLDED: ${TARGET_ABS}"
  echo "  Parent index link: ${PARENT_HANDOFF_REL}"
  echo "  Action Required: Update parent HANDOFF.md to add this subproject"
  echo "  under Section 2 (Active Subprojects) and Section 3 (Roadmap)!"
  echo "-----------------------------------------------------------------"
  echo ""
else
  PROJECT_PURPOSE="Production-grade repository managed under Agent Overwatch multi-agent orchestration."
  FRAMEWORKS="Standard language toolchain and automated verification suites."

  TEMPLATE_FILE="$(find_template "HANDOFF.template.md" || true)"
  if [[ -n "$TEMPLATE_FILE" && -f "$TEMPLATE_FILE" ]]; then
    HANDOFF_CONTENT="$(cat "$TEMPLATE_FILE")"
  else
    HANDOFF_CONTENT="$(get_fallback_handoff)"
  fi

  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{PROJECT_NAME\}\}/$PROJECT_NAME}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{PROJECT_PURPOSE\}\}/$PROJECT_PURPOSE}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{PROJECT_ROOT\}\}/$TARGET_ABS}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{ACTIVE_BRANCH\}\}/$ACTIVE_BRANCH}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//\{\{FRAMEWORKS\}\}/$FRAMEWORKS}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//<PROJECT_NAME>/$PROJECT_NAME}"
  HANDOFF_CONTENT="${HANDOFF_CONTENT//<branch-name>/$ACTIVE_BRANCH}"

  write_file_safe "$TARGET_ABS/HANDOFF.md" "$HANDOFF_CONTENT" "Root HANDOFF.md"
fi

# 2. Scaffolding AGENT_BUS (unless --no-bus)
if [[ "$NO_BUS" == true ]]; then
  echo "[INFO] Skipping AGENT_BUS.md (--no-bus specified; host runtime messaging board active)"
else
  TEMPLATE_BUS="$(find_template "AGENT_BUS.template.md" || true)"
  if [[ -n "$TEMPLATE_BUS" && -f "$TEMPLATE_BUS" ]]; then
    BUS_CONTENT="$(cat "$TEMPLATE_BUS")"
  else
    BUS_CONTENT="$(get_fallback_agent_bus)"
  fi
  write_file_safe "$TARGET_ABS/AGENT_BUS.md" "$BUS_CONTENT" "Inter-Agent Coordination Bus (AGENT_BUS.md)"
fi

# 3. Scaffolding status/ directory
create_dir_safe "$TARGET_ABS/status" "Status snapshots directory"
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would create file: $TARGET_ABS/status/.gitkeep"
else
  if [[ ! -f "$TARGET_ABS/status/.gitkeep" ]]; then
    touch "$TARGET_ABS/status/.gitkeep"
    echo "[OK] Created $TARGET_ABS/status/.gitkeep"
  fi
fi

# Scaffolding status/README.md for quick agent reference
read -r -d '' STATUS_README <<'STATUS_EOF' || true
# Agent Status Directory

Each participating agent may periodically write a single snapshot file here
representing its current task, progress, and verification status:

- `status/qa-agent.md`
- `status/dev-agent.md`
- `status/deploy-agent.md`
- `status/research-agent.md`

> **Discipline Rule:** Each agent updates **only its own status file**. Never overwrite a peer agent's snapshot.
STATUS_EOF
write_file_safe "$TARGET_ABS/status/README.md" "$STATUS_README" "Status Directory README"

# 4. .gitignore: the bus is local coordination and must not be tracked.
#    Existing files keep their content; only the missing line is appended.
#    HANDOFF.md stays tracked for cross-machine handoff.
GITIGNORE_FILE="$TARGET_ABS/.gitignore"
if [[ "$NO_BUS" == true ]]; then
  :
elif [[ -f "$GITIGNORE_FILE" ]] && grep -qxF "AGENT_BUS.md" "$GITIGNORE_FILE"; then
  echo "[SKIP] ${GITIGNORE_FILE} already ignores AGENT_BUS.md"
elif [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would add 'AGENT_BUS.md' to ${GITIGNORE_FILE}"
else
  if [[ -s "$GITIGNORE_FILE" && -n "$(tail -c 1 "$GITIGNORE_FILE")" ]]; then
    printf '\n' >> "$GITIGNORE_FILE"
  fi
  printf '%s\n' "AGENT_BUS.md" >> "$GITIGNORE_FILE"
  echo "[OK] Added 'AGENT_BUS.md' to ${GITIGNORE_FILE}"
fi
if [[ "$NO_BUS" != true ]]; then
  echo "[NOTE] AGENT_BUS.md is local coordination (git-ignored, not committed). Use the tracked HANDOFF.md for cross-machine handoff."
fi

# 5. .overwatch/secret-allowlist for overwatch_watch.sh
read -r -d '' ALLOWLIST_CONTENT <<'ALLOW_EOF' || true
# Secret-scan allowlist for overwatch_watch.sh (one POSIX ERE per line).
# Lines starting with '#' and blank lines are ignored.
# Each pattern is tested against the matched text and, for key=value hits,
# against the value alone. Anchor patterns so they stay narrow.
# This file holds patterns only. Never paste a real secret here.
#
# Git commit SHAs (full or abbreviated):
# ^[0-9a-f]{40}$
# ^[0-9a-f]{7,12}$
#
# UUIDs:
# ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$
#
# 32-hex account / tenant IDs that are not credentials:
# ^[0-9a-f]{32}$
ALLOW_EOF
write_file_safe "$TARGET_ABS/.overwatch/secret-allowlist" "$ALLOWLIST_CONTENT" "Secret-scan allowlist (.overwatch/secret-allowlist)"

# 6. Coordinator lease: never pre-create a placeholder that could look held.
LEASE_SCRIPT="$SCRIPT_DIR/coordinator_lease.sh"
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would report coordinator lease status (status/coordinator.lease is not pre-created)"
elif [[ -f "$LEASE_SCRIPT" ]]; then
  echo "[INFO] Coordinator lease status:"
  # A subproject is governed by the root lease (see SUBDIR_HANDOFF.template.md).
  LEASE_ROOT="$TARGET_ABS"
  if [[ "$IS_SUBDIR" == true ]]; then
    LEASE_ROOT="$(cd "$TARGET_ABS/$(dirname "$PARENT_HANDOFF_REL")" 2>/dev/null && pwd || echo "$TARGET_ABS")"
  fi
  LEASE_PATH="$LEASE_ROOT/status/coordinator.lease"
  bash "$LEASE_SCRIPT" status --id "init_workspace" --file "$LEASE_PATH" 2>&1 | sed 's/^/         /' || true
  echo "[HINT] Claim it with: $LEASE_SCRIPT claim --file $LEASE_PATH (set AO_COORDINATOR_ID for a stable id)"
fi

# 7. Hints for local runtime files
echo "[HINT] Add '.overwatch/watch.state' (watcher offset state) to .gitignore; commit .overwatch/secret-allowlist."
if git -C "$TARGET_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && git -C "$TARGET_ABS" check-ignore -q .overwatch/secret-allowlist 2>/dev/null; then
  echo "[HINT] .overwatch/secret-allowlist is git-ignored (e.g. by a '*secret*' rule); add '!.overwatch/secret-allowlist' to .gitignore to share it."
fi

echo "================================================================="
echo "[SUCCESS] Workspace initialization complete in ${TARGET_ABS}"
echo "================================================================="
