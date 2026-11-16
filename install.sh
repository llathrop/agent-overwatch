#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Agent Overwatch: multi-tool installer
#
# Installs the agent-overwatch skill, role agents, commands, and templates for
# Antigravity, Claude Code, Codex, Gemini CLI, Cursor, and GitHub.
#
# Modes:   copy (default) | --link (symlinks into this clone; `git pull` updates)
# Actions: install (default) | --uninstall | --build | --check-build
#
# Every file, symlink, directory, and instruction-file block the installer
# creates is recorded in <target>/.agent-overwatch-manifest, where <target> is
# the workspace directory or $HOME (for --global). --uninstall removes only the
# recorded items. --force prunes recorded items that are no longer installed.
# -----------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_NAME="agent-overwatch"
AGENT_ROLES=(qa-agent dev-agent deploy-agent research-agent)
ALL_TARGETS=(antigravity claude codex gemini cursor github)
MANIFEST_NAME=".agent-overwatch-manifest"
DIST_DIR="$REPO_ROOT/dist"

START_MARKER="<!-- >>> agent-overwatch >>> -->"
END_MARKER="<!-- <<< agent-overwatch <<< -->"
# Markers written by earlier installer versions (still recognised for replace/remove).
LEGACY_START="# >>> AGENT-OVERWATCH START >>>"
LEGACY_END="# <<< AGENT-OVERWATCH END <<<"

# Selected targets as a space-delimited list (bash 3.2 has no associative arrays).
WANT=" "
INSTALL_ALL=false
IS_GLOBAL=false
WORKSPACE_DIR=""
DRY_RUN=false
FORCE=false
MODE="copy"
ACTION="install"

