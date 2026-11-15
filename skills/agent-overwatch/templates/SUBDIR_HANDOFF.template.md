# SUBDIRECTORY HANDOFF: <SUBDIR_PATH> (Module Summary)

**Parent Repository Root Handoff:** `[Root HANDOFF.md](../../HANDOFF.md)` *(adjust relative depth and remove backticks when instantiating)*  
**Last Updated:** `<YYYY-MM-DD HH:MM UTC>`  
**Active Module Branch:** `<branch-name>`  
**Module Status:** `<STATUS_BADGE>` (e.g., `GREEN` / `IN_PROGRESS` / `BLOCKED`)

> **Notice:** This document is the localized handoff for the `<SUBDIR_PATH>` sub-package. It details local runtime boundaries, isolated test suites, and sub-workstreams. Global policies and repo-wide integration branch statuses are maintained in the root `HANDOFF.md`.

---

## 1. Scope & Architectural Boundaries

### What Belongs in `<SUBDIR_PATH>`
- `<Explicit list of files, directories, features, and assets owned by this module>`
- `<Local Dockerfile, package.json, Cargo.toml, go.mod, or pyproject.toml>`
- `<Component-specific unit and integration test fixtures>`

### What Belongs to Parent / Sibling Modules (DO NOT TOUCH HERE)
- `<Parent orchestrations, root CI/CD pipelines, or global configuration>`
- `<Sibling packages, e.g., shared backend models if this is the frontend client>`
- `<External secrets, infrastructure state files, or production deployment keys>`

---

## 2. Local Stack & Environment

| Component | Technology / Version | Configuration Source | Local Runtime URL / Port |
|---|---|---|---|
| Runtime Engine | `<e.g., Node.js 20 LTS / Python 3.12 / Go 1.22>` | `.nvmrc` / `runtime.txt` | N/A |
| Local Server / Service | `<e.g., Vite Dev Server / FastAPI / Gin>` | `vite.config.ts` / `.env.local` | `http://localhost:<port>` |
| Test Runner | `<e.g., Vitest / Pytest / Go test>` | `vitest.config.ts` | CLI |
| Mock / Dependencies | `<e.g., Local SQLite / WireMock / Redis>` | `docker-compose.local.yml` | `localhost:<port>` |

---

## 3. Local Branching & QA Verification Rules

1. **Sub-Branch Hygiene:**
   - Develop module changes on branches isolated to this sub-tree: `feat/<subdir-name>-<feature-slug>`.
   - Never modify sibling directories on this branch unless coordinated via a root workstream.
2. **Local Verification Gate:**
   - All local tests, type-checks, and linters must pass with zero errors or unhandled warnings before requesting QA review.
3. **QA Overwatch Review:**
   - Any pull request touching this subdirectory must be audited by the QA Overwatch agent against both local test suites and parent integration health.
4. **Local Coordination Bus:**
   - If this subdirectory operates with an independent sub-agent swarm and a local log is required (when no built-in messaging/board supersedes it), append entries atomically to `[AGENT_BUS.md](./AGENT_BUS.md)`. Otherwise, coordinate via the native tool or root coordination mechanism.

---

## 4. Subdirectory Workstreams

| Workstream ID | Task Description | Branch | Owner / Agent | Status | Local Deliverables | Next Action |
|---|---|---|---|---|---|---|
| `SUB-01` | `<Component feature implementation>` | `feat/<name>` | `<agent-id>` | `IN_PROGRESS` | Component test suite written | Implement component logic |
| `SUB-02` | `<Performance optimization>` | `perf/<name>` | `<agent-id>` | `QA_READY` | Benchmark results in `BENCHMARK.md` | Request QA review |

---

## 5. Local Verification Commands

Run these commands inside `<SUBDIR_PATH>` before committing:

```bash
# Navigate to this module
cd <SUBDIR_PATH>

# 1. Install local dependencies (frozen lockfile)
npm ci || pip install -r requirements-dev.txt || go mod download

# 2. Run local linter & type-checker
npm run lint && npm run typecheck || ruff check . || golangci-lint run

# 3. Execute local tests with coverage
npm test -- --coverage || pytest --cov=. || go test -v -cover ./...

# 4. Local build validation
npm run build || python -m build || go build ./...
```
