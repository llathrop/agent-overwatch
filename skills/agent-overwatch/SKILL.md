---
name: agent-overwatch
description: >-
  Orchestrates high-velocity, parallel multi-agent engineering and operations
  workflows gated by mandatory independent QA overwatch, atomic Git/GitHub
  branching, cost-tiered model routing with fallback, and HANDOFF/AGENT_BUS
  coordination. Use when decomposing non-trivial tasks across parallel agents,
  enforcing independent verification gates, or coordinating multi-session teams.
---

# Agent Overwatch

A general-purpose multi-agent operating model that combines **parallel execution** of independent work with **mandatory independent QA** on every plan, code change, and deployment.

Source, agent prompts, and installer: https://github.com/llathrop/agent-overwatch. Paths such as `agents/qa-agent.md` or `install.sh` below refer to that repository, not to this installed skill folder.

## 1. Core Philosophy

Speed and reliability come from the same discipline:

1. **Split work into collision-free lanes** so multiple agents execute concurrently instead of queuing behind one serial bottleneck.
2. **Don't defer necessary independent work.** "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)." This means starting required work that has no dependency now. It does not mean inventing optional work to fill waiting time.
3. **Gate every milestone with independent, read-only QA.** High velocity only holds if defects, broken assumptions, and unverified rollouts are caught before merge or promotion.

---

## 2. Agent Roles & Mandatory QA Pairing

