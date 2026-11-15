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

A general-purpose multi-agent operating model that combines **parallel execution** and **continuous non-blocking dispatch** with **mandatory independent QA** on every plan, code change, and deployment.

## 1. Core Philosophy

Speed and reliability come from the same discipline:

1. **Split work into collision-free lanes** so multiple agents execute concurrently instead of queuing behind one serial bottleneck.
2. **Never sit idle on a slow dependency** — whenever one lane blocks on long tests, builds, research, or soak checks, immediately dispatch non-dependent work to separate lanes.
3. **Gate every milestone with independent, read-only QA.** High velocity only holds if defects, broken assumptions, and unverified rollouts are caught before merge or promotion.

---

## 2. Agent Roles & Mandatory QA Pairing

Assign every participant one clear role. Keep author/ops lanes and verification lanes strictly separated. For brief templates, checklists, and installer tool mappings, see [agent-roles.md](./references/agent-roles.md). Portable agent prompts live under [agents/](../../agents/).

### 2.1 Coordinator / Orchestrator

- **When to use:** Any task spanning multiple files, domains, investigation paths, or execution phases (planning -> build -> verify -> deploy).
- **How to use:**
  1. Decompose work into non-overlapping slices (by file, directory, service, branch, or question).
  2. Issue **self-contained briefs**: exact owned scope, off-limits files/systems, required inputs, verification criteria, and who receives the handoff next.
  3. Dispatch parallel workers immediately, keep turns short, monitor status, and route outputs directly to QA without paraphrasing away exact paths or raw logs.
  4. Post **self-contained user-facing progress updates** after each completed batch or phase (never waiting until everything finishes or assuming the user reads internal agent messages or `AGENT_BUS.md`).
- **Strict boundaries:** Do not write large diffs, run long debugging loops, or perform slow manual checks inline while workers wait. Never override or bypass a `QA HOLD`.
- **Mandatory QA pairing:** Maintain roughly **1 `qa-agent` per 2–4 active workers**. Track every deliverable through `QA APPROVE` before allowing implementation on a plan, merge of a branch, or promotion of a release.

### 2.2 Research / Planner Agent (`research-agent`)

- **When to use:** Codebase exploration, root-cause investigation, upgrade/compatibility analysis, RFCs, security audits, or trade-off comparisons before implementation or rollout.
- **How to use:** Dispatch with specific questions and target scopes in [agents/research-agent.md](../../agents/research-agent.md). Require exact file paths, line numbers, verified command/API facts, failure modes, validation gates, and rollback plans.
- **Strict boundaries:** **Read-only.** Never edits production/source files, never applies infrastructure changes, and never presents inferred behavior as verified fact.
- **Mandatory QA pairing:** **Pre-execution audit.** Before `dev-agent` writes code or `deploy-agent` touches runtime state, `qa-agent` audits the research/plan for wrong assumptions, race/ordering hazards, missing edge cases, testability, and rollback completeness.

### 2.3 Development / Author Agent (`dev-agent`)

