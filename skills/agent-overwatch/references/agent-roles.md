# Agent Roles, Brief Templates & QA Checklists

Detailed execution playbooks, handoff contracts, and mandatory QA verification gates for all five roles in `agent-overwatch`.

---

## 1. Self-Contained Brief Template

A freshly spawned worker sees only what is inside its brief and the files it reads. Never omit ownership, constraints, or "done" checks.

```markdown
Role: <research-agent | dev-agent | deploy-agent | qa-agent>
Branch / Worktree: <e.g., feat/add-rate-limiter at ../wt-rate-limiter, or read-only>
Goal: <one sentence describing the exact outcome>
Owned Scope (may touch):
- <exact files, directories, services, or investigation questions>
Off-Limits (must NOT touch):
- <sibling files, main branch, prod hosts, other agents' worktrees>
Known Inputs & References:
- <paths, commit SHAs, board message IDs, issue numbers>
Verification / Done Criteria:
- <exact tests, linters, dry-runs, or read-only checks to run>
Next Handoff:
- Report diff/results + verification output to <qa-agent / coordinator> via <native channel or AGENT_BUS.md>.
```

---

## 2. Role Playbooks & Anti-Patterns

### 2.1 Coordinator / Orchestrator

- **Core Duties:**
  1. Partition work into collision-free lanes before spawning writers.
  2. Keep 1 `qa-agent` assigned per 2–4 active workers.
  3. Keep turns short — delegate coding, deep reading, builds, and deploys; avoid becoming a serial bottleneck.
  4. Dispatch non-dependent future work whenever an active lane hits a slow build, test run, or deploy soak.
  5. Route raw diffs, exact paths, and test outputs directly to QA (never paraphrase away evidence).
  6. Own final merge decisions only after `QA APPROVE`.
- **Anti-Patterns:**
  - Two writers assigned to overlapping files or the same branch/worktree.
  - Implementing large patches inline while workers wait idle.
  - Letting an unverified branch pile up across multiple milestones.
  - Ignoring or softening a `QA HOLD`.

### 2.2 Research / Planner Agent (`research-agent`)

- **Core Duties:**
  1. Inspect code, configs, docs, dependencies, and logs in read-only mode.
  2. Cite exact file paths, line ranges, symbol names, commit SHAs, or command outputs directly observed. Clearly label any inference as inferred.
  3. Deliver actionable plans containing: target files/commands, edge cases, failure modes, pre-execution backups (if operational), verification gates, and rollback instructions.
- **Anti-Patterns:**
  - Editing source/config files or mutating runtime environments during exploration.
  - Reporting unverified APIs, assumed package versions, or guessed file contents as fact.
  - Shipping plans without concrete verification gates or rollback steps.

### 2.3 Development / Author Agent (`dev-agent`)

- **Core Duties:**
  1. Work exclusively inside the assigned atomic branch and file scope (or dedicated `git worktree`).
  2. Write minimal, cohesive diffs plus tests covering happy path and failure/edge cases.
  3. Run unit/integration tests, linters, and formatting locally after the final edit.
  4. Never hardcode or log secrets, tokens, keys, or personal credentials.
  5. Hand off branch name, commit SHA, `git diff --stat`, and exact test output to `qa-agent`.
- **Anti-Patterns:**
  - Opportunistic refactoring outside assigned files that collides with parallel workers.
  - Merging directly into `main` without `QA APPROVE`.
  - Claiming tests pass after editing a file without re-running tests.

### 2.4 Deployment / Operations Agent (`deploy-agent`)

- **Core Duties:**
  1. Confirm `qa-agent` approved the rollout plan BEFORE changing runtime state.
  2. Snapshot/backup current config, schema, or binary versions with verified permissions (`0600`/`0700` for sensitive backups).
  3. Run `--dry-run` / `config --quiet` / syntax validation before applying.
  4. Apply one atomic rollout slice at a time; run health checks, log checks, and smoke tests.
  5. Keep an explicit stop-condition rule: if health degrades or invariants fail, execute documented rollback immediately.
- **Anti-Patterns:**
  - Improvising untested config edits directly on a production host during a rollout.
  - Skipping pre-change backups or forgetting `--no-deps` / targeted flags when updating one service.
  - Printing environment files, tokens, or connection secrets into terminal logs or bus messages.

