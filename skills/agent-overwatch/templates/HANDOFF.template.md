# HANDOFF: <PROJECT_NAME> (Living Summary)

**Last Updated:** `<YYYY-MM-DD HH:MM UTC>`  
**Active Integration Branch:** `<branch-name>` (e.g., `main` or `epic/<feature-name>`)  
**Overall System Status:** `<STATUS_BADGE>` (e.g., `GREEN` / `YELLOW - In Migration` / `RED - Incident`)

> **Purpose:** This file is the single source of truth for repository state, workstream status, and inter-agent handoffs. Any newly spawned agent (or human engineer) must read this file first to resume or coordinate work without context loss. Keep this document current on every significant state change or milestone.

> **Size caps:** keep each cell/bullet ≤ 200 chars; push detail to AGENT_BUS.md; whole file ≤ ~150 lines.

---

## Repository & Architectural Overview

- **Repository Root:** `<workspace-root-or-relative-path>`
- **Core Mission:** `<1-3 sentence summary of what this repository builds, deploys, or manages>`
- **Architecture Highlights:**
  - `<Core architectural pattern: e.g., microservices, monorepo, event-driven, CLI tool, client-server>`
  - `<Primary languages, frameworks, runtime versions>`
- **Security & Secrets Policy:**
  - **NEVER** commit secrets, private keys, API tokens, passwords, or personally identifiable information (PII) to this file or any Git-tracked file.
  - Pass secrets strictly via environment variables, secret managers, or standard input streams.
  - Before committing or requesting QA sign-off, run the local secret-scan gate.

---

## Coordinator

- **Lease file:** `status/coordinator.lease`, written only by `coordinator_lease.sh`. Never hand-edit it. Keys (key=value): `id`, `since`, `last_seen` (UTC, `YYYY-MM-DD HH:MM:SS UTC`), `ttl_min` and `last_seen_epoch`. A lease with only `id`/`since`/`last_seen` is read with ttl 30.
- **Check it before acting:** `coordinator_lease.sh status` (exit 0 = you hold it, 3 = another live session holds it, 4 = expired or none).
- **Hold it while coordinating:** `coordinator_lease.sh claim`, then `renew` at least every `ttl_min` minutes (set `AO_COORDINATOR_ID` for a stable id).
- **Takeover rule:** take over a live lease only when its holder is known to be gone, with `coordinator_lease.sh claim --takeover`, which posts a `TAKEOVER` bus entry. A returning coordinator that finds exit 3 must stop, read this file and the bus tail, and post before touching `main`.
- **Watcher:** `overwatch_watch.sh --once` (or looped under a background watcher) prints `LEASE stale: ...` when the lease expires.

---

## 1. Target Systems & Environments

| Environment / Host | Role / Purpose | Access / Protocol | State / Health URL | Notes & Constraints |
|---|---|---|---|---|
| `dev` / `local` | Local development workspace | Local CLI / Shell | `http://localhost:<port>` | Sandbox environment; clean git working tree required. |
| `staging` | Pre-production integration | SSH / VPN / CI | `https://staging.<domain>` | Mirrors production configuration; sanitized test data only. |
| `production` | Live system | Controlled Deploy Gate | `https://<domain>/health` | Strict change management: requires QA `APPROVE` + rollback plan. |

---

## 2. Mandatory Workflow & QA Rules

1. **Role Separation:**
   - **Dev Agents:** Formulate plans, author code, write unit/integration tests, update documentation. Dev agents **do not** deploy directly to production.
   - **Deploy Agents:** Execute runtime operations, container rollouts, migrations, and infrastructure commands. Always announce intent before state-changing actions.
   - **QA Overwatch Agent:** Independent verification gate. Skeptical by default; trusts no claims without reproducible test output, diff review, secret scans, and live health verification. QA holds unilateral veto (`HOLD`) power.
   - **Research Agents:** Gather background context, investigate upstream issues, assess security advisories, and document findings without mutating code.
2. **Atomic Branching & Parallel Execution:**
   - Independent workstreams **must** run on separate, dedicated feature branches: `feat/<workstream-name>` or `fix/<issue-name>`.
   - Never cross-contaminate concurrent workstreams. Branch from the agreed integration base.
   - Merge incrementally: once QA approves an atomic branch, merge it into integration base immediately to avoid long-lived divergent rebases.
3. **Safety & Rollback Gates:**
   - Always verify a clean rollback strategy before any state-changing execution (`git revert`, snapshot restore, container rollback).
   - If a rollback command has not been documented and tested, the change is blocked.
