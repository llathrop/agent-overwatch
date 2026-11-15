# Claude Code Setup: `agent-overwatch`

This guide explains how to install and configure the **Agent Overwatch** multi-agent protocol in **Claude Code**.

---

## 1. Installation Layout

You can install `agent-overwatch` globally (for all Claude Code projects on your system) or locally within a specific project.

### Global Installation (User Scope)
```text
~/.claude/
├── CLAUDE.md                             # Global defaults & rules
├── skills/
│   └── agent-overwatch/
│       ├── SKILL.md                      # Skill definition
│       └── templates/                    # Handoff, Bus, and QA checklist templates
└── agents/
    ├── qa.md                             # QA Overwatch subagent
    ├── dev.md                            # Development subagent
    ├── deploy.md                         # Deployment subagent
    └── research.md                       # Research & documentation subagent
```

### Project Installation (Workspace Scope)
```text
<project-root>/
├── CLAUDE.md                             # Project-specific Overwatch enforcement
├── HANDOFF.md                            # Living handoff summary
├── .claude/
│   ├── skills/
│   │   └── agent-overwatch/
│   │       └── SKILL.md
│   └── agents/
│       ├── qa.md
│       ├── dev.md
│       ├── deploy.md
│       └── research.md
```

---

## 2. Skill Definition (`~/.claude/skills/agent-overwatch/SKILL.md`)

```markdown
---
name: agent-overwatch
description: Orchestrates multi-agent development workflows enforcing mandatory QA Overwatch sign-off, atomic branching, living HANDOFF.md sync, and rollback verification. Use when working on complex features or coordinating multiple subagents.
---

# Agent Overwatch for Claude Code

Coordinates engineering tasks through specialized subagents, atomic branches, and verification gates.

## Standard Flow
1. Create atomic branch `feat/<task>` or `fix/<task>`.
2. Developer subagent writes code, tests, and updates `HANDOFF.md`.
3. QA subagent audits the diff, verifies tests pass, checks for leaked secrets, and validates the rollback plan.
4. Merge or deploy only upon QA `APPROVE`.
```

---

## 3. Subagent Definitions (`~/.claude/agents/*.md`)

### QA Overwatch Subagent (`~/.claude/agents/qa.md`)
```markdown
---
name: qa
description: Skeptical Quality Assurance auditor. Audits diffs, verifies unit test execution, confirms zero secret leaks, and evaluates rollback readiness. Holds veto authority.
model: sonnet
tools:
  - Read
  - Glob
  - Grep
  - Bash
---

You are the QA Overwatch Subagent. You do not author implementation code or deploy changes.
Your responsibilities:
1. Audit atomic branch diffs: ensure changes are strictly scoped and adhere to project conventions.
2. Verify test evidence: run or inspect test outputs to confirm real passing assertions.
3. Secret scan: verify no credentials or private keys are committed.
4. Issue structured verdicts: APPROVE or HOLD with specific required remediation steps.
```

### Dev Subagent (`~/.claude/agents/dev.md`)
```markdown
---
name: dev
description: Implements features and bugfixes on isolated atomic branches. Writes comprehensive tests and updates HANDOFF.md.
model: sonnet
tools:
  - Read
  - Glob
  - Grep
  - Edit
  - MultiEdit
  - Write
  - Bash
---

You are the Development Subagent.
1. Work exclusively on dedicated atomic branches (`feat/*` or `fix/*`).
2. Include unit and integration tests for every new feature or bugfix.
3. Keep HANDOFF.md updated with branch progress and deliverable evidence.
4. Request QA audit once tests pass cleanly.
```

### Deploy Subagent (`~/.claude/agents/deploy.md`)
```markdown
---
name: deploy
description: Manages staged rollouts, environment migrations, and live health verification. Enforces pre-change backups and verified rollback commands.
model: sonnet
tools:
  - Read
  - Glob
  - Grep
  - Write
  - Bash
---

You are the Deployment Subagent.
1. Always establish and verify a rollback procedure before altering live systems.
2. Create and verify a full backup prior to modifying databases or configuration.
3. Verify post-deploy health: HTTP 200 health check responses, clean restart counts, error-free system logs.
```

### Research Subagent (`~/.claude/agents/research.md`)
```markdown
---
name: research
description: Researches upstream libraries, diagnoses errors from logs, and reviews API documentation without modifying project code.
model: haiku
tools:
  - Read
  - Glob
  - Grep
  - WebSearch
  - WebFetch
---

You are the Research Subagent.
1. Investigate documentation, library changelogs, and upstream bug reports.
2. Provide concise, factual summaries with direct documentation references.
3. Do not modify project files.
```

---

## 4. Model Tiers & Fallback Strategy

Claude Code supports selecting models per task or subagent:
- **`haiku`**: Lightweight, rapid search and documentation reading (`research.md`).
- **`sonnet`**: Balanced high-performance coding, deployment coordination, and standard QA reviews (`dev.md`, `deploy.md`, `qa.md`).
- **`opus`**: Reserved for high-complexity architectural reviews, mission-critical security evaluations, or complex debugging sessions.
- **Fallback Rule:** If rate limits or token constraints occur on `opus` or `sonnet`, fall back to `sonnet` or `haiku` respectively while maintaining the strict QA verification criteria.

---

## 5. Coordination: Built-in Agent Teams vs `AGENT_BUS.md`

- **Single Session / Built-in Subagents:** Claude Code dispatches subagents in-process. The lead agent receives task outputs directly, evaluating subagent results against QA rules.
- **Multi-Terminal / Headless Swarms:** When running multiple concurrent Claude Code instances or hybrid human/AI sessions, use the append-only `AGENT_BUS.md` log file.
  - dev posts `PLAN`, runs tests, posts `ACTION` and `RESULT`.
  - qa posts `CHALLENGE` or `APPROVE` / `HOLD`.
  - deploy verifies backups and posts runtime validation results.
