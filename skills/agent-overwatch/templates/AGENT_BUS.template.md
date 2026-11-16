# AGENT BUS: Append-Only Multi-Agent Coordination Log

> [!IMPORTANT]
> **Use built-in agent board/messaging tools (e.g., `swarm` board or native `send_message`) instead if available; keep `AGENT_BUS.md` only when no built-in board exists or when a repo-committed audit trail is required.**

---

## Operating Protocol & Rules of Engagement

1. **STRICTLY APPEND-ONLY, VIA `bus_append.sh`:**
   - Never edit, overwrite, reorder, or delete existing entries. All agents append new entries at the bottom of the log.
   - Append with `skills/agent-overwatch/scripts/bus_append.sh`, never by hand-typing headers. It stamps the UTC time (with seconds) automatically, resolves `--ref auto` to `<branch>@<sha12>`, appends atomically (flock, or a mkdir lock), validates the entry type, and refuses (exit 2) any subject/body that matches a secret pattern (reporting the line number only):
     ```bash
     ./skills/agent-overwatch/scripts/bus_append.sh --bus AGENT_BUS.md \
       --from dev-1 --to qa-1,coordinator --type RESULT \
       --subject "fix/topic ready for QA" --ref auto <<'EOF'
     Files: scripts/foo.sh, tests/test_foo.sh
     Tests: tests/test_foo.sh -> passed: 12 failed: 0
     EOF
     ```
2. **Standard Entry Format** (what `bus_append.sh` writes):
   ```markdown
   ### [<YYYY-MM-DD HH:MM:SS UTC>] <from> -> <to-list|all> | <TYPE> [<branch>@<sha12>] <subject>
   <Concise body with facts, commands, outputs, or requests (may be empty)>
   ```
3. **Supported Entry Types** (`bus_append.sh --type` accepts exactly these):
   - `TAKEOVER`: A coordinator session takes over (or claims) the workstream; states why and what it owns.
   - `BRIEF`: Task initialization, assignment, shared interface spec, or lane ownership.
   - `ACTION`: Posted **BEFORE** executing any state-changing command (migrations, file writes, container restarts, git pushes). Must include exact commands and rollback steps.
   - `RESULT`: Posted immediately **AFTER** execution with exact output status, return codes, and evidence. Use `--ref auto` so the entry is bound to the commit under review.
   - `CONCERN`: A risk, challenge, missing test, or cross-lane interface conflict raised by any agent.
   - `QA APPROVE`: Formal QA sign-off for one exact commit (see Verdict Format below).
   - `QA HOLD`: Formal QA veto for one exact commit, blocking merge until defects are resolved.
   - `STATUS`: Periodic milestone heartbeat (step X complete; next step Y).
   - `USAGE`: Token / budget / rate-limit usage report.
4. **QA Verdict Format (binding; checked by `verify_atomic_branch.sh`):**
   ```markdown
   ### [YYYY-MM-DD HH:MM:SS UTC] <qa-role> -> <to> | QA APPROVE <branch>@<sha12> <subject>
   ### [YYYY-MM-DD HH:MM:SS UTC] <qa-role> -> <to> | QA HOLD <branch>@<sha12> <subject>
   ```
   - **QA writes its own verdicts** with `bus_append.sh --from <qa-role> --type "QA APPROVE" --ref auto` (or an explicit `--ref <branch>@<sha>`). The author role must contain `qa`; the coordinator never relays or paraphrases a verdict, and `bus_append.sh` refuses QA types from non-QA roles.
   - The verdict is bound to `<branch>@<sha>` (sha prefix >= 7). `verify_atomic_branch.sh` only accepts an APPROVE whose branch equals the current branch and whose sha matches HEAD. **The latest verdict for that branch wins**, so a later `QA HOLD` blocks. Any new commit after an APPROVE makes it stale: QA must re-review and post a new verdict for the new HEAD.
   - Legacy verdicts without `<branch>@<sha>` are ignored by the gate.
   - **Every verdict body must cite evidence:** the exact commands QA ran and their results (exit codes, pass/fail counts, relevant output lines). A verdict without evidence is not a review. HOLD bodies list numbered remediation items.
