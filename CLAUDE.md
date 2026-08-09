# CLAUDE.md

TaskTracker — a personal task manager plus an optional device-independent focus timer for
macOS, iOS and watchOS. Local-first, iCloud-synchronised, no backend, no third-party dependencies.

**Read `AGENTS.md` first.** It holds the repository structure, dependency rules, prohibitions and
completion checklist that apply to all agents including you. This file adds only Claude-specific
working instructions.

## Before any implementation task

1. Read `AGENTS.md`, `memory.md`, and the `docs/` file that owns the area you are touching.
2. Confirm which package owns the change. If two packages seem to own it, the boundary is wrong —
   raise it rather than splitting logic across both.
3. Implement the smallest coherent change.
4. Run tests (`xcrun swift test` — note `xcrun`, see `AGENTS.md` Environment).
5. Update the affected docs and `memory.md` in the same session.
6. Report what changed, what you verified, and what you did not.

## The two decisions that explain most of this codebase

**Task and Timer are independent domains.** A task never requires a timer; a timer never requires a
task. A timer references a task only as `UUID?`. If you find yourself wanting to import one domain
from the other, stop — the answer is an identifier or a join in `AppData`.

**The timer is an append-only event log, not a mutable record.** SwiftData's CloudKit mirroring
offers no custom merge hook and merges at property granularity, which can produce timer states that
never existed. Immutable events are never merged. This single constraint explains the projection, the
arbitration rules, the absence of stored derived state, and most of `TimerDomain`.

## Key documents

| Question | File |
|---|---|
| Why is the timer built this way? | `docs/TIMER_ARCHITECTURE.md` |
| Why was X decided? | `docs/DECISIONS.md` |
| Where does this code belong? | `docs/ARCHITECTURE.md` |
| What can I store and how? | `docs/DATA_MODEL.md` |
| How does sync behave? | `docs/ICLOUD_SYNC.md` |
| What must I test? | `docs/TESTING.md` |
| What appearance rules apply? | `docs/DESIGN_SYSTEM.md` |
| What is next? | `docs/ROADMAP.md`, `memory.md` |

## Delegation

Implementation may be delegated to Cursor CLI or opencode; Codex handles review and
high-complexity work. Whoever writes it, the completion checklist in `AGENTS.md` still applies, and
**you are responsible for verifying delegated work before reporting it as done** — build it, test it,
and check it against the dependency rules. Do not relay an agent's claim of success as your own
verification.

## Forbidden shortcuts

- Do not weaken a test to make it pass.
- Do not disable strict concurrency, add `@unchecked Sendable`, or `@preconcurrency` to silence a
  real data race.
- Do not add a stored property to a synced model without checking the CloudKit constraints.
- Do not let a timer calculation drift into a view.
- Do not report a milestone complete without running the verification for it.

## Updating memory

`memory.md` is current state, not history: project state, current milestone, completed and active
work, decisions made, constraints, known issues, open questions, next steps. Keep it short. Durable
knowledge belongs in `docs/`, never here.
