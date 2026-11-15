# Coordination Files & Built-In Supersession

Standards for `HANDOFF.md`, `AGENT_BUS.md`, optional `QA_BUS.md` / `status/<agent>.md`, built-in tool supersession, and monorepo subdirectory scoping.

---

## 1. Built-In Tool Supersession Matrix

Always prefer the host runtime's native coordination primitives over file polling when both exist:

| Environment | Live Coordination Mechanism | `AGENT_BUS.md` Role | `HANDOFF.md` Role |
| --- | --- | --- | --- |
| **Antigravity Swarm** | **Superseded by** `post_message`, `read_board`, `swarm_wait` (cite `#seq` IDs instead of copy-pasting) | Omit for live chat; optional only if a Git-committed summary log is desired | Maintained at milestones/handoffs |
| **Native Parent / Subagent Messaging** | **Superseded by** native `send_message` / subagent response channel | Optional unless multiple asynchronous peers/sessions need shared file history | Maintained at milestones/handoffs |
| **Claude Code Agent Teams / Task Board** | **Superseded by** native teammate messaging & shared task list | Optional for cross-session persistence | Maintained at milestones/handoffs |
| **Plain CLI / Multi-Tool / Cross-Session** | **Required:** `AGENT_BUS.md` (and optional `QA_BUS.md`) | **Primary append-only coordination bus** | **Required living state file** |

**Rule:** Never force agents to duplicate every native board post into `AGENT_BUS.md`. Either use the native board for live turn-to-turn traffic OR use `AGENT_BUS.md` when no native board exists or when a durable repo log is explicitly needed.

---

## 2. `HANDOFF.md` Schema (Living Single Source of Truth)

`HANDOFF.md` lets any newly spawned agent or next-day human session orient in under 60 seconds without reading the entire commit history.

```markdown
# HANDOFF — <Project or Service Name>

## 1. System / Architecture Summary
- Stack, runtime hosts/environments, entry points, key constraints.
- (If root of a multi-project workspace, link to child `HANDOFF.md` files here.)

## 2. Current State (as of YYYY-MM-DD HH:MM UTC)
- **Active branch(es):** `<branch>` (status: in progress / awaiting QA / merged)
- **Recently completed:** Short bullet list with commit SHAs / PR numbers.
- **Known blockers or risks:** Clear owner and mitigation.

## 3. Ordered Next Steps
1. Next atomic task + target branch + assigned role.
2. Subsequent task(s).

## 4. Subprojects (if applicable)
- `<service-a>/HANDOFF.md` — concise one-line status
- `<service-b>/HANDOFF.md` — concise one-line status
```

**Maintenance Rules:**
- Update `HANDOFF.md` when starting/completing a milestone, changing branches, or shifting priorities — not on every trivial tool call.
- Assign update ownership cleanly (usually the Coordinator or Lead) so parallel agents do not overwrite each other's `HANDOFF.md` edits.

---

## 3. `AGENT_BUS.md` & `QA_BUS.md` Schemas

### 3.1 Atomic Append Rule (Concurrency Safety)

Parallel agents **MUST NEVER** update `AGENT_BUS.md` or `QA_BUS.md` via full-file rewrite or read-then-patch edits, because concurrent writers will silently clobber earlier entries. Always:

1. Read the last ~20 lines first to check current state.
2. Append atomically using a single-quoted heredoc so the shell opens with `O_APPEND` and avoids unintended variable expansion:

```bash
cat <<'EOF' >> AGENT_BUS.md

### [2026-11-15 14:30 UTC] dev-1 -> qa-1,coordinator | RESULT feat/auth-middleware ready for QA
- Branch: `feat/auth-middleware` @ `a1b2c3d`
- Scope: `src/auth/middleware.ts`, `tests/auth/middleware.test.ts`
- Verification: `npm test -- auth` passed (14/14).
EOF
```

### 3.2 Message Format & Types

```markdown
### [YYYY-MM-DD HH:MM UTC] <from> -> <to> | <TYPE> <concise subject>
- <bullets with exact paths, line ranges, commit SHAs, or command output summaries>
```

| `<TYPE>` | Emitter | Purpose |
| --- | --- | --- |
| `TAKEOVER` | Newly spawned agent | Acknowledge brief and scope before starting |
| `BRIEF` | Coordinator | Assign scoped atomic task (when file-bus mode is active) |
| `ACTION` | `deploy-agent` / `dev-agent` | State pre-flight intent before mutating shared state |
| `RESULT` | `research-agent` / `dev-agent` / `deploy-agent` | Deliver verified artifacts and checks |
| `CONCERN` | Any worker | Flag unexpected state, failure, or scope collision immediately |
| `QA APPROVE` | `qa-agent` | Clear deliverable for execution or merge (cite evidence) |
| `QA HOLD` | `qa-agent` | Block progression with numbered defects + line/log citations |
| `STATUS` | Any agent | Periodic milestone update on long-running lanes |

### 3.3 Optional `QA_BUS.md` and `status/<agent>.md`

- **`QA_BUS.md`:** Useful in high-throughput swarms when separating `QA APPROVE` / `QA HOLD` verdicts from general chatter helps the Coordinator track gates cleanly. Follows the exact same `cat <<'EOF' >> QA_BUS.md` rule.
- **`status/<agent>.md`:** Optional single-line/short-card snapshot per agent (e.g., `status/dev-1.md`, `status/qa-1.md`). An agent may overwrite **only its own** `status/<name>.md` file.

---

## 4. Subdirectory Scoping (Monorepos & Multi-Project Workspaces)

In a workspace holding multiple services, packages, or independent subprojects:

```text
workspace/
├── HANDOFF.md                  # Thin root index + cross-project priorities
├── AGENT_BUS.md                # Cross-project / root coordination only
├── services/
│   ├── billing/
│   │   ├── HANDOFF.md          # Billing architecture, branches, next steps
│   │   └── AGENT_BUS.md        # Billing-specific worker/QA bus (if file-bus mode)
│   └── web-ui/
│       ├── HANDOFF.md          # Web UI state, branches, next steps
│       └── AGENT_BUS.md
```

**When a subdirectory needs its own `HANDOFF.md` & `AGENT_BUS.md`:**
1. It is a nested Git repository or independently versioned/deployed service.
2. Multiple agents work inside that subdirectory across sessions with domain-specific runbooks, environments, or invariants.
3. Dumping its implementation details into root `HANDOFF.md` would bloat context for agents working in sibling directories.

**Scoping Contract:**
- **Root `HANDOFF.md`** stays compact and points to `<subproject>/HANDOFF.md` with a one-line status summary — never duplicate child details upward.
- **Child agents** working inside `services/billing/` read and update `services/billing/HANDOFF.md` (and `services/billing/AGENT_BUS.md` when file-bus mode is active).
- **Cross-boundary changes** (shared contracts, workspace CI, root tooling) update root `HANDOFF.md` and reference affected child docs.

---

## 5. Secret Hygiene Across All Coordination Files

- **NEVER** write passwords, API tokens, SSH private keys, session cookies, webhook secrets, encryption passphrases, or raw `.env` values into `HANDOFF.md`, `AGENT_BUS.md`, `QA_BUS.md`, `status/*.md`, or native board posts.
- Refer to credentials strictly by **variable name, key path, file permissions, and byte length** (e.g., `"API_TOKEN present in .env, mode 0600, len=40"`).
- Always run output-redaction checks (`grep -iE "password|token|secret|key|bearer|authorization"`) before pasting diagnostic logs into any shared artifact.
