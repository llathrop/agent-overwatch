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
  1. Run `scripts/coordinator_lease.sh status` before acting; `claim` (or `claim --takeover` for a stale lease) and `renew` while active. If the lease shows you were replaced, stand down or coordinate on the bus.
  2. Partition work into collision-free lanes before spawning writers.
  3. Scale QA to the review load so verification doesn't queue.
  4. Keep turns short: delegate coding, deep reading, builds, and deploys; avoid becoming a serial bottleneck.
  5. Don't wait to do something that must be done in the project. If a lane is busy and another required slice doesn't depend on it, start that slice now with a separate agent. Don't invent optional work to fill the wait.
  6. Route raw diffs, exact paths, and test outputs directly to QA (never paraphrase away evidence).
  7. Merge only after QA's own `QA APPROVE <branch>@<sha12>` matches the branch HEAD and `verify_atomic_branch.sh` passes.
  8. Track usage when the runtime reports it and warn the user near limits (see `model-routing-and-scaling.md` section 5).
- **Anti-Patterns:**
  - Two writers assigned to overlapping files or the same branch/worktree.
  - Implementing large patches inline while workers wait on you.
  - Writing, paraphrasing, or relaying a QA verdict ("QA says it's fine") instead of letting QA post its own.
  - Running a command QA was denied, on QA's behalf.
  - Deferring a required, independent slice until the current lane finishes; or, the opposite, spawning speculative work nobody asked for.
  - Letting an unverified branch pile up across multiple milestones.
  - Ignoring or softening a `QA HOLD`.

#### User-Facing Progress Reporting

The Coordinator bridges parallel agent execution and the human user. Never go silent through multiple phases or expect the user to read `AGENT_BUS.md`, swarm boards, or raw subagent replies.

- **Report at every batch/gate boundary:** When a research plan clears QA, a feature branch merges, or a rollout completes, give the user a self-contained update right away alongside what parallel work is starting next.
- **Always include:** (1) what was built/changed and why (plus key technical choices/tradeoffs), (2) anything `qa-agent` flagged (`QA HOLD` / hygiene catch) and how it was resolved, (3) verified test/check status, and (4) next active lanes or user confirmations required.
- **Keep it concise and secret-free:** Summarize outcomes without pasting raw terminal walls or credentials.

| Quality | Example Progress Update | Why It Works / Fails |
| --- | --- | --- |
| **Good (Self-Contained)** | *"Merged `feat/rate-limiter` (`a1b2c3d`) into `main`. Added sliding-window throttling backed by Redis sorted sets instead of a fixed counter to avoid boundary bursts. During pre-merge QA, `qa-agent` flagged a missing `429 Retry-After` header and a test fixture using an unredacted token string; `dev-agent` added the header check and replaced the fixture (`pytest`: 18/18 passed). Next: `dev-2` is starting `feat/metrics-export` while `research-1` evaluates cache eviction."* | Self-contained, explains technical tradeoff, surfaces QA catches and exact fixes, reports verified tests, and previews parallel next work. |
| **Bad (Opaque / Delayed)** | *"Updated #12 and #14 on the board; moving to step 3."* *(or saying nothing until 6 branches finish)* | Assumes user reads internal bus/board IDs, hides QA catches and tradeoffs, leaves user blind across slow phases. |

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
  1. Read modified files, plans, and local git diffs (`git diff`, `git log`, `git rev-parse`) to audit logic, architecture, edge cases, and the test/verification outputs posted by `dev-agent` and `deploy-agent`. Running test suites, linters, builds, Docker containers, or live probes is out of QA scope — if checks are missing or stale, issue `QA HOLD` directing the owning lane to run them and post output.
  2. Maintain zero-trust: never mark `APPROVE` from someone else's summary without observing the artifact or command output directly.
  3. Scan diffs, logs, and coordination artifacts for accidentally leaked secrets or credentials.
  4. Post its own verdict, bound to the exact commit, from the branch's checkout:
     ```bash
     scripts/bus_append.sh --from qa-1 --to coordinator,dev-1 --type "QA APPROVE" \
       --subject "parser error handling" --ref auto <<'EOF'
     - Verified dev-1 posted `pytest tests/parser` output (31 passed on HEAD)
     - Checked src/parser.py:40-72 (empty input path handled)
     EOF
     ```
     `--ref auto` records `<branch>@<sha12>`. **`QA APPROVE`** lists verified files, checks run, and scope; **`QA HOLD`** numbers each blocking issue with `file:line`/log citations and fix criteria. Any later commit on the branch needs a fresh review.
  5. For live deploys, react to `scripts/overwatch_watch.sh` events (`BUS:`, `SECRET?`, `CHECK-FAIL`) instead of assuming it can watch continuously; a subagent's turn ends.
  6. If a command is denied, say so in the verdict and verify from the evidence others posted. Never work around a permission denial.
- **Anti-Patterns:**
  - Editing code, fixing typos, or restarting services directly (creates race conditions and hides systemic author/ops errors).
  - Running test suites, linters, builds, Docker containers, or live host probes yourself instead of directing `dev-agent` or `deploy-agent` via `QA HOLD`.
  - Rubber-stamping an unrun test suite or partial diff.
  - Approving by message to the coordinator instead of a ref-bound bus entry.

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
- [ ] The verdict ref matches the branch HEAD being reviewed (`git rev-parse --short=12 HEAD`).
- [ ] No hardcoded secrets, tokens, private keys, or sensitive `.env` files are staged or committed.
- [ ] Docs/`HANDOFF.md` reflect any changed behavior, flags, or setup steps.

