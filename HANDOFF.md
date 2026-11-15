# HANDOFF — Agent Overwatch

## 1. Purpose
`agent-overwatch` is a general-purpose, cross-platform multi-agent orchestration skill, Antigravity plugin bundle, multi-tool installer, and portable subagent role suite designed around **high-velocity parallel execution gated by mandatory independent QA**.

## 2. Current State (as of 2026-11-15 23:17 UTC)
- **`main` branch (`4bc4493`):** Complete implementation merged incrementally via three QA-approved `--no-ff` feature branches:
  1. `237b465` — `chore: initialize agent-overwatch repository` (baseline `.gitignore`, `README.md`, `HANDOFF.md`, `AGENT_BUS.md`)
  2. `4433d18` — `Merge feat/core-skill-and-agents` (`285f96f`, `QA APPROVE`): `plugin.json`, `skills/agent-overwatch/SKILL.md`, 4 `references/*.md` guides, and 4 portable `agents/*.md` subagents
  3. `bc98b82` — `Merge feat/templates-and-examples` (`66ac9f5`, `QA APPROVE`): 4 `skills/agent-overwatch/templates/*.template.md` starters and 10 multi-tool `examples/` files (Antigravity, Claude Code, Codex CLI, Cursor, Gemini CLI, GitHub)
  4. `4bc4493` — `Merge feat/scripts-and-installer` (`617aa94`, `QA APPROVE`): executable `install.sh`, `skills/agent-overwatch/scripts/init_workspace.sh`, `skills/agent-overwatch/scripts/verify_atomic_branch.sh`, and updated `README.md` / `SKILL.md` links
- **Workspace hygiene:** All merged atomic feature branches deleted cleanly; temporary sibling staging directories (`../agent-overwatch-staging-b2a` and `../agent-overwatch-staging-b2b`) removed and verified never tracked in git.
- **Active branch (`docs/final-handoff`):** Cut from `main` @ `4bc4493` to finalize `HANDOFF.md` and `AGENT_BUS.md` — **awaiting final `qa-overwatch` audit before merge to `main`**.

## 3. Repository Layout on `main` (31 tracked files)
- **Root (6):** `.gitignore`, `AGENT_BUS.md`, `HANDOFF.md`, `README.md`, `install.sh`, `plugin.json`
- **`agents/` (4):** `qa-agent.md`, `research-agent.md`, `dev-agent.md`, `deploy-agent.md`
- **`skills/agent-overwatch/` (11):**
  - `SKILL.md`
  - `references/` (`agent-roles.md`, `coordination-files.md`, `git-and-github-workflow.md`, `model-routing-and-scaling.md`)
  - `templates/` (`HANDOFF.template.md`, `SUBDIR_HANDOFF.template.md`, `AGENT_BUS.template.md`, `QA_CHECKLIST.template.md`)
  - `scripts/` (`init_workspace.sh`, `verify_atomic_branch.sh`)
- **`examples/` (10):** `antigravity/README.md`, `claude-code/{CLAUDE.md,README.md}`, `codex/{AGENTS.md,README.md}`, `cursor/agent-overwatch.mdc`, `gemini-cli/{GEMINI.md,agent-overwatch.toml}`, `github/{ISSUE_TEMPLATE/atomic_task.md,PULL_REQUEST_TEMPLATE.md}`

## 4. Verified Commands & Smoke Checks
- `bash -n install.sh skills/agent-overwatch/scripts/*.sh` — shell syntax verified
- `./install.sh --all --dry-run` & `./install.sh --all --global --dry-run` — workspace and global dry-runs verified
- `./install.sh --all --workspace <tmp>` + `--force` + `init_workspace.sh` (`root` & `--subdir`) — full cross-tool install and idempotency verified
- `./skills/agent-overwatch/scripts/verify_atomic_branch.sh --repo . --base main` — branch isolation, clean tree, diff scope, secret scan, and latest-verdict Gate 5 verified (`HOLD` blocks `exit 1`, `APPROVE` passes `exit 0`)
- Repo-wide `plugin.json`, YAML frontmatter (`SKILL.md`, `agents/*.md`, Cursor `.mdc`, GitHub Issue template), TOML (`agent-overwatch.toml`), relative link resolution (32 links), and secret/hygiene checks passed

## 5. Next Steps
1. Complete `qa-overwatch` final audit on `docs/final-handoff` and merge `--no-ff` to `main`.
2. User can install locally (`./install.sh --antigravity --global`, `./install.sh --all --workspace <project>`) or push to a remote repository when ready.

## 6. Repo Conventions
- **Never commit secrets.** `.gitignore` blocks `.env*`, keys, and temp files.
- **Atomic branches + QA gate:** Every step develops on a short-lived branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`), receives `qa-agent` `APPROVE`, and merges incrementally to `main`.
- **Single source of truth:** `HANDOFF.md` tracks current state and pointers; live inter-agent messages use the environment's native messaging/board tool when available, or append atomically to `AGENT_BUS.md` otherwise.