show_help() {
  cat <<'EOF'
Agent Overwatch: multi-tool installer

Usage:
  install.sh [TARGETS] (--global | --workspace DIR | DIR) [OPTIONS]
  install.sh --uninstall [TARGETS] (--global | --workspace DIR | DIR) [--dry-run]
  install.sh --build | --check-build

A scope is required: there is no implicit "current directory" default, and the
installer refuses to install into an agent-overwatch checkout itself.

Targets (paths verified against vendor docs; see README.md "Install paths"):
  --antigravity   Global:    ~/.gemini/config/plugins/agent-overwatch/ (plugin.json, skills/, agents/)
                  Workspace: <ws>/.agents/skills/agent-overwatch/ and <ws>/.agents/agents/*.md
  --claude        Global:    ~/.claude/skills/agent-overwatch/, ~/.claude/agents/*.md, ~/.claude/CLAUDE.md
                  Workspace: <ws>/.claude/skills/agent-overwatch/, <ws>/.claude/agents/*.md, <ws>/CLAUDE.md
                  (For Claude Code the native plugin is the better path; see README.md.)
  --codex         Global:    ~/.agents/skills/agent-overwatch/, ~/.codex/agents/*.toml, ~/.codex/AGENTS.md
                  Workspace: <ws>/.agents/skills/agent-overwatch/, <ws>/.codex/agents/*.toml, <ws>/AGENTS.md
  --gemini        Global:    ~/.gemini/commands/agent-overwatch.toml, ~/.gemini/GEMINI.md
                  Workspace: <ws>/.gemini/commands/agent-overwatch.toml, <ws>/GEMINI.md
  --cursor        Workspace only: <ws>/.cursor/rules/agent-overwatch.mdc
  --github        Workspace only: <ws>/.github/ISSUE_TEMPLATE/atomic_task.md, <ws>/.github/PULL_REQUEST_TEMPLATE.md
  --all           Every target that applies to the chosen scope

Scope (exactly one):
  --global            Install into your home directory. Instruction files get a
                      short pointer only, never workspace rules.
  --workspace DIR     Install into project DIR (a bare positional DIR also works).
                      Instruction files get the full workspace rules block.

Options:
  --link              Symlink the skill directory, generated agents, and commands to
                      this clone, so `git pull` updates them. Re-run --build after a
                      pull that changes agents/*.md. Cursor/GitHub files are copied.
  --copy              Copy files (default).
  --force             Overwrite existing files, replace the instruction block, and
                      prune manifest entries this run no longer installs.
  --uninstall         Remove only what the manifest says the installer created, and
                      remove the agent-overwatch block from instruction files.
                      With no target flags, uninstalls every recorded target.
  --build             Regenerate per-platform agents into dist/ from agents/*.md.
  --check-build       Exit 1 if dist/ is out of date with agents/*.md.
  --dry-run           Print planned actions without writing anything.
  -h, --help          Show this help and exit.

Examples:
  ./install.sh --all --workspace /path/to/project --dry-run
  ./install.sh --claude --codex --global --link
  ./install.sh --antigravity /path/to/project
  ./install.sh --uninstall --global
  ./install.sh --build
EOF
}

die() { echo "[ERROR] $*" >&2; exit 1; }

want() { case "$WANT" in *" $1 "*) ;; *) WANT="$WANT$1 " ;; esac; }
is_selected() { case "$WANT" in *" $1 "*) return 0 ;; esac; return 1; }

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --antigravity|--claude|--codex|--gemini|--cursor|--github) want "${1#--}"; shift ;;
    --all) INSTALL_ALL=true; shift ;;
    --global) IS_GLOBAL=true; shift ;;
    --workspace)
      [[ -n "${2:-}" && "${2:-}" != -* ]] || die "--workspace requires a directory argument."
      [[ -z "$WORKSPACE_DIR" ]] || die "Workspace given twice."
      WORKSPACE_DIR="$2"; shift 2 ;;
    --link) MODE="link"; shift ;;
    --copy) MODE="copy"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --build) ACTION="build"; shift ;;
    --check-build) ACTION="check-build"; shift ;;
    -*) die "Unknown option: $1 (run '$0 --help')" ;;
    *)
      [[ -z "$WORKSPACE_DIR" ]] || die "Unexpected argument: $1 (run '$0 --help')"
      WORKSPACE_DIR="$1"; shift ;;
  esac
done

# -----------------------------------------------------------------------------
# Agent rendering (agents/*.md -> per-platform files)
# -----------------------------------------------------------------------------
# Claude Code: `tools:` is a comma-separated list of Claude tool names
#   (https://code.claude.com/docs/en/sub-agents). Read-only roles (qa, research)
#   never receive Edit/Write/NotebookEdit.
# Antigravity: verified against GetAllPlugins + migrate-agent-settings/SKILL.md.
#   Omitting `tools:` falls back to a 5-tool default (`send_message`, `view_file`,
#   `search_web`, `schedule`, `generate_image`) lacking run_command, edit_file,
#   write_file, and manage_task. Emitting native YAML `tools:` grants those exact
#   tools plus `send_message`, enforcing read-only roles (qa, research) at the
#   tool layer by excluding `edit_file` and `write_file`.
# Codex: standalone TOML with name/description/developer_instructions
#   (https://learn.chatgpt.com/docs/agent-configuration/subagents).
render_agents() {
  local platform="$1" outdir="$2"
  mkdir -p "$outdir"
  python3 - "$platform" "$REPO_ROOT/agents" "$outdir" "${AGENT_ROLES[@]}" <<'PY'
import json, pathlib, re, sys

platform, srcdir, outdir, roles = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4:]

def parse(text):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    meta, key, mode, buf = {}, None, None, []
    for raw in m.group(1).splitlines():
        if key and (raw.startswith((" ", "\t")) or raw.strip() == ""):
            s = raw.strip()
            if mode == "list" and s.startswith("- "):
                meta[key].append(s[2:].strip().strip("\"'"))
            else:
                buf.append(s)
                meta[key] = " ".join(x for x in buf if x).strip()
            continue
        key, mode, buf = None, None, []
        if ":" in raw and not raw.lstrip().startswith("#"):
            k, v = (x.strip() for x in raw.split(":", 1))
            key = k
            if v in (">-", ">", "|", "|-"):
                mode, meta[k] = "scalar", ""
            elif v == "":
                mode, meta[k] = "list", []
            elif v.startswith("[") and v.endswith("]"):
                meta[k] = [x.strip().strip("\"'") for x in v[1:-1].split(",") if x.strip()]
            else:
                meta[k] = v.strip("\"'")
    return meta, m.group(2)

CLAUDE_MAP = {
    "read_file": ["Read", "Glob", "Grep"],
    "edit_file": ["Edit"],
    "write_file": ["Write"],
    "run_command": ["Bash"],
    "search_web": ["WebSearch", "WebFetch"],
    "manage_task": ["TodoWrite"],
}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
ANTIGRAVITY_WRITE_TOOLS = {"edit_file", "write_file"}

for role in roles:
    src = srcdir / f"{role}.md"
    meta, body = parse(src.read_text(encoding="utf-8"))
    name = meta.get("name") or role
    desc = meta.get("description") or f"Agent Overwatch role {role}"
    readonly = "qa" in role or "research" in role
    tools = meta.get("tools")
    if not isinstance(tools, list) or not tools:
        tools = ["read_file", "run_command", "search_web"] if readonly else \
                ["read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"]
    note = f"Generated by install.sh --build from agents/{role}.md. Do not edit; edit the source and rebuild."
    body = body.lstrip()
    if platform == "claude":
        mapped = []
        for t in tools:
            for ct in CLAUDE_MAP.get(t, []):
                if ct not in mapped and not (readonly and ct in WRITE_TOOLS):
                    mapped.append(ct)
        fm = ["---", f"name: {name}", f"description: {json.dumps(desc)}", "tools: " + ", ".join(mapped), "---"]
        out, ext = "\n".join(fm) + f"\n\n<!-- {note} -->\n\n" + body, ".md"
    elif platform == "antigravity":
        ag_tools = []
        for t in tools:
            if t not in ag_tools and not (readonly and t in ANTIGRAVITY_WRITE_TOOLS):
                ag_tools.append(t)
        fm = [
            "---",
            f"name: {name}",
            f"description: {json.dumps(desc)}",
            "subagent: true",
            "mainAgent: false",
            "tools:",
            *[f"  - {t}" for t in ag_tools],
            "---",
        ]
        out, ext = "\n".join(fm) + f"\n\n<!-- {note} -->\n\n" + body, ".md"
    elif platform == "codex":
        out = "\n".join([
            f"# {note}",
            f"name = {json.dumps(name)}",
            f"description = {json.dumps(desc)}",
            f"developer_instructions = {json.dumps(body)}",
        ]) + "\n"
        ext = ".toml"
    else:
        raise SystemExit(f"unsupported platform: {platform}")
    (outdir / f"{role}{ext}").write_text(out, encoding="utf-8")
PY
}

render_all() {
  local root="$1" p
  for p in claude antigravity codex; do
    render_agents "$p" "$root/$p/agents"
  done
}

RENDER_DIR=""
cleanup() { [[ -n "$RENDER_DIR" && -d "$RENDER_DIR" ]] && rm -rf "$RENDER_DIR"; return 0; }
trap cleanup EXIT

dist_in_sync() {
  [[ -d "$DIST_DIR" ]] && diff -r "$RENDER_DIR" "$DIST_DIR" >/dev/null 2>&1
}

if [[ "$ACTION" == "build" || "$ACTION" == "check-build" ]]; then
  RENDER_DIR="$(mktemp -d)"
  render_all "$RENDER_DIR"
  if [[ "$ACTION" == "check-build" ]]; then
    if dist_in_sync; then
      echo "[OK] dist/ is in sync with agents/*.md"
      exit 0
    fi
    diff -r "$RENDER_DIR" "$DIST_DIR" >&2 || true
    die "dist/ is out of date. Run: ./install.sh --build"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would regenerate $DIST_DIR/{claude,antigravity,codex}/agents"
    exit 0
  fi
  for p in claude antigravity codex; do
    rm -rf "${DIST_DIR:?}/$p/agents"
    mkdir -p "$DIST_DIR/$p"
    cp -R "$RENDER_DIR/$p/agents" "$DIST_DIR/$p/agents"
  done
  echo "[OK] Regenerated agents into $DIST_DIR"
  exit 0
fi

# -----------------------------------------------------------------------------
# Scope resolution (explicit, never the agent-overwatch repo itself)
# -----------------------------------------------------------------------------
if [[ "$IS_GLOBAL" == true && -n "$WORKSPACE_DIR" ]]; then
  die "Choose one scope: --global or --workspace DIR, not both."
fi
if [[ "$IS_GLOBAL" == false && -z "$WORKSPACE_DIR" ]]; then
  die "No scope given. Pass --workspace DIR (or a positional DIR) or --global."
fi

abs_path() {
  # Physical absolute path, for paths that may not exist yet.
  python3 -c 'import os,sys; print(os.path.realpath(os.path.abspath(sys.argv[1])))' "$1"
}

is_overwatch_checkout() {
  [[ -f "$1/install.sh" && -f "$1/skills/$SKILL_NAME/SKILL.md" && -d "$1/agents" ]]
}

if [[ "$IS_GLOBAL" == true ]]; then
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die "\$HOME is not set to an existing directory."
  ROOT="$(cd "$HOME" && pwd -P)"
else
  ROOT="$(abs_path "$WORKSPACE_DIR")"
fi

if [[ "$ACTION" == "install" ]]; then
  case "$ROOT/" in
    "$REPO_ROOT/"*) die "Refusing to install into the agent-overwatch repo itself ($ROOT). Pass --workspace with your project directory, or --global." ;;
  esac
  if is_overwatch_checkout "$ROOT"; then
    die "Refusing to install into an agent-overwatch checkout ($ROOT). Pass --workspace with your project directory, or --global."
  fi
fi

MANIFEST="$ROOT/$MANIFEST_NAME"

# Target selection
if [[ "$INSTALL_ALL" == true ]]; then
  want antigravity; want claude; want codex; want gemini
  if [[ "$IS_GLOBAL" == false ]]; then want cursor; want github; fi
fi

# -----------------------------------------------------------------------------
# Manifest helpers.
# On disk:   <target>\t<kind>\t<path relative to ROOT>
# In memory: <target>\t<kind>\t<absolute path under ROOT>
# kinds: file, link, dir, block (appended to an existing file), blockfile (file created for the block)
#
# The manifest is untrusted input. An entry is used only if its path is
# relative, has no "." or ".." component, and resolves inside ROOT without any
# symlinked directory on the way (the final component may be a symlink; it is
# then only ever unlinked, never followed).
#
# Arrays are expanded as ${a[@]+"${a[@]}"} because bash < 4.4 treats an empty
# "${a[@]}" as unbound under `set -u`.
# -----------------------------------------------------------------------------
OLD_ENTRIES=()
NEW_ENTRIES=()
TAB=$'\t'

# inside_root ABS: ABS is ROOT or below it, and its nearest existing ancestor
# directory (excluding ABS itself) is reached without symlinks.
inside_root() {
  local abs="$1" d
  case "$abs" in "$ROOT"|"$ROOT"/*) ;; *) return 1 ;; esac
  case "$abs/" in */../*|*/./*|*//*) return 1 ;; esac
  [[ "$abs" == "$ROOT" ]] && return 0
  d="$(dirname "$abs")"
  while [[ ! -d "$d" ]]; do
    [[ -e "$d" || -L "$d" ]] && return 1
    d="$(dirname "$d")"
  done
  [[ "$(cd "$d" && pwd -P)" == "$d" ]] || return 1
  case "$d" in "$ROOT"|"$ROOT"/*) return 0 ;; esac
  return 1
}

valid_target() { case " ${ALL_TARGETS[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

if [[ -L "$MANIFEST" ]]; then
  die "Manifest $MANIFEST is a symlink; refusing to use it."
fi
if [[ -f "$MANIFEST" ]]; then
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    m_target="${line%%"$TAB"*}"; m_rest="${line#*"$TAB"}"
    m_kind="${m_rest%%"$TAB"*}"; m_rel="${m_rest#*"$TAB"}"
    m_ok=true
    [[ "$m_rest" != "$line" && "$m_rel" != "$m_rest" ]] || m_ok=false
    valid_target "$m_target" || m_ok=false
    case "$m_kind" in file|link|dir|block|blockfile) ;; *) m_ok=false ;; esac
    case "$m_rel" in ""|/*|*"$TAB"*) m_ok=false ;; esac
    if [[ "$m_ok" == true ]] && ! inside_root "$ROOT/$m_rel"; then m_ok=false; fi
    if [[ "$m_ok" != true ]]; then
      echo "[WARN] Ignoring unsafe or malformed manifest entry at $MANIFEST line $lineno" >&2
      continue
    fi
    OLD_ENTRIES+=("$m_target$TAB$m_kind$TAB$ROOT/$m_rel")
  done < "$MANIFEST"
fi

entry_target() { printf '%s' "${1%%"$TAB"*}"; }
entry_kind()   { local r="${1#*"$TAB"}"; printf '%s' "${r%%"$TAB"*}"; }
entry_path()   { local r="${1#*"$TAB"}"; printf '%s' "${r#*"$TAB"}"; }

record() {
  local e="$1$TAB$2$TAB$3" x
  for x in ${NEW_ENTRIES[@]+"${NEW_ENTRIES[@]}"}; do [[ "$x" == "$e" ]] && return 0; done
  NEW_ENTRIES+=("$e")
}

# owned PATH [KIND]: true if any manifest entry (old or new, any target) records PATH.
# record_existing TARGET PATH: keep ownership of an existing recorded path, with its real kind.
record_existing() {
  owned "$2" || return 0
  if [[ -L "$2" ]]; then record "$1" link "$2"; else record "$1" file "$2"; fi
}

owned() {
  local p="$1" k="${2:-}" x
  for x in ${OLD_ENTRIES[@]+"${OLD_ENTRIES[@]}"} ${NEW_ENTRIES[@]+"${NEW_ENTRIES[@]}"}; do
    [[ "$(entry_path "$x")" == "$p" ]] || continue
    [[ -z "$k" || "$(entry_kind "$x")" == "$k" ]] && return 0
  done
  return 1
}

old_kind_for() {
  local t="$1" p="$2" x
  for x in ${OLD_ENTRIES[@]+"${OLD_ENTRIES[@]}"}; do
    if [[ "$(entry_target "$x")" == "$t" && "$(entry_path "$x")" == "$p" ]]; then
      entry_kind "$x"; return 0
    fi
  done
  return 1
}

# A path is "physical" when no component of its parent is a symlink. The
# installer never writes or deletes through a symlinked parent, so it cannot
# touch files inside the clone via a --link symlink.
parent_is_physical() {
  local parent; parent="$(dirname "$1")"
  [[ -d "$parent" ]] || return 1
  [[ "$(cd "$parent" && pwd -P)" == "$parent" ]]
}

write_manifest() {   # ENTRY...  (absolute in memory, written relative to ROOT)
  local e
  [[ "$DRY_RUN" == true ]] && return 0
  if [[ $# -eq 0 ]]; then
    if [[ -f "$MANIFEST" ]]; then rm -f "$MANIFEST"; echo "[OK] Removed manifest: $MANIFEST"; fi
    return 0
  fi
  {
    echo "# agent-overwatch installer manifest. Do not edit. Used by install.sh --uninstall and --force."
    echo "# Paths are relative to the directory holding this file."
    for e in "$@"; do
      printf '%s\t%s\t%s\n' "$(entry_target "$e")" "$(entry_kind "$e")" "${e##*"$TAB$ROOT"/}"
    done
  } > "$MANIFEST"
}

# -----------------------------------------------------------------------------
# Instruction-file block helpers
# -----------------------------------------------------------------------------
BLOCK_PY='
import pathlib, re, sys
mode, path = sys.argv[1], pathlib.Path(sys.argv[2])
markers = [(sys.argv[3], sys.argv[4]), (sys.argv[5], sys.argv[6])]
text = path.read_text(encoding="utf-8")
pats = [re.compile(r"\n?" + re.escape(s) + r".*?" + re.escape(e) + r"\n?", re.DOTALL) for s, e in markers]
if mode == "has":
    sys.exit(0 if any(p.search(text) for p in pats) else 1)
if mode == "replace":
    new = sys.stdin.read().strip("\n")
    for p in pats:
        if p.search(text):
            text = p.sub(lambda m: ("\n" if m.group(0).startswith("\n") else "") + new + "\n", text, count=1)
            break
elif mode == "strip":
    for p in pats:
        text = p.sub(lambda m: "\n" if m.group(0).startswith("\n") and m.group(0).endswith("\n") and m.start() > 0 and m.end() < len(text) else "", text)
path.write_text(text, encoding="utf-8")
'
block_op() { python3 -c "$BLOCK_PY" "$1" "$2" "$START_MARKER" "$END_MARKER" "$LEGACY_START" "$LEGACY_END"; }

global_snippet() {
  cat <<EOF
$START_MARKER
## Agent Overwatch (pointer)
When a task is multi-agent (parallel workers, subagents, or an independent QA
gate), load the \`agent-overwatch\` skill and follow it. This note adds no rules
to single-agent work.
$END_MARKER
EOF
}

workspace_snippet() {
  cat <<EOF
$START_MARKER
## Agent Overwatch multi-agent orchestration
For multi-agent work in this workspace, load the \`agent-overwatch\` skill and follow it:
- **Roles:** Coordinator, Research (\`research-agent\`), Dev (\`dev-agent\`), Deploy (\`deploy-agent\`), QA (\`qa-agent\`).
- **QA gate:** Plans, atomic branches, and live deployments need an independent read-only \`qa-agent\` verdict (\`QA APPROVE\`).
- **Branches:** In git repos with a shared \`main\`/\`master\`, work on short-lived branches (\`feat/*\`, \`fix/*\`, \`docs/*\`) and merge only after QA approval.
- **Coordination:** Keep living state in \`HANDOFF.md\` and the append-only log in \`AGENT_BUS.md\`, unless the runtime has a native board.
- **User updates:** Report each finished batch to the user in self-contained terms (what changed, tradeoffs, QA findings, test results, what runs next).
- **Secret hygiene:** Never commit tokens, credentials, passwords, or private keys.
$END_MARKER
EOF
}

# -----------------------------------------------------------------------------
# Install primitives
# -----------------------------------------------------------------------------
# ensure_dir TARGET DIR: create DIR, recording every directory created, and
# sharing ownership of directories already recorded by another target.
ensure_dir() {
  local t="$1" dir="$2" d
  local -a chain=()
  d="$dir"
  while [[ "$d" != "$ROOT" && "$d" != "/" && "$d" == "$ROOT"/* ]]; do
    chain+=("$d"); d="$(dirname "$d")"
  done
  for d in ${chain[@]+"${chain[@]}"}; do
    if [[ ! -e "$d" && ! -L "$d" ]]; then
      [[ "$DRY_RUN" == true ]] || record "$t" dir "$d"
    elif owned "$d" dir; then
      record "$t" dir "$d"
    fi
  done
  if [[ "$DRY_RUN" == true ]]; then
    [[ -d "$dir" ]] || echo "[DRY-RUN] Would create directory: $dir"
    return 0
  fi
  [[ -L "$dir" ]] && die "Refusing to write through symlinked directory: $dir"
  mkdir -p "$dir"
}

install_file() {   # TARGET SRC DEST LABEL
  local t="$1" src="$2" dest="$3" label="$4"
  [[ -f "$src" ]] || { echo "[WARN] Source missing: $src" >&2; return 1; }
  ensure_dir "$t" "$(dirname "$dest")"
  if [[ "$DRY_RUN" == false ]] && ! parent_is_physical "$dest"; then
    die "Refusing to write through a symlinked parent: $dest"
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$FORCE" != true ]]; then
      record_existing "$t" "$dest"
      echo "[SKIP] $label exists: $dest (use --force to overwrite)"
      return 0
    fi
    if [[ -d "$dest" && ! -L "$dest" ]]; then
      echo "[WARN] $label: $dest is a directory; leaving it alone" >&2
      return 0
    fi
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would copy $label: $src -> $dest"
    return 0
  fi
  rm -f "$dest"
  cp "$src" "$dest"
  [[ -x "$src" ]] && chmod +x "$dest"
  record "$t" file "$dest"
  echo "[OK] Installed $label: $dest"
}

# remove_owned_tree DIR: remove a real directory only if every file in it is
# recorded in the manifest. Used when --force switches copy mode to link mode.
remove_owned_tree() {
  local dir="$1" f
  while IFS= read -r -d '' f; do
    owned "$f" || return 1
  done < <(find "$dir" \( -type f -o -type l \) -print0)
  [[ "$DRY_RUN" == true ]] && return 0
  rm -rf "$dir"
}

install_link() {   # TARGET SRC DEST LABEL
  local t="$1" src="$2" dest="$3" label="$4" f
  [[ -e "$src" ]] || { echo "[WARN] Source missing: $src" >&2; return 1; }
  ensure_dir "$t" "$(dirname "$dest")"
  if [[ "$DRY_RUN" == false ]] && ! parent_is_physical "$dest"; then
    die "Refusing to create a link under a symlinked parent: $dest"
  fi
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    record "$t" link "$dest"
    echo "[OK] $label already linked: $dest -> $src"
    return 0
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$FORCE" != true ]]; then
      if [[ -d "$dest" && ! -L "$dest" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
          while IFS= read -r -d '' f; do record_existing "$t" "$f"; done < <(find "$dest" -type f -print0)
        fi
      else
        record_existing "$t" "$dest"
      fi
      echo "[SKIP] $label exists: $dest (use --force to replace it with a link)"
      return 0
    fi
    if [[ -d "$dest" && ! -L "$dest" ]]; then
      remove_owned_tree "$dest" || die "$dest contains files the installer did not create; move them away first."
    elif [[ "$DRY_RUN" == false ]]; then
      rm -f "$dest"
    fi
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would link $label: $dest -> $src"
    return 0
  fi
  ln -s "$src" "$dest"
  record "$t" link "$dest"
  echo "[OK] Linked $label: $dest -> $src"
}

install_tree() {   # TARGET SRC_DIR DEST_DIR LABEL  (copy mode)
  local t="$1" src="$2" dest="$3" label="$4" f rel
  [[ -d "$src" ]] || { echo "[WARN] Source missing: $src" >&2; return 1; }
  if [[ -L "$dest" ]]; then
    if [[ "$FORCE" != true ]]; then
      record_existing "$t" "$dest"
      echo "[SKIP] $label is a symlink: $dest (use --force to replace it with a copy)"
      return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would remove symlink $dest"
    else
      rm -f "$dest"
    fi
  fi
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    install_file "$t" "$f" "$dest/$rel" "$label ($rel)"
  done < <(find "$src" -type f -print0 | sort -z)
}

place_file() {   # TARGET SRC DEST LABEL: copy or link by MODE
  if [[ "$MODE" == "link" ]]; then install_link "$@"; else install_file "$@"; fi
}

place_tree() {   # TARGET SRC_DIR DEST_DIR LABEL
  if [[ "$MODE" == "link" ]]; then install_link "$@"; else install_tree "$@"; fi
}

# Agents: copy mode uses freshly rendered files; link mode links into dist/.
agent_src_dir() {
  if [[ "$MODE" == "link" ]]; then echo "$DIST_DIR/$1/agents"; else echo "$RENDER_DIR/$1/agents"; fi
}

place_agents() {   # TARGET PLATFORM DEST_DIR EXT
  local t="$1" p="$2" dest="$3" ext="$4" role src
  src="$(agent_src_dir "$p")"
  for role in "${AGENT_ROLES[@]}"; do
    place_file "$t" "$src/$role$ext" "$dest/$role$ext" "$p agent $role"
  done
}

update_instruction_file() {   # TARGET FILE LABEL
  local t="$1" file="$2" label="$3" snippet kind
  if [[ "$IS_GLOBAL" == true ]]; then snippet="$(global_snippet)"; else snippet="$(workspace_snippet)"; fi
  ensure_dir "$t" "$(dirname "$file")"
  if [[ ! -e "$file" ]]; then
    if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would create $label instruction file: $file"; return 0; fi
    printf '%s\n' "$snippet" > "$file"
    record "$t" blockfile "$file"
    echo "[OK] Created $label instruction file: $file"
    return 0
  fi
  kind="$(old_kind_for "$t" "$file" || true)"
  [[ "$kind" == block || "$kind" == blockfile ]] || kind=""
  if block_op has "$file"; then
    if [[ "$FORCE" == true ]]; then
      if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would replace agent-overwatch block in $file"; return 0; fi
      printf '%s\n' "$snippet" | block_op replace "$file"
      record "$t" "${kind:-block}" "$file"
      echo "[OK] Replaced agent-overwatch block in $file"
    else
      record "$t" "${kind:-block}" "$file"
      echo "[SKIP] agent-overwatch block already in $file (use --force to update)"
    fi
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would append agent-overwatch block to $file"; return 0; fi
  printf '\n%s\n' "$snippet" >> "$file"
  record "$t" "${kind:-block}" "$file"
  echo "[OK] Appended agent-overwatch block to $file"
}

# -----------------------------------------------------------------------------
# Removal (shared by --uninstall and --force pruning)
# -----------------------------------------------------------------------------
remove_path() {   # KIND PATH
  local kind="$1" p="$2" real
  if ! inside_root "$p" || [[ "$p" == "$ROOT" ]]; then
    echo "[KEEP] $p is outside $ROOT or reached through a symlink; not removing" >&2
    return 0
  fi
  if [[ "$kind" == block || "$kind" == blockfile ]] && [[ -L "$p" ]]; then
    real="$(abs_path "$p")"
    case "$real" in
      "$ROOT"/*) ;;
      *) echo "[KEEP] $p links outside $ROOT; not editing it" >&2; return 0 ;;
    esac
  fi
  case "$kind" in
    file)
      if [[ -f "$p" && ! -L "$p" ]]; then
        if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would remove file: $p"; else rm -f "$p"; echo "[OK] Removed file: $p"; fi
      fi ;;
    link)
      if [[ -L "$p" ]]; then
        if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would remove link: $p"; else rm -f "$p"; echo "[OK] Removed link: $p"; fi
      fi ;;
    block|blockfile)
      if [[ -f "$p" ]] && block_op has "$p"; then
        if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would remove agent-overwatch block from: $p"; return 0; fi
        block_op strip "$p"
        echo "[OK] Removed agent-overwatch block from: $p"
      fi
      if [[ "$kind" == blockfile && -f "$p" && "$DRY_RUN" == false ]] && ! grep -q '[^[:space:]]' "$p"; then
        rm -f "$p"; echo "[OK] Removed empty file: $p"
      fi ;;
    dir)
      if [[ -d "$p" && ! -L "$p" ]]; then
        if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] Would remove directory if empty: $p"
        elif rmdir "$p" 2>/dev/null; then echo "[OK] Removed directory: $p"
        else echo "[KEEP] Directory not empty: $p"; fi
      fi ;;
  esac
}

# remove_entries: remove each path in REM_DROP that no entry in REM_KEEP still
# references. Files first, then directories deepest first. (Globals instead of
# namerefs, for bash 3.2.)
REM_KEEP=()
REM_DROP=()
remove_entries() {
  local e p k x referenced
  local -a dirs=()
  for e in ${REM_DROP[@]+"${REM_DROP[@]}"}; do
    p="$(entry_path "$e")"; k="$(entry_kind "$e")"
    referenced=false
    for x in ${REM_KEEP[@]+"${REM_KEEP[@]}"}; do [[ "$(entry_path "$x")" == "$p" ]] && { referenced=true; break; }; done
    [[ "$referenced" == true ]] && continue
    if [[ "$k" == dir ]]; then dirs+=("$p"); else remove_path "$k" "$p"; fi
  done
  if [[ ${#dirs[@]} -gt 0 ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && remove_path dir "$p"
    done < <(printf '%s\n' "${dirs[@]}" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- | awk '!seen[$0]++')
  fi
}

selected_targets() {
  local t
  for t in "${ALL_TARGETS[@]}"; do is_selected "$t" && echo "$t"; done
  return 0
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "uninstall" ]]; then
  if [[ ${#OLD_ENTRIES[@]} -eq 0 ]]; then
    echo "[INFO] No manifest at $MANIFEST; nothing to uninstall."
    exit 0
  fi
  if [[ -z "$(selected_targets)" ]]; then
    for e in "${OLD_ENTRIES[@]}"; do want "$(entry_target "$e")"; done
  fi
  echo "Agent Overwatch uninstall from $ROOT: $(selected_targets | tr '\n' ' ')"
  for e in "${OLD_ENTRIES[@]}"; do
    if is_selected "$(entry_target "$e")"; then REM_DROP+=("$e"); else REM_KEEP+=("$e"); fi
  done
  remove_entries
  write_manifest ${REM_KEEP[@]+"${REM_KEEP[@]}"}
  echo "[SUCCESS] Uninstall finished."
  exit 0
fi

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
[[ -n "$(selected_targets)" ]] || die "No target selected. Pass one or more of --antigravity --claude --codex --gemini --cursor --github, or --all."

RENDER_DIR="$(mktemp -d)"
render_all "$RENDER_DIR"
if [[ "$MODE" == "link" ]] && ! dist_in_sync; then
  echo "[WARN] dist/ is out of date with agents/*.md, so linked agents would be stale." >&2
  echo "[WARN] Run './install.sh --build' in $REPO_ROOT, then re-run this install." >&2
  [[ "$DRY_RUN" == true ]] || die "Stale dist/; aborting --link install."
fi

echo "================================================================="
echo "Agent Overwatch installer"
echo "  Source:  $REPO_ROOT"
if [[ "$IS_GLOBAL" == true ]]; then echo "  Scope:   global ($ROOT)"; else echo "  Scope:   workspace ($ROOT)"; fi
echo "  Mode:    $MODE    Dry run: $DRY_RUN    Force: $FORCE"
echo "  Targets: $(selected_targets | tr '\n' ' ')"
echo "  Manifest: $MANIFEST"
echo "================================================================="

SKILL_SRC="$REPO_ROOT/skills/$SKILL_NAME"
if [[ "$IS_GLOBAL" == false ]]; then
  [[ "$DRY_RUN" == true ]] || mkdir -p "$ROOT"
fi

if is_selected antigravity; then
  echo ""; echo "--- Antigravity ---"
  if [[ "$MODE" == "link" ]]; then
    echo "[NOTE] Antigravity's customization scanner skips symlinks; use copy mode (omit --link) for Antigravity installs."
  fi
  if [[ "$IS_GLOBAL" == true ]]; then
    PLUGIN_DIR="$ROOT/.gemini/config/plugins/$SKILL_NAME"
    place_file antigravity "$REPO_ROOT/plugin.json" "$PLUGIN_DIR/plugin.json" "Antigravity plugin manifest"
    place_tree antigravity "$SKILL_SRC" "$PLUGIN_DIR/skills/$SKILL_NAME" "Antigravity skill"
    place_agents antigravity antigravity "$PLUGIN_DIR/agents" .md
  else
    place_tree antigravity "$SKILL_SRC" "$ROOT/.agents/skills/$SKILL_NAME" "Antigravity skill"
    place_agents antigravity antigravity "$ROOT/.agents/agents" .md
  fi
fi

if is_selected claude; then
  echo ""; echo "--- Claude Code ---"
  if [[ "$IS_GLOBAL" == true ]]; then CL="$ROOT/.claude"; CL_MD="$ROOT/.claude/CLAUDE.md"
  else CL="$ROOT/.claude"; CL_MD="$ROOT/CLAUDE.md"; fi
  place_tree claude "$SKILL_SRC" "$CL/skills/$SKILL_NAME" "Claude skill"
  place_agents claude claude "$CL/agents" .md
  update_instruction_file claude "$CL_MD" "Claude Code"
fi

if is_selected codex; then
  echo ""; echo "--- Codex ---"
  if [[ "$IS_GLOBAL" == true ]]; then CX_MD="$ROOT/.codex/AGENTS.md"; else CX_MD="$ROOT/AGENTS.md"; fi
  place_tree codex "$SKILL_SRC" "$ROOT/.agents/skills/$SKILL_NAME" "Codex skill"
  place_agents codex codex "$ROOT/.codex/agents" .toml
  update_instruction_file codex "$CX_MD" "Codex"
fi

if is_selected gemini; then
  echo ""; echo "--- Gemini CLI ---"
  if [[ "$IS_GLOBAL" == true ]]; then GM_MD="$ROOT/.gemini/GEMINI.md"; else GM_MD="$ROOT/GEMINI.md"; fi
  place_file gemini "$REPO_ROOT/examples/gemini-cli/agent-overwatch.toml" "$ROOT/.gemini/commands/agent-overwatch.toml" "Gemini command"
  update_instruction_file gemini "$GM_MD" "Gemini CLI"
fi

# Cursor and GitHub files live in the project repository, where an absolute
# symlink into this clone would be committed by mistake, so they are always copied.
if is_selected cursor; then
  echo ""; echo "--- Cursor ---"
  if [[ "$IS_GLOBAL" == true ]]; then
    echo "[INFO] Cursor rules are workspace-scoped; skipping for --global."
  else
    install_file cursor "$REPO_ROOT/examples/cursor/agent-overwatch.mdc" "$ROOT/.cursor/rules/agent-overwatch.mdc" "Cursor rule"
  fi
fi

if is_selected github; then
  echo ""; echo "--- GitHub templates ---"
  if [[ "$IS_GLOBAL" == true ]]; then
    echo "[INFO] GitHub templates are repository-scoped; skipping for --global."
  else
    install_file github "$REPO_ROOT/examples/github/ISSUE_TEMPLATE/atomic_task.md" "$ROOT/.github/ISSUE_TEMPLATE/atomic_task.md" "GitHub issue template"
    install_file github "$REPO_ROOT/examples/github/PULL_REQUEST_TEMPLATE.md" "$ROOT/.github/PULL_REQUEST_TEMPLATE.md" "GitHub PR template"
  fi
fi

# Merge the manifest. Entries for targets outside this run are kept untouched.
# Without --force, previous entries for this run's targets are kept as well.
# With --force, previous entries this run did not re-record are pruned.
FINAL=()
STALE=()
for e in ${OLD_ENTRIES[@]+"${OLD_ENTRIES[@]}"}; do
  in_new=false
  for x in ${NEW_ENTRIES[@]+"${NEW_ENTRIES[@]}"}; do [[ "$x" == "$e" ]] && { in_new=true; break; }; done
  [[ "$in_new" == true ]] && continue
  if is_selected "$(entry_target "$e")" && [[ "$FORCE" == true ]]; then
    STALE+=("$e")
  else
    FINAL+=("$e")
  fi
done
FINAL+=(${NEW_ENTRIES[@]+"${NEW_ENTRIES[@]}"})
if [[ ${#STALE[@]} -gt 0 ]]; then
  echo ""; echo "--- Pruning stale files (--force) ---"
  REM_KEEP=(${FINAL[@]+"${FINAL[@]}"})
  REM_DROP=("${STALE[@]}")
  remove_entries
fi
write_manifest ${FINAL[@]+"${FINAL[@]}"}

echo ""
echo "================================================================="
if [[ "$DRY_RUN" == true ]]; then
  echo "[SUCCESS] Dry run finished; nothing was written."
else
  echo "[SUCCESS] Installed. Undo with: $0 --uninstall $([[ "$IS_GLOBAL" == true ]] && echo --global || echo "--workspace $ROOT")"
fi
echo "================================================================="