- **When to use:** Writing features, bug fixes, tests, refactoring, IaC/configs, CI pipelines, or documentation.
- **How to use:** Assign one atomic branch (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`) and non-overlapping file scope via [agents/dev-agent.md](../../agents/dev-agent.md). When running multiple `dev-agent` instances concurrently, isolate them via strict file ownership or separate `git worktree` checkouts.
- **Strict boundaries:** Edit only assigned files/worktree; run relevant tests/linters before handoff; never commit credentials or push/merge unreviewed work; never deploy directly to shared production unless explicitly scoped.
- **Mandatory QA pairing:** **Pre-merge audit.** Before any branch merges to `main`, `qa-agent` inspects the full diff, checks test/lint evidence, audits edge cases and secret hygiene, and emits `APPROVE` or `HOLD`.

### 2.4 Deployment / Operations Agent (`deploy-agent`)

- **When to use:** Package/container upgrades, runtime config rollouts, database migrations, infrastructure provisioning, or live environment verification.
- **How to use:** Dispatch with an approved plan via [agents/deploy-agent.md](../../agents/deploy-agent.md). Always snapshot/backup pre-change state first, apply the minimum atomic change, execute smoke/soak checks, and keep rollback scripts verified.
- **Strict boundaries:** Never deploy an unapproved plan or skip pre-change backups. Never rewrite application architecture mid-rollout; stop and roll back if stop-criteria trigger.
- **Mandatory QA pairing:** **Two-stage ops audit.** Pre-deploy: `qa-agent` checks backup integrity, dry-run output, and rollback readiness. Post-deploy: `qa-agent` independently audits live health checks, logs, permissions, and secret hygiene.

### 2.5 Mandatory QA / Overwatch Agent (`qa-agent`)

- **When to use:** Continuously across every active lane — planning, coding, and operations.
- **How to use:** Spawn via [agents/qa-agent.md](../../agents/qa-agent.md) (one QA per 2–4 workers). Point QA directly at the plan, branch/diff, test logs, or live read-only checks. Require a binary **`APPROVE`** or **`HOLD`** verdict citing exact file paths, line numbers, and command outputs.
- **Strict boundaries:** **Zero-trust and strictly read-only on deliverables.** Never edits source code, never patches configs to "help out", and never deploys. Defects go back to the originating agent so ownership stays clean and two agents never collide in one file.
- **Cross-role pairing loop:** Audits `research-agent` plans pre-execution, `dev-agent` diffs and tests pre-merge, and `deploy-agent` backups/rollouts pre- and post-deploy, escalating blockers cleanly to the originating lane and Coordinator.

---

## 3. Horizontal Scaling & Zero-Idle Parallelism

- **Scale horizontally on demand:** Launch `research-1..N`, `dev-1..N`, `deploy-1..N`, and `qa-1..N` whenever tasks partition cleanly without colliding on the same files, ports, locks, or mutable hosts.
- **Keep QA proportional:** Target **1 `qa-agent` per 2–4 active workers** so verification never queues behind implementation.
- **Non-Dependent Work Rule (Zero-Idle Dispatch):** Whenever any lane enters a slow or blocking step (full test suites, container builds, deep research, timed deploy soaks, CI waits), **immediately dispatch non-dependent work** to free or newly spawned agents — for example, drafting the next atomic RFC (`research-agent`), scaffolding tests or docs for another module (`dev-agent`), or auditing a completed sibling branch (`qa-agent`). Every side lane still obeys strict file ownership and mandatory QA.

See [model-routing-and-scaling.md](./references/model-routing-and-scaling.md) for sharding patterns and parallel scheduling tables.

---

## 4. Coordination Files & Supersession Rules

Use explicit artifacts to preserve shared state across turns, compactions, and sessions (schemas and templates in [coordination-files.md](./references/coordination-files.md)):

| Artifact | Purpose | Write Rule |
| --- | --- | --- |
| `HANDOFF.md` | Living current state: architecture, active branches, risks, ordered next steps | Updated on milestones/handoffs by coordinator or designated lead |
| `AGENT_BUS.md` | Append-only chronological log (`BRIEF`, `ACTION`, `RESULT`, `QA APPROVE`/`HOLD`) | Read tail first; **atomic heredoc append only** (`cat <<'EOF' >> AGENT_BUS.md`) |
| `QA_BUS.md` *(optional)* | Dedicated audit ledger when QA traffic is high | Same atomic append rule; cross-reference from `AGENT_BUS.md` |
| `status/<agent>.md` *(optional)* | Current per-agent snapshot for quick status scans | Each agent updates **only its own** file |

### Built-In Tool Supersession (Mandatory)

- **Native messaging/board tools win for live coordination:** If your runtime provides a built-in swarm message board or agent-to-agent messaging tool (e.g., Antigravity `swarm` `post_message` / `read_board`, `send_message`, or native agent teams), **use that native mechanism instead of `AGENT_BUS.md` for live turn-to-turn handoffs**.
- **When `AGENT_BUS.md` is used:** Keep `AGENT_BUS.md` when no native board exists (plain CLI sessions, multi-tool handoffs) or when the project requires a Git-committed chronological audit trail.

### Subdirectory Scoping (Monorepos & Nested Projects)

When a workspace hosts independent services, sub-packages, or nested project repositories under subdirectories:

- Give an independent subproject its own `<subproject>/HANDOFF.md` and `<subproject>/AGENT_BUS.md` whenever it has an independent release cycle, architecture, or active agent stream.
- Keep the **root `HANDOFF.md` thin**: summarize workspace-wide rules and link directly to child `<subproject>/HANDOFF.md` files instead of duplicating per-service state.
- **Update scope:** Agents executing inside a subproject update `<subproject>/HANDOFF.md` (and `<subproject>/AGENT_BUS.md` if file-bus mode is active); update root `HANDOFF.md` only when shared interfaces, workspace priorities, or cross-project status change.

---

## 5. Model Cost Tiering & Graceful Fallback

Match model cost and reasoning depth to the cognitive risk of each role (details in [model-routing-and-scaling.md](./references/model-routing-and-scaling.md)):

| Tier | Representative Models | Best Fit Roles & Tasks |
| --- | --- | --- |
| **Economy / Fast** | `flash_lite`, `flash`, `haiku`, `mini` | Log parsing, file/inventory checks, status formatting, boilerplate scaffolding |
| **Standard** | `sonnet`, `pro`, `gpt-4o` | Routine `dev-agent` features/tests, documentation, standard `deploy-agent` runbooks |
| **Frontier / Reasoning** | `opus`, `pro`, deep reasoning (`o3`) | **Mandatory `qa-agent` overwatch**, subtle debugging, security audits, complex `research-agent` architecture |

**Graceful Fallback Rule (Mandatory):** If tiered model selection is unavailable in your tool runtime, restricted by platform/orchestrator policy (e.g., inherit-only swarm workers unless the user explicitly overrides), or blocked by quota/rate limits, **drop differing-cost routing immediately and run all agents on the default/inherited model**. Never stall waiting on a specific tier when the default model is healthy.

---

## 6. Git & Remote Repository Workflow

Deliver cleanly in small, independently verifiable increments (full playbook in [git-and-github-workflow.md](./references/git-and-github-workflow.md)):

1. **Atomic Branches:** Cut a short-lived branch per cohesive unit (`feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `ops/<topic>`). Parallel authors use isolated `git worktree` directories.
2. **Incremental QA-Gated Merge:** Finish one atomic change -> run tests/checks -> obtain `qa-agent` `APPROVE` -> **merge immediately to `main`/`master`** -> cut the next branch from updated `main`. Never stockpile unmerged multi-step work on giant branches.
3. **Own Repositories & Own Forks (GitHub / GitLab):**
   - Open or link an Issue for the atomic task.
   - Push the feature branch and open a Pull/Merge Request referencing the Issue (`Closes #N`) with test evidence and QA sign-off.
   - Merge once CI + QA pass, then clean up the branch.
