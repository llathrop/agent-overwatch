# HANDOFF — Agent Overwatch

## 1. Purpose
`agent-overwatch` is a general-purpose multi-agent orchestration skill, plugin bundle, and subagent role suite designed for parallel execution with mandatory read-only QA overwatch, atomic Git/GitHub branching, and clean coordination across any software or operations repository.

## 2. Current State (Baseline)
- **Active branch:** `main` (repository initialization baseline)
- **Completed:** Git repository initialized (`README.md`, `.gitignore`, `HANDOFF.md`, `AGENT_BUS.md`).
- **In progress:** Preparing Step B1 (`feat/core-skill-and-agents`) — core `plugin.json`, `skills/agent-overwatch/SKILL.md`, 4 reference guides, and 4 portable subagent files.

## 3. Planned Atomic Roadmap
1. **Step B1 (`feat/core-skill-and-agents`):** Core plugin manifest, `SKILL.md`, `references/*.md`, and `agents/*.md` — merge to `main` after QA `APPROVE`.
2. **Step B2 (`feat/installers-and-templates`):** Cross-tool `install.sh` and reusable `HANDOFF.md` / `AGENT_BUS.md` / `QA_BUS.md` starter templates — merge to `main` after QA `APPROVE`.
3. **Step B3 (`feat/validation-and-ci`):** Automated validation/lint scripts and smoke tests verifying frontmatter, links, JSON validity, and installer idempotency — merge to `main` after QA `APPROVE`.

## 4. Repo Conventions
- **Never commit secrets.** `.gitignore` blocks `.env*`, keys, and temp files.
- **Atomic branches + QA gate:** Every step develops on a short-lived branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`), receives `qa-agent` `APPROVE`, and merges incrementally to `main`.
- **Single source of truth:** `HANDOFF.md` tracks current state and pointers; live inter-agent messages use the environment's native messaging/board tool when available, or append atomically to `AGENT_BUS.md` otherwise.
