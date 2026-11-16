#!/usr/bin/env bash
# Tests for install.sh. Uses a temp copy of the repo, a temp HOME, and temp
# workspaces; never touches the real ~ or the real checkout.
# shellcheck disable=SC2016  # single quotes are intentional: args are passed to bash -c positionally
set -uo pipefail

SRC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

# Fresh copy of the repo (without .git) so tests may edit sources safely.
REPO="$TMP/repo"
mkdir -p "$REPO"
(cd "$SRC_REPO" && tar --exclude=.git -cf - .) | (cd "$REPO" && tar -xf -)
INSTALL="$REPO/install.sh"

new_home() { local h; h="$(mktemp -d "$TMP/home.XXXXXX")" || exit 1; [[ -d "$h" ]] || exit 1; echo "$h"; }
run() {
  [[ -n "${H:-}" && -d "$H" ]] || { echo "test HOME missing" >&2; return 1; }
  HOME="$H" "$INSTALL" "$@" >"$TMP/last.log" 2>&1
}
empty_dir() { [[ -z "$(find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]]; }

echo "# syntax and lint"
check "bash -n install.sh" bash -n "$INSTALL"
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck install.sh" shellcheck "$INSTALL"
else
  echo "skip - shellcheck not installed"
fi

echo "# dist/ in sync with agents/*.md"
check "--check-build passes on the committed tree" "$INSTALL" --check-build

echo "# plugin JSON"
check ".claude-plugin and plugin.json are valid JSON with required fields" python3 - "$REPO" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
pj = json.loads((root / ".claude-plugin/plugin.json").read_text())
mj = json.loads((root / ".claude-plugin/marketplace.json").read_text())
ag = json.loads((root / "plugin.json").read_text())
assert pj["name"] == "agent-overwatch"
for a in pj["agents"]:
    assert a.startswith("./") and (root / a).is_file(), a
assert mj["name"] and mj["owner"]["name"] and mj["plugins"]
entry = mj["plugins"][0]
assert entry["name"] == pj["name"] and entry["source"] == "./"
assert ag["name"] == "agent-overwatch"
PY
check "Claude agents: comma-separated tools; qa/research have no Edit/Write" python3 - "$REPO" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1]) / "dist/claude/agents"
for f in sorted(d.glob("*.md")):
    fm = re.match(r"^---\n(.*?)\n---\n", f.read_text(), re.S).group(1)
    tools = re.search(r"^tools: (.+)$", fm, re.M).group(1)
    assert "[" not in tools, f
    names = [t.strip() for t in tools.split(",")]
    allowed = {"Read", "Glob", "Grep", "Edit", "Write", "Bash", "TodoWrite", "WebSearch", "WebFetch"}
    assert set(names) <= allowed, (f, names)
    if "qa" in f.name or "research" in f.name:
        assert not {"Edit", "Write"} & set(names), f
    assert re.search(r"^name: \S+$", fm, re.M) and re.search(r"^description: ", fm, re.M), f
PY
check "Antigravity agents: YAML tools list; qa/research have no edit_file/write_file" python3 - "$REPO" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1]) / "dist/antigravity/agents"
allowed = {"read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"}
for f in sorted(d.glob("*.md")):
    fm = re.match(r"^---\n(.*?)\n---\n", f.read_text(), re.S).group(1)
    assert re.search(r"^name: \S+$", fm, re.M) and re.search(r"^description: ", fm, re.M), f
    assert re.search(r"^subagent: true$", fm, re.M), f
    assert re.search(r"^mainAgent: false$", fm, re.M), f
    m = re.search(r"^tools:\n((?:  - \S+\n?)+)", fm, re.M)
    assert m, f"Missing YAML tools list in {f}"
    names = [line.strip()[2:].strip() for line in m.group(1).strip().splitlines()]
    assert names and set(names) <= allowed, (f, names)
    if "qa" in f.name or "research" in f.name:
        assert not {"edit_file", "write_file"} & set(names), (f, names)
    else:
        assert {"edit_file", "write_file"} <= set(names), (f, names)
PY
check "Codex agents are valid TOML with required keys" python3 - "$REPO" <<'PY'
import pathlib, sys, tomllib
for f in (pathlib.Path(sys.argv[1]) / "dist/codex/agents").glob("*.toml"):
    data = tomllib.loads(f.read_text())
    assert {"name", "description", "developer_instructions"} <= set(data), f
