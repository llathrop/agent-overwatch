# CLAUDE.md — Agent Overwatch Rules for Claude Code

This file configures Claude Code to operate under the **Agent Overwatch** multi-agent development and quality assurance protocol.

---

## Core Protocol Rules

1. **Mandatory QA Overwatch Review:**
   - Every feature, refactor, or bugfix must be independently audited and granted an `APPROVE` verdict by the QA agent before being merged into the integration branch or deployed.
   - Self-approval by dev or deploy agents is strictly prohibited.
2. **Atomic Branch Isolation:**
   - Never commit directly to `main` or the primary integration branch.
   - Create focused atomic branches: `feat/<name>` or `fix/<name>`.
   - Keep diffs minimal and strictly scoped to the task acceptance criteria.
3. **Incremental Merges:**
   - Once an atomic branch receives QA `APPROVE`, merge it immediately to prevent branch drift and painful rebases.
4. **Living Handoff Synchronization:**
   - Keep the root `HANDOFF.md` updated with active branch status, deliverables, open questions, and active agent ownership.
5. **Rollback Strategy Before State Changes:**
   - Before executing state-changing commands (database migrations, server restarts, file deletion), document the exact rollback command. If rollback is not verified, do not proceed.
6. **Zero-Secret Invariant:**
   - Never print, echo, or log credentials, tokens, or private keys. Sourced strictly via environment variables or stdin.
7. **Live User-Facing Progress Updates:**
   - Provide concise, self-contained user progress summaries as phases and subagent batches finish (never wait until all work ends or assume the user reads internal messages or `AGENT_BUS.md`). Include what changed and why, technical tradeoffs, any QA catches/fixes, verification outcomes, and what parallel work runs next.

---

## Subagent Architecture & Model Tiering

When dispatching subagents in Claude Code, route tasks according to model capabilities:

| Subagent Role | Target Agent Config | Recommended Model Tier | Primary Responsibilities |
|---|---|---|---|
| **QA Overwatch** | `.claude/agents/qa.md` | `sonnet` (or `opus` for high-risk audits) | Sips no Kool-Aid. Audits diffs, verifies test outputs, checks secrets, reviews rollback plans. Issues `APPROVE` or `HOLD`. |
| **Developer** | `.claude/agents/dev.md` | `sonnet` | Authors code, adds comprehensive unit/integration tests, updates docs, strictly within atomic feature branch. |
| **Deployer** | `.claude/agents/deploy.md` | `sonnet` | Pre-change backups, staging rollouts, live health checks (`/health` HTTP 200, zero container restarts). |
| **Researcher** | `.claude/agents/research.md` | `haiku` (fallback: `sonnet`) | Explores documentation, analyzes CVEs, summarizes external API specs without touching code. |

---

## Communication & Coordination

- **Native Agent Teams:** If running Claude Code with subagent dispatching enabled, pass structured parameters directly between supervisor and subagents.
- **Audit Bus (`AGENT_BUS.md`):** If multiple Claude Code terminal sessions are operating concurrently in the workspace, use append-only entries in `AGENT_BUS.md` following standard format:
  `### [<TIME>] <role> -> <recipient|all> | <TYPE>` (types: `PLAN`, `ACTION`, `RESULT`, `CHALLENGE`, `APPROVE`, `HOLD`).
- Always tail `AGENT_BUS.md` or check subagent returns before state-changing steps.
