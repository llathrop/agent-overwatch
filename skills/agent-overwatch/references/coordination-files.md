# Coordination Files & Built-In Supersession

Standards for `HANDOFF.md`, `AGENT_BUS.md`, the coordinator lease, optional `QA_BUS.md` / `status/<agent>.md`, built-in tool supersession, and monorepo subdirectory scoping.

---

## 1. Built-In Tool Supersession Matrix

Always prefer the host runtime's native coordination primitives over file polling when both exist:

| Environment | Live Coordination Mechanism | `AGENT_BUS.md` Role | `HANDOFF.md` Role |
| --- | --- | --- | --- |
| **Swarm message board** | **Superseded by** the board's post/read/wait primitives (cite message IDs instead of copy-pasting) | Omit for live chat; optional only if a Git-committed summary log is desired | Maintained at milestones/handoffs |
| **Native Parent / Subagent Messaging** | **Superseded by** native `send_message` / subagent response channel | Optional unless multiple asynchronous peers/sessions need shared file history | Maintained at milestones/handoffs |
| **Native agent teams / shared task board** | **Superseded by** native teammate messaging & shared task list | Optional for cross-session persistence | Maintained at milestones/handoffs |
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
- **Coordinator:** `<session id>` (lease in `status/coordinator.lease`)
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
- Update `HANDOFF.md` when starting/completing a milestone, changing branches, or shifting priorities, not on every trivial tool call.
- Assign update ownership cleanly (usually the Coordinator or Lead) so parallel agents do not overwrite each other's `HANDOFF.md` edits.
- **Size caps:** keep each table cell or bullet at 200 characters or fewer and the whole file around 150 lines. It is a current-state summary; history, evidence, and long explanations go to the bus, and `HANDOFF.md` points at them.
- **Rate-limit pauses:** when a session pauses on a 429 or usage limit, it records running lanes, branch@SHA, pending verdicts, and the next step here so another session can resume.

---

## 3. `AGENT_BUS.md` & `QA_BUS.md` Schemas

### 3.1 Atomic Append Rule (Concurrency Safety)

Parallel agents **MUST NEVER** update `AGENT_BUS.md` or `QA_BUS.md` via full-file rewrite or read-then-patch edits, because concurrent writers will silently clobber earlier entries. Always:

1. Read the last ~20 lines first to check current state.
2. Append with `scripts/bus_append.sh`. It stamps the UTC time itself (never hand-type timestamps), appends atomically (using `flock` when available), and refuses a body or subject that matches a secret pattern, reporting only the line number:

```bash
scripts/bus_append.sh --from dev-1 --to qa-1,coordinator --type RESULT \
  --subject "feat/auth-middleware ready for QA" --ref auto <<'EOF'
- Scope: `src/auth/middleware.ts`, `tests/auth/middleware.test.ts`
- Verification: `npm test -- auth` passed (14/14).
EOF
```

