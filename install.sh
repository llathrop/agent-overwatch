#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch — Multi-Tool Installer
# Installs Agent Overwatch skills, agents, commands, and templates across
# Antigravity, Claude Code, Codex, Gemini CLI, Cursor, and GitHub.
# -----------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target selection
INSTALL_ANTIGRAVITY=false
INSTALL_CLAUDE=false
INSTALL_CODEX=false
INSTALL_GEMINI=false
INSTALL_CURSOR=false
INSTALL_GITHUB=false
INSTALL_ALL=false

# Scope selection
IS_GLOBAL=false
WORKSPACE_DIR=""

# Execution modifiers
DRY_RUN=false
FORCE=false

show_help() {
  cat <<'EOF'
Agent Overwatch — Multi-Tool Installer

Usage:
  install.sh [TARGETS] [SCOPE] [OPTIONS]

Targets:
  --antigravity       Install Agent Overwatch for Antigravity:
                      - Global: as an Antigravity plugin at ~/.gemini/config/plugins/agent-overwatch/
                      - Workspace: into <workspace>/.agents/skills/ & .agents/agents/
  --claude            Install for Claude Code:
                      - Global: ~/.claude/skills/ & ~/.claude/agents/ & update ~/.claude/CLAUDE.md
                      - Workspace: <workspace>/.claude/skills/ & agents & update CLAUDE.md
  --codex             Install for Codex:
                      - Global: ~/.codex/skills/ & update ~/.codex/AGENTS.md
                      - Workspace: <workspace>/.codex/skills/ & update AGENTS.md
  --gemini            Install for Gemini CLI:
                      - Global: ~/.gemini/commands/ & update ~/.gemini/GEMINI.md
                      - Workspace: <workspace>/.gemini/commands/ & update GEMINI.md
  --cursor            Install for Cursor IDE:
                      - Workspace only: <workspace>/.cursor/rules/agent-overwatch.mdc
  --github            Install GitHub templates:
                      - Workspace only: .github/ISSUE_TEMPLATE/atomic_task.md and PULL_REQUEST_TEMPLATE.md
  --all               Install for all applicable tools in the selected scope

Scope (Mutually Exclusive):
  --global            Install globally into user home directory (~/.gemini, ~/.claude, ~/.codex)
  --workspace <DIR>   Install locally into the specified workspace (default: current directory ".")

Options:
  --dry-run           Print planned directory creations and file installs without writing to disk
  --force             Overwrite existing files (default: skip existing files safely)
  -h, --help          Show this help message and exit

Examples:
  ./install.sh --all --workspace .
  ./install.sh --antigravity --global
  ./install.sh --claude --workspace /path/to/my-project
  ./install.sh --all --dry-run
  ./install.sh --gemini --codex --global --force
EOF
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --antigravity)
      INSTALL_ANTIGRAVITY=true
      shift
      ;;
    --claude)
      INSTALL_CLAUDE=true
      shift
      ;;
    --codex)
      INSTALL_CODEX=true
      shift
      ;;
    --gemini)
      INSTALL_GEMINI=true
      shift
      ;;
    --cursor)
      INSTALL_CURSOR=true
      shift
      ;;
    --github)
      INSTALL_GITHUB=true
      shift
      ;;
    --all)
      INSTALL_ALL=true
      shift
      ;;
    --global)
      IS_GLOBAL=true
      shift
      ;;
    --workspace)
      WORKSPACE_DIR="${2:-}"
      if [[ -z "$WORKSPACE_DIR" || "$WORKSPACE_DIR" =~ ^-- ]]; then
        echo "[ERROR] --workspace requires a valid directory argument." >&2
        exit 1
      fi
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
    *)
      # If positional argument and WORKSPACE_DIR is unset, assume it's the workspace directory
      if [[ -z "$WORKSPACE_DIR" && "$IS_GLOBAL" == false ]]; then
        WORKSPACE_DIR="$1"
      else
        echo "[ERROR] Unexpected argument: $1" >&2
        echo "Run '$0 --help' for usage." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate scope
