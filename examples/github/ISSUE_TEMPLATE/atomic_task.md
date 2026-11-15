---
name: Atomic Task / Workstream
about: Define an isolated, single-responsibility workstream under the Agent Overwatch protocol.
title: "[TASK]: "
labels: ["agent-overwatch", "atomic"]
assignees: ""
---

## 1. Problem Statement & Scope Boundary

- **Problem / Goal Description:**
  <!-- Clearly describe the bug or feature. Distinguish root cause from symptoms. -->
  
- **In-Scope:**
  <!-- Explicit list of files, functions, or components to be modified. -->
  - 

- **Out-of-Scope (Non-Goals):**
  <!-- What must NOT be touched on this task? -->
  - 

---

## 2. Target Branch & Workstream Identifier

- **Workstream ID:** `WS-` <!-- e.g., WS-01 -->
- **Target Branch:** `feat/` or `fix/` <!-- e.g., feat/jwt-auth -->
- **Base Integration Branch:** `main`

---

## 3. Acceptance Criteria

- [ ] Core functionality implemented according to specifications.
- [ ] Unit tests added with >80% branch coverage on modified code.
- [ ] Integration / end-to-end test passes cleanly.
- [ ] Automated linter and type-checker pass with 0 errors.
- [ ] Zero secrets, private keys, or credentials committed.
- [ ] `HANDOFF.md` updated with branch status and deliverable links.

---

## 4. Rollback Plan

- **Rollback Mechanism:** <!-- e.g., git revert, database migration down script, container tag reversion -->
- **Rollback Command:**
  ```bash
  # Exact command to cleanly revert changes if issues arise
  ```
- **Estimated Rollback Time:** `< 2 minutes`