### 2.5 Mandatory QA / Overwatch Agent (`qa-agent`)

- **Core Duties:**
  1. Independently re-read modified files/plans and run read-only verification (`git diff`, test commands, schema checks, read-only health/log probes).
  2. Maintain zero-trust: never mark `APPROVE` from someone else's summary without observing the artifact or command output directly.
  3. Scan diffs, logs, and coordination artifacts for accidentally leaked secrets or credentials.
  4. Emit one clear verdict:
     - **`QA APPROVE`** with verified file paths, line numbers, checks run, and exact scope.
     - **`QA HOLD`** with numbered blocking issues, exact file/line/log citations, and concrete fix criteria.
- **Anti-Patterns:**
  - Editing code, fixing typos, or restarting services directly (creates race conditions and hides systemic author/ops errors).
  - Rubber-stamping an unrun test suite or partial diff.

---

## 3. Role-Specific Mandatory QA Audit Checklists

### 3.1 Plan / Research Audit (Before Execution)

- [ ] Every claimed file path, dependency version, digest, or API behavior is verified or explicitly marked inferred.
- [ ] File/host ownership is non-overlapping with concurrent lanes.
- [ ] Failure modes, race conditions, and ordering dependencies are addressed.
- [ ] Pre-change backup commands (with safe permissions) and exact rollback commands are present.
- [ ] Concrete pass/fail verification gates exist (dry-run, config check, smoke probe).

### 3.2 Code / Diff Audit (Before Merge)

- [ ] `git diff` stays strictly inside the assigned atomic slice and branch.
- [ ] Logic handles boundary/error cases cleanly without hidden duplication.
- [ ] Automated tests and linters ran *after the final edit* and passed without skipped/relaxed assertions.
- [ ] No hardcoded secrets, tokens, private keys, or sensitive `.env` files are staged or committed.
- [ ] Docs/`HANDOFF.md` reflect any changed behavior, flags, or setup steps.

### 3.3 Operations / Deploy Audit (Pre-Deploy & Post-Deploy)

- [ ] **Pre-deploy:** Backup artifact exists, is non-empty, and uses restrictive permissions where sensitive; dry-run/syntax check passed.
- [ ] **Post-deploy:** Target service/release reports healthy status; unrelated services remain undisturbed; error logs show zero new regressions.
- [ ] **Secret hygiene:** Rollout output, status snapshots, and bus logs contain zero secret values.

---

## 4. Installer & Platform Tool Mapping

The subagent definitions under `agents/*.md` use Antigravity's native plugin frontmatter (`subagent: true`, `mainAgent: false`, `tools: [...]`) alongside **tool-neutral system prompt instructions** in the Markdown body so any installer or runtime can adapt the frontmatter cleanly without rewriting the role logic.

| Portable Role File | Capability Scope | Antigravity Native (`agents/*.md`) | Claude Code (`~/.claude/agents/*.md`) | Codex / Gemini CLI / Cursor |
| --- | --- | --- | --- | --- |
| `agents/qa-agent.md` | Read-only + read-only verification shell + web | `tools: [read_file, run_command, search_web]` | `tools: Read, Glob, Grep, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/research-agent.md` | Read-only + inspection shell + web | `tools: [read_file, run_command, search_web]` | `tools: Read, Glob, Grep, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/dev-agent.md` | Full read/edit/write/shell/task/web | `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` | `tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/deploy-agent.md` | Full read/edit/write/shell/task/web | `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` | `tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |

**Installer Mapping Rules:**
1. **Antigravity:** Installs `plugin.json`, `skills/`, and `agents/*.md` directly (no tool rewriting needed).
2. **Claude Code:** Translates `tools:` entries using the mapping above, strips Antigravity-specific keys (`subagent`, `mainAgent`, `manage_task`), and optionally sets `model:` (`opus` / `sonnet` / `haiku`) unless uniform/fallback routing is selected.
3. **Codex / Gemini CLI / Cursor:** Installs `skills/agent-overwatch/` into the tool's skills folder (or projects instructions into `AGENTS.md` / `GEMINI.md` / `.cursor/rules/`) and drops unsupported agent frontmatter.
