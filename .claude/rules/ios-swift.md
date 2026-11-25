---
paths:
  - "**/*.swift"
---

# SovEmu.iOS: Swift

Code style, adapted from Sovereign.iOS's rules to this smaller app.

## Concurrency

- **SovEmuKit is Swift 6 with strict concurrency**: every model is `Sendable`, and shared mutable
  state sits behind an `actor` or a `Mutex` (Synchronization). Prefer `Mutex` to `NSLock` in new
  code.
- **`@unchecked Sendable` only with a lock and a comment** saying what makes it safe (which
  threads touch it, what guards them), as `FrameLatency` and `FrameTap` have. Never use
  `nonisolated(unsafe)` to silence a diagnostic.
- **App models are `@MainActor @Observable final class`es**, injected with `.environment(model)`;
  no `ObservableObject`/`@Published`.
- Work leaves the main actor in an `async` function or an actor, never by blocking it. A
  long-running task is a stored `Task`, cancelled by its owner; rethrow `CancellationError`
  rather than reporting it as a failure.
- The app is in Swift 5 mode only for WebRTC's delegates: write its code as if it were Swift 6.
  Add no new mutable `static var`s (`ClientEvents` has them only because Swift 5 allows it).

## Dependencies and time

- **Dependencies come in through `init`.** No new singletons (`static let shared`) beyond the
  system's; default arguments stand in for a container.
- **Time is injected in SovEmuKit**: a `now` closure (`now: @Sendable () -> Date`) or a `nowMs`
  parameter, so its tests control the clock. A polling, debouncing or timing-out controller that
  moves into SovEmuKit takes its time and sleep the same way, never `Date()` or `Task.sleep`
  directly.

## Safety

- No `try!`, `as!` or force unwrap outside tests, unless the line before it makes it true (a
  guarded `isEmpty`, a `layerClass` cast) and a comment says so. Prefer `guard let` and a typed
  error.
- Errors the user should see carry a message the UI shows; nothing is swallowed with `try?`
  without a comment saying why it may be.

## Style

- 4-space indentation, lines of about 120 columns, comments wrapped at 100.
- Doc comments are `///` and say why, not what; file headers are `//` and name the counterparts
  in the other clients; group a long file with `// MARK: -`.
- Swift naming: types `UpperCamelCase`, everything else `lowerCamelCase`; a ported type keeps
  its Web/Android name.
