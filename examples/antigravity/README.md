# Antigravity Multi-Agent Setup: `agent-overwatch`

This example demonstrates how to configure and deploy the `agent-overwatch` multi-agent coordination system in **Antigravity**.

In Antigravity, multi-agent workflows leverage native subagent orchestration, event-driven reactive messaging (`send_message`), model tier routing (`flash`, `pro`, `inherit`), and structured skills.

---

## 1. Directory Structure

You can install `agent-overwatch` at either the **workspace scope** (recommended for project-specific team configurations) or as a **global plugin** available across all workspaces.

### Workspace Scope Layout
```text
<project-root>/
├── .agents/
│   ├── skills/
│   │   └── agent-overwatch/
│   │       ├── SKILL.md
│   │       ├── templates/
│   │       │   ├── HANDOFF.template.md
│   │       │   ├── SUBDIR_HANDOFF.template.md
│   │       │   ├── AGENT_BUS.template.md
│   │       │   └── QA_CHECKLIST.template.md
│   │       └── references/
│   │           ├── agent-roles.md
│   │           ├── coordination-files.md
│   │           ├── git-and-github-workflow.md
│   │           └── model-routing-and-scaling.md
│   └── agents/
│       ├── qa-agent.md
│       ├── dev-agent.md
│       ├── deploy-agent.md
│       └── research-agent.md
├── GEMINI.md               # Workspace rules loaded automatically
└── HANDOFF.md              # Living project handoff
```

### Global Plugin Layout
```text
~/.gemini/config/plugins/agent-overwatch/
├── plugin.json
├── skills/
│   └── agent-overwatch/
│       ├── SKILL.md
│       └── references/
└── agents/
    ├── qa-agent.md
    ├── dev-agent.md
    ├── deploy-agent.md
    └── research-agent.md
```

---

## 2. Skill Definition (`SKILL.md`)

Save at `.agents/skills/agent-overwatch/SKILL.md`:

```markdown
---
name: agent-overwatch
description: Orchestrates multi-agent development with mandatory QA review, atomic branch isolation, living HANDOFF.md synchronization, and rollback verification. Use when coordinating multiple agents or complex refactors.
---

# Agent Overwatch Skill

This skill coordinates specialized subagents (`dev-agent`, `deploy-agent`, `qa-agent`, `research-agent`) to ensure rigorous engineering standards.

## Execution Rules
1. Assign every workstream an atomic branch (`feat/<name>` or `fix/<name>`).
2. Require QA Overwatch review and formal `APPROVE` verdict before any merge or deploy.
3. Keep `HANDOFF.md` updated with branch status, deliverables, and active agent assignments.
4. Pass state updates directly using native `send_message`.
```

---

## 3. Subagent Definitions (`.agents/agents/*.md`)

### QA Overwatch Subagent (`.agents/agents/qa-agent.md`)
```markdown
---
name: qa-agent
description: Independent, skeptical Quality Assurance Overwatch. Audits code diffs, verifies unit/integration test results, checks for secrets, and validates deployment health. Holds unilateral veto authority.
subagent: true
mainAgent: false
tools:
  - read_file
  - run_command
  - search_web
---

You are the QA Overwatch Subagent. You do not write application code or execute live deployments.
Your duty is independent verification:
1. Audit PR diffs for small atomic scope and zero leaked secrets.
2. Verify test runs produce real passing outputs with exit code 0.
3. Audit rollback plans before state-changing deployments.
4. Provide formal verdicts: APPROVE or HOLD with specific actionable remediation items.
5. Report findings back via native messaging (`send_message` / swarm board) or `AGENT_BUS.md`.
```

### Dev Subagent (`.agents/agents/dev-agent.md`)
```markdown
---
name: dev-agent
description: Implements features, refactors code, and authors comprehensive tests within atomic feature branches. Does not deploy to production.
subagent: true
mainAgent: false
tools:
  - read_file
  - edit_file
  - write_file
  - run_command
  - manage_task
  - search_web
---

You are the Development Subagent. You implement changes on dedicated atomic branches.
1. Formulate clear plans and add unit/integration tests for all changes.
2. Update HANDOFF.md when your branch milestones change.
3. Once tests pass, notify QA Overwatch via native messaging (`send_message` / swarm board) or `AGENT_BUS.md`.
```

### Deploy Subagent (`.agents/agents/deploy-agent.md`)
```markdown
---
name: deploy-agent
description: Executes controlled environment deployments, infrastructure migrations, and runtime container management. Enforces rollback plans and pre-change backups.
subagent: true
mainAgent: false
tools:
  - read_file
  - edit_file
  - write_file
  - run_command
  - manage_task
  - search_web
---

You are the Deployment Subagent.
1. Always create a verified backup before modifying any live environment or configuration.
2. Verify rollback commands before applying changes.
3. Announce an ACTION message prior to execution via native messaging or `AGENT_BUS.md`.
4. Verify health endpoints, clean restart counts, and error logs post-deploy.
5. Report a RESULT message with full return status to qa-agent and the lead coordinator.
```

### Research Subagent (`.agents/agents/research-agent.md`)
```markdown
---
name: research-agent
description: Researches documentation, investigates CVEs and dependency upgrades, diagnoses tricky bugs, and designs architectural blueprints without modifying source code.
subagent: true
mainAgent: false
tools:
  - read_file
  - run_command
  - search_web
---

You are the Research Subagent.
1. Gather documentation, investigate upstream issues, and cite exact verified references.
2. Provide factual findings without guessing unverified CLI flags, paths, or library methods.
3. Return research briefs via native messaging (`send_message` / swarm board) or `AGENT_BUS.md`.
```

---

## 4. Native Messaging (`send_message` / Swarm Board) vs `AGENT_BUS.md`

In Antigravity:
- **Native Event-Driven Messaging:** Antigravity agents communicate in real time using `send_message` or the swarm board (`post_message`, `read_board`, `swarm_wait`). The runtime wakes up recipient agents reactively without polling loops.
- **When to Use `AGENT_BUS.md`:**
  - Native messaging/swarm boards supersede `AGENT_BUS.md` for live coordination.
  - Retain `AGENT_BUS.md` only when no native board is active or when the project requires an append-only, Git-committed audit trail across sessions or across multiple tools.

---

## 5. Model Routing & Graceful Fallback

When an Antigravity workflow (such as explicit user-requested swarm model selection) permits per-worker model routing:
- **Economy / Fast (`flash`):** Lightweight lookups, formatting, and quick file inventories.
- **Standard / Reasoning (`pro`, `opus`, `sonnet`):** Implementation, deployment verification, and **mandatory QA Overwatch** (`qa-agent`).
- **Mandatory Fallback Rule:** By default, Antigravity subagents and inherit-mode swarm workers run on the parent conversation's active model (`inherit`). If tiered selection is disallowed or quota-limited, drop differing-cost routing and run all agents on the default/inherited model.