Other flags: `--ref BRANCH@SHA` to name a ref explicitly, `--bus PATH` for a non-default bus file (e.g. a subproject's or `QA_BUS.md`), `--repo DIR` to resolve `--ref auto` in another checkout.

**Fallback** when the script is not installed: a single-quoted heredoc append (`cat <<'EOF' >> AGENT_BUS.md`), with the timestamp taken from `date -u '+%F %T'` rather than typed by hand.

### 3.2 Message Format & Types

```markdown
### [YYYY-MM-DD HH:MM:SS UTC] <from> -> <to> | <TYPE> [<branch>@<sha12>] <concise subject>
- <bullets with exact paths, line ranges, commit SHAs, or command output summaries>
```

**QA verdict header (branch- and SHA-bound):**

```markdown
### [YYYY-MM-DD HH:MM:SS UTC] qa-1 -> coordinator,dev-1 | QA APPROVE feat/auth-middleware@1a2b3c4d5e6f auth middleware
```

- The author field must contain `qa`, and QA writes the entry itself (`bus_append.sh --type "QA APPROVE"|"QA HOLD" --ref auto`). The coordinator never writes or relays a verdict.
- The body cites evidence: commands run, their outputs, and `file:line` references.
- `verify_atomic_branch.sh` takes the latest verdict for the branch; it must be `QA APPROVE` and its SHA must match HEAD (prefix of 7+ characters). A newer commit, or a later `QA HOLD`, blocks the merge until QA re-reviews.

| `<TYPE>` | Emitter | Purpose |
| --- | --- | --- |
| `TAKEOVER` | New coordinator session / newly spawned agent | Coordinator replacement (posted automatically by `coordinator_lease.sh claim --takeover`), or an agent acknowledging its brief |
| `BRIEF` | Coordinator | Assign scoped atomic task (when file-bus mode is active) |
| `ACTION` | `deploy-agent` / `dev-agent` | State pre-flight intent before mutating shared state |
| `RESULT` | `research-agent` / `dev-agent` / `deploy-agent` | Deliver verified artifacts and checks |
| `CONCERN` | Any worker | Flag unexpected state, failure, or scope collision immediately |
| `QA APPROVE` | `qa-agent` only | Clear `<branch>@<sha12>` for execution or merge (cite evidence) |
| `QA HOLD` | `qa-agent` only | Block `<branch>@<sha12>` with numbered defects + line/log citations |
| `STATUS` | Any agent | Periodic milestone update on long-running lanes |
| `USAGE` *(optional)* | Coordinator | Usage/spend figure and its source when the runtime reports one (e.g. near 75%/90% of a limit) |

### 3.3 Optional `QA_BUS.md` and `status/<agent>.md`

- **`QA_BUS.md`:** Useful in high-throughput swarms when separating `QA APPROVE` / `QA HOLD` verdicts from general chatter helps the Coordinator track gates cleanly. Append with `scripts/bus_append.sh --bus QA_BUS.md` (same rules as the main bus); fallback: a quoted heredoc append (`cat <<'EOF' >> QA_BUS.md`).
- **`status/<agent>.md`:** Optional single-line/short-card snapshot per agent (e.g., `status/dev-1.md`, `status/qa-1.md`). An agent may overwrite **only its own** `status/<name>.md` file.

### 3.4 Committing the Bus Across Parallel Branches

When `AGENT_BUS.md` is committed and several branches each append to it, ordinary merges conflict at the file end. `init_workspace.sh` adds this line to `.gitattributes`:

```text
AGENT_BUS.md merge=union
```

Union merge keeps both sides' appended lines. It is safe only because the bus is append-only; never use it for `HANDOFF.md`.

---

## 4. Coordinator Lease & Takeover

Only one session should coordinate a workspace at a time. The lease file `status/coordinator.lease` (key=value: `id`, `since`, `last_seen` in UTC) records which one.

```bash
scripts/coordinator_lease.sh status --id "$SESSION_ID"   # 0 = held by me, 3 = held by another live id, 4 = expired/none
scripts/coordinator_lease.sh claim  --id "$SESSION_ID" --ttl 30
scripts/coordinator_lease.sh renew  --id "$SESSION_ID"   # at each batch boundary
scripts/coordinator_lease.sh release --id "$SESSION_ID"  # when handing off cleanly
```

- **Every session checks `status` before acting** on the workspace (dispatching, merging, editing `HANDOFF.md`).
- `claim` refuses while another id holds a non-expired lease. To replace a stale or abandoned coordinator, use `claim --takeover`, which also appends a `TAKEOVER` entry to the bus.
- **A returning session that sees itself replaced** (status exit 3) stands down, or posts on the bus and coordinates with the current holder. It does not resume merging or dispatching.
- `overwatch_watch.sh` warns when the lease goes stale.

---

## 5. Subdirectory Scoping (Monorepos & Multi-Project Workspaces)

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

## 6. Secret Hygiene Across All Coordination Files

- **NEVER** write passwords, API tokens, SSH private keys, session cookies, webhook secrets, encryption passphrases, or raw `.env` values into `HANDOFF.md`, `AGENT_BUS.md`, `QA_BUS.md`, `status/*.md`, or native board posts.
- Refer to credentials strictly by **variable name, key path, file permissions, and byte length** (e.g., `"API_TOKEN present in .env, mode 0600, len=40"`).
- Always run output-redaction checks (`grep -iE "password|token|secret|key|bearer|authorization"`) before pasting diagnostic logs into any shared artifact. `bus_append.sh` also refuses entries that match a secret pattern.
- **False positives:** add a regex per line to `.overwatch/secret-allowlist` (created by `init_workspace.sh`, read by `overwatch_watch.sh --allowlist`). Allowlist the specific pattern or path, never a broad match.
- **Reporting a hit:** give `file:line` and the pattern name (e.g. `config/app.yml:12 aws-access-key`), never the matched value.