if [[ "$IS_GLOBAL" == true && -n "$WORKSPACE_DIR" ]]; then
  echo "[ERROR] Cannot specify both --global and --workspace simultaneously. Please choose one scope." >&2
  exit 1
fi

if [[ "$IS_GLOBAL" == false && -z "$WORKSPACE_DIR" ]]; then
  WORKSPACE_DIR="."
fi

# Resolve workspace directory if applicable
WORKSPACE_ABS=""
if [[ "$IS_GLOBAL" == false ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$WORKSPACE_DIR" = /* ]]; then
      WORKSPACE_ABS="$WORKSPACE_DIR"
    elif [[ -d "$WORKSPACE_DIR" ]]; then
      WORKSPACE_ABS="$(cd "$WORKSPACE_DIR" && pwd)"
    else
      WORKSPACE_ABS="$(pwd)/$WORKSPACE_DIR"
    fi
  else
    mkdir -p "$WORKSPACE_DIR"
    WORKSPACE_ABS="$(cd "$WORKSPACE_DIR" && pwd)"
  fi
fi

# Handle --all selection
if [[ "$INSTALL_ALL" == true ]]; then
  INSTALL_ANTIGRAVITY=true
  INSTALL_CLAUDE=true
  INSTALL_CODEX=true
  INSTALL_GEMINI=true
  if [[ "$IS_GLOBAL" == false ]]; then
    INSTALL_CURSOR=true
    INSTALL_GITHUB=true
  fi
fi

# Ensure at least one target is chosen
if [[ "$INSTALL_ANTIGRAVITY" == false && \
      "$INSTALL_CLAUDE" == false && \
      "$INSTALL_CODEX" == false && \
      "$INSTALL_GEMINI" == false && \
      "$INSTALL_CURSOR" == false && \
      "$INSTALL_GITHUB" == false ]]; then
  echo "[ERROR] No target selected. Specify one or more tool flags (--antigravity, --claude, etc.) or --all." >&2
  echo "Run '$0 --help' for usage." >&2
  exit 1
fi

echo "================================================================="
echo "Agent Overwatch — Multi-Tool Installer"
echo "  Repo Root:   ${REPO_ROOT}"
echo "  Scope:       $([ "$IS_GLOBAL" = true ] && echo "Global (~/)" || echo "Workspace (${WORKSPACE_ABS})")"
echo "  Dry Run:     ${DRY_RUN}"
echo "  Force:       ${FORCE}"
echo "  Targets:"
[[ "$INSTALL_ANTIGRAVITY" == true ]] && echo "   - Antigravity"
[[ "$INSTALL_CLAUDE" == true ]]      && echo "   - Claude Code"
[[ "$INSTALL_CODEX" == true ]]       && echo "   - Codex"
[[ "$INSTALL_GEMINI" == true ]]      && echo "   - Gemini CLI"
[[ "$INSTALL_CURSOR" == true ]]      && echo "   - Cursor"
[[ "$INSTALL_GITHUB" == true ]]      && echo "   - GitHub Templates"
echo "================================================================="

# -----------------------------------------------------------------------------
# Internal Helpers
# -----------------------------------------------------------------------------

safe_mkdir() {
  local target_dir="$1"
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would create directory: ${target_dir}"
    return 0
  fi
  if [[ ! -d "$target_dir" ]]; then
    mkdir -p "$target_dir"
    echo "[OK] Created directory: ${target_dir}"
  fi
}

safe_copy_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ ! -f "$src" ]]; then
    echo "[WARN] Source file missing: ${src}" >&2
    return 1
  fi

  if [[ -f "$dest" && "$FORCE" != true ]]; then
    echo "[SKIP] ${label} already exists: ${dest} (use --force to overwrite)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would copy ${label}: ${src} -> ${dest}"
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "$dest")"
  mkdir -p "$parent_dir"
  cp "$src" "$dest"
  # Preserve executable bit if source is executable
  if [[ -x "$src" ]]; then
    chmod +x "$dest"
  fi
  echo "[OK] Installed ${label}: ${dest}"
}

