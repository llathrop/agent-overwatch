# QA Overwatch Verification Checklist

**Audit Date:** `<YYYY-MM-DD HH:MM UTC>`  
**Auditor (QA Agent ID):** `<qa-agent-id>`  
**Target Pull Request / Branch:** `PR #<N>` (`<branch-name>` -> `<target-branch>`)  
**Workstream ID:** `<WS-ID>`  
**Reviewed Commit:** `<branch-name>@<sha12>` (the exact HEAD you tested; any later commit needs a new review)  
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
  - [ ] `verify_atomic_branch.sh --repo . --base <target>` secret scan clean: it checks the final files AND the lines added by every commit in `merge-base..HEAD`, so a credential added and later deleted still fails (rewrite history and rotate the credential).
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

### Evidence (required for every verdict)
List every command you ran yourself against `<branch-name>@<sha12>` and what it returned. Do not restate the author's claims as evidence.

| # | Command | Exit code | Result (counts / key lines) |
|---|---------|-----------|-----------------------------|
| 1 | `<e.g. tests/test_foo.sh>` | `0` | `<passed: N failed: 0>` |
| 2 | `<e.g. shellcheck scripts/*.sh>` | `0` | `<no findings>` |
| 3 | `verify_atomic_branch.sh --repo . --base <target> --qa-file <ledger>` | `<0/1>` | `<gate summary>` |

### Evaluation Summary
`<Rationale for the decision, tied to the evidence rows above. For HOLD, list numbered remediation items.>`

### Posting the Verdict (QA writes it; the coordinator never relays it)
QA appends its own verdict to the ledger with `bus_append.sh`. The header is bound to the exact branch and commit, and the author role must contain `qa`:

```bash
./skills/agent-overwatch/scripts/bus_append.sh --bus AGENT_BUS.md --repo <worktree> \
  --from <qa-role> --to <dev-role>,coordinator --type "QA APPROVE" \
  --subject "<short reason>" --ref auto <<'EOF'
Evidence:
1. `<command>` -> exit 0, <result>
2. `<command>` -> exit 0, <result>
EOF
```

This writes:

```text
### [YYYY-MM-DD HH:MM:SS UTC] <qa-role> -> <to> | QA APPROVE <branch>@<sha12> <subject>
```

Use `--type "QA HOLD"` to block. `verify_atomic_branch.sh` takes the **latest** verdict for the current branch: a HOLD blocks, and an APPROVE passes only if its sha matches HEAD (prefix >= 7). New commits after an APPROVE require a fresh review and a new verdict.

### Decision Block

```text
======================================================================
QA VERDICT: [ APPROVE | HOLD ]
======================================================================
Branch@SHA:  <branch-name>@<sha12> (PR #<N>)
Status:      <APPROVED FOR MERGE / ROLLOUT | BLOCKED PENDING RESOLUTION>
Auditor:     <qa-role>
Timestamp:   <stamped by bus_append.sh>
Bus entry:   <header line printed by bus_append.sh>

Action Items (if HOLD):
1. <Remediation item 1>
2. <Remediation item 2>
======================================================================
```
