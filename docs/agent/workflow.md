# Repository workflow

Read before every repository change. Routine choices within the authorized scope need no further approval.

## Branches and commits

Every independent change, documentation and maintenance included, lives on its own branch and ends with a pull request: one branch and PR per coherent task, follow-up fixes on the same branch until merge, unrelated work on separate branches. `main` receives only merges; the repository's first commit, which created `main`, is the single exception.

Before editing: read `AGENTS.md`, inspect `git status`, name the task scope. Fetch the remote and branch from the current `origin/main`. Unrelated changes already in the checkout stay as they are: work in a separate worktree. A follow-up on an existing task continues that task's branch.

Branch names are `<type>/<short-kebab-case-description>` in lowercase English, with the commit types below: `feat/dungeon-generator`, `fix/dash-cooldown`, `docs/agent-workflow`. The `pre-commit` hook enforces the shape and the `main` guard.

Commit subjects follow [Conventional Commits 1.0.0-beta.2](https://www.conventionalcommits.org/en/v1.0.0-beta.2/): `<type>[optional scope]: <description>`, for example `feat(combat): add dash cooldown`. Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`, `style`, `perf`, `revert`. Scopes follow the repository layout, plus `agent` for agent instructions and skills. Style: lowercase type, short imperative English description, no trailing period, no emoji or ticket prefix. An optional body and footer follow after blank lines; an incompatible change starts the body or footer with `BREAKING CHANGE: <explanation>` (beta.2 has no `!` shorthand). A change to a persisted format is breaking unless it bumps the format version. Issue references go in the footer.

Stage only intended files: review the diff for accidental files, secrets, keys, tokens and unrelated edits before committing.

## Design before code

A stage, feature or design that is not in the contract goes through `/grill-me-with-docs` before implementation. The user starts it; the lead proposes it whenever a task arrives without a settled stage. The session runs `grilling` (rounds until the frontier is empty) and `domain-modeling` (terms into `GLOSSARY.md` and decisions into `docs/adr/` the moment they crystallise).

The session is done when the contract holds everything the implementation needs:

- the stage in `docs/plan.md` with checkable acceptance criteria;
- one ADR per decision that passes the skill's three criteria; anything else is a line in the plan or a commit body;
- every term the stage introduces, in the glossary.

One open decision inside a planned stage gets `grilling` alone. A decision that passes the ADR criteria during implementation or review is recorded with `domain-modeling` on the task branch, in the same PR.

## Local hooks

`.githooks/` needs only Git and a POSIX shell. Enable once per clone with `make hooks` (`git config core.hooksPath .githooks`). `commit-msg` runs [`scripts/check-commit-msg.sh`](../../scripts/check-commit-msg.sh); `make commits` runs the same script over the branch as a backstop, so the gate catches a missing hook. `pre-commit` guards branch names and `main`. Hooks run on every commit; `--no-verify` is off the table.

## Before every push

This applies to PR updates too.

1. Run the checks the final diff needs, from the `Makefile`. Before a merge the gate passes on the PR's pushed revision, after `git fetch` so `make commits` checks the right range.
2. A documentation-only change gets an accuracy and link review and `git diff --check`; say so in the PR. A change to `AGENTS.md`, `docs/agent/`, agent definitions or skills is written with `writing-for-agents` loaded.
3. A failure is fixed and the affected checks rerun on the new revision; an earlier run proves nothing about the current one. A check that cannot run is reported with its exact command and blocker, and the push waits for it to pass or for the user's explicit exception.
4. `git diff --check`, the final diff and `git status` show only the intended change.

Push the task branch and open a PR against `main` titled like a commit subject, using the [PR template](../../.github/pull_request_template.md) rewritten around the final scope: the problem, the change, checks actually run with results (the gate's result for the pushed revision; a check that did not run is reported as not run), demonstration steps, limitations and follow-up. When the remote or PR creation is unavailable, leave the work ready locally and report the blocker. The final report names the branch and the PR link. A PR is left open for review; merging and publishing wait for the user's explicit request.

## Task lifecycle and Q&A

One session works on one stage from `docs/plan.md`, or a narrower task inside it: understand the request and existing behavior, clarify consequential unknowns, isolate the task, plan, delegate the bounded units per [delegation](delegation.md), integrate, verify, review, push, open or update the PR.

Before asking, check whether the conversation, the contract or the code already answers. When a question meets the criteria in `AGENTS.md`, ask in the grilling format: numbered questions, each with a recommended answer, worded so that "yes" accepts it; a round when several hang together, one question when it stands alone. Facts are found by looking, decisions are the user's.

Continue independent work while waiting; a missing answer is a blocked branch of the design tree, so the dependent choice waits. Accepted outcomes go into the plan, the glossary or a new ADR. New evidence that changes the agreed scope reopens the round.

Progress updates carry findings, uncertainty and the next action. The completion report carries change and purpose, checks actually run, demonstration, limitations, next step, branch and PR. A blocked task leaves a handoff: revision, preserved work, exact next action.

## Parallel work and review

Read [delegation](delegation.md) before every stage task. Independent tasks use separate worktrees, branches and PRs; within one task, agents own files exclusively and the lead alone mutates Git.

Review the integrated diff against the acceptance criteria, the non-negotiable rules and the glossary: a concept named differently from `GLOSSARY.md` is a finding, and so is a decision in the diff that should have been an ADR. Test evidence names the tested revision; after integration, conflict resolution or further edits the affected checks run again. A PR is ready once every required check passes.

Branch protection and merge enforcement are proposed separately when needed. Shared history stays as it is: force-pushes, rewrites and discarding another task's work happen only on the user's explicit authorization.
