# Codex CLI Setup: `agent-overwatch`

This directory provides the configuration setup for using **Agent Overwatch** with OpenAI's **Codex CLI**.

---

## 1. Directory & File Structure

Codex CLI supports global and project-level instructions, skills, and prompts.

```text
~/.codex/                                 # Global user scope
├── config.toml                           # Codex CLI runtime settings & MCP servers
├── AGENTS.md                             # Global instructions
└── skills/
    └── agent-overwatch/
        ├── SKILL.md                      # Codex-compatible skill definition
        └── templates/
            ├── HANDOFF.template.md
            ├── SUBDIR_HANDOFF.template.md
            ├── AGENT_BUS.template.md
            └── QA_CHECKLIST.template.md

<project-root>/                           # Project workspace scope
├── AGENTS.md                             # Project-level Overwatch instructions
├── HANDOFF.md                            # Living repository handoff
├── services/
│   └── api/
│       ├── AGENTS.md                     # Subdirectory-specific overrides
│       └── HANDOFF.md                    # Subdirectory local handoff
```

---

## 2. Skill Definition (`~/.codex/skills/agent-overwatch/SKILL.md`)

```markdown
---
name: agent-overwatch
description: Orchestrates multi-agent workflows with mandatory QA sign-off, atomic branches, living HANDOFF.md synchronization, and verified rollback strategies.
---

# Agent Overwatch for Codex CLI

Enforces strict engineering standards:
1. Every task is assigned an atomic branch (`feat/<name>` or `fix/<name>`).
2. Unit and integration tests must pass cleanly with reproducible CLI logs.
3. PR diffs must undergo QA review covering scope minimality, test coverage, and secret scanning.
4. Merge or rollout is allowed only after QA issues an APPROVE verdict.
```

---

## 3. Hierarchical `AGENTS.md` Behavior

Codex CLI applies instruction files hierarchically based on the current working directory:

1. **Global Instructions (`~/.codex/AGENTS.md`):**
   - Establishes global developer identity, default safety constraints, and base QA requirements across all projects.
2. **Project Root (`<project-root>/AGENTS.md`):**
   - Tailors rules to the project: points to root `HANDOFF.md`, specifies local test runners (`pytest`, `npm test`, `cargo test`), and defines the integration branch (`main`).
3. **Subdirectory Overrides (`<project-root>/services/api/AGENTS.md`):**
   - Applies localized rules when Codex is operating inside that specific sub-tree:
   - Example:
     ```markdown
     # AGENTS.md — API Sub-service Overrides
     
     Inherits all root AGENTS.md rules.
     - Local test runner: `pytest -v tests/unit/`
     - Local handoff: `services/api/HANDOFF.md`
     - Do not modify files outside `services/api/` on sub-branches.
     ```
