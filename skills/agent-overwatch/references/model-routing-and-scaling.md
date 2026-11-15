# Model Cost Routing, Graceful Fallback & Parallel Scaling

Guidelines for matching model capability to task risk, scaling workers horizontally without collisions, and dispatching non-dependent work continuously.

---

## 1. Model Tiering Matrix

Use cheaper/faster models for mechanical tasks and reserve high-reasoning frontier models for architecture, hard debugging, and independent QA — **when the active platform allows per-agent model selection**.

| Tier | Example Model Classes | Assigned Tasks & Roles | Why |
| --- | --- | --- | --- |
| **Economy / Fast** | `flash_lite`, `flash`, `haiku`, `mini` | File/tree inventories, log filtering, formatting/lint cleanup, boilerplate test stubs, quick status summarization | High token throughput, low latency and cost on deterministic/low-risk operations |
| **Standard** | `sonnet`, `pro`, `gpt-4o` | Routine `dev-agent` feature slices, unit tests, reference docs, standard `deploy-agent` checklist execution | Balanced reasoning, code fluency, and cost for well-scoped specifications |
| **Frontier / Reasoning** | `opus`, `pro` (high reasoning), `o3` | **Mandatory `qa-agent` overwatch**, security/concurrency reviews, complex `research-agent` root-cause debugging, subtle architectural design | Maximizes defect catch rate before code merges or infrastructure mutates |

---

## 2. Graceful Fallback Rule (Mandatory)

Tiered routing is an optimization, **never a blocker**. Immediately fall back to running all agents on the **default / inherited model** whenever ANY of these conditions holds:

1. **Tool/Runtime Restriction:** The environment has no per-subagent `model` selector, or platform rules require inheriting the parent's model (e.g., Antigravity Swarm inherit-only mode unless the user explicitly specifies models).
2. **User Preference:** The user requests a specific uniform model for the session.
3. **Quota / Capacity / Availability:** A tier returns rate-limit/quota exhaustion or is unavailable for an account.

**Fallback Behavior:**
- Do **not** abort workflows, skip QA, or stall waiting on a specific model tier.
- Keep the exact same role separation (`research-agent`, `dev-agent`, `deploy-agent`, and independent read-only `qa-agent`) on the uniform default/inherited model.

---

## 3. Horizontal Scaling & Collision-Free Sharding

Scale workers horizontally whenever work divides into independent units with zero shared mutable state:

### 3.1 Sharding Patterns

| Work Shape | How to Shard Safely | QA Ratio |
| --- | --- | --- |
| Multi-module feature | One `dev-agent` + dedicated `git worktree` per directory/module (`dev-api`, `dev-ui`, `dev-tests`) | 1 `qa-agent` auditing merged interfaces & per-branch diffs |
| Multi-area codebase audit | Parallel `research-1..N` split by subsystem or question | 1 `qa-agent` cross-checking cited files/assumptions across reports |
| Parallel test / validation suites | Split unit, integration, lint/typecheck, and build verification across parallel read-only/isolated runners | 1 `qa-agent` verifying full command matrix and edge assertions |
| Multi-host / multi-service rollout | One `deploy-agent` per independent host/environment **only if** services share no rolling lock or coupled DB migration | 1 `qa-agent` per 2–4 deploy lanes verifying backups + post-deploy health |

### 3.2 Mandatory QA Ratio & Specialization

- Maintain **roughly 1 `qa-agent` per 2–4 active workers**.
- When scaling past ~6 active workers, split QA by verification phase or domain (`qa-plan`, `qa-diff`, `qa-ops`) so verification stays parallel rather than forming a single-threaded review queue.
- Two writers **never** share one file or branch; if two lanes must touch a shared interface file, serialize that shared interface first (with QA sign-off), then fan out implementation lanes from that stable contract.

---

## 4. Non-Dependent Work Rule (Zero-Idle Dispatch)

Waiting idly for a slow operation wastes wall-clock time. Whenever an active agent enters a blocking or long-running phase, the Coordinator **immediately dispatches non-dependent work** to other agents (still under mandatory QA):

| Blocking Activity (Lane A) | Immediate Non-Dependent Work to Dispatch (Lanes B, C...) | QA Pairing |
| --- | --- | --- |
| Long test suite, CI run, or container build | `research-agent` investigates the next atomic slice; `dev-agent` writes docs or unrelated module tests in a separate worktree | `qa-agent` audits the new research plan or doc/test PR |
| Timed deployment soak / health observation window | `dev-agent` prepares next non-dependent feature branch; `research-agent` checks compatibility notes for upcoming upgrade | `qa-agent` monitors Lane A live logs/health while gating Lane B's plan |
| Deep external research / dependency audit | `dev-agent` creates test fixtures, CI skeleton, or non-blocked refactoring on an independent branch | `qa-agent` audits fixtures and validates independent refactor |
| Waiting for user confirmation on upstream PR | Prepare unrelated local documentation, tests, or subsequent independent local work | `qa-agent` pre-audits local staged diffs |

**Guardrail:** Never dispatch side-lane work that **mutates the same runtime target, branch, or files** under active validation in Lane A, and never promote or merge any side lane without `qa-agent` `APPROVE`.