4. **Coordination Bus:**
   - Keep communication transparent. If your agent platform provides built-in messaging (e.g., `send_message` or a swarm board), use it.
   - If running in headless/multi-process CLI environments, use the project's append-only `AGENT_BUS.md`.

---

## 3. Workstreams & Atomic Branch Status

| Workstream ID | Description | Active Branch | Assigned Agent(s) | Status (`PENDING` / `IN_PROGRESS` / `QA_READY` / `DONE`) | Evidence & Deliverables | Next Step / Blocker |
|---|---|---|---|---|---|---|
| `WS-01` | `<Feature description>` | `feat/<name>` | `<agent-id>` | `IN_PROGRESS` | Unit test suite passing; PR `#<N>` drafted. | Complete integration tests & request QA audit. |
| `WS-02` | `<Bugfix description>` | `fix/<name>` | `<agent-id>` | `QA_READY` | Diff clean; secret scan clean; staging verification logs linked. | Awaiting QA Overwatch `APPROVE`. |
| `WS-03` | `<Refactor description>` | `refactor/<name>` | `<agent-id>` | `PENDING` | Architectural spec approved. | Unblocked once `WS-01` merges. |

---

## 4. Subdirectory `HANDOFF.md` Index

When a sub-package, service, or module within this repository has its own localized build lifecycle, independent deploy targets, or dedicated sub-agent teams, maintain a nested `HANDOFF.md` inside that directory.

| Subdirectory Path | Domain / Responsibility | Local Handoff File *(make it a relative link once the file exists)* | Scope & Boundary Summary |
|---|---|---|---|
| `services/<service-a>/` | `<Backend API service>` | `services/<service-a>/HANDOFF.md` | Self-contained backend microservice; owns its own Dockerfile and database migrations. |
| `frontend/` | `<Web application client>` | `frontend/HANDOFF.md` | Web SPA client; consumes mock API in local dev, backend in staging. |
| `infra/terraform/` | `<Cloud infrastructure>` | `infra/terraform/HANDOFF.md` | Terraform state & modules; restricted deploy rules apply. |

*Guidelines for Subdirectory Handoffs:*
- The root `HANDOFF.md` governs global repo status, integration branches, and cross-cutting rules.
- Local `HANDOFF.md` files govern module-specific tasks, local build commands, and component-level status.
- Every nested `HANDOFF.md` must link back to this root document.

---

## 5. Open Questions & Decision Log

### Active Questions Requiring Clarification
- [ ] **Q1:** `<Question statement, trade-offs under consideration, and impact on timeline/architecture>`
- [ ] **Q2:** `<Question statement regarding third-party API / credential / upstream dependency>`

### Recorded Decisions (Historical Record)
- **`<YYYY-MM-DD>` — `<Decision Title>`:** `<Summary of decision made, rationale, alternatives rejected, and authorizing user/lead>`
- **`<YYYY-MM-DD>` — `<Decision Title>`:** `<Summary of decision made>`

---

## 6. Active Agents & Current Assignments

| Agent Identifier | Role / Persona | Model / Platform | Active Workstream | Current Step / Ownership | Status File / Channel |
|---|---|---|---|---|---|
| `qa-overwatch` | QA Overwatch | standard tier | All | Auditing PRs and validating test runs | Built-in messaging / `AGENT_BUS.md` |
| `dev-lead` | Lead Developer | standard tier | `WS-01` | Implementing core business logic | Branch `feat/core-logic` |
| `dev-worker-1` | Sub-Developer | economy tier | `WS-02` | Writing unit tests and edge cases | Branch `fix/edge-cases` |
| `deploy-ops` | Deploy Specialist | standard tier | `WS-01` | Staging deployment preparation | Staging host / container logs |

---

## 7. Helper Scripts & Verification Gates

Run these commands locally before marking any workstream ready for QA audit:

```bash
# 1. Code quality, formatting, and linting
make lint          # or: npm run lint / ruff check . / golangci-lint run

# 2. Automated test suite (unit + integration)
make test          # or: pytest -v / npm test / go test ./...

# 3. Secret scan (mandatory zero-leak check)
git diff main...HEAD | grep -iE 'password|secret|api[_-]?key|bearer|token' || echo "Secret scan clean."

# 4. Working tree hygiene
git status --short # Ensure no untracked artifacts, temporary files, or credential files remain
```