### 3.3 Operations / Deploy Audit (Pre-Deploy & Post-Deploy)

- [ ] **Pre-deploy:** Backup artifact exists, is non-empty, and uses restrictive permissions where sensitive; dry-run/syntax check passed.
- [ ] **During rollout:** `overwatch_watch.sh` runs with the agreed `--check` health commands, and every `CHECK-FAIL` / `SECRET?` event was looked at.
- [ ] **Post-deploy:** Target service/release reports healthy status; unrelated services remain undisturbed; error logs show zero new regressions.
- [ ] **Secret hygiene:** Rollout output, status snapshots, and bus logs contain zero secret values.

---

## 4. QA Permissions Recipe (Enforce Read-Only)

A prompt that says "read-only" is enforced only by the model following it. Use the runtime's own controls as well:

- **Tool lists:** give the QA and research agents a tool set with no edit, write or notebook-edit tools (read, search, and a minimal inspection shell only). Because a shell can still write, restrict your runtime's permission allowlist to local git inspection and bus verdict posting (`git diff`, `git log`, `git status`, `git rev-parse`, `bus_append.sh`), and leave everything else to prompt or deny. Running tests and live probes belongs to `dev-agent` and `deploy-agent`, not QA. The adapter reference below shows the per-tool syntax.
- **Other controls:** sandbox or approval modes, per-agent tool lists, command allowlists.
- **When QA is denied:** QA states which command was denied and verifies from the evidence that authors or deployers posted (command plus output, `file:line`). It never works around the denial with another tool or path.
- **The coordinator** must not run denied commands on QA's behalf. If the evidence is not enough, ask the owning lane to post it, or ask the user to grant the permission.

---

## 5. Adapter reference (per tool)

This section is tool-specific and optional. The role logic in sections 1 to 4 applies to any runtime. The subagent definitions under `agents/*.md` use Antigravity's native plugin frontmatter (`subagent: true`, `mainAgent: false`, `tools: [...]`) alongside **tool-neutral system prompt instructions** in the Markdown body so any installer or runtime can adapt the frontmatter cleanly without rewriting the role logic.

| Portable Role File | Capability Scope | Antigravity Native (`agents/*.md`) | Claude Code (`~/.claude/agents/*.md`) | Codex / Gemini CLI / Cursor |
| --- | --- | --- | --- | --- |
| `agents/qa-agent.md` | Read-only + read-only verification shell + web | `tools: [read_file, run_command, search_web]` | `tools: Read, Glob, Grep, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/research-agent.md` | Read-only + inspection shell + web | `tools: [read_file, run_command, search_web]` | `tools: Read, Glob, Grep, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/dev-agent.md` | Full read/edit/write/shell/task/web | `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` | `tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |
| `agents/deploy-agent.md` | Full read/edit/write/shell/task/web | `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` | `tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, WebSearch, WebFetch` | Inline role prompt in `AGENTS.md` / `.mdc` rules |

**Installer Mapping Rules:**
1. **Antigravity:** Installs `plugin.json`, `skills/`, and generated `dist/antigravity/agents/*.md`. Live `GetAllPlugins` checks and built-in `migrate-agent-settings/SKILL.md` confirmed that omitting `tools:` falls back to a 5-tool default lacking `run_command`, `edit_file`, `write_file`, and `manage_task`, while native YAML `tools:` lists grant those exact tools plus `send_message`. Generated Antigravity agents emit explicit `tools:` lists and drop `edit_file`/`write_file` from read-only roles (`qa-agent`, `research-agent`).
2. **Claude Code:** Translates `tools:` entries using the mapping above, strips Antigravity-specific keys (`subagent`, `mainAgent`, `manage_task`), maps `manage_task` to `TodoWrite`, and strips write tools from `qa-agent` and `research-agent`.
3. **Codex / Gemini CLI / Cursor:** Installs `skills/agent-overwatch/` into Codex's `.agents/skills/` (with standalone `.codex/agents/*.toml` role configs), Gemini commands + `GEMINI.md`, or `.cursor/rules/agent-overwatch.mdc`.

**Install options** (from the repository root of https://github.com/llathrop/agent-overwatch):
- `./install.sh` copies the skill and generated agent files into the chosen runtime's folders (recommended for Antigravity, because Antigravity's customization scanner skips symlinks).
- `./install.sh --link` symlinks the skill folder and generated agents instead for runtimes that follow symlinks (documented for Codex; **skipped by Antigravity**, and unverified for Claude Code skill dirs — prefer Claude's marketplace plugin install).
- `./install.sh --uninstall` removes what the installer placed.
- Claude Code can also install it as a native plugin: `/plugin marketplace add llathrop/agent-overwatch`, then install the `agent-overwatch` plugin from that marketplace (see the repository README for the exact names).

---

**Claude Code QA permissions example:** the installer generates `tools: Read, Glob, Grep, Bash, WebSearch, WebFetch` for QA and research agents (no `Edit`, `MultiEdit`, `Write` or `NotebookEdit`). Allowlist only local git inspection and bus verdict posting in `.claude/settings.json`, for example `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git status:*)`, `Bash(git rev-parse:*)`, and `Bash(*bus_append.sh:*)`.
