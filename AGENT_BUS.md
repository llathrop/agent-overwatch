# AGENT_BUS — Inter-Agent Coordination Log

> **Supersession Rule:** When your runtime provides a built-in message board or native agent-to-agent messaging tool (for example, Antigravity `swarm` `post_message` / `read_board`, `send_message`, or agent teams), use that native channel for live coordination. Use `AGENT_BUS.md` when no native board exists or when a Git-committed file-based audit trail is explicitly required.
>
> **Append-Only Discipline:** Read the tail before writing and **always append atomically** using a quoted heredoc (`cat <<'EOF' >> AGENT_BUS.md`) so parallel agents never clobber concurrent entries.
>
> **Secret Hygiene:** Never write tokens, passwords, private keys, API keys, PII, or credential strings into `AGENT_BUS.md` (or any committed file).

## Entry Format

```markdown
### [YYYY-MM-DD HH:MM UTC] <from> -> <to> | <TYPE> <short subject>
- Concise scope, file paths, verification output, or blocker.
```

Standard `<TYPE>` tags: `TAKEOVER`, `BRIEF`, `ACTION`, `RESULT`, `CONCERN`, `QA APPROVE`, `QA HOLD`, `STATUS`.

---

### [2026-11-15 23:04 UTC] dev-agent -> qa-agent,coordinator | RESULT Step B1 feat/core-skill-and-agents ready for QA
- Branch: `feat/core-skill-and-agents` (branched from `main` @ `237b465`, awaiting QA before merge).
- Deliverables added/updated:
  - `plugin.json`
  - `skills/agent-overwatch/SKILL.md`
  - `skills/agent-overwatch/references/agent-roles.md`
  - `skills/agent-overwatch/references/coordination-files.md`
  - `skills/agent-overwatch/references/git-and-github-workflow.md`
  - `skills/agent-overwatch/references/model-routing-and-scaling.md`
  - `agents/qa-agent.md`, `agents/research-agent.md`, `agents/dev-agent.md`, `agents/deploy-agent.md`
  - `HANDOFF.md`, `AGENT_BUS.md`
- Checks: JSON schema, YAML frontmatter, relative link resolution, portability/tool-neutrality, and domain-neutrality checks passed after final edit.

### [2026-11-15 23:08 UTC] coordinator -> all | QA APPROVE (Merge #1 feat/core-skill-and-agents)
- `qa-overwatch` issued `QA APPROVE` on `feat/core-skill-and-agents` (`285f96f`).
- Merged incrementally into `main` via `--no-ff` (`4433d18`); deleted merged local branch `feat/core-skill-and-agents`.

### [2026-11-15 23:08 UTC] dev-agent -> qa-overwatch,coordinator | RESULT Atomic Branch 2 feat/templates-and-examples ready for QA
- Branch: `feat/templates-and-examples` (branched from `main` @ `4433d18`, awaiting QA before merge).
- Deliverables added (14 files from staging + pre-commit fixes + coordination updates):
  - `skills/agent-overwatch/templates/`: `HANDOFF.template.md`, `SUBDIR_HANDOFF.template.md`, `AGENT_BUS.template.md`, `QA_CHECKLIST.template.md`
  - `examples/`: `antigravity/README.md`, `claude-code/{CLAUDE.md,README.md}`, `codex/{AGENTS.md,README.md}`, `cursor/agent-overwatch.mdc`, `gemini-cli/{GEMINI.md,agent-overwatch.toml}`, `github/{ISSUE_TEMPLATE/atomic_task.md,PULL_REQUEST_TEMPLATE.md}`
  - Fixes applied over staged drafts: quoted YAML `description:` in `examples/cursor/agent-overwatch.mdc`; replaced broken `file:///` links in `HANDOFF.template.md` and unresolved template links in `SUBDIR_HANDOFF.template.md` with safe backticked relative syntax; aligned `examples/antigravity/README.md` plugin tree (`plugin.json`, real `references/` names) and agent frontmatter (`tools:` matching Antigravity plugin loader + inherit fallback note).
- Verification: Full repo YAML/TOML/JSON syntax, relative markdown link checks, and domain/hygiene scan passed after final edits.

### [2026-11-15 23:13 UTC] coordinator -> all | QA APPROVE (Merge #2 feat/templates-and-examples)
- `qa-overwatch` issued `QA APPROVE` on `feat/templates-and-examples` (`66ac9f5`).
- Merged incrementally into `main` via `--no-ff` (`bc98b82`); deleted merged local branch `feat/templates-and-examples`.

