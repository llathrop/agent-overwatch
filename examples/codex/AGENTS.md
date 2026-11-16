# AGENTS.md — Agent Overwatch Rules for Codex CLI

This file establishes the **Agent Overwatch** rules for the Codex CLI environment.

---

## Operating Principles

1. **Mandatory QA Sign-Off:**
   - No feature or bugfix may be merged into the primary branch without explicit verification and `APPROVE` sign-off from a QA Overwatch pass.
   - Self-approval is disallowed. Every pull request or merge commit requires verifiable test output and a clean diff audit.
   - The QA pass records its own verdict with `scripts/bus_append.sh --type "QA APPROVE"|"QA HOLD" --ref auto` (`<branch>@<sha12>`, citing commands, outputs, `file:line`). The coordinator never writes or relays one. New commits need re-review; `verify_atomic_branch.sh` fails without a matching verdict unless `--allow-external-qa`.
   - Enforce QA read-only through sandbox/approval settings, not only the prompt. If QA is denied a command, it says so and verifies from posted evidence; nobody runs the denied command for it.
2. **Atomic Branches & Minimal Diffs:**
   - All work must be conducted on isolated branches: `feat/<name>` or `fix/<name>`.
   - Never mix multiple unrelated features or refactors into a single branch.
3. **Synchronized Handoff State:**
   - Keep `HANDOFF.md` at the project root up to date. Every completed milestone, newly created branch, or open decision must be reflected in `HANDOFF.md`. Keep it short (≤200 chars per cell/bullet, ~150 lines); detail goes to the bus via `scripts/bus_append.sh` (never hand-typed timestamps).
   - Check `scripts/coordinator_lease.sh status` before coordinating; use `claim --takeover` to replace a stale coordinator. A replaced session stands down.
4. **Safety & Rollback Priority:**
   - State-changing actions (database changes, server configurations, file deletions) require an explicit, documented rollback procedure.
   - If a rollback command is missing or untested, the action must be halted.
5. **Zero-Secret Invariant:**
   - Never hardcode or echo secrets, tokens, or private keys. Sourced strictly via environment variables or secret stores.
6. **Non-Dependent Work:**
   - "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)." Start required independent work now; never invent optional work to fill time. Scale QA to the review load so verification doesn't queue.
7. **Usage & Budget Awareness:**
   - If usage or spend numbers are available, track them and warn the user near ~75% and ~90%, naming what is still running. If none are available, ignore this; don't guess or throttle. On a rate limit (429), pause and record state in `HANDOFF.md`.
8. **Live User-Facing Progress Updates:**
   - Deliver self-contained progress updates after each completed phase or batch rather than waiting until the end or assuming the user inspected internal logs/`AGENT_BUS.md`. Summarize what changed and why, key technical tradeoffs, QA catches/fixes, test outcomes, and next parallel steps without pasting raw log spam or secrets.

---

## Hierarchical Configuration Overrides

Codex CLI reads instructions hierarchically:
- Global defaults: `~/.codex/AGENTS.md`
- Project root overrides: `<project-root>/AGENTS.md`
- Subdirectory module overrides: `<project-root>/<subdir>/AGENTS.md`

Rules defined in a subdirectory `AGENTS.md` take precedence for files within that subtree while inheriting the global Overwatch safety rules.
