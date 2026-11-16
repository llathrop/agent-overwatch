# Model Cost Routing, Graceful Fallback & Parallel Scaling

Guidelines for matching model capability to task risk, scaling workers horizontally without collisions, starting independent required work without waiting, and tracking usage when the runtime reports it.

---

## 1. Model Tiering Matrix

Use cheaper/faster models for mechanical tasks and reserve high-reasoning frontier models for architecture, hard debugging, and independent QA, **when the active platform allows per-agent model selection**. Tiers are defined by capability, not by vendor.

| Tier | Capability | Assigned Tasks & Roles | Why |
| --- | --- | --- | --- |
| **Economy** | Small, fast, low-cost models | File/tree inventories, log filtering, formatting/lint cleanup, boilerplate test stubs, quick status summarization | High token throughput, low latency and cost on deterministic/low-risk operations |
| **Standard** | Balanced general-purpose models | Routine `dev-agent` feature slices, unit tests, reference docs, standard `deploy-agent` checklist execution | Balanced reasoning, code fluency, and cost for well-scoped specifications |
| **Frontier** | Strongest available reasoning models | **Mandatory `qa-agent` overwatch**, security/concurrency reviews, complex `research-agent` root-cause debugging, subtle architectural design | Maximizes defect catch rate before code merges or infrastructure mutates |

**Vendor examples (illustrative only, not requirements; map to whatever your runtime offers):**

| Tier | Examples |
| --- | --- |
| Economy | Claude Haiku, Gemini Flash / Flash-Lite, GPT mini-class |
| Standard | Claude Sonnet, Gemini Pro, GPT-4o-class |
| Frontier | Claude Opus, Gemini Pro (high reasoning), OpenAI o-series |

---

## 2. Graceful Fallback Rule (Mandatory)

Tiered routing is an optimization, **never a blocker**. Immediately fall back to running all agents on the **default / inherited model** whenever ANY of these conditions holds:

1. **Tool/Runtime Restriction:** The environment has no per-subagent `model` selector, or platform rules require inheriting the parent's model (for example, a swarm runtime in inherit-only mode unless the user explicitly specifies models).
2. **User Preference:** The user requests a specific uniform model for the session.
3. **Quota / Capacity / Availability:** A tier returns rate-limit/quota exhaustion or is unavailable for an account.

**Fallback Behavior:**
- Do **not** abort workflows, skip QA, or stall waiting on a specific model tier.
- Keep the exact same role separation (`research-agent`, `dev-agent`, `deploy-agent`, and independent read-only `qa-agent`) on the uniform default/inherited model.

---

## 3. Horizontal Scaling & Collision-Free Sharding

Scale workers horizontally whenever work divides into independent units with zero shared mutable state:

### 3.1 Sharding Patterns

| Work Shape | How to Shard Safely | QA Coverage |
| --- | --- | --- |
| Multi-module feature | One `dev-agent` + dedicated `git worktree` per directory/module (`dev-api`, `dev-ui`, `dev-tests`) | 1 `qa-agent` auditing merged interfaces & per-branch diffs |
| Multi-area codebase audit | Parallel `research-1..N` split by subsystem or question | 1 `qa-agent` cross-checking cited files/assumptions across reports |
| Parallel test / validation suites | Split unit, integration, lint/typecheck, and build verification across parallel read-only/isolated runners | 1 `qa-agent` verifying full command matrix and edge assertions |
| Multi-host / multi-service rollout | One `deploy-agent` per independent host/environment **only if** services share no rolling lock or coupled DB migration | QA sized to the number of rollouts in flight, verifying backups + post-deploy health (driven by `overwatch_watch.sh` events) |

### 3.2 Scaling QA to the Review Load

- Scale QA to the review load so verification doesn't queue. There is no fixed ratio: a few large or risky diffs can need more QA than many small doc changes.
- Signs QA is under-provisioned: `RESULT` entries waiting for a verdict while authors are already done, or branches waiting to merge. Add a QA agent or split QA by phase or domain (`qa-plan`, `qa-diff`, `qa-ops`).
- Two writers **never** share one file or branch; if two lanes must touch a shared interface file, serialize that shared interface first (with QA sign-off), then fan out implementation lanes from that stable contract.

---

## 4. Non-Dependent Work Rule

> "Don't wait to do something that must be done in the project. If an agent is busy working on one aspect, and some other aspect doesn't depend on that work, work on it now with a separate agent (or agents)."

The rule is about **not deferring necessary independent work**. It is not about keeping agents busy. Only dispatch work that the project actually requires; never invent optional or speculative tasks to fill a wait.

| Situation (Lane A busy) | Required work that may start now | Not this |
| --- | --- | --- |
| Long test suite, CI run, or build on branch A | A planned slice B that does not depend on A's result (separate worktree) | "Nice to have" refactors or extra docs nobody asked for |
| Deploy soak / health observation window | QA audit of an already-finished sibling branch; the next planned slice that touches other files/hosts | A new feature that was never in scope |
| Research on question X | Implementation of an already-approved, unrelated plan Y | Coding the part that depends on X's answer |
| Waiting for user confirmation | Planned local work that the decision does not affect | Guessing the user's answer and building on it |

**Guardrails:**
- Never dispatch side-lane work that **mutates the same runtime target, branch, or files** under active validation in Lane A.
- Never promote or merge any lane without its own `qa-agent` `QA APPROVE`.
- If nothing independent remains, waiting is correct.

---

## 5. Usage & Budget Awareness

Parallel lanes multiply spend. Track it only when real numbers exist.

1. **If the runtime exposes usage or spend numbers** (a usage/limits command, statusline cost data, a budget API, token-target directives in the prompt), read them at batch boundaries and before launching new lanes.
2. **Warn the user as limits approach**, for example at about 75% and again at about 90%. Each warning states the current figure and which lanes are still running, so the user can decide what to stop.
3. **If no usage numbers are available, ignore this section.** Don't estimate tokens, don't guess at spend, and don't throttle parallelism on a hunch.
4. **On a rate limit or HTTP 429:** pause instead of retrying in a loop. Record the state in `HANDOFF.md` (running lanes, branches with SHAs, verdicts pending, the next step) so another session can resume, then retry later or fall back per section 2.
5. **Optional bus entry:** `scripts/bus_append.sh --type USAGE` with the figure and its source (for example `weekly limit 76% per /usage`), so other sessions see it.
