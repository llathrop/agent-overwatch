# CLAUDE.md — Agent Overwatch Rules for Claude Code

This file configures Claude Code to operate under the **Agent Overwatch** multi-agent development and quality assurance protocol.

---

## Core Protocol Rules

1. **Mandatory QA Overwatch Review:**
   - Every feature, refactor, or bugfix must be independently audited and granted an `APPROVE` verdict by the QA agent before being merged into the integration branch or deployed.
   - Self-approval by dev or deploy agents is strictly prohibited.
   - QA posts its own verdict bound to the commit: `scripts/bus_append.sh --type "QA APPROVE" --ref auto` (or `"QA HOLD"`), giving `<branch>@<sha12>` and citing commands, outputs, and `file:line`. The main session never writes or relays a verdict. New commits need re-review, and `verify_atomic_branch.sh` fails without a matching verdict unless `--allow-external-qa` is given.
2. **Atomic Branch Isolation:**
   - Never commit directly to `main` or the primary integration branch.
   - Create focused atomic branches: `feat/<name>` or `fix/<name>`.
   - Keep diffs minimal and strictly scoped to the task acceptance criteria.
3. **Incremental Merges:**
   - Once an atomic branch receives QA `APPROVE`, merge it immediately to prevent branch drift and painful rebases.
4. **Living Handoff Synchronization:**
   - Keep the root `HANDOFF.md` updated with active branch status, deliverables, open questions, and active agent ownership. Cap it (≤200 chars per cell/bullet, ~150 lines); detail goes to the bus.
   - Before coordinating, run `scripts/coordinator_lease.sh status`; `claim` (or `claim --takeover` for a stale lease) and `renew` while active. If another session replaced you, stand down or coordinate on the bus.
5. **Rollback Strategy Before State Changes:**
   - Before executing state-changing commands (database migrations, server restarts, file deletion), document the exact rollback command. If rollback is not verified, do not proceed.
6. **Zero-Secret Invariant:**
   - Never print, echo, or log credentials, tokens, or private keys. Sourced strictly via environment variables or stdin.
7. **Non-Dependent Work:**
   - "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)." Start required independent work now; never invent optional work to fill time. Scale QA to the review load so verification doesn't queue.
8. **Usage & Budget Awareness:**
   - If usage or spend numbers are available (`/usage`, statusline cost, token-target directives), track them and warn the user near ~75% and ~90%, naming what is still running. If none are available, ignore this; don't guess or throttle. On a rate limit (429), pause and record state in `HANDOFF.md` so another session can resume.
9. **Live User-Facing Progress Updates:**
   - Provide concise, self-contained user progress summaries as phases and subagent batches finish (never wait until all work ends or assume the user reads internal messages or `AGENT_BUS.md`). Include what changed and why, technical tradeoffs, any QA catches/fixes, verification outcomes, and what parallel work runs next.

---

## Subagent Architecture & Model Tiering

When dispatching subagents in Claude Code, route tasks according to model capabilities:

| Subagent Role | Target Agent Config | Recommended Model Tier | Primary Responsibilities |
|---|---|---|---|
| **QA Overwatch** | `.claude/agents/qa-agent.md` | `sonnet` (or `opus` for high-risk audits) | Sips no Kool-Aid. Audits diffs, verifies test outputs, checks secrets, reviews rollback plans. Issues `APPROVE` or `HOLD`. |
| **Developer** | `.claude/agents/dev-agent.md` | `sonnet` | Authors code, adds comprehensive unit/integration tests, updates docs, strictly within atomic feature branch. |
| **Deployer** | `.claude/agents/deploy-agent.md` | `sonnet` | Pre-change backups, staging rollouts, live health checks (`/health` HTTP 200, zero container restarts). |
| **Researcher** | `.claude/agents/research-agent.md` | `haiku` (fallback: `sonnet`) | Explores documentation, analyzes CVEs, summarizes external API specs without touching code. |

**Enforce QA read-only with tools, not just the prompt:** keep the QA and research agents' `tools:` free of `Edit`, `MultiEdit`, and `Write`, and add permission allowlist entries in `.claude/settings.json` for the specific read-only commands QA needs (e.g. `Bash(git diff:*)`, `Bash(ssh host systemctl status:*)`). If QA is denied a command, it says so and verifies from posted evidence; the main session must not run the denied command for it.

**Live overwatch:** subagents end their turns, so during a deploy run `scripts/overwatch_watch.sh --once --check '<health cmd>'` under the Monitor tool or `/loop`, and wake QA on each `BUS:`, `SECRET?`, or `CHECK-FAIL` line.

---

## Communication & Coordination

- **Native Agent Teams:** If running Claude Code with subagent dispatching enabled, pass structured parameters directly between supervisor and subagents.
- **Local Bus (`AGENT_BUS.md`, git-ignored, not committed; use `HANDOFF.md` for tracked handoff):** If multiple Claude Code terminal sessions are operating concurrently in the workspace, append entries with `scripts/bus_append.sh --from ROLE --to LIST --type TYPE --subject TEXT [--ref auto]` (body on stdin). It stamps the UTC time; never hand-type timestamps. Format:
  `### [<YYYY-MM-DD HH:MM:SS UTC>] <role> -> <recipient|all> | <TYPE> [<branch>@<sha12>] <subject>` (types: `BRIEF`, `PLAN`, `ACTION`, `RESULT`, `CONCERN`, `QA APPROVE`, `QA HOLD`, `TAKEOVER`, `STATUS`, `USAGE`).
- Always tail `AGENT_BUS.md` or check subagent returns before state-changing steps.
