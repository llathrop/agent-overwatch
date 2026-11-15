# HANDOFF — Agent Overwatch

## 1. Purpose
`agent-overwatch` is a general-purpose multi-agent orchestration skill, plugin bundle, installer, and subagent role suite designed for parallel execution with mandatory read-only QA overwatch, atomic Git/GitHub branching, and clean coordination across any software or operations repository.

## 2. Current State (as of 2026-11-15 23:13 UTC)
- **Main branch (`main`):** `@ bc98b82` (`feat/templates-and-examples` `@ 66ac9f5` received `QA APPROVE` from `qa-overwatch` and merged incrementally via `--no-ff`).
- **Active branch:** `feat/scripts-and-installer` (branched from `main` @ `bc98b82`) — **ready for `qa-overwatch` pre-merge audit** (not yet merged to `main`).
- **Completed in Atomic Branch 3 (`feat/scripts-and-installer`):**
  - `install.sh` (executable multi-tool installer supporting `--antigravity`, `--claude`, `--codex`, `--gemini`, `--cursor`, `--github`, `--all`, `--global`/`--workspace`, `--dry-run`, `--force`; includes safe `sys.argv`/`stdin` instruction updates and multiline-YAML-safe Antigravity/Claude agent mapping)
  - `skills/agent-overwatch/scripts/init_workspace.sh` (root and `--subdir` scaffolding with `--no-bus`, `--dry-run`, `--force`)
  - `skills/agent-overwatch/scripts/verify_atomic_branch.sh` (5-gate pre-merge checker including latest-verdict Gate 5 inspection)
  - Updated `README.md` and `skills/agent-overwatch/SKILL.md` links to include `install.sh`, `templates/`, `scripts/`, and `examples/`.

## 3. Ordered Next Steps
1. **QA gate on Atomic Branch 3 (`feat/scripts-and-installer`):** `qa-overwatch` audits `install.sh`, `init_workspace.sh`, `verify_atomic_branch.sh`, and doc links before `--no-ff` merge to `main`.
2. **Post-merge cleanup & live user installation:** After Branch 3 receives `QA APPROVE` and merges to `main`, clean up sibling temporary staging directories (`../agent-overwatch-staging-b2a` and `../agent-overwatch-staging-b2b`) and run any desired user-requested `--global` or `--workspace` installs.

## 4. Repo Conventions
- **Never commit secrets.** `.gitignore` blocks `.env*`, keys, and temp files.
- **Atomic branches + QA gate:** Every step develops on a short-lived branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`), receives `qa-agent` `APPROVE`, and merges incrementally to `main`.
- **Single source of truth:** `HANDOFF.md` tracks current state and pointers; live inter-agent messages use the environment's native messaging/board tool when available, or append atomically to `AGENT_BUS.md` otherwise.