### [2026-11-15 23:13 UTC] dev-agent -> qa-overwatch,coordinator | RESULT Atomic Branch 3 feat/scripts-and-installer ready for QA
- Branch: `feat/scripts-and-installer` (branched from `main` @ `bc98b82`, awaiting QA before merge).
- Deliverables added/updated:
  - `install.sh` (`chmod +x`) — fixed source paths (`examples/gemini-cli/agent-overwatch.toml`, `examples/cursor/agent-overwatch.mdc`, `examples/github/ISSUE_TEMPLATE/atomic_task.md`, `examples/github/PULL_REQUEST_TEMPLATE.md`) and direct `safe_copy_file` error surfacing; fixed `update_instruction_file` `--force` Python block to use `sys.argv`/`sys.stdin`; added multiline-YAML-safe `install_agent_file` supporting both Antigravity (`subagent`, `mainAgent`, `tools`) and Claude Code (`Read`/`Glob`/`Grep`/`Edit`/`MultiEdit`/`Write`/`Bash`/`WebSearch`/`WebFetch` mapping).
  - `skills/agent-overwatch/scripts/init_workspace.sh` (`chmod +x`) — safe `sys.argv` `os.path.relpath` invocation and clean `<PROJECT_NAME>`/`<SUBDIR_PATH>`/`<SUBDIR_NAME>`/`<branch-name>` substitution alongside `{{...}}`.
  - `skills/agent-overwatch/scripts/verify_atomic_branch.sh` (`chmod +x`) — fixed Gate 5 to evaluate only actual verdict entries and inspect the **latest** verdict via `tail -n 1` (preventing stale `QA APPROVE` from masking a subsequent `QA HOLD`), plus checking for newer `RESULT` entries after `QA APPROVE`.
  - `README.md`, `skills/agent-overwatch/SKILL.md`, `HANDOFF.md`, `AGENT_BUS.md`.
- Tests pending final post-commit verification output attached in QA submission.

### [2026-11-15 23:17 UTC] coordinator -> all | QA APPROVE (Merge #3 feat/scripts-and-installer)
- `qa-overwatch` issued `QA APPROVE` on `feat/scripts-and-installer` (`617aa94`).
- Merged incrementally into `main` via `--no-ff` (`4bc4493`); deleted merged local branch `feat/scripts-and-installer`.
- Removed sibling temporary staging directories (`../agent-overwatch-staging-b2a` and `../agent-overwatch-staging-b2b`) and verified neither was ever tracked in git.

### [2026-11-15 23:17 UTC] dev-agent -> qa-overwatch,coordinator | RESULT docs/final-handoff ready for final QA
- Branch: `docs/final-handoff` (branched from `main` @ `4bc4493`, awaiting final `qa-overwatch` audit before merge to `main`).
- Updated `HANDOFF.md` and `AGENT_BUS.md` with complete 3-merge history (`4433d18`, `bc98b82`, `4bc4493`), 31-file `main` layout, staging directory cleanup confirmation, and verified test commands.

### [2026-11-15 23:21 UTC] coordinator -> all | QA APPROVE (Merge #4 docs/final-handoff)
- `qa-overwatch` issued `QA APPROVE` on `docs/final-handoff` (`71e8b37`).
- Merged incrementally into `main` via `--no-ff` (`ed9ee17`); deleted merged local branch `docs/final-handoff`.

### [2026-11-15 23:21 UTC] dev-agent -> qa-overwatch,coordinator | RESULT feat/user-progress-updates ready for QA
- Branch: `feat/user-progress-updates` (branched from `main` @ `ed9ee17`, awaiting `qa-overwatch` audit before merge).
- Implemented live self-contained user-facing progress reporting across:
  - `skills/agent-overwatch/SKILL.md`: added Coordinator step 4 and dedicated Section `## 7. Live User-Facing Progress Updates` (renumbered reference library to `## 8`), specifying real-time batch/phase reporting without assuming the user reads internal agent messages or `AGENT_BUS.md`.
  - `skills/agent-overwatch/references/agent-roles.md`: added `User-Facing Progress Reporting` playbook + Good vs. Bad table under Section `2.1 Coordinator / Orchestrator`.
  - `examples/claude-code/CLAUDE.md`, `examples/codex/AGENTS.md`, `examples/gemini-cli/GEMINI.md`, `examples/cursor/agent-overwatch.mdc`, and `install.sh` (`update_instruction_file` snippet).
  - Updated `HANDOFF.md` and `AGENT_BUS.md`.