PY
if command -v claude >/dev/null 2>&1; then
  VH="$(new_home)"
  if out="$(HOME="$VH" claude plugin validate "$REPO" 2>&1)"; then
    if grep -q "Validation passed" <<<"$out"; then ok "claude plugin validate"; else bad "claude plugin validate: $out"; fi
  else
    bad "claude plugin validate failed: $out"
  fi
else
  echo "skip - claude CLI not installed"
fi

echo "# scope and self-install refusal"
H="$(new_home)"
check "no scope is refused" bash -c '! HOME="$1" "$2" --claude >/dev/null 2>&1' _ "$H" "$INSTALL"
check "installing into the repo itself is refused" bash -c '! HOME="$1" "$2" --all --workspace "$3" >/dev/null 2>&1' _ "$H" "$INSTALL" "$REPO"
check "positional repo path is refused too" bash -c 'cd "$3" && ! HOME="$1" "$2" --claude . >/dev/null 2>&1' _ "$H" "$INSTALL" "$REPO"
check "refusal wrote no manifest into the repo" test ! -e "$REPO/.agent-overwatch-manifest" -a ! -e "$REPO/.claude"
CLONE="$TMP/other-checkout"; mkdir -p "$CLONE/skills/agent-overwatch" "$CLONE/agents"
touch "$CLONE/install.sh" "$CLONE/skills/agent-overwatch/SKILL.md"
check "installing into another agent-overwatch checkout is refused" bash -c '! HOME="$1" "$2" --claude --workspace "$3" >/dev/null 2>&1' _ "$H" "$INSTALL" "$CLONE"

echo "# dry-run for each target writes nothing"
for t in antigravity claude codex gemini cursor github; do
  H="$(new_home)"; WS="$TMP/dry-$t"
  check "dry-run --$t workspace" run "--$t" --workspace "$WS" --dry-run
  check "dry-run --$t workspace created nothing" test ! -e "$WS"
  check "dry-run --$t global" run "--$t" --global --dry-run
  check "dry-run --$t global wrote nothing to HOME" empty_dir "$H"
done
H="$(new_home)"
check "dry-run --uninstall without a manifest" run --uninstall --global --dry-run

echo "# real workspace install"
H="$(new_home)"; WS="$TMP/ws1"; mkdir -p "$WS"
printf '# My project rules\nKeep this line.\n' > "$WS/CLAUDE.md"
check "install --all --workspace" run --all --workspace "$WS"
for f in .claude/skills/agent-overwatch/SKILL.md .claude/agents/qa-agent.md \
         .agents/skills/agent-overwatch/SKILL.md .agents/agents/dev-agent.md \
         .codex/agents/qa-agent.toml .gemini/commands/agent-overwatch.toml \
         .cursor/rules/agent-overwatch.mdc .github/PULL_REQUEST_TEMPLATE.md \
         .github/ISSUE_TEMPLATE/atomic_task.md AGENTS.md GEMINI.md .agent-overwatch-manifest; do
  check "installed $f" test -f "$WS/$f"
done
check "existing CLAUDE.md content kept" grep -q "Keep this line." "$WS/CLAUDE.md"
check "workspace block has the conditional branch rule" grep -q "In git repos with a shared" "$WS/CLAUDE.md"
check "workspace block has no unconditional main rule" bash -c '! grep -q "Never commit directly" "$1"' _ "$WS/CLAUDE.md"
for wf in CLAUDE.md AGENTS.md GEMINI.md; do
  check "workspace $wf authorizes model tiering" grep -q "explicitly user-authorized" "$WS/$wf"
done
check "installed skill's ../../agents link resolves for Claude" test -f "$WS/.claude/skills/agent-overwatch/../../agents/qa-agent.md"
check "re-run without --force is idempotent" run --all --workspace "$WS"
check "re-run keeps a single block" test "$(grep -c '>>> agent-overwatch >>>' "$WS/CLAUDE.md")" = 1
check "--force re-run succeeds" run --all --workspace "$WS" --force
check "--force keeps a single block" test "$(grep -c '>>> agent-overwatch >>>' "$WS/CLAUDE.md")" = 1

