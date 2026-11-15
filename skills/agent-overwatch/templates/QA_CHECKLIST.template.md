# QA Overwatch Verification Checklist

**Audit Date:** `<YYYY-MM-DD HH:MM UTC>`  
**Auditor (QA Agent ID):** `<qa-agent-id>`  
**Target Pull Request / Branch:** `PR #<N>` (`<branch-name>` -> `<target-branch>`)  
**Workstream ID:** `<WS-ID>`  
**Overall Decision:** `[ APPROVE | HOLD ]`

---

## 1. Plan Audit

- [ ] **Problem Formulation:** The problem statement clearly defines root cause vs symptom.
- [ ] **Scope Minimality:** Proposed changes are tightly scoped to the single issue/feature; no unrelated "drive-by" refactoring.
- [ ] **Staged Execution:** Multi-step changes are ordered from lowest risk (read-only/runtime) to persistent modifications.
- [ ] **Rollback Strategy:** Every step defines an explicit, automated revert procedure (e.g., config backup restore, `git revert`, container tag rollback).
- [ ] **Pre-conditions Met:** Required environment variables, access permissions, and dependent services are verified.

---

## 2. Research Audit

- [ ] **Documentation Verification:** Third-party libraries, APIs, or system packages match verified upstream documentation and version compatibility matrices.
- [ ] **Known Issues & CVEs:** No known vulnerabilities (CVEs) or deprecation notices introduced by new dependencies.
- [ ] **Reproducible Diagnosis:** Root causes for bugs are demonstrated with reproducible logs, failing tests, or kernel/runtime diagnostics prior to fixing.
- [ ] **Zero Hallucination:** Configuration flags, CLI parameters, and SDK methods have been verified against actual installed versions.

---

## 3. Dev & Branch Audit

- [ ] **Atomic Scope:** Diff touches only the files necessary for this workstream.
- [ ] **Test Coverage & Evidence:**
  - [ ] Unit tests added or updated for all new logic branches.
  - [ ] Edge cases tested (null inputs, timeouts, network disconnects, invalid payloads).
  - [ ] Integration tests pass in isolated staging/dev environment.
  - [ ] Exact test commands and stdout/stderr evidence provided.
- [ ] **Secret & Security Scan:**
  - [ ] `git diff` audited for API keys, bearer tokens, private keys, database passwords, or hardcoded IP/host secrets.
  - [ ] Credentials strictly sourced via environment variables, secret managers, or stdin.
  - [ ] File permissions audited (e.g., sensitive files set to `600` or `700`, not world-readable).
- [ ] **Code Hygiene & Standards:**
  - [ ] Automated linter passed with zero errors.
  - [ ] Static type-checker (if applicable) passed cleanly.
  - [ ] No dead code, debug logging, or commented-out blocks left behind.
- [ ] **Documentation & Handoff Updated:**
  - [ ] Root `HANDOFF.md` updated with branch status and milestone progress.
  - [ ] Subdirectory `HANDOFF.md` (if applicable) synchronized.
  - [ ] Relevant README or API schema documentation updated.

---

## 4. Deploy & Runtime Audit (Required if Touching Staging or Production)

- [ ] **Backup Verification:**
  - [ ] Full backup or snapshot generated and verified (file size non-zero, checksum valid) before state change.
  - [ ] Backup path and restoration command recorded in the audit log.
- [ ] **Rollback Validation:**
  - [ ] Rollback procedure tested in non-production or dry-run mode.
  - [ ] Verified that aborting deployment leaves the system in a known good state.
- [ ] **Deployment Observation:**
  - [ ] Deploy agent posted `ACTION` prior to execution.
  - [ ] Deploy agent posted `RESULT` with return code and output immediately after execution.
- [ ] **Live Health & Telemetry Verification:**
  - [ ] HTTP health endpoints return `200 OK` (e.g., `/health`, `/ready`).
  - [ ] Container / service status checked (`systemctl status`, `docker compose ps` shows healthy with zero unhandled crash loops).
  - [ ] System error logs inspected (`journalctl`, container logs) showing zero new errors or panics.
  - [ ] Performance metrics (CPU, memory, latency) remain within baseline boundaries.

---

## 5. QA Overwatch Verdict

### Evaluation Summary
`<Detailed rationale explaining why the workstream passes or fails the audit criteria. Highlight any specific test results, code snippets, or verification evidence.>`

### Decision Block

```text
======================================================================
QA VERDICT: [ APPROVE | HOLD ]
======================================================================
Branch / PR: <branch-name> (PR #<N>)
Status:      <APPROVED FOR MERGE / ROLLOUT | BLOCKED PENDING RESOLUTION>
Auditor:     <qa-agent-id>
Timestamp:   <YYYY-MM-DD HH:MM:SS UTC>

Action Items (if HOLD):
1. <Remediation item 1>
2. <Remediation item 2>
======================================================================
```
