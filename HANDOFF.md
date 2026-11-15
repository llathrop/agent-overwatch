# HANDOFF — Agent Overwatch

## 1. Purpose
`agent-overwatch` is a general-purpose multi-agent orchestration skill, plugin bundle, and subagent role suite designed for parallel execution with mandatory read-only QA overwatch, atomic Git/GitHub branching, and clean coordination across any software or operations repository.

## 2. Current State (as of 2026-11-15 23:04 UTC)
- **Active branch:** `feat/core-skill-and-agents` (branched from `main` @ `237b465`) — **ready for `qa-agent` pre-merge audit** (not yet merged to `main`).
- **Completed in Step B1:**
  - `plugin.json` manifest
  - `skills/agent-overwatch/SKILL.md` core workflow skill
  - `skills/agent-overwatch/references/` (`agent-roles.md`, `coordination-files.md`, `git-and-github-workflow.md`, `model-routing-and-scaling.md`)
  - `agents/` portable subagent definitions (`qa-agent.md`, `research-agent.md`, `dev-agent.md`, `deploy-agent.md`)
- **Validation:** JSON schema, YAML frontmatter, relative markdown link resolution, and tool/domain-neutrality checks passed locally.

## 3. Ordered Next Steps
1. **QA gate on Step B1 (`feat/core-skill-and-agents`):** Independent `qa-agent` audits diff, frontmatter compatibility, links, and requirements before merging to `main`.
2. **Step B2 (`feat/installers-and-templates`):** Cut from updated `main` after Step B1 merges; implement cross-tool `install.sh` (Antigravity, Claude Code, Codex CLI, Gemini CLI, Cursor) and starter templates (`HANDOFF.md`, `AGENT_BUS.md`, `QA_BUS.md`).
3. **Step B3 (`feat/validation-and-ci`):** Cut from updated `main` after Step B2 merges; add automated validation/linting scripts and installer smoke tests.

## 4. Repo Conventions
- **Never commit secrets.** `.gitignore` blocks `.env*`, keys, and temp files.
- **Atomic branches + QA gate:** Every step develops on a short-lived branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`), receives `qa-agent` `APPROVE`, and merges incrementally to `main`.
- **Single source of truth:** `HANDOFF.md` tracks current state and pointers; live inter-agent messages use the environment's native messaging/board tool when available, or append atomically to `AGENT_BUS.md` otherwise.
