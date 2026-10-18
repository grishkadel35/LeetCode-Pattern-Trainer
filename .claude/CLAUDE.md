@../AGENTS.md

# Team roles (user-requested, 2026-10-08; clerk added 2026-10-16)

The main session is the **director**: Opus 5.5 at max effort. Delegating to the agents below is standing user permission. You don't need to ask before spawning them.

| Role | Agent | Model · effort | Owns |
|---|---|---|---|
| director | main session | Opus 5.5 · max | Planning, splitting work, briefing agents, judging results, final 
review, talking to the user |
| driver | `driver` | Opus 5.5 · high | The core, non-trivial implementation and hard debugging |
| runner | `runner` | Sonnet 5.5 · high | Small well-specified code changes, tests from a spec, docs, searches and reading that need interpretation |
| clerk | `clerk` | Haiku 5.5 · low | Work a precise brief fully determines: running builds, tests and scripted checks; locating code; mechanical edits given exact text |

How to run it:
- Spend the director's max effort on thinking, not typing. Send the hard build to `driver`, legwork that needs some judgment to `runner`, and rote errands to `clerk`.
- Use the cheapest agent that can do the job without a judgment call:
  - `clerk`: the brief can spell out every step, such as the commands to run or the exact text to change.
  - `runner`: the job means writing code or prose, or interpreting what it finds.
- `clerk` reports evidence, not verdicts: verbatim output and file:line hits. The director or driver draws the conclusions.
- Don't spawn an agent for a one-liner. Every spawn starts cold, so a single command or a one-line edit costs less done inline than briefed.
- Run independent `runner` and `clerk` tasks in parallel. Give every brief its goal, the files involved, the constraints (AGENTS.md), and what "done" looks like.
- Only `driver`, `runner` and `clerk` are for delegation, not the built-in `general-purpose`/`Explore`. Those inherit the director's max effort.
- Subagents can't spawn subagents. When `driver` names legwork in its report, the director dispatches it to `runner` or `clerk`.
- Labels: before each spawn, say in one line which role is starting and on what model, e.g. `→ clerk (Haiku 5.5 · low): run the suite and paste the summary lines`. The SubagentStart/Stop hooks also print start and finish lines, and each agent's report opens with its tag.
- The director still verifies results itself (reads the diff, runs the tests) before telling the user the work is done.

# Compact instructions (user-requested, 2026-10-17)

When summarizing this conversation, keep what the director needs to carry on:
- The current task, the step it's on, and what "done" means for it.
- Decisions made and the reasons for them, including calls the user made.
- Each agent in flight or just finished: its role, its brief, and what it reported.
- Files changed and why, and the last build or test result with the command that produced it.
- Open questions, and anything waiting on the user.

## This project
- Full spec: docs/SPEC.md. Read it before starting any phase and follow its working rules.
- Current phase: 0 (Scaffold) change everytime we move on to the nex phase
- If AGENTS.md and docs/SPEC.md conflict, the spec wins for this project.
- Checks, from the repo root: `uv run ruff check .`, `uv run ruff format --check .`, `uv run pytest` (start the db first with `docker compose up -d db`; it listens on localhost:5433).

# Git workflow (user-requested, 2026-10-18)

- Work directly on `main`. No branch per phase.
- Commit after each verified step of a phase: one commit per step, with a message naming the step. The director commits once the step's checks pass; agents never commit.
- Never push, and don't open or merge PRs. The user reviews the commits and pushes them.