5. **Zero-Secret Invariant:**
   - Never log passwords, tokens, API keys, or private identifiers. Reference paths or variable names only. `bus_append.sh` enforces this for the patterns it knows; that is a backstop, not a licence to paste credentials.

---

## Coordination Log

### [2026-11-16 10:00:00 UTC] coordinator -> all | BRIEF WS-01 JWT auth middleware
Workstream WS-01 initiated: Implementing JWT authentication middleware for API gateway. Base branch: `main`. Dedicated atomic branch: `feat/jwt-auth`. Assigned to `dev-agent-1`. QA Overwatch is assigned to `qa-agent`. Target delivery includes unit tests, integration middleware test, and zero external secret leaks.

### [2026-11-16 10:05:00 UTC] dev-agent-1 -> qa-agent | BRIEF implementation plan for feat/jwt-auth
Proposing 3-stage implementation on branch `feat/jwt-auth`:
1. Add token verification helper using HMAC-SHA256 (`src/auth/jwt.py`) with RS256 readiness.
2. Inject middleware into HTTP handler pipeline (`src/server.py`).
3. Add unit test suite `tests/test_jwt.py` covering expired tokens, invalid signatures, malformed headers, and valid payload extraction.
Rollback strategy: `git revert` or branch deletion (no live DB changes). Awaiting QA review before action.

### [2026-11-16 10:07:30 UTC] qa-agent -> dev-agent-1 | CONCERN secret handling in stage 1
Plan reviewed. Challenge on stage 1: Ensure secret keys are read from environment (`JWT_SECRET_KEY`) with explicit error handling if unset (do not default to an insecure fallback string like "dev-secret"). Also, ensure clock skew tolerance is capped at <= 60 seconds.

### [2026-11-16 10:09:15 UTC] dev-agent-1 -> qa-agent | STATUS concern addressed
Acknowledged. `JWT_SECRET_KEY` will raise `ConfigurationError("JWT_SECRET_KEY environment variable required")` on startup if absent. Added 30-second leeway test case. Proceeding to implementation.

### [2026-11-16 10:25:00 UTC] dev-agent-1 -> all | ACTION run tests and commit on feat/jwt-auth
Executing test suite and branch commit on `feat/jwt-auth`:
Command: `pytest -v tests/test_jwt.py && ruff check .`
Changes staged: `src/auth/jwt.py`, `src/server.py`, `tests/test_jwt.py`.
Rollback command: `git checkout main && git branch -D feat/jwt-auth`.

### [2026-11-16 10:26:40 UTC] dev-agent-1 -> qa-agent,coordinator | RESULT feat/jwt-auth@3f9c2a1b7d4e feat/jwt-auth ready for QA
Test suite completed with return code 0.
Output:
- `tests/test_jwt.py`: 12 passed in 0.42s (100% branch coverage on `src/auth/jwt.py`).
- Linter `ruff check .`: 0 errors, 0 warnings.
- Secret scan: `git diff main...feat/jwt-auth` checked against secret patterns: 0 matches.
Pull request `#42` opened for QA Overwatch audit.

### [2026-11-16 10:32:07 UTC] qa-agent -> dev-agent-1,coordinator | QA APPROVE feat/jwt-auth@3f9c2a1b7d4e PR #42 cleared for merge
Evidence (commands run by QA against `feat/jwt-auth@3f9c2a1b7d4e`):
1. `pytest -v tests/test_jwt.py` -> exit 0, 12 passed in 0.42s; fuzzed invalid header tokens rejected with HTTP 401.
2. `ruff check .` -> exit 0, 0 errors.
3. `verify_atomic_branch.sh --repo . --base main` -> secret scan of final files + every branch commit: 0 hits.
4. Scope: `git diff --stat main...HEAD` -> 3 files, all inside the WS-01 slice. Rollback: `git revert -m 1 <merge>` verified on a scratch branch.

---
<!-- Append new entries below this line -->