echo "# --force prunes files dropped from the source"
STALE="$REPO/skills/agent-overwatch/references/zz-stale.md"
echo "temporary" > "$STALE"
check "install picks up new source file" run --claude --workspace "$WS" --force
check "new file present in target" test -f "$WS/.claude/skills/agent-overwatch/references/zz-stale.md"
echo "user" > "$WS/.claude/skills/agent-overwatch/references/user-notes.md"
rm -f "$STALE"
check "--force after removal" run --claude --workspace "$WS" --force
check "stale file pruned" test ! -e "$WS/.claude/skills/agent-overwatch/references/zz-stale.md"
check "stale file dropped from manifest" bash -c '! grep -q zz-stale "$1"' _ "$WS/.agent-overwatch-manifest"
check "user file in the same dir survives pruning" test -f "$WS/.claude/skills/agent-overwatch/references/user-notes.md"
rm -f "$WS/.claude/skills/agent-overwatch/references/user-notes.md"

echo "# partial uninstall keeps shared files"
check "uninstall --antigravity only" run --uninstall --antigravity --workspace "$WS"
check "shared .agents skill kept for codex" test -f "$WS/.agents/skills/agent-overwatch/SKILL.md"
check "antigravity agents removed" test ! -e "$WS/.agents/agents"

echo "# full uninstall leaves no files"
check "uninstall (all recorded targets)" run --uninstall --workspace "$WS"
check "user CLAUDE.md content kept after uninstall" grep -q "Keep this line." "$WS/CLAUDE.md"
check "block removed from CLAUDE.md" bash -c '! grep -q "agent-overwatch" "$1"' _ "$WS/CLAUDE.md"
rm -f "$WS/CLAUDE.md"
check "workspace is empty apart from the user file" empty_dir "$WS"

echo "# tampered manifest: entries outside the target are never touched"
plant() {
  OUT="$TMP/outside-$1"; mkdir -p "$OUT/vdir"
  echo victim > "$OUT/victim"; echo victim2 > "$OUT/victim2"; echo victim3 > "$OUT/victim3"
  printf 'keep\n<!-- >>> agent-overwatch >>> -->\nx\n<!-- <<< agent-overwatch <<< -->\n' > "$OUT/notes.md"
  cp "$OUT/notes.md" "$OUT/notes.orig"
  ln -s "$OUT" "$WS/esc"
  ln -s "$OUT/victim2" "$WS/lnk"
  ln -s "$OUT/victim3" "$WS/flnk"
  ln -s "$OUT/notes.md" "$WS/blk.md"
  T="$(printf '\t')"
  {
    echo "claude${T}file${T}$OUT/victim"
    echo "claude${T}file${T}/$OUT/victim"
    echo "claude${T}file${T}../outside-$1/victim"
    echo "claude${T}file${T}.claude/../../outside-$1/victim"
    echo "claude${T}dir${T}../outside-$1/vdir"
    echo "claude${T}file${T}esc/victim"
    echo "claude${T}dir${T}esc/vdir"
    echo "claude${T}link${T}lnk"
    echo "claude${T}file${T}flnk"
    echo "claude${T}block${T}blk.md"
    echo "claude${T}file${T}./CLAUDE.md"
    echo "bogus${T}file${T}x"
  } >> "$WS/.agent-overwatch-manifest"
}
assert_outside_intact() {
  check "$1: absolute/.. victim file survives" test -f "$OUT/victim"
  check "$1: victim dir survives" test -d "$OUT/vdir"
  check "$1: symlink target of a link entry survives" test -f "$OUT/victim2"
  check "$1: symlink target of a file entry survives" test -f "$OUT/victim3"
  check "$1: block file reached via symlink unchanged" cmp -s "$OUT/notes.md" "$OUT/notes.orig"
}
for mode in uninstall force; do
  H="$(new_home)"; WS="$TMP/ws-tamper-$mode"; mkdir -p "$WS"
  check "tamper/$mode: base install" run --claude --workspace "$WS"
  plant "$mode"
  if [[ "$mode" == uninstall ]]; then
    check "tamper/$mode: uninstall runs" run --uninstall --workspace "$WS"
  else
    check "tamper/$mode: --force prune runs" run --claude --workspace "$WS" --force
  fi
  check "tamper/$mode: unsafe entries are reported" grep -q "Ignoring unsafe or malformed manifest entry" "$TMP/last.log"
  assert_outside_intact "tamper/$mode"
  check "tamper/$mode: escape symlink itself left alone" test -L "$WS/esc"