Assign every participant one clear role. Keep author/ops lanes and verification lanes strictly separated. Brief templates, checklists, QA permission recipes, and installer tool mappings are in [agent-roles.md](./references/agent-roles.md). The portable role prompts are `agents/research-agent.md`, `agents/dev-agent.md`, `agents/deploy-agent.md`, and `agents/qa-agent.md` in the repository (the installer copies them into your runtime's agents folder).

### 2.1 Coordinator / Orchestrator

- **When to use:** Any task spanning multiple files, domains, investigation paths, or execution phases (planning -> build -> verify -> deploy).
- **How to use:**
  1. **Check the coordinator lease first** (`scripts/coordinator_lease.sh status`; see section 4). Act only if you hold it or have claimed it.
  2. Decompose work into non-overlapping slices (by file, directory, service, branch, or question).
  3. Issue **self-contained briefs**: exact owned scope, off-limits files/systems, required inputs, verification criteria, and who receives the handoff next.
  4. Dispatch every independent required slice now, keep turns short, and route outputs directly to QA without paraphrasing away exact paths or raw logs.
  5. Post **self-contained user-facing progress updates** after each completed batch or phase (section 7).
- **Strict boundaries:** Do not write large diffs, run long debugging loops, or perform slow manual checks inline while workers wait. Never override or bypass a `QA HOLD`. **Never write, paraphrase, or relay a QA verdict**: QA posts its own. Never run commands that QA was denied on QA's behalf.
- **Mandatory QA pairing:** Scale QA to the review load so verification doesn't queue. Track every deliverable through `QA APPROVE` before allowing implementation on a plan, merge of a branch, or promotion of a release.

### 2.2 Research / Planner Agent (`research-agent`)

- **When to use:** Codebase exploration, root-cause investigation, upgrade/compatibility analysis, RFCs, security audits, or trade-off comparisons before implementation or rollout.
- **How to use:** Dispatch with specific questions and target scopes. Require exact file paths, line numbers, verified command/API facts, failure modes, validation gates, and rollback plans.
- **Strict boundaries:** **Read-only.** Never edits production/source files, never applies infrastructure changes, and never presents inferred behavior as verified fact.
- **Mandatory QA pairing:** **Pre-execution audit.** Before `dev-agent` writes code or `deploy-agent` touches runtime state, `qa-agent` audits the plan for wrong assumptions, race/ordering hazards, missing edge cases, testability, and rollback completeness.

### 2.3 Development / Author Agent (`dev-agent`)

- **When to use:** Writing features, bug fixes, tests, refactoring, IaC/configs, CI pipelines, or documentation.
- **How to use:** Assign one atomic branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`) and a non-overlapping file scope. Isolate concurrent `dev-agent` instances with strict file ownership or separate `git worktree` checkouts.
- **Strict boundaries:** Edit only assigned files/worktree; run relevant tests/linters before handoff; never commit credentials or push/merge unreviewed work; never deploy directly to shared production unless explicitly scoped.
- **Mandatory QA pairing:** **Pre-merge audit (logic & direction only).** Before any branch merges to `main`, `dev-agent` runs tests/linters and posts the raw outputs; `qa-agent` inspects the full diff, logic, architecture, edge cases, secret hygiene, and posted test evidence (never running tests or builds itself), and posts `QA APPROVE` or `QA HOLD` bound to `<branch>@<sha12>`. Any new commit after an approval needs re-review.

### 2.4 Deployment / Operations Agent (`deploy-agent`)

- **When to use:** Package/container upgrades, runtime config rollouts, database migrations, infrastructure provisioning, or live environment verification.
- **How to use:** Dispatch with an approved plan. Always snapshot/backup pre-change state first, apply the minimum atomic change, execute smoke/soak checks, and keep rollback scripts verified. During a live rollout, run `scripts/overwatch_watch.sh` so QA is woken by real events (section 3).
- **Strict boundaries:** Never deploy an unapproved plan or skip pre-change backups. Never rewrite application architecture mid-rollout; stop and roll back if stop-criteria trigger.
- **Mandatory QA pairing:** **Two-stage ops audit (logic & direction only).** Pre-deploy: `qa-agent` audits posted backup integrity, dry-run output, and rollback readiness. Post-deploy: `deploy-agent` runs live probes and posts health/log outputs; `qa-agent` audits those posted outputs and `overwatch_watch.sh` events (never logging into hosts or running probes itself), issuing `QA HOLD` to direct `deploy-agent` if any check is missing.

### 2.5 Mandatory QA / Overwatch Agent (`qa-agent`)

- **When to use:** Across every active lane: planning, coding, and operations.
- **How to use:** `qa-agent` performs **logic, architecture, and direction review only**. Point QA at the plan, branch/diff (`git diff`, `git log`, `git rev-parse`), and posted test/deploy outputs; QA writes its **own** binary verdict with `scripts/bus_append.sh --type "QA APPROVE" --ref auto` (or `"QA HOLD"`), citing reviewed files (`file:line`) and verified posted outputs.
- **Strict boundaries:** **Zero-trust, read-only, and never runs tests or probes.** Never edits source code, never patches configs, never deploys, and never runs test suites, linters, builds, Docker containers, or live probes itself — issue `QA HOLD` to direct `dev-agent` or `deploy-agent` whenever a check is needed. Enforce read-only with the runtime's tool restrictions (see [agent-roles.md](./references/agent-roles.md)). If QA is denied an inspection command, it says so and verifies from posted evidence; it never works around the denial.
- **Cross-role pairing loop:** Audits `research-agent` plans pre-execution, `dev-agent` diffs and tests pre-merge, and `deploy-agent` backups/rollouts pre- and post-deploy, escalating blockers to the originating lane and Coordinator.

---

## 3. Horizontal Scaling & Non-Dependent Work

- **Scale horizontally on demand:** Launch `research-1..N`, `dev-1..N`, `deploy-1..N`, and `qa-1..N` whenever required tasks partition cleanly without colliding on the same files, ports, locks, or mutable hosts.
- **Scale QA to the review load** so verification doesn't queue behind implementation.
- **Non-dependent work rule:** "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)." Do not create speculative or optional work just to fill time. Every lane still obeys strict file ownership and mandatory QA.
- **Live overwatch needs a watcher:** Subagents end their turns, so a QA agent cannot "keep watching" a deploy by itself. Run `scripts/overwatch_watch.sh --once` under a background watcher (any monitor, cron job or shell loop), with `--check '<health cmd>'` probes and the secret allowlist, and wake QA on each `BUS:`, `SECRET?`, or `CHECK-FAIL` line it prints.

See [model-routing-and-scaling.md](./references/model-routing-and-scaling.md) for sharding patterns and scheduling tables.

---

## 4. Coordination Files & Supersession Rules

Use explicit artifacts to preserve shared state across turns, compactions, and sessions (schemas in [coordination-files.md](./references/coordination-files.md)):

| Artifact | Purpose | Write Rule |
| --- | --- | --- |
| `HANDOFF.md` | Living current state: architecture, active branches, risks, ordered next steps | Coordinator/lead only; keep it short (≤200 chars per cell or bullet, ~150 lines). Detail goes to the bus |
| `AGENT_BUS.md` | Append-only log (`BRIEF`, `ACTION`, `RESULT`, `QA APPROVE`/`HOLD`, `TAKEOVER`, `USAGE`) | Read the tail first; append with `scripts/bus_append.sh` (it stamps the UTC time; never hand-type timestamps) |
| `status/coordinator.lease` | Which session is the active coordinator | Only through `scripts/coordinator_lease.sh claim\|renew\|release\|status` |
| `QA_BUS.md` *(optional)* | Optional separate local ledger when QA traffic is high (also untracked) | Same append rule; cross-reference from `AGENT_BUS.md` |
| `status/<agent>.md` *(optional)* | Per-agent snapshot for quick status scans | Each agent updates **only its own** file |

- **Coordinator lease and takeover:** Every session runs `coordinator_lease.sh status` before acting. To replace a stale coordinator, `claim --takeover` (this posts a `TAKEOVER` entry). A returning session that finds itself replaced stands down or coordinates on the bus; it does not resume acting.
- **The bus is local, not committed:** `AGENT_BUS.md` is git-ignored (`init_workspace.sh` adds it to `.gitignore`). It is live coordination on one machine, not an audit trail in git and never pushed. With parallel worktrees, point every agent at the one shared copy with `--bus <path>`. `HANDOFF.md` is the tracked file; cross-machine handoff goes through it.
- **Secret-scan false positives:** List allowed patterns in `.overwatch/secret-allowlist`. Report hits as `file:line` plus the pattern name, never the value.

### Built-In Tool Supersession (Mandatory)

- **Native messaging/board tools win for live coordination:** If your runtime provides a built-in swarm message board or agent-to-agent messaging tool (for example a swarm message board, a `send_message` tool, or native agent teams), **use it instead of `AGENT_BUS.md` for live turn-to-turn handoffs**.
- **When `AGENT_BUS.md` is used:** When no native board exists (plain CLI sessions, multi-tool handoffs), or when `verify_atomic_branch.sh` must find QA verdicts in a ledger.

### Subdirectory Scoping (Monorepos & Nested Projects)

- Give an independent subproject its own `<subproject>/HANDOFF.md` and `<subproject>/AGENT_BUS.md` when it has an independent release cycle, architecture, or active agent stream.
- Keep the **root `HANDOFF.md` thin**: summarize workspace-wide rules and link to child `HANDOFF.md` files instead of duplicating per-service state.
- Agents inside a subproject update that subproject's files; update the root only when shared interfaces, workspace priorities, or cross-project status change.

---

## 5. Model Cost Tiering, Fallback & Usage Awareness

Match model cost and reasoning depth to the cognitive risk of each role. Tiers are defined by capability (details and vendor examples in [model-routing-and-scaling.md](./references/model-routing-and-scaling.md)):

| Tier | Capability | Best Fit Roles & Tasks |
| --- | --- | --- |
| **Economy** | Small, fast, low-cost | Log parsing, file/inventory checks, status formatting, boilerplate scaffolding |
| **Standard** | Balanced general-purpose | Routine `dev-agent` features/tests, documentation, standard `deploy-agent` runbooks |
| **Frontier** | Strongest reasoning available | **Mandatory `qa-agent` overwatch**, subtle debugging, security audits, complex `research-agent` architecture |

**Graceful Fallback Rule (Mandatory):** If tiered model selection is unavailable, restricted by platform/orchestrator policy (for example, inherit-only swarm workers), or blocked by quota, **run all agents on the default/inherited model**. Never stall waiting on a specific tier when the default model is healthy.

**Usage & budget awareness:**

- If the runtime exposes usage or spend numbers (a usage/limits command, statusline cost data, a budget API, token-target directives), track them and warn the user as limits approach (around 75% and 90%), stating which lanes are still running. Optionally log a `USAGE` bus entry.
- If no usage numbers are available, ignore this rule. Don't guess and don't throttle.
- On a rate limit (HTTP 429 or equivalent), pause and record the state in `HANDOFF.md` (running lanes, branches, pending verdicts) so another session can resume.

---

## 6. Git & Remote Repository Workflow

Deliver in small, independently verifiable increments (full playbook in [git-and-github-workflow.md](./references/git-and-github-workflow.md)):

1. **Atomic Branches:** Cut a short-lived branch per cohesive unit (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `ops/<topic>`). Parallel authors use isolated `git worktree` directories.
2. **Incremental QA-Gated Merge:** Finish one atomic change -> run checks -> QA posts `QA APPROVE <branch>@<sha12>` -> `scripts/verify_atomic_branch.sh` passes -> **merge to `main`** -> cut the next branch from updated `main`. The gate fails without a matching QA verdict for the current HEAD unless `--allow-external-qa` is passed explicitly (for QA recorded outside the bus, such as a PR review).
3. **Own Repositories & Own Forks (GitHub / GitLab):** Open or link an Issue, push the branch, open a PR referencing it (`Closes #N`) with test evidence and the QA verdict ref, and merge once CI + QA pass.
4. **Public / Upstream Repositories (Strict Safety Guardrail):**
   - Follow the project's `CONTRIBUTING.md`, style guides, tests, and issue/PR templates.
   - **ALWAYS ask the user for explicit confirmation BEFORE any action that affects the remote upstream**: opening/commenting on upstream issues, pushing branches to shared/upstream remotes, or opening/updating Pull Requests.

---

## 7. Live User-Facing Progress Updates

Keep the user informed in plain, self-contained summaries as agents launch and finish work phases:

- **Report as you go, not just at the end:** Summarize whenever a batch, branch, or QA gate finishes and when dispatching the next lanes.
- **Never assume shared internal context:** The user may not see subagent messages, swarm boards, raw logs, or `AGENT_BUS.md`. Every update must stand on its own without cryptic internal IDs.
- **Each milestone update covers:** (1) what changed and why, including key tradeoffs; (2) what QA caught and how it was fixed; (3) verification evidence as a concise pass/fail summary; (4) what runs next and any decision needed from the user. Include usage warnings when section 5 applies.
- **Strict boundary:** Never paste secrets, tokens, keys, or raw credential values into progress messages.

---

## 8. Reference & Tooling Library

- [references/agent-roles.md](./references/agent-roles.md): brief templates, anti-patterns, per-role QA checklists, QA permission recipes, installer tool mappings and install options
- [references/coordination-files.md](./references/coordination-files.md): `HANDOFF.md` / `AGENT_BUS.md` schemas, verdict format, coordinator lease, size caps, supersession matrix, monorepo scoping
- [references/git-and-github-workflow.md](./references/git-and-github-workflow.md): verdict-gated merge cycle, parallel worktrees, local (untracked) bus, GitHub CLI/PR flow, upstream safety gates
- [references/model-routing-and-scaling.md](./references/model-routing-and-scaling.md): model tiers, fallback, usage & budget awareness, sharding, non-dependent work
- [templates/](./templates/): [HANDOFF.template.md](./templates/HANDOFF.template.md), [SUBDIR_HANDOFF.template.md](./templates/SUBDIR_HANDOFF.template.md), [AGENT_BUS.template.md](./templates/AGENT_BUS.template.md), [QA_CHECKLIST.template.md](./templates/QA_CHECKLIST.template.md)
- [scripts/init_workspace.sh](./scripts/init_workspace.sh): scaffolds root or `--subdir` workspaces (`--no-bus`, `--dry-run`, `--force`), including the `.gitignore` entry for the local bus, the lease placeholder, and `.overwatch/secret-allowlist`
- [scripts/verify_atomic_branch.sh](./scripts/verify_atomic_branch.sh): pre-merge gate for branch isolation, clean tree, diff scope, per-commit secret scan, and a QA verdict matching `<branch>@<sha>` (`--allow-external-qa` to override)
- `scripts/bus_append.sh`: atomic, timestamped, secret-checked bus append (`--from --to --type --subject [--ref auto]`, body on stdin)
- `scripts/overwatch_watch.sh`: event watcher for live overwatch (`--once`, `--check 'CMD'`, `--allowlist FILE`, `--interval SEC`)
- `scripts/coordinator_lease.sh`: coordinator lease (`claim|renew|release|status`, `--takeover`, `--ttl MIN`)
- Installer (repository root `install.sh`): installs adapters for several agent runtimes and GitHub templates. `--link` symlinks so `git pull` updates the install and `--uninstall` removes it. Per-tool details are in the adapter reference at the end of [agent-roles.md](./references/agent-roles.md) and in `examples/<tool>/`.