safe_copy_dir() {
  local src_dir="$1"
  local dest_dir="$2"
  local label="$3"

  if [[ ! -d "$src_dir" ]]; then
    echo "[WARN] Source directory missing: ${src_dir}" >&2
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would sync directory ${label}: ${src_dir} -> ${dest_dir}"
    return 0
  fi

  mkdir -p "$dest_dir"
  # Copy files while respecting FORCE
  while IFS= read -r file; do
    local rel_file="${file#$src_dir/}"
    local target_file="$dest_dir/$rel_file"
    safe_copy_file "$file" "$target_file" "$label ($rel_file)"
  done < <(find "$src_dir" -type f)
}

# Instruction snippet insertion
update_instruction_file() {
  local file_path="$1"
  local tool_name="$2"

  local snippet
  read -r -d '' snippet <<'SNIPPET_EOF' || true
# >>> AGENT-OVERWATCH START >>>
## Agent Overwatch Multi-Agent Orchestration
This workspace adheres to the Agent Overwatch operating model:
- **Roles:** Coordinator, Research (`research-agent`), Dev (`dev-agent`), Deploy (`deploy-agent`), QA (`qa-agent`).
- **QA Gate:** Every plan, atomic branch, and live deployment requires independent read-only `qa-agent` approval (`QA APPROVE`).
- **Atomic Branches:** Use dedicated short-lived branches (`feat/*`, `fix/*`, `docs/*`). Never commit directly to `main` or `master`.
- **Coordination:** Maintain living state in `HANDOFF.md` and chronological audit log in `AGENT_BUS.md` (unless superseded by runtime native board).
- **User Updates:** Deliver clear, self-contained user-facing progress updates as batches/phases finish (what changed and why, technical tradeoffs, QA catches/fixes, test outcomes, and what runs next) without assuming the user reads internal agent messages or `AGENT_BUS.md`.
- **Secret Hygiene:** Never commit tokens, credentials, passwords, or private keys.
# <<< AGENT-OVERWATCH END <<<
SNIPPET_EOF

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would update instruction file for ${tool_name}: ${file_path}"
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "$file_path")"
  mkdir -p "$parent_dir"

  local start_marker="# >>> AGENT-OVERWATCH START >>>"
  local end_marker="# <<< AGENT-OVERWATCH END <<<"

  if [[ ! -f "$file_path" ]]; then
    printf '%s\n' "$snippet" > "$file_path"
    echo "[OK] Created ${tool_name} instruction file: ${file_path}"
    return 0
  fi

  if grep -qF "$start_marker" "$file_path"; then
    if [[ "$FORCE" == true ]]; then
      # Replace existing block safely using sys.argv and stdin (no shell interpolation in Python)
      printf '%s\n' "$snippet" | python3 -c '
import pathlib, re, sys
target = pathlib.Path(sys.argv[1])
start_marker = sys.argv[2]
end_marker = sys.argv[3]
replacement = sys.stdin.read().strip()
content = target.read_text(encoding="utf-8")
pattern = re.compile(re.escape(start_marker) + r".*?" + re.escape(end_marker), re.DOTALL)
new_content = pattern.sub(lambda _: replacement, content, count=1)
target.write_text(new_content, encoding="utf-8")
' "$file_path" "$start_marker" "$end_marker"
      echo "[OK] Replaced Agent Overwatch block in ${file_path} (--force)"
    else
      echo "[SKIP] Agent Overwatch block already present in: ${file_path} (use --force to update)"
    fi
  else
    # Append snippet to existing file
    {
      echo ""
      printf '%s\n' "$snippet"
    } >> "$file_path"
    echo "[OK] Appended Agent Overwatch block to: ${file_path}"
  fi
}

