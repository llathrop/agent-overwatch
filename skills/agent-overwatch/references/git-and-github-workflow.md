# Git, Parallel Worktrees & Remote Repository Workflow

Disciplined atomic branching, incremental QA-gated merges, and remote safety rules for both personal/fork repositories and public upstream projects.

---

## 1. Atomic Branching & Incremental Merge Lifecycle

Never build five unrelated milestones on one giant branch and try to review/merge everything at the end. Keep every branch **small, single-purpose, independently testable, and short-lived**.

### 1.1 Branch Naming

| Prefix | Use For | Example |
| --- | --- | --- |
| `feat/<topic>` | New feature or capability slice | `feat/core-skill-and-agents` |
| `fix/<topic>` | Targeted bug or regression fix | `fix/retry-backoff-overflow` |
| `docs/<topic>` | Documentation, guides, runbooks | `docs/api-auth-examples` |
| `ops/<topic>` | Infrastructure, CI, deployment config | `ops/add-smoke-workflow` |
| `refactor/<topic>` | Behavior-preserving structural cleanup | `refactor/extract-token-parser` |
| `chore/<topic>` | Dependency pins, repo hygiene | `chore/pin-runtime-digests` |

### 1.2 Incremental Merge Loop (Mandatory)

```text
  main (clean, verified)
    │
    ├──► 1. git checkout -b feat/slice-a main
    │       ├── dev-agent implements + runs tests, commits, posts RESULT feat/slice-a@<sha12>
    │       └── qa-agent audits that exact SHA and posts its own
    │           QA APPROVE feat/slice-a@<sha12>  (bus_append.sh --ref auto)
    │           (new commits after this? -> back to qa-agent for re-review)
    │
    ├──◄ 2. verify_atomic_branch.sh passes (verdict matches HEAD)
    │       Merge feat/slice-a -> main immediately (PR or local merge)
    │       Delete merged feat/slice-a branch/worktree
    │
    └──► 3. git checkout -b feat/slice-b main  (branched from updated main!)
            ├── dev-agent implements + runs tests
            └── qa-agent audits ──► ...
```

**Why this matters:**
- Every merge keeps `main` green and releasable.
- QA diffs stay small (tens or hundreds of lines, not thousands), catching subtler defects faster.
- Parallel branches rebase onto updated `main` cleanly with minimal conflict radius.

### 1.3 Verdict-Bound Merge Gate

- **QA writes its own verdict** on the bus with `scripts/bus_append.sh --type "QA APPROVE" --ref auto` (or `"QA HOLD"`), run from the branch checkout so the ref is `<branch>@<sha12>` (from a worktree with a shared bus: `--repo <worktree> --bus <main-checkout>/AGENT_BUS.md`). The body cites commands, outputs, and `file:line` evidence.
- **The coordinator never writes or relays a verdict.** A coordinator entry saying "QA approved" does not count, and the gate ignores it (the author must contain `qa`).
- **New commits invalidate an approval.** If the branch HEAD moves after `QA APPROVE`, QA must review the new SHA.
- **Gate before merging:** run `scripts/verify_atomic_branch.sh`. It checks the latest verdict for this branch, requires `QA APPROVE` with a SHA matching HEAD, and secret-scans the lines added by every commit since the merge base. With no matching verdict it fails.
- **`--allow-external-qa`** skips the verdict requirement with a warning. Use it only when QA is recorded somewhere else on purpose (for example an approved PR review), and say so in the merge message. `--allow-bus-only` is a deprecated alias.

---

## 2. Isolating Parallel Authors with `git worktree`

When two or more `dev-agent` instances write concurrently in the same repository, they **MUST NOT** share one working tree (`HEAD`, staging index, and untracked files will collide).

Give each concurrent author its own worktree and atomic branch:

```bash
# Coordinator / setup creates isolated worktrees off updated main
git worktree add ../wt-parser -b feat/parser-errors main
git worktree add ../wt-cli    -b feat/cli-flags main
```

- Author 1 works exclusively inside `../wt-parser` on `feat/parser-errors`.
- Author 2 works exclusively inside `../wt-cli` on `feat/cli-flags`.
- Readers and `qa-agent` inspect each branch/worktree read-only (`git -C ../wt-parser diff main...HEAD` or `git diff main...feat/parser-errors`).
- **Committed bus:** if `AGENT_BUS.md` is committed and several branches append to it, keep `AGENT_BUS.md merge=union` in `.gitattributes` (added by `init_workspace.sh`) so those appends merge without conflicts.
- **Critical Cleanup Rule:** NEVER remove a worktree (`git worktree remove`) until its commits are merged into `main` (or explicitly archived/abandoned by coordinator decision). Removing a worktree with unmerged work risks losing the lane's changes.

---

## 3. GitHub / GitLab Workflow: Own Repos & Own Forks

For repositories or personal forks owned by the user/team:

1. **Create or reference an Issue** for the atomic unit of work so intent and acceptance criteria are tracked:
   ```bash
   gh issue create --title "feat: add rate limiter middleware" --body "..."
   ```
2. **Branch, implement, test, and pass `qa-agent` audit** locally first.
3. **Push the atomic branch and open a Pull Request** linked to the Issue, including exact test output and QA verification summary:
   ```bash
   git push -u origin feat/rate-limiter
   gh pr create \
     --title "feat: add rate limiter middleware" \
     --body "Closes #42\n\n## Verification\n- \`pytest tests/test_rate_limit.py\`: 12 passed\n- QA Verdict: QA APPROVE feat/rate-limiter@<sha12> (AGENT_BUS.md)"
   ```
4. **Merge once CI + QA pass** and `verify_atomic_branch.sh` succeeds for the current HEAD, then sync local `main` and prune the feature branch:
   ```bash
   gh pr merge --squash --delete-branch
   git checkout main && git pull --ff-only
   ```
5. Cut the next atomic branch from updated `main`.

---

## 4. Public & Upstream Repositories (Strict Safety Guardrail)

Contributing to an external/public upstream repository carries reputational and process obligations.

### 4.1 Mandatory Preparation (Read-Only)

Before proposing changes, `research-agent` or `dev-agent` MUST read and follow:
- `CONTRIBUTING.md`, `DEVELOPMENT.md`, `CODE_OF_CONDUCT.md`
- `.github/ISSUE_TEMPLATE/*` and `.github/PULL_REQUEST_TEMPLATE.md`
- Code style, commit message conventions (e.g., Conventional Commits, DCO `Signed-off-by:`), and required local test/lint suites.
- Existing open issues/PRs to avoid duplicating ongoing upstream work.

### 4.2 Mandatory Stop-and-Ask Gate Before Any Upstream Action

**ALWAYS ask the user for clarification and explicit confirmation BEFORE executing ANY action that affects a remote public/upstream repository**, including:
- Creating or commenting on an upstream GitHub/GitLab Issue or Discussion
- Pushing a branch to a shared or upstream remote (`git push upstream ...`, or pushing a PR-ready branch meant for upstream submission if remote visibility is external)
- Creating, editing, force-pushing, or commenting on an upstream Pull Request
- Modifying repository settings, labels, releases, or tags

**Safe Local Staging Pattern for Upstream Contributions:**
1. Do all exploration, coding, local tests, and `qa-agent` audit locally on an atomic branch (or local clone of the user's fork).
2. Present the exact proposed PR title, body (conforming to the upstream template), diff summary, test evidence, and target repo/branch to the user.
3. Wait for explicit user approval before running `gh issue create`, `git push`, or `gh pr create`.
