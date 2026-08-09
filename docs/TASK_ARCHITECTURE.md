# Task Architecture

## TaskDomain Responsibilities

TaskDomain is a pure value-type package with zero dependencies beyond the standard library and Foundation. It contains no persistence vocabulary, no SwiftUI types, no CloudKit types, and no knowledge that timers exist.

TaskDomain owns:
- The `Task` model and its lifecycle
- `DayKey` (the calendar-stable day identifier)
- Task validation rules
- Repository protocols (interface only, no implementation)

TaskDomain does NOT own:
- Persistence (that is `AppData`)
- Sync (that is `AppData`)
- Timer association logic (that is `TimerDomain`, via `UUID?`)
- UI (that is `AppFeature` + app targets)

---

## Task Model

```
TaskDomain/
├── Models/         Task, TaskStatus, DayKey
├── Services/       TaskService (create/edit/complete/schedule rules)
├── Repositories/   TaskRepository (protocol only)
└── Support/        TimeSource, TaskValidationError
```

**`Task`** fields: `id`, `title`, `notes`, `createdAt`, `completedAt: Date?`, `scheduledDay: DayKey?`, `updatedAt`.

### Completion: derived from `completedAt`

`isCompleted = completedAt != nil`. One field, not two, so the two can never disagree after a merge (plan §9).

This is a deliberate design choice. A parallel boolean (`isCompleted`) would create two fields that must agree — and after a merge, they could disagree. With a single field, there is exactly one source of truth for whether a task is done.

### Task invariants

- Title non-empty after trimming.
- `completedAt` never in the future.
- Completing does not clear `scheduledDay`.
- `updatedAt` monotonic per device.

---

## DayKey

`DayKey` wraps an ISO `yyyy-MM-dd` string, resolved in the device's **current calendar at the moment of assignment** (plan §9).

### Why a string key, not a `Date`

A `Date` meaning "today" is an instant, and an instant is ambiguous across timezone changes and DST — a task scheduled for the 9th can become the 8th after a flight. A day key is a *calendar* fact and is stable under both (plan §9).

A `DayKey` is:
- An ISO `yyyy-MM-dd` string (e.g., "2026-08-09")
- Resolved in the device's current `Calendar` at the moment of assignment
- Stable across timezone changes (a task scheduled for "2026-08-09" stays on "2026-08-09" regardless of which timezone the device is in)
- Stable across DST boundaries

This is tested: a task scheduled for the 9th must not become the 8th after a flight (`TESTING.md`).

### Why not `isInToday: Bool`

Rejected: cannot express "tomorrow", needs a nightly job to clear (plan §9).

---

## Today and Pool Semantics

### Today

A focused list, assembled by pulling from the Pool or creating directly. Today assignment is expressed as `scheduledDay: DayKey?` on `Task`. When `scheduledDay` is non-nil, the task appears in Today for that day.

### Pool

`scheduledDay == nil && completedAt == nil` **is** the Pool. It is a query, not a container (plan §9).

A task in the Pool has:
- No scheduled day (not assigned to Today)
- Not completed

The Pool is a *durable reservoir of ideas* that is *supposed* to stay full and be drawn from repeatedly. This is why it is called "Pool" and not "Inbox" or "Backlog" (plan §9):

- **Inbox** — a triage queue that must be processed to zero. A never-emptied Inbox generates guilt.
- **Backlog** — implies prioritised committed work.
- **Pool** — the user's own word and the only one whose connotation matches the behaviour.

### Lifecycle transitions

```
New task → Pool (scheduledDay=nil, completedAt=nil)
Pool → Today (scheduledDay=DayKey for today)
Today → Pool (scheduledDay=nil)
Any → Completed (completedAt=Date)
Completed → Any (completedAt=nil, optionally reschedule)
```

Completed tasks are never in the Pool, even if `scheduledDay` is nil. The Pool query is `scheduledDay == nil && completedAt == nil`.

---

## Task ↔ Timer Association

`TimerDomain` references a task only as an opaque `UUID?` — specifically `TimerEvent.relatedTaskID`, set once on `.started` and immutable thereafter (plan §11).

### Why immutable

A session records what you were doing at the time; re-pointing it later would rewrite history and corrupt per-task totals (plan §11).

### Why `UUID?` and not a typed reference

A typed reference requires `TimerDomain` to import `TaskDomain`, which the dependency rules prohibit (plan §3, §11). A `UUID` is a primitive both sides understand.

### Referential integrity

Deliberately **not** enforced. A deleted task leaves sessions with a dangling ID; the join in `AppData` resolves it to "Deleted task" for display. Enforcing it would require a real relationship, which the persistence architecture rules out (plan §11).

---

## Repository Abstraction

`TaskRepository` is a protocol only — no implementation lives in `TaskDomain`. Implementations live in `AppData`, where SwiftData models are mapped to domain value types at the repository boundary (plan §8, §25).

This keeps `TaskDomain` persistence-ignorant. The protocol defines the contract; the implementation details are invisible to the domain.

---

## Task Invariants (detailed)

1. **Title non-empty after trimming.** A task cannot be created or saved with an empty or whitespace-only title.
2. **`completedAt` never in the future.** Completion timestamp is always ≤ now.
3. **Completing does not clear `scheduledDay`.** A completed Today task retains its scheduled day; this preserves the ability to uncomplete and have it reappear in Today.
4. **`updatedAt` monotonic per device.** Each edit on a device produces a strictly later `updatedAt`. This is enforced locally, not across devices (different devices may have different `updatedAt` values for the same logical edit — property-level LWW is acceptable for single-user title/notes edits, plan §28).
5. **Completion is derived.** `isCompleted = completedAt != nil` — never a parallel boolean (plan §9).
6. **Pool is a query.** `scheduledDay == nil && completedAt == nil` defines membership. There is no separate Pool entity, no Pool container, no Pool state on the task.

---

## Future Extension Boundaries

TaskDomain is designed to be extended without breaking changes:

- **Recurrence** — if added, introduce a new `TaskSchedule` entity in `AppData` with a CloudKit relationship to `Task`. Backfill from existing `scheduledDay` values. TaskDomain's model does not change; only `AppData` gains a new entity (plan §9).
- **Tags / categories** — could be added as a separate entity in `AppData` with a UUID association, following the same pattern as timer association (plan §11).
- **Subtasks** — explicitly out of scope, but if ever reconsidered, would be a new entity with a parent UUID, not a nested structure within `Task`.
- **Projects** — explicitly out of scope.

None of these require changes to `Task` fields or `TaskDomain` invariants. They are additive: new entities in `AppData`, new queries, new UI in `AppFeature`.

---

## Cross-References

- `ARCHITECTURE.md` — package structure, dependency graph, concurrency boundaries
- `TIMER_ARCHITECTURE.md` — how `TimerEvent.relatedTaskID` references tasks
- `DATA_MODEL.md` — `TaskRecord` persistence model, CloudKit constraints, indexes
- `ICLOUD_SYNC.md` — how task changes propagate across devices
- `TESTING.md` — TaskDomain test requirements
- `PRODUCT.md` — terminology (Pool, Today), user flows
