# GEMINI.md — Agent Overwatch Rules for Gemini CLI

This snippet configures Google Gemini CLI to enforce the **Agent Overwatch** protocol.

---

## Agent Overwatch Core Rules

1. **Mandatory QA Gate:**
   - Any proposed code modification or refactor must pass an independent QA evaluation before merging or deployment.
   - Do not self-approve changes. Validate test evidence, clean diffs, and security scans.
2. **Atomic Branch Isolation:**
   - Always operate in dedicated, single-purpose branches (`feat/<feature-slug>` or `fix/<bug-slug>`).
   - Keep changes tightly scoped to the immediate task requirements.
3. **Living Handoff Maintenance:**
   - Keep `HANDOFF.md` synchronized after every completed milestone.
   - Any new agent taking over this workspace must review `HANDOFF.md` before initiating actions.
4. **Safety & Rollback Verification:**
   - Before executing state-changing operations, verify that a clean, tested rollback command is documented.
5. **Zero-Secret Invariant:**
   - Never print or commit passwords, API keys, bearer tokens, or sensitive credentials. Reference environment variables only.