done
check "tamper/uninstall: in-root link entry removed without following it" test ! -L "$TMP/ws-tamper-uninstall/lnk"
check "manifest stores relative paths only" bash -c '! cut -f3 "$1" | grep -q "^/"' _ "$TMP/ws-tamper-force/.agent-overwatch-manifest"

echo "# global install: pointer snippet only"
H="$(new_home)"
check "install --all --global" run --all --global
for f in .claude/CLAUDE.md .codex/AGENTS.md .gemini/GEMINI.md; do
  check "$f has the skill pointer" grep -q 'load the `agent-overwatch` skill' "$H/$f"
  check "$f has no hard rules" bash -c '! grep -qiE "never commit|QA gate:|Branches:|Secret hygiene" "$1"' _ "$H/$f"
  check "$f block is short (<= 8 lines)" test "$(wc -l < "$H/$f")" -le 8
  check "$f authorizes model tiering" grep -q "explicitly user-authorized" "$H/$f"
done
check "global Antigravity plugin manifest" test -f "$H/.gemini/config/plugins/agent-overwatch/plugin.json"
check "global Codex skill under ~/.agents/skills" test -f "$H/.agents/skills/agent-overwatch/SKILL.md"
check "global uninstall" run --uninstall --global
check "HOME is empty after global uninstall" empty_dir "$H"

echo "# --link mode"
H="$(new_home)"; WS="$TMP/ws-link"
check "install --claude --codex --antigravity --gemini --link" run --claude --codex --antigravity --gemini --workspace "$WS" --link
check "skill dir is a symlink" test -L "$WS/.claude/skills/agent-overwatch"
check "skill symlink resolves" test -f "$WS/.claude/skills/agent-overwatch/SKILL.md"
check "agent is a symlink into dist/claude" bash -c '[[ "$(readlink "$1")" == "$2/dist/claude/agents/qa-agent.md" ]]' _ "$WS/.claude/agents/qa-agent.md" "$REPO"
check "codex agent symlink resolves" test -f "$WS/.codex/agents/qa-agent.toml"
check "gemini command is a symlink" test -L "$WS/.gemini/commands/agent-overwatch.toml"
echo "LINK-CANARY" >> "$REPO/skills/agent-overwatch/SKILL.md"
check "source change is visible through the link" grep -q LINK-CANARY "$WS/.claude/skills/agent-overwatch/SKILL.md"
check "copy install over links without --force does not write into the clone" run --claude --workspace "$WS"
check "clone untouched by the copy attempt" test ! -e "$REPO/skills/agent-overwatch/.agent-overwatch-manifest"
check "--force switches links to copies" run --claude --workspace "$WS" --force
check "skill dir is now a real dir" bash -c '[[ -d "$1" && ! -L "$1" ]]' _ "$WS/.claude/skills/agent-overwatch"
check "--force --link switches copies back to links" run --claude --workspace "$WS" --force --link
check "skill dir is a symlink again" test -L "$WS/.claude/skills/agent-overwatch"
check "uninstall link install" run --uninstall --workspace "$WS"
check "link workspace is empty after uninstall" empty_dir "$WS"
check "uninstall did not delete clone files" test -f "$REPO/skills/agent-overwatch/SKILL.md" -a -f "$REPO/dist/claude/agents/qa-agent.md"

echo "# stale dist/ blocks --link"
printf '\nSTALE-CANARY\n' >> "$REPO/agents/qa-agent.md"
check "--check-build detects stale dist" bash -c '! "$1" --check-build >/dev/null 2>&1' _ "$INSTALL"
H="$(new_home)"
check "--link refuses with stale dist" bash -c '! HOME="$1" "$2" --claude --global --link >/dev/null 2>&1' _ "$H" "$INSTALL"
check "--build regenerates dist" "$INSTALL" --build
check "--check-build passes after rebuild" "$INSTALL" --check-build
check "rebuilt agent carries the change" grep -q STALE-CANARY "$REPO/dist/claude/agents/qa-agent.md"

echo ""
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