4. **Public / Upstream Repositories (Strict Safety Guardrail):**
   - Read and follow the project's `CONTRIBUTING.md`, style guides, tests, and issue/PR templates strictly.
   - **ALWAYS ask the user for clarification and explicit confirmation BEFORE taking any action that affects the remote upstream** — including opening/commenting on upstream issues, pushing branches to shared/upstream remotes, or opening/updating Pull Requests.

---

## 7. Live User-Facing Progress Updates

Keep the user continuously informed in plain, self-contained summaries as agents launch and finish work phases:

- **Report continuously, not just at the end:** Summarize progress whenever a meaningful batch, branch, or QA gate finishes and when dispatching the next parallel lanes.
- **Never assume shared internal context:** The user may not see native subagent messages, swarm boards, raw logs, or `AGENT_BUS.md`. State enough context so every update stands on its own without cryptic internal IDs.
- **What every milestone update should cover:**
  1. **What changed and why** — concrete deliverables, key technical decisions, and notable tradeoffs.
  2. **QA catches and fixes** — any bugs, failing checks, edge cases, or hygiene/secret issues caught by `qa-agent` and how the originating agent fixed them.
  3. **Verification evidence** — concise pass/fail summary of tests, syntax/lint checks, or health probes observed (no raw terminal log dumps).
  4. **What runs next** — active or newly dispatched parallel lanes and any decision/confirmation needed from the user.
- **Strict boundary:** Stay concise and never paste secrets, tokens, keys, or raw credential values into progress messages.

---

## 8. Reference & Tooling Library

- [references/agent-roles.md](./references/agent-roles.md) — Brief templates, anti-patterns, per-role QA checklists, and installer tool mappings
- [references/coordination-files.md](./references/coordination-files.md) — `HANDOFF.md` / `AGENT_BUS.md` schemas, supersession matrix, and monorepo scoping
- [references/git-and-github-workflow.md](./references/git-and-github-workflow.md) — Atomic merge cycle, parallel worktrees, GitHub CLI/PR flow, and upstream safety gates
- [references/model-routing-and-scaling.md](./references/model-routing-and-scaling.md) — Model tier matrix, quota/policy fallback, sharding, and non-dependent dispatch
- [templates/](./templates/) — Ready-to-copy [HANDOFF.template.md](./templates/HANDOFF.template.md), [SUBDIR_HANDOFF.template.md](./templates/SUBDIR_HANDOFF.template.md), [AGENT_BUS.template.md](./templates/AGENT_BUS.template.md), and [QA_CHECKLIST.template.md](./templates/QA_CHECKLIST.template.md)
- [scripts/init_workspace.sh](./scripts/init_workspace.sh) — Scaffolds root or `--subdir` workspaces (supports `--no-bus`, `--dry-run`, `--force`)
- [scripts/verify_atomic_branch.sh](./scripts/verify_atomic_branch.sh) — Enforces branch isolation, clean tree, diff scope, secret scan, and latest QA verdict pre-merge
- [install.sh](../../install.sh) — Cross-platform installer for Antigravity, Claude Code, Codex CLI, Gemini CLI, Cursor, and GitHub templates
