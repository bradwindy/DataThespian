# Changelog

## 2.0.0 (2026-10-07, bradwindy fork)

Depends on the `bradwindy/FelinePine` fork, 2.0.0 or later.

### Source-breaking

Each of these turns code that compiled against upstream 1.0.x into a compile error.

- `getOptional(for:with:)` and `fetch(for:with:)` are `async throws`, not `async rethrows`,
  in `Queryable`, the `Database` extension and the conveniences built on them
  (`getOptional(for:)`, `fetch(for:)`, `fetch(for: [Selector.Get], with:)`). The fetch inside can fail even when the closure
  cannot, and `rethrows` hid that. Every call needs `try`:
  `let x = await database.fetch(...) { ... }` becomes `let x = try await ...`, and an
  `async let x = database.fetch(...)` must be read with `try await x`. In a function that
  cannot throw, decide what a failed fetch means there (log and keep the previous state,
  for example) rather than `try?` turning it into an empty result.
- The `ModelActor`-only `getOptional(for:with:)` override and the non-throwing
  `fetch(for:) -> [Model]` overload, which logged an error and returned `[]`, are removed.
  Every `Database` now reports fetch failures the same way.
- `insertIf(_:notExist:)` and `insertIf(_:notExist:with:)` moved from `extension Queryable`
  to `extension Database` and now `throw`. They are no longer available on a type that
  conforms to `Queryable` but not `Database`.
- `Database.withModelContext` requires `T: Sendable`, as do `BackgroundDatabase` and the
  environment default, so `withModelContext { $0 }` or a closure returning `@Model`
  objects no longer compiles. A `Database` conformer whose witness forwards to another
  database must declare `func withModelContext<T: Sendable>(...)`; an unconstrained `T`
  still satisfies the requirement but cannot call the constrained one it wraps.
- `CollectionDifference` gains a stored `modelsToUpdate` property and initialiser.
  The existing initialiser still compiles.

### Changed behaviour

- `transaction(_:)` and `deleteAll(of:)` discard a failed block's changes instead of
  leaving them pending for the next `save()`. A context that was clean on entry is rolled
  back. A context that already held another caller's unsaved work is not, since that
  would discard the other work too; only the block's inserts are removed, and its updates
  and deletions of existing models stay pending.
- `CollectionSynchronizer.synchronizeDifference` applies updates to the compared models in
  data order, throws `QueryError.itemNotFound` or `SynchronizationError.keyMismatch`
  instead of asserting, and rolls back on failure when the context was clean on entry.
- The `DatabaseChangePublicist` SwiftUI environment default logs a warning instead of
  asserting when subscribed to before a publicist is injected. `.never()` is a real no-op.
- `Model.NotFoundError`, `AnyModel.NotFoundError` and `ModelActor.assertIsBackground` are
  deprecated. Nothing threw the errors; catch `QueryError.itemNotFound`.

### Fixed

- A `.model` selector no longer resolves a deleted or stale model to a placeholder that
  traps when read. `getOptional` returns `nil` and `get` throws `itemNotFound`.
- `fetch(for: [Selector.Get], with:)` returns results in selector order.
- `insertIf` checks and inserts in one step on the database's context, so concurrent
  callers cannot both insert, and the transform runs on the inserted instance.
- `CollectionDifference` no longer traps on duplicate keys.
- `UniqueKeyPath.predicate(equals:)` is implemented, so `Selector.Get.unique` works.
- Change notifications: registrations and change sets are delivered in order through one
  queue, a save straight after registering is no longer missed, and an unconvertible
  object ID is logged and dropped instead of asserting.
- `withModelContext` no longer asserts that work runs on the main thread.

### Added

- `Database.insertAndSave(_:)` returns a `Model` holding the permanent identifier. The
  `Model` from `insert(_:)` or `insertIf` holds a temporary identifier that stops
  resolving after the next save.
- `ModelActorDatabase.makeInBackground` builds the database off the caller's actor.