# Portable YAML frontmatter parser & target formatter for Antigravity and Claude Code
install_agent_file() {
  local platform="$1"   # "antigravity" or "claude"
  local src_file="$2"
  local dest_file="$3"

  if [[ ! -f "$src_file" ]]; then
    echo "[WARN] Source subagent file missing: ${src_file}" >&2
    return 1
  fi

  if [[ -f "$dest_file" && "$FORCE" != true ]]; then
    echo "[SKIP] Subagent already exists: ${dest_file} (use --force to overwrite)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would install normalized ${platform} subagent: ${src_file} -> ${dest_file}"
    return 0
  fi

  mkdir -p "$(dirname "$dest_file")"

  python3 -c '
import json, os, pathlib, re, sys

platform, src, dest = sys.argv[1], sys.argv[2], sys.argv[3]
stem = os.path.splitext(os.path.basename(dest))[0]
content = pathlib.Path(src).read_text(encoding="utf-8")

fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", content, re.DOTALL)
meta = {}
body = content
if fm_match:
    fm_text, body = fm_match.group(1), fm_match.group(2)
    cur_key = None
    cur_mode = None
    lines = []
    for raw in fm_text.splitlines():
        if cur_key and (raw.startswith((" ", "\t")) or raw.strip() == ""):
            stripped = raw.strip()
            if cur_mode == "list" and stripped.startswith("- "):
                meta[cur_key].append(stripped[2:].strip().strip("\"\x27"))
            else:
                lines.append(stripped)
                meta[cur_key] = " ".join(x for x in lines if x).strip()
            continue
        cur_key = None
        cur_mode = None
        lines = []
        if ":" in raw and not raw.lstrip().startswith("#"):
            k, v = raw.split(":", 1)
            k, v = k.strip(), v.strip()
            cur_key = k
            if v in (">-", ">", "|", "|-"):
                cur_mode = "scalar"
                meta[k] = ""
            elif v == "":
                cur_mode = "list"
                meta[k] = []
            elif v.startswith("[") and v.endswith("]"):
                meta[k] = [x.strip().strip("\"\x27") for x in v[1:-1].split(",") if x.strip()]
            else:
                meta[k] = v.strip("\"\x27")

name = meta.get("name") or stem
desc = meta.get("description") or f"Agent Overwatch role for {stem}"
tools = meta.get("tools")
if not isinstance(tools, list) or not tools:
    if "qa" in stem or "research" in stem:
        tools = ["read_file", "run_command", "search_web"]
    else:
        tools = ["read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"]

out_lines = ["---", f"name: {name}", f"description: {json.dumps(desc)}"]
if platform == "antigravity":
    out_lines.append("subagent: true")
    out_lines.append("mainAgent: false")
    out_lines.append("tools: [" + ", ".join(tools) + "]")
elif platform == "claude":
    mapping = {
        "read_file": ["Read", "Glob", "Grep"],
        "edit_file": ["Edit", "MultiEdit"],
        "write_file": ["Write"],
        "run_command": ["Bash"],
        "search_web": ["WebSearch", "WebFetch"],
        "manage_task": [],
    }
    mapped = []
    for t in tools:
        for ct in mapping.get(t, [t]):
            if ct not in mapped:
                mapped.append(ct)
    out_lines.append("tools: " + ", ".join(mapped))
else:
    raise SystemExit(f"Unsupported platform: {platform}")

out_lines.append("---")
out = "\n".join(out_lines) + "\n\n" + body.lstrip()
pathlib.Path(dest).write_text(out, encoding="utf-8")
' "$platform" "$src_file" "$dest_file"

  echo "[OK] Installed verified ${platform} subagent: ${dest_file}"
}

