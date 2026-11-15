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
