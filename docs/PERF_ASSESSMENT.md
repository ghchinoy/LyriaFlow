# Quick Bounce Assessment — LyriaFlow

**Assessment Date:** 2026-08-31  
**Target:** LyriaFlow (`/Users/ghchinoy/projects/LyriaFlow`)  
**Assessor:** `quick-bounce-assessor` (Agent Skills v1.0.0 / `macos-performance`)

---

## Executive Summary

**Verdict:** **NOT quick-bounce-ready.**  
The first frame is gated by synchronous disk I/O on the main actor during `@StateObject` construction (`LyriaFlowApp.swift:24` → `PlaybackCoordinator.init` → `PersistenceStore.loadTracks()`), plus lazy shell/env file parsing on first access. Steady-state rendering has confirmed per-body formatter allocations and an unthrottled 25 Hz publish→re-render loop.

**App Profile:** macOS-only SwiftUI (min macOS 14), Swift Package Manager, Swift tools 5.9 / Swift 5 language mode, MVVM via `ObservableObject`. Strict concurrency is not enabled.

---

## Detailed Category Findings

### Category 1 — Launch Path / Main-Actor I/O

| Status | Evidence | Finding & Fix |
|---|---|---|
| **FAIL** | `Sources/LyriaFlowKit/ViewModels/PlaybackCoordinator.swift:40` (constructed at `Sources/LyriaFlow/App/LyriaFlowApp.swift:24`) | `tracks = persistence.loadTracks()` runs synchronously on the main actor during app launch initialization. **Fix:** Initialize `tracks = []`, load tracks asynchronously in a background `Task`, and assign to `@Published tracks` on `@MainActor`. |
| **FAIL** | `Sources/LyriaFlowKit/Services/PersistenceStore.swift:40,43,92` | `Data(contentsOf:)` + `JSONDecoder.decode` (or directory scan + re-encode) executes on the calling thread. **Fix:** Provide an `async` or `nonisolated` loading method running on a background worker thread (`Task.detached`). |
| **FAIL** | `Sources/LyriaFlowKit/Services/EnvironmentLoader.swift:12-14` (`init` → `loadEnvironment()`) | Singleton `init` synchronously reads and parses `~/.zshrc`, `~/.zshenv`, `~/.bash_profile`, `~/.bashrc`, multiple `.env` candidates, and probes gcloud ADC upon first access on the main thread. **Fix:** Make `init` lightweight; expose an explicit `async loadEnvironment()` or deferred background loader before first subprocess/network call. |
| **WARNING** | `Sources/LyriaFlowKit/Services/AppLogger.swift:14-24` | `init` synchronously creates directory and writes initial log header. **Fix:** Defer file handle initialization off the critical launch path. |
| **PASS** | `Sources/LyriaFlow/App/LyriaFlowApp.swift:6-14` | `applicationDidFinishLaunching` in `AppDelegate` is lightweight (window activation deferred to `DispatchQueue.main.async`). |

### Category 2 — Strict Concurrency Posture

| Status | Evidence | Finding & Fix |
|---|---|---|
| **WARNING** | `Package.swift:29-49` (no `swiftSettings`) | Swift strict concurrency is not enabled; compiler does not enforce Sendability or isolation checks. **Fix:** Add `.enableUpcomingFeature("StrictConcurrency")` per target (`LyriaFlowKit` first in targeted, then complete mode). |
| **WARNING** | `PersistenceStore.swift:4`, `EnvironmentLoader.swift:5`, `AppLogger.swift:5`, `MCPModels.swift:32`, `main.swift:55` | Five manual `@unchecked Sendable` conformances with lock-based safety unverified by compiler. **Fix:** Verify thread-safety invariants under strict checking and remove `@unchecked` where possible. |

### Category 3 — View-Model / Business-Logic Separation

| Status | Evidence | Finding & Fix |
|---|---|---|
| **WARNING** | `Sources/LyriaFlowKit/ViewModels/PlaybackCoordinator.swift` (504 lines) | God-object view model containing queue pre-generation worker (`:377-425`), movement suite logic (`:249-304`), auto-play scheduling (`:189-217`), and persistence orchestration. **Fix:** Extract dedicated plain `Sendable` domain services (`QueueService`, `SuiteComposer`, `AutoPlaySelector`). |
| **PASS** | `Sources/LyriaFlowKit/Services/MCPClient.swift:3` | `public actor MCPClient` correctly encapsulates shared mutable state (subprocess stdio JSON-RPC). |
| **PASS** | Entire codebase (no `.sink` or custom subjects) | Combine is used exclusively for SwiftUI's `@Published` property wrappers. Async work uses Swift concurrency (`async/await`). |

### Category 4 — Steady-State Render Budget

| Status | Evidence | Finding & Fix |
|---|---|---|
| **FAIL** | `Sources/LyriaFlowKit/Services/AudioEngine.swift:101-111,118-170` + `Sources/LyriaFlowKit/Views/WaveformVisualizerView.swift:37-71` | 25 Hz metering timer continuously mutates `@Published powerLevels`, invalidating 32 animated bar subviews with springs, gradients, and shadows. **Fix:** Move waveform rendering to `TimelineView` + `Canvas` and decouple meter polling from `@Published`. |
| **FAIL** | `Sources/LyriaFlowKit/Views/NowPlayingView.swift:174` | `DateFormatter()` is instantiated repeatedly inside `formattedDate()` called within view `body`. **Fix:** Hoist to a static shared formatter or use `Date.FormatStyle`. |
| **FAIL** | `Sources/LyriaFlowKit/Views/TrackInspectorView.swift:197,360` | `ISO8601DateFormatter()` is instantiated inline directly in the `body` view hierarchy (`:197`) and in `formatDate()` (`:360`). **Fix:** Hoist formatters to static properties. |

### Category 5 — App Lifecycle & Window Setup

| Status | Evidence | Finding & Fix |
|---|---|---|
| **PASS** | `Sources/LyriaFlow/App/LyriaFlowApp.swift:5-19` | Application launch delegate is non-blocking. |
| **WARNING** | `Sources/LyriaFlowKit/ViewModels/PlaybackCoordinator.swift:6` | `ObservableObject` with 11 `@Published` properties causes broad view invalidation when any property mutates. **Fix:** Consider migrating to the `@Observable` macro (macOS 14+). |

---

## Scorecard Summary

- **FAIL:** 6 (4 launch path, 2 render budget)
- **WARNING:** 5 (2 concurrency, 2 architecture, 1 observation)
- **PASS:** 4

---

## Action Plan (Ranked by ROI)

1. **Phase 1: Clear First-Frame Launch Path** (Remediates Cat 1 FAILs)
2. **Phase 2: Adopt Strict Concurrency** (Remediates Cat 2 WARNINGs)
3. **Phase 3: Domain Service Extraction** (Remediates Cat 3 WARNINGs)
4. **Phase 4: Render Budget Optimization** (Remediates Cat 4 FAILs)
