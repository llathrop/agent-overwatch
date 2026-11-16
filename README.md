# Agent Overwatch

A general-purpose, cross-platform multi-agent workflow skill, plugin bundle, installer, and portable subagent suite built around **high-velocity parallel execution gated by mandatory independent QA**.

## Why Agent Overwatch

- **Don't defer independent work:** If necessary work doesn't depend on work already in progress, don't defer it. Run it now on a separate agent (`research-agent`, `dev-agent`, `deploy-agent`) across non-overlapping files, modules, and worktrees.
- **Mandatory independent QA:** Every research plan, code diff, backup, and deployment is independently verified by a strictly read-only `qa-agent` (`APPROVE` or `HOLD` with exact file/line/command evidence) before moving forward or merging.
- **Portable across tools:** The workflow is plain Markdown and shell, so any agent or human can follow it. [install.sh](install.sh) and the per-tool adapters in `examples/` cover Antigravity, Claude Code, Codex CLI, Gemini CLI, Cursor, and GitHub Issue/PR templates.
- **Atomic Git & GitHub discipline:** Small, single-purpose feature branches, incremental QA-gated merges back to `main`, automated pre-merge verification via [verify_atomic_branch.sh](skills/agent-overwatch/scripts/verify_atomic_branch.sh), and strict upstream safety guardrails for public repositories.

## Install

The core (`skills/`, `agents/`) is tool-neutral. The sections below are per-tool adapters.

### Claude Code: native plugin (recommended)

The repo is its own Claude Code plugin marketplace ([.claude-plugin/marketplace.json](.claude-plugin/marketplace.json)). Inside a Claude Code session:

```text
/plugin marketplace add llathrop/agent-overwatch
/plugin install agent-overwatch@agent-overwatch
```

You get the `agent-overwatch` skill and four subagents (`agent-overwatch:qa-agent`, `dev-agent`, `deploy-agent`, `research-agent`). Updates come through Claude Code's plugin update mechanism: run `/plugin marketplace update agent-overwatch`, or turn on auto-update for the marketplace under **Marketplaces** in `/plugin`. The plugin manifest sets no `version` on purpose, so every pushed commit counts as a new version. This is a better path than `--link` for Claude Code: there are no symlinks to keep valid and no build step for you to run.

The plugin's agents come from the generated [dist/claude/agents/](dist/claude/agents/), which [.claude-plugin/plugin.json](.claude-plugin/plugin.json) lists explicitly. Because of that, `claude plugin validate` notes that the raw `agents/` folder is not scanned. The raw `agents/*.md` files use portable tool names, and the generated files have valid Claude Code frontmatter (`tools:` as comma-separated Claude tool names, and no Edit/Write for `qa-agent` and `research-agent`).