# -----------------------------------------------------------------------------
# 1. Antigravity Installation
# -----------------------------------------------------------------------------
if [[ "$INSTALL_ANTIGRAVITY" == true ]]; then
  echo ""
  echo "--- Installing for Antigravity ---"
  SKILL_SRC="$REPO_ROOT/skills/agent-overwatch"
  AGENTS_SRC="$REPO_ROOT/agents"

  if [[ "$IS_GLOBAL" == true ]]; then
    PLUGIN_DIR="$HOME/.gemini/config/plugins/agent-overwatch"
    safe_mkdir "$PLUGIN_DIR"
    
    # plugin.json
    if [[ -f "$REPO_ROOT/plugin.json" ]]; then
      safe_copy_file "$REPO_ROOT/plugin.json" "$PLUGIN_DIR/plugin.json" "Antigravity plugin manifest"
    else
      # Fallback manifest
      if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create default plugin.json: $PLUGIN_DIR/plugin.json"
      elif [[ ! -f "$PLUGIN_DIR/plugin.json" || "$FORCE" == true ]]; then
        cat <<'EOF' > "$PLUGIN_DIR/plugin.json"
{
  "name": "agent-overwatch",
  "displayName": "Agent Overwatch",
  "version": "1.0.0",
  "description": "Multi-agent orchestration framework with parallel execution, mandatory QA gates, and atomic Git branching."
}
EOF
        echo "[OK] Scaffolding default plugin.json: $PLUGIN_DIR/plugin.json"
      fi
    fi

    # skills/agent-overwatch
    safe_copy_dir "$SKILL_SRC" "$PLUGIN_DIR/skills/agent-overwatch" "Antigravity plugin skill"

    # agents
    safe_mkdir "$PLUGIN_DIR/agents"
    for agent in qa-agent dev-agent deploy-agent research-agent; do
      install_agent_file antigravity "$AGENTS_SRC/$agent.md" "$PLUGIN_DIR/agents/$agent.md"
    done
  else
    # Workspace mode: .agents/skills and .agents/agents
    WS_AGENTS_DIR="$WORKSPACE_ABS/.agents"
    safe_mkdir "$WS_AGENTS_DIR"
    safe_copy_dir "$SKILL_SRC" "$WS_AGENTS_DIR/skills/agent-overwatch" "Workspace skill"

    safe_mkdir "$WS_AGENTS_DIR/agents"
    for agent in qa-agent dev-agent deploy-agent research-agent; do
      install_agent_file antigravity "$AGENTS_SRC/$agent.md" "$WS_AGENTS_DIR/agents/$agent.md"
    done
  fi
fi

# -----------------------------------------------------------------------------
# 2. Claude Code Installation
# -----------------------------------------------------------------------------
if [[ "$INSTALL_CLAUDE" == true ]]; then
  echo ""
  echo "--- Installing for Claude Code ---"
  SKILL_SRC="$REPO_ROOT/skills/agent-overwatch"
  AGENTS_SRC="$REPO_ROOT/agents"

  if [[ "$IS_GLOBAL" == true ]]; then
    CLAUDE_DIR="$HOME/.claude"
    safe_mkdir "$CLAUDE_DIR"
    safe_copy_dir "$SKILL_SRC" "$CLAUDE_DIR/skills/agent-overwatch" "Claude global skill"

    safe_mkdir "$CLAUDE_DIR/agents"
    for agent in qa-agent dev-agent deploy-agent research-agent; do
      install_agent_file claude "$AGENTS_SRC/$agent.md" "$CLAUDE_DIR/agents/$agent.md"
    done

    update_instruction_file "$CLAUDE_DIR/CLAUDE.md" "Claude Code (Global)"
  else
    CLAUDE_WS_DIR="$WORKSPACE_ABS/.claude"
    safe_mkdir "$CLAUDE_WS_DIR"
    safe_copy_dir "$SKILL_SRC" "$CLAUDE_WS_DIR/skills/agent-overwatch" "Claude workspace skill"

    safe_mkdir "$CLAUDE_WS_DIR/agents"
    for agent in qa-agent dev-agent deploy-agent research-agent; do
      install_agent_file claude "$AGENTS_SRC/$agent.md" "$CLAUDE_WS_DIR/agents/$agent.md"
    done

    update_instruction_file "$WORKSPACE_ABS/CLAUDE.md" "Claude Code (Workspace)"
  fi
fi

