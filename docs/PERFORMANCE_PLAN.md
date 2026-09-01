# LyriaFlow Performance Plan

A phased plan to improve LyriaFlow's launch responsiveness ("quick bounce" —
time-to-first-rendered-frame), concurrency safety, architecture, and
steady-state render budget.

All `file:line` references reflect the codebase at the time of writing and are
starting points, not exact post-edit locations.

## Guiding principle

> At the earliest point in the lifecycle, do all non-main-actor-necessary work
> **off** the main actor so a single SwiftUI/AppKit frame can render
> immediately. Publish results back to the main actor when ready.

The app is macOS-only SwiftUI (min macOS 14) built with SPM (`Package.swift`),
Swift tools 5.9, Swift 5 language mode. MVVM via `ObservableObject`/`@Published`
(no `@Observable`). One real actor (`MCPClient`); `@MainActor` on
`PlaybackCoordinator` and `AudioEngine`. Strict concurrency is **not** enabled.

---

## Phase 1 — Clear the first-frame ("quick bounce") path

**Goal:** nothing synchronous and I/O-bound runs on the main actor before the
first frame. Highest ROI, low risk.

### Findings
- `PlaybackCoordinator.init` calls `self.tracks = persistence.loadTracks()`
  **synchronously on the main actor** during `@StateObject` construction at app
  launch (`Sources/LyriaFlowKit/ViewModels/PlaybackCoordinator.swift:40`,
  constructed at `Sources/LyriaFlow/App/LyriaFlowApp.swift:24`).
- `PersistenceStore.loadTracks()` decodes the entire tracks JSON DB, or falls
  back to scanning the Tracks directory and re-encoding it
  (`Sources/LyriaFlowKit/Services/PersistenceStore.swift:31`, `:91`).
- `EnvironmentLoader.init` performs synchronous disk I/O and parsing on first
  touch: `~/.zshrc`, `~/.zshenv`, `~/.bash_profile`, `~/.bashrc`, multiple
  `.env` candidates, and a gcloud ADC probe
  (`Sources/LyriaFlowKit/Services/EnvironmentLoader.swift:12`, `:17-87`).
- `AppLogger.init` creates a directory and writes a log line
  (`Sources/LyriaFlowKit/Services/AppLogger.swift:14-24`).

### Actions
1. `PlaybackCoordinator`: start with `tracks = []`; load tracks in a `Task` and
   assign `@Published tracks` back on `@MainActor`. Trigger from a `.task` on
   the root view or at the end of `init`.
2. `PersistenceStore`: add an `async` (or `nonisolated` async) `loadTracks`
   variant that runs decode + directory scan off the main thread (e.g.
   `Task.detached`). Keep the `@Published` assignment on main.
3. `EnvironmentLoader`: remove disk parsing from `init`. Make loading explicit
   and `async`, awaited before first network/subprocess use — not lazily on the
   main thread at first access.
4. `AppLogger`: defer directory creation / first write off the launch path.

### Acceptance
- Instruments Time Profiler / `os_signpost` shows no synchronous file reads on
  the main thread during launch.
- Measurable reduction in launch-to-first-frame.

---

## Phase 2 — Adopt Swift strict concurrency (incremental)

**Goal:** get compiler enforcement for concurrency invariants the code already
hand-maintains.

### Findings
- No strict concurrency anywhere: no `swiftSettings` block on any target
  (`Package.swift:29-49`), no `swiftLanguageModes`.
- Manual `@unchecked Sendable` (backed by `NSLock`/`NSRecursiveLock`) on
  `PersistenceStore`, `EnvironmentLoader`, `AppLogger`, `AnyCodable`,
  `StdioLineReader` — unverified promises today.

### Actions
1. Add per-target `swiftSettings` with
   `.enableUpcomingFeature("StrictConcurrency")` in `Package.swift`, starting
   with `LyriaFlowKit` in **targeted** mode.
2. Resolve warnings; verify each `@unchecked Sendable` actually holds; drop
   `@unchecked` where the compiler can prove `Sendable`.
3. Escalate `LyriaFlowKit` to **complete** checking, then the executables.
4. Defer Swift 6 language mode until targets are warning-clean.

### Acceptance
- `swift build` clean for `LyriaFlowKit` under targeted (then complete) strict
  concurrency.

---

## Phase 3 — Separate business logic from the view model

**Goal:** shrink the 504-line `PlaybackCoordinator` god object; keep it a thin
`@MainActor` view model.

### Findings
- Orchestration/domain rules live inside `PlaybackCoordinator`:
  - Queue pre-generation worker + concurrency gating (`:377-425`).
  - Movement-suite composition (`:249-304`).
  - Auto-play selection/scheduling (`:189-217`).
- Inline `print(...)` debug logging (`:63, 67, 101, 105, 391, 411`).

### Actions
1. Extract plain (non-actor, `Sendable` where possible) service types called by
   the coordinator: `QueueService`, `SuiteComposer`, `AutoPlaySelector`.
2. Keep `actor` usage only where shared mutable state crosses threads (already
   correct with `MCPClient`). For streaming results, prefer `AsyncStream` over
   Combine pipelines. (Combine is currently used only for `@Published`; do not
   add `.sink`/subjects.)
3. Replace inline `print` with `AppLogger`.

### Acceptance
- Coordinator materially smaller; `Tests/LyriaFlowTests` still green (DI in
  `init` already supports substitution).

---

## Phase 4 — Steady-state render budget: metering & waveform

**Goal:** keep a smooth frame budget during playback.

### Findings
- `AudioEngine` runs a 25 Hz metering timer (`timeInterval: 0.04`) that
  republishes a 32-element `@Published powerLevels` every tick
  (`Sources/LyriaFlowKit/Services/AudioEngine.swift:101-111`, `:118-170`).
- `WaveformVisualizerView` rebuilds all 32 bars with gradients/shadows/springs
  on each publish (`Sources/LyriaFlowKit/Views/WaveformVisualizerView.swift:37-71`).
- `NowPlayingView.formattedDate` allocates a `DateFormatter` on every `body`
  call (`Sources/LyriaFlowKit/Views/NowPlayingView.swift:173-178`).
- `TrackInspectorView` instantiates `ISO8601DateFormatter()` inline in the view
  `body` (`:197`) and `DateFormatter()` in `formatDate()` (`:360`).

### Actions
1. Render the waveform with `TimelineView` + `Canvas` so metering does not
   invalidate the whole SwiftUI subtree; decouple the meter tick from
   `@Published` where possible.
2. Use shared static formatters (`DateFormatter`, `ISO8601DateFormatter`) or
   `Date.FormatStyle` instead of per-body allocations.

### Acceptance
- No dropped frames during playback in Instruments; reduced view-body
  invalidations.

---

## Sequencing

1 → 2 → 3 → 4. Phases 1 and 4 are independently shippable. Phase 2 should
precede Phase 3 so the compiler guides the extraction.

## Assessing progress

Use the `quick-bounce-assessor` agent skill
(`agent-skills/plugins/macos-performance/skills/quick-bounce-assessor`) to
re-scan the launch path and produce a PASS/WARNING/FAIL report against these
phases.
