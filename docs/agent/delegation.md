# Delegation and parallel work

Read before every stage task. The lead plans, decides and integrates; bounded work goes to subagents on the model that fits it. Any task with more than one independent part is delegated by default.

## Route work by kind

| Kind | Examples | Who |
|---|---|---|
| Judgment | Grill a design, plan a stage, decide a persisted format or migration, name a concept, root-cause a hard failure, review against the contract | Opus: the lead with `grilling` and `domain-modeling`, or `reviewer` / `investigator` for an independent opinion |
| Generation | Implement a specified change in assigned files, write tests, wire assets, update docs to an agreed outcome | Sonnet: `implementer` |
| Checks | Formatting, lint, tests, commit subjects, branch names, whether `make ci` passed | Deterministic commands: `make`, hooks, `git`. An exit code answers these; a model does not |

Read-only searches across many files go to the built-in `Explore` agent. Agent definitions live in `.claude/agents/` (the `model` field picks the model) and `.codex/agents/`. A tool without a model runs what it has and the report names what actually ran.

Skills are the lead's: the interview and the docs it produces are a conversation with the user. A subagent that meets a term missing from `GLOSSARY.md`, or a decision that looks like an ADR, reports it; the lead runs `domain-modeling`.

## Escalation

In order; an earlier rule wins.

1. Hard rules first. Persisted formats and migrations, client-server remotes and their validation, fairness and exploitability stay with the lead and get an independent `reviewer` pass, however small the change. The contract changes only through the user.
2. A blocked or uncertain subagent stops: an ambiguous brief, a file outside its ownership, the same check failing twice. The lead decides, rewrites the brief or takes the work.
3. A question the contract leaves open goes to the user per the [workflow](workflow.md): a grilling round when it opens further questions, one question when it stands alone.

## When to delegate

Once a task has a plan, each bounded unit with an exact file list and a stable interface goes to an `implementer`:

- after a module's interface is fixed, its server and client sides run as two parallel implementers;
- tests run in parallel with the implementation once the interface is agreed;
- a hard failure runs in an `investigator` while the lead continues;
- a finished change to a hard-rule area, and the integrated diff of a stage, get a `reviewer` pass before the PR is ready.

Independent units start together, in one message; a unit that needs another's result starts after it, since subagents cannot read each other's output. Up to four writers at a time. The lead keeps edits of a few lines, work whose brief would outweigh the change, and anything undecided: undecided means a grilling round first.

## Roles and ownership

The lead owns architecture, the contract, integration, user communication and Git. Subagents inspect code, implement a stable interface in exclusively assigned files, or review a concrete risk; Git mutations and further delegation stay with the lead.

Every writing assignment lists exact files or directories; one agent per file at a time, the lead included. Shared module interfaces, persisted formats and the contract each have one named owner. Scope grows only through the lead. Read-only reviews may overlap, each naming the revision it reviewed and staying off files being rewritten.

## Delegation brief

Give the minimum state as evidence rather than summaries: the exact plan stage, the ADRs and glossary terms that apply, interface signatures, the failing command and its output. Safeguards stay in; irrelevant context goes.

```text
Agent: implementer | reviewer | investigator | Explore
Goal: One concrete result.
Ownership: Exact writable paths; all other paths are read-only.
Inputs: Relevant instructions, plan stage, ADRs, glossary terms and interfaces.
Acceptance: Observable conditions for success.
Constraints: Exclusions and decisions that must remain unchanged.
Verification: Required checks and environment.
Return: Changed files, checks/results, risks and blockers; keep concise.
Coordination: No Git mutations or further delegation; report scope conflicts.
```

Reuse an agent for a related follow-up rather than paying for the same exploration twice. Ask for file references and evidence rather than transcripts or copied source. Stalled or redundant work is stopped and rescoped.

## Integration

A subagent's success report is a claim. The lead reads every diff and its verification evidence, resolves interface issues and runs the checks on the combined result. After an interruption, inspect what was actually written before repeating a step.

Parallel work trades tokens for elapsed time; judge cost per completed task. A token or cost saving is claimed only with measurements. Polling, repeated full-file reads and rerunning unchanged checks are waste.

## Independent concurrent tasks

Each independent task has its own worktree, branch and PR; subagents within one task share its worktree with exclusive file ownership. Worktrees share external services and a running Studio session, so conflicting checks are serialized.

Shared interfaces are agreed before parallel implementation: a prerequisite PR, then independent consumer PRs. Deliberately stacked PRs record the dependency and base branch, merge in dependency order, then rebase and verify again.

A worktree is removed once its work is preserved, it is clean and no task uses it.