Sources: [plugin manifest reference](https://code.claude.com/docs/en/plugins-reference), [create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces), [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference.md), [host and update a marketplace](https://code.claude.com/docs/en/plugins/host-marketplace.md), [subagent frontmatter](https://code.claude.com/docs/en/sub-agents).

### Other tools: install.sh

A scope is required (`--global`, or `--workspace DIR` or a bare `DIR`). The installer refuses to install into an agent-overwatch checkout itself.

```bash
# Preview without writing anything
./install.sh --all --workspace /path/to/your-project --dry-run

# Copy into a project (full workspace rules go into CLAUDE.md / AGENTS.md / GEMINI.md)
./install.sh --all --workspace /path/to/your-project

# Install for your user account (instruction files get a short pointer only)
./install.sh --antigravity --codex --gemini --global

# Remove exactly what the installer created
./install.sh --uninstall --global
./install.sh --uninstall --workspace /path/to/your-project
```

- **Manifest:** Each file, symlink, directory, and instruction-file block the installer creates is recorded in `<target>/.agent-overwatch-manifest` (`<target>` is the workspace, or `$HOME` for `--global`). `--uninstall` removes only those items and strips the agent-overwatch block out of instruction files, leaving your other content alone. `--uninstall` with no target flags removes every recorded target. Add flags such as `--codex` to remove just that target. Manifest paths are stored relative to the target, and the manifest is treated as untrusted. Entries that are absolute, contain `.` or `..`, or resolve through a symlinked directory are ignored with a warning. A symlink is only ever unlinked, never followed.
- **`--force`:** Overwrites files and replaces the instruction block. It also prunes manifest entries that this run no longer installs, such as files dropped from the source. Files you added yourself are never pruned.
- **Global vs. workspace text:** `--global` writes only a pointer to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and `~/.gemini/GEMINI.md`: "when a task is multi-agent, load the agent-overwatch skill". That keeps solo and non-git projects free of workflow rules. Workspace installs write the full rules, and the branch rule only applies in git repos with a shared `main`.

### Pull-to-update: `--link`

```bash
git clone https://github.com/llathrop/agent-overwatch ~/src/agent-overwatch
~/src/agent-overwatch/install.sh --codex --antigravity --gemini --global --link
# later
git -C ~/src/agent-overwatch pull
```

- **Skill directories** are symlinked to `skills/agent-overwatch/` in the clone, so a `git pull` updates them right away.
- **Agent files** can't link straight to `agents/*.md`, because each platform needs different frontmatter. `./install.sh --build` generates them into the committed [dist/](dist/) directory (`dist/claude/agents/*.md`, `dist/antigravity/agents/*.md`, `dist/codex/agents/*.toml`), and `--link` links to those files. **After a pull that changes `agents/*.md`, re-run `./install.sh --build` in the clone**, unless the pull already included the rebuilt `dist/`. `--link` refuses to run while `dist/` is stale. `./install.sh --check-build` exits 1 when `dist/` is out of date, and `tests/test_install.sh` checks this too.
- **Instruction-file blocks** are copied text, which is why they are kept as minimal pointers that rarely change. Re-run with `--force` to refresh them.
- **Cursor rules and GitHub templates** are always copied. They live inside your project repository, where an absolute symlink into your clone would get committed by mistake.
- Re-running with `--force` switches an existing install between copy mode and link mode. The installer never writes or deletes through a symlinked directory, so it can't touch files in your clone.

### Install paths

| Target | `--global` | `--workspace DIR` | Verified against |
| :- | :- | :- | :- |
| Antigravity | `~/.gemini/config/plugins/agent-overwatch/` (`plugin.json`, `skills/`, `agents/`) | `DIR/.agents/skills/agent-overwatch/`, `DIR/.agents/agents/*.md` | [plugins](https://antigravity.google/docs/plugins.md), [build plugins](https://antigravity.google/docs/build-plugins.md), [skills](https://antigravity.google/docs/skills.md), [subagents](https://antigravity.google/docs/subagents.md) |
| Claude Code | `~/.claude/skills/agent-overwatch/`, `~/.claude/agents/*.md`, `~/.claude/CLAUDE.md` | `DIR/.claude/skills/…`, `DIR/.claude/agents/*.md`, `DIR/CLAUDE.md` | [subagents](https://code.claude.com/docs/en/sub-agents) |
| Codex | `~/.agents/skills/agent-overwatch/`, `~/.codex/agents/*.toml`, `~/.codex/AGENTS.md` | `DIR/.agents/skills/…`, `DIR/.codex/agents/*.toml`, `DIR/AGENTS.md` | [skills](https://learn.chatgpt.com/docs/build-skills), [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) |
| Gemini CLI | `~/.gemini/commands/agent-overwatch.toml`, `~/.gemini/GEMINI.md` | `DIR/.gemini/commands/…`, `DIR/GEMINI.md` | [custom commands](https://geminicli.com/docs/cli/custom-commands/), [GEMINI.md](https://geminicli.com/docs/cli/gemini-md/) |
| Cursor | n/a | `DIR/.cursor/rules/agent-overwatch.mdc` | |
| GitHub | n/a | `DIR/.github/ISSUE_TEMPLATE/atomic_task.md`, `DIR/.github/PULL_REQUEST_TEMPLATE.md` | |

Paths checked against those pages on 2026-11-15. Earlier versions of this installer used `~/.codex/skills` and `.codex/skills`, which Codex does not scan; Codex reads skills from `.agents/skills`. Two things are not verified:

- **Antigravity agent `tools:`** The installer omits it from generated Antigravity agents. The documented built-in tool names disagree between pages, and the docs warn that an unknown name can hang a subagent. With `tools:` omitted the agent gets all tools, so `qa-agent` and `research-agent` stay read-only only because their prompts say so.
- **Symlinked skill folders** are documented for Codex. For Claude Code and Antigravity they are expected to work but not documented.

### Initialize and verify

```bash
./skills/agent-overwatch/scripts/init_workspace.sh /path/to/your-project
./skills/agent-overwatch/scripts/init_workspace.sh /path/to/your-project/services/api --subdir
./skills/agent-overwatch/scripts/verify_atomic_branch.sh --repo /path/to/your-project --base main
```

Read the workflow manual first: [skills/agent-overwatch/SKILL.md](skills/agent-overwatch/SKILL.md).

## Portable Subagent Roles

- [agents/qa-agent.md](agents/qa-agent.md): read-only verification and `APPROVE` / `HOLD` gatekeeper
- [agents/research-agent.md](agents/research-agent.md): read-only exploration, root-cause analysis, and RFCs
- [agents/dev-agent.md](agents/dev-agent.md): isolated authoring, refactoring, and automated tests
- [agents/deploy-agent.md](agents/deploy-agent.md): backup-first rollouts, smoke checks, and rollback readiness

Edit these sources, then run `./install.sh --build` and commit the regenerated `dist/`.

## Repository Layout

```text
agent-overwatch/
├── .claude-plugin/
│   ├── plugin.json                          # Claude Code plugin manifest (agents -> dist/claude/agents)
│   └── marketplace.json                     # Claude Code marketplace (this repo is the plugin)
├── plugin.json                              # Antigravity plugin manifest
├── install.sh                               # Installer: copy/--link, --uninstall, --force pruning, --build
├── agents/                                  # Portable subagent sources
├── dist/                                    # Generated per-platform agents (install.sh --build); committed
│   ├── claude/agents/*.md
│   ├── antigravity/agents/*.md
│   └── codex/agents/*.toml
├── examples/                                # Tool-specific setups & GitHub templates
├── skills/agent-overwatch/                  # The skill: SKILL.md, references/, templates/, scripts/
├── tests/test_install.sh                    # Installer tests (temp HOME and workspaces only)
├── HANDOFF.md                               # This repo's own dev coordination state (not installed)
└── AGENT_BUS.md                             # This repo's local coordination log (git-ignored, not tracked, not installed)
```

## Status & Coordination

[HANDOFF.md](HANDOFF.md) at the repo root is this repository's tracked development handoff, and the way to resume on another machine. `AGENT_BUS.md` is local agent coordination: it is git-ignored, never committed or pushed, and not an audit trail in git. Neither is part of what gets installed. The installer and plugin ship only the skill, the agents, the commands, and the templates. Projects get their own copies from `init_workspace.sh`.

## Tests

```bash
bash tests/test_install.sh
```
