# AGENTS.md — Agent Overwatch Rules for Codex CLI

This file establishes the **Agent Overwatch** rules for the Codex CLI environment.

---

## Operating Principles

1. **Mandatory QA Sign-Off:**
   - No feature or bugfix may be merged into the primary branch without explicit verification and `APPROVE` sign-off from a QA Overwatch pass.
   - Self-approval is disallowed. Every pull request or merge commit requires verifiable test output and a clean diff audit.
2. **Atomic Branches & Minimal Diffs:**
   - All work must be conducted on isolated branches: `feat/<name>` or `fix/<name>`.
   - Never mix multiple unrelated features or refactors into a single branch.
3. **Synchronized Handoff State:**
   - Keep `HANDOFF.md` at the project root up to date. Every completed milestone, newly created branch, or open decision must be reflected in `HANDOFF.md`.
4. **Safety & Rollback Priority:**
   - State-changing actions (database changes, server configurations, file deletions) require an explicit, documented rollback procedure.
   - If a rollback command is missing or untested, the action must be halted.
5. **Zero-Secret Invariant:**
   - Never hardcode or echo secrets, tokens, or private keys. Sourced strictly via environment variables or secret stores.

---

## Hierarchical Configuration Overrides

Codex CLI reads instructions hierarchically:
- Global defaults: `~/.codex/AGENTS.md`
- Project root overrides: `<project-root>/AGENTS.md`
- Subdirectory module overrides: `<project-root>/<subdir>/AGENTS.md`

Rules defined in a subdirectory `AGENTS.md` take precedence for files within that subtree while inheriting the global Overwatch safety rules.
