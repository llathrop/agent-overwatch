# Agent Overwatch

A general-purpose, cross-platform multi-agent workflow skill, plugin bundle, installer, and portable subagent suite built around **high-velocity parallel execution gated by mandatory independent QA**.

## Why Agent Overwatch

- **Zero-idle parallelism:** Scale `research-agent`, `dev-agent`, and `deploy-agent` horizontally across non-overlapping files, modules, and worktrees while dispatching non-dependent work whenever a worker hits a slow build, test suite, or deploy.
- **Mandatory independent QA:** Every research plan, code diff, backup, and deployment is independently verified by a strictly read-only `qa-agent` (`APPROVE` or `HOLD` with exact file/line/command evidence) before moving forward or merging.
- **Portable across tools:** Ships with [install.sh](install.sh) and tool examples for Antigravity (`plugin.json` + `skills/` + `agents/`), Claude Code, Codex CLI, Gemini CLI, Cursor, and GitHub Issue/PR templates.
- **Atomic Git & GitHub discipline:** Small, single-purpose feature branches, incremental QA-gated merges back to `main`, automated pre-merge verification via [verify_atomic_branch.sh](skills/agent-overwatch/scripts/verify_atomic_branch.sh), and strict upstream safety guardrails for public repositories.

## Quick Start

1. Read the core workflow manual: [skills/agent-overwatch/SKILL.md](skills/agent-overwatch/SKILL.md).
2. Preview or install into your workspace or home configuration using [install.sh](install.sh):
   ```bash
   # Preview all installers without writing files
   ./install.sh --all --dry-run

   # Install into a project workspace (Antigravity, Claude, Codex, Gemini, Cursor, GitHub)
   ./install.sh --all --workspace /path/to/your-project

   # Install globally as an Antigravity plugin (~/.gemini/config/plugins/agent-overwatch/)
   ./install.sh --antigravity --global
   ```
3. Initialize coordination files (`HANDOFF.md`, `AGENT_BUS.md`, `status/`) in any project or child subproject:
   ```bash
   ./skills/agent-overwatch/scripts/init_workspace.sh /path/to/your-project
   ./skills/agent-overwatch/scripts/init_workspace.sh /path/to/your-project/services/api --subdir
   ```
4. Verify an atomic branch before merging:
   ```bash
   ./skills/agent-overwatch/scripts/verify_atomic_branch.sh --repo /path/to/your-project --base main
   ```

## Portable Subagent Roles

- [agents/qa-agent.md](agents/qa-agent.md) — Read-only verification and `APPROVE` / `HOLD` gatekeeper
- [agents/research-agent.md](agents/research-agent.md) — Read-only exploration, root-cause analysis, and RFCs
- [agents/dev-agent.md](agents/dev-agent.md) — Isolated authoring, refactoring, and automated tests
- [agents/deploy-agent.md](agents/deploy-agent.md) — Backup-first rollouts, smoke checks, and rollback readiness

## Repository Layout

```text
agent-overwatch/
├── plugin.json                              # Antigravity plugin manifest
├── install.sh                               # Multi-tool installer (--dry-run, --global, --workspace)
├── README.md                                # Project overview and quick start
├── HANDOFF.md                               # Living project state and next steps
├── AGENT_BUS.md                             # Append-only file coordination log
├── agents/                                  # Portable subagent definitions
│   ├── qa-agent.md
│   ├── dev-agent.md
│   ├── deploy-agent.md
│   └── research-agent.md
├── examples/                                # Tool-specific setups & GitHub templates
│   ├── antigravity/
│   ├── claude-code/
│   ├── codex/
│   ├── cursor/
│   ├── gemini-cli/
│   └── github/
└── skills/
    └── agent-overwatch/
        ├── SKILL.md                         # Core workflow skill
        ├── references/                      # Progressive-disclosure reference guides
        │   ├── agent-roles.md
        │   ├── coordination-files.md
        │   ├── git-and-github-workflow.md
        │   └── model-routing-and-scaling.md
        ├── templates/                       # Reusable HANDOFF, bus, & QA templates
        │   ├── HANDOFF.template.md
        │   ├── SUBDIR_HANDOFF.template.md
        │   ├── AGENT_BUS.template.md
        │   └── QA_CHECKLIST.template.md
        └── scripts/                         # Workspace initializer & pre-merge verifier
            ├── init_workspace.sh
            └── verify_atomic_branch.sh
```

## Status & Coordination

- Living project state: [HANDOFF.md](HANDOFF.md)
- Coordination log (used when no native board supersedes it): [AGENT_BUS.md](AGENT_BUS.md)
