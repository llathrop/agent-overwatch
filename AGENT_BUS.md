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
