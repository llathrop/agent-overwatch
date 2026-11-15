# HANDOFF — Agent Overwatch

## 1. Purpose
`agent-overwatch` is a general-purpose multi-agent orchestration skill, plugin bundle, and subagent role suite designed for parallel execution with mandatory read-only QA overwatch, atomic Git/GitHub branching, and clean coordination across any software or operations repository.

## 2. Current State (as of 2026-11-15 23:08 UTC)
- **Main branch (`main`):** `@ 4433d18` (`feat/core-skill-and-agents` `@ 285f96f` received `QA APPROVE` from `qa-overwatch` and merged incrementally via `--no-ff`).
- **Active branch:** `feat/templates-and-examples` (branched from `main` @ `4433d18`) — **ready for `qa-overwatch` pre-merge audit** (not yet merged to `main`).
- **Completed in Atomic Branch 2 (`feat/templates-and-examples`):**
  - `skills/agent-overwatch/templates/`: `HANDOFF.template.md`, `SUBDIR_HANDOFF.template.md`, `AGENT_BUS.template.md`, `QA_CHECKLIST.template.md`
  - `examples/`: `antigravity/`, `claude-code/`, `codex/`, `cursor/`, `gemini-cli/`, `github/` (`ISSUE_TEMPLATE/atomic_task.md`, `PULL_REQUEST_TEMPLATE.md`)
- **Validation:** YAML frontmatter (`examples/cursor/agent-overwatch.mdc`, `examples/github/ISSUE_TEMPLATE/atomic_task.md`), TOML (`examples/gemini-cli/agent-overwatch.toml`), relative markdown link resolution, and domain-neutrality/hygiene checks passed locally after final edits.

## 3. Ordered Next Steps
1. **QA gate on Atomic Branch 2 (`feat/templates-and-examples`):** `qa-overwatch` audits templates, examples, syntax, links, and hygiene before `--no-ff` merge to `main`.
2. **Atomic Branch 3 (`feat/installers-and-validation`):** Cut from updated `main` after Branch 2 merges; deliver cross-tool `install.sh` (`--dry-run`, idempotency across Antigravity, Claude Code, Codex CLI, Gemini CLI, Cursor) plus automated smoke tests/validators.

## 4. Repo Conventions
- **Never commit secrets.** `.gitignore` blocks `.env*`, keys, and temp files.
- **Atomic branches + QA gate:** Every step develops on a short-lived branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`), receives `qa-agent` `APPROVE`, and merges incrementally to `main`.
- **Single source of truth:** `HANDOFF.md` tracks current state and pointers; live inter-agent messages use the environment's native messaging/board tool when available, or append atomically to `AGENT_BUS.md` otherwise.