# -----------------------------------------------------------------------------
# 3. Codex Installation
# -----------------------------------------------------------------------------
if [[ "$INSTALL_CODEX" == true ]]; then
  echo ""
  echo "--- Installing for Codex ---"
  SKILL_SRC="$REPO_ROOT/skills/agent-overwatch"

  if [[ "$IS_GLOBAL" == true ]]; then
    CODEX_DIR="$HOME/.codex"
    safe_mkdir "$CODEX_DIR"
    safe_copy_dir "$SKILL_SRC" "$CODEX_DIR/skills/agent-overwatch" "Codex global skill"
    update_instruction_file "$CODEX_DIR/AGENTS.md" "Codex (Global)"
  else
    CODEX_WS_DIR="$WORKSPACE_ABS/.codex"
    safe_mkdir "$CODEX_WS_DIR"
    safe_copy_dir "$SKILL_SRC" "$CODEX_WS_DIR/skills/agent-overwatch" "Codex workspace skill"
    update_instruction_file "$WORKSPACE_ABS/AGENTS.md" "Codex (Workspace)"
  fi
fi

# -----------------------------------------------------------------------------
# 4. Gemini CLI Installation
# -----------------------------------------------------------------------------
if [[ "$INSTALL_GEMINI" == true ]]; then
  echo ""
  echo "--- Installing for Gemini CLI ---"
  GEMINI_CMD_SRC="$REPO_ROOT/examples/gemini-cli/agent-overwatch.toml"

  if [[ "$IS_GLOBAL" == true ]]; then
    GEMINI_CMD_DIR="$HOME/.gemini/commands"
    safe_mkdir "$GEMINI_CMD_DIR"
    safe_copy_file "$GEMINI_CMD_SRC" "$GEMINI_CMD_DIR/agent-overwatch.toml" "Gemini command"
    update_instruction_file "$HOME/.gemini/GEMINI.md" "Gemini CLI (Global)"
  else
    GEMINI_WS_CMD_DIR="$WORKSPACE_ABS/.gemini/commands"
    safe_mkdir "$GEMINI_WS_CMD_DIR"
    safe_copy_file "$GEMINI_CMD_SRC" "$GEMINI_WS_CMD_DIR/agent-overwatch.toml" "Gemini command"
    update_instruction_file "$WORKSPACE_ABS/GEMINI.md" "Gemini CLI (Workspace)"
  fi
fi

# -----------------------------------------------------------------------------
# 5. Cursor Installation (Workspace Only)
# -----------------------------------------------------------------------------
if [[ "$INSTALL_CURSOR" == true ]]; then
  echo ""
  echo "--- Installing for Cursor ---"
  if [[ "$IS_GLOBAL" == true ]]; then
    echo "[INFO] Cursor rules are workspace-scoped (.cursor/rules/*.mdc). Skipping global installation."
  else
    CURSOR_RULE_DIR="$WORKSPACE_ABS/.cursor/rules"
    safe_mkdir "$CURSOR_RULE_DIR"
    CURSOR_SRC="$REPO_ROOT/examples/cursor/agent-overwatch.mdc"
    safe_copy_file "$CURSOR_SRC" "$CURSOR_RULE_DIR/agent-overwatch.mdc" "Cursor MDC rule"
  fi
fi

# -----------------------------------------------------------------------------
# 6. GitHub Templates Installation (Workspace Only)
# -----------------------------------------------------------------------------
if [[ "$INSTALL_GITHUB" == true ]]; then
  echo ""
  echo "--- Installing GitHub Templates ---"
  if [[ "$IS_GLOBAL" == true ]]; then
    echo "[INFO] GitHub issue and PR templates are workspace/repository-scoped (.github/). Skipping global installation."
  else
    GITHUB_ISSUE_DIR="$WORKSPACE_ABS/.github/ISSUE_TEMPLATE"
    safe_mkdir "$GITHUB_ISSUE_DIR"

    ISSUE_SRC="$REPO_ROOT/examples/github/ISSUE_TEMPLATE/atomic_task.md"
    safe_copy_file "$ISSUE_SRC" "$GITHUB_ISSUE_DIR/atomic_task.md" "GitHub Issue Template"

    PR_SRC="$REPO_ROOT/examples/github/PULL_REQUEST_TEMPLATE.md"
    safe_copy_file "$PR_SRC" "$WORKSPACE_ABS/.github/PULL_REQUEST_TEMPLATE.md" "GitHub Pull Request Template"
  fi
fi

echo ""
echo "================================================================="
echo "[SUCCESS] Agent Overwatch installation routine completed."
echo "================================================================="
