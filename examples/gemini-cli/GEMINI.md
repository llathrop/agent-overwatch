# GEMINI.md — Agent Overwatch Rules for Gemini CLI

This snippet configures Google Gemini CLI to enforce the **Agent Overwatch** protocol.

---

## Agent Overwatch Core Rules

1. **Mandatory QA Gate:**
   - Any proposed code modification or refactor must pass an independent QA evaluation before merging or deployment.
   - Do not self-approve changes. Validate test evidence, clean diffs, and security scans.
   - QA records its own verdict with `scripts/bus_append.sh --type "QA APPROVE"|"QA HOLD" --ref auto` (`<branch>@<sha12>`, with commands, outputs, `file:line`). The coordinator never writes or relays one; new commits need re-review. If QA is denied a command, it says so and verifies from posted evidence.
2. **Atomic Branch Isolation:**
   - Always operate in dedicated, single-purpose branches (`feat/<feature-slug>` or `fix/<bug-slug>`).
   - Keep changes tightly scoped to the immediate task requirements.
3. **Living Handoff Maintenance:**
   - Keep `HANDOFF.md` synchronized after every completed milestone.
   - Any new agent taking over this workspace must review `HANDOFF.md` and run `scripts/coordinator_lease.sh status` before initiating actions (`claim --takeover` to replace a stale coordinator).
   - Keep `HANDOFF.md` short (≤200 chars per cell/bullet, ~150 lines); detail goes to the bus via `scripts/bus_append.sh`.
4. **Safety & Rollback Verification:**
   - Before executing state-changing operations, verify that a clean, tested rollback command is documented.
5. **Zero-Secret Invariant:**
   - Never print or commit passwords, API keys, bearer tokens, or sensitive credentials. Reference environment variables only.
6. **Non-Dependent Work:**
   - "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)." Start required independent work now; never invent optional work to fill time.
7. **Usage & Budget Awareness:**
   - If usage or spend numbers are available, warn the user near ~75% and ~90%, naming what is still running. If none are available, ignore this; don't guess or throttle. On a rate limit (429), pause and record state in `HANDOFF.md`.
8. **Live User-Facing Progress Updates:**
   - Report concise, self-contained progress summaries as each batch or QA gate completes (do not stay silent until the end or assume the user read internal subagent messages or `AGENT_BUS.md`). Cover what changed and why, tradeoffs, QA catches/fixes, verified results, and upcoming parallel work.
