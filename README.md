# Agent Overwatch

A general-purpose, cross-platform multi-agent workflow skill, plugin bundle, and portable subagent suite built around **high-velocity parallel execution gated by mandatory independent QA**.

## Why Agent Overwatch

- **Zero-idle parallelism:** Scale `research-agent`, `dev-agent`, and `deploy-agent` horizontally across non-overlapping files, modules, and worktrees while dispatching non-dependent work whenever a worker hits a slow build, test suite, or deploy.
- **Mandatory independent QA:** Every research plan, code diff, backup, and deployment is independently verified by a strictly read-only `qa-agent` (`APPROVE` or `HOLD` with exact file/line/command evidence) before moving forward or merging.
- **Portable across tools:** Ships as an Antigravity plugin (`plugin.json` + `skills/` + `agents/`) with portable subagent definitions adaptable to Claude Code, Codex CLI, Gemini CLI, and Cursor (`install.sh` arriving in Step B2).
- **Atomic Git & GitHub discipline:** Small, single-purpose feature branches, incremental QA-gated merges back to `main`, and strict upstream safety guardrails for public repositories.

## Quick Start

1. Read the core workflow manual: [skills/agent-overwatch/SKILL.md](skills/agent-overwatch/SKILL.md).
2. Review the portable subagent roles under [agents/](agents/):
   - [agents/qa-agent.md](agents/qa-agent.md) — Read-only verification and `APPROVE` / `HOLD` gatekeeper
   - [agents/research-agent.md](agents/research-agent.md) — Read-only exploration, root-cause analysis, and RFCs
   - [agents/dev-agent.md](agents/dev-agent.md) — Isolated authoring, refactoring, and automated tests
   - [agents/deploy-agent.md](agents/deploy-agent.md) — Backup-first rollouts, smoke checks, and rollback readiness
3. **Installation:** Cross-tool installer `install.sh` (Antigravity, Claude Code, Codex CLI, Gemini CLI, Cursor) will be added in Step B2. Until then, load this repository directly as a local Antigravity plugin via `plugin.json`, or copy `skills/agent-overwatch/` into your workspace `.agents/skills/` directory.

## Repository Layout

```text
agent-overwatch/
├── plugin.json                              # Plugin manifest
├── README.md                                # Project overview and quick start
├── HANDOFF.md                               # Living project state and next steps
├── AGENT_BUS.md                             # Append-only file coordination log
├── agents/                                  # Portable subagent definitions
│   ├── qa-agent.md
│   ├── dev-agent.md
│   ├── deploy-agent.md
│   └── research-agent.md
└── skills/
    └── agent-overwatch/
        ├── SKILL.md                         # Core workflow skill
        └── references/                      # Progressive-disclosure reference guides
            ├── agent-roles.md
            ├── coordination-files.md
            ├── git-and-github-workflow.md
            └── model-routing-and-scaling.md
```

## Status & Coordination

- Living project state: [HANDOFF.md](HANDOFF.md)
- Coordination log (used when no native board supersedes it): [AGENT_BUS.md](AGENT_BUS.md)
