> [!WARNING] **Skepticism Disclaimer**
> Verified across 26 automated unit tests, clean debug compilation, and release packaging, but live end-to-end audio output on physical CoreAudio speakers and network Gemini endpoints require active runtime credentials.

## 1. What the prior attempt got wrong

1. **TrackInspectorView static value capture defect**:
   - **Input:** User clicks "Favorite" or track status/suggestions change while `TrackInspectorView` is presented.
   - **Expected:** The inspector's favorite button ("Favorite" / "Favorited") and metadata fields update dynamically in real time.
   - **Actual:** The view rendered a static snapshot captured at instantiation (`let track: Track`), leaving the Favorite button stuck on "Favorite" despite coordinator state changing.
   - **Root Cause:** `TrackInspectorView` did not compute `liveTrack` reactively from `@ObservedObject var coordinator`.

2. **Queue background pre-generation unhandled error stoppage**:
   - **Input:** Background pre-generation of any queue item encounters a failure (e.g. MCP timeout or generation error).
   - **Expected:** The failed item is marked `.failed(...)` and the queue worker continues processing the next items in FIFO order.
   - **Actual:** The queue worker halted permanently; all subsequent items remained indefinitely trapped in `.queued` status.
   - **Root Cause:** `processQueueWorker()` only called `self.processQueueWorker()` in the success block of `queueWorkerTask`, omitting it from the `catch` block.

3. **Background pre-generation halted after foreground generation**:
   - **Input:** User plays a queue item that was not yet ready, skips tracks, or clicks "Generate" on the prompt bar while items are queued.
   - **Expected:** Once foreground generation finishes, background pre-generation of pending queue items resumes.
   - **Actual:** Queue pre-generation was not kicked off because `generateAndPlay` did not invoke `processQueueWorker()` upon completion.
   - **Root Cause:** `generateAndPlay()` lacked a call to `processQueueWorker()` in its completion/error handlers, and `processQueueWorker()` did not guard against overlapping foreground generation.

4. **Auto-Play stalled when current suggestions are nil**:
   - **Input:** A track finishes playback with Auto-Play enabled while `currentSuggestions` is nil (e.g. loading or network offline).
   - **Expected:** Auto-Play automatically generates a 3-track coherent suite using fallback base vibes.
   - **Actual:** Auto-Play halted completely because `handleTrackDidFinish()` had `else if let suggestions = currentSuggestions` guarding Auto-Play execution.
   - **Root Cause:** Guard condition required non-nil suggestions instead of delegating to `scheduleAutoPlaySuite(suggestions: currentSuggestions)` which handles nil gracefully.

5. **GeminiSuggestionEngine.generateMovementSuite dead code**:
   - **Input:** User configures a Gemini API key and queues a 3x Movement Suite.
   - **Expected:** `generateMovementSuite(vibePrompt:apiKey:modelName:)` dynamically creates custom progressive movement prompts.
   - **Actual:** `generateMovementSuite` was never invoked anywhere; only static fallback strings were ever used.
   - **Root Cause:** `queueMovementSuite` only called `fallbackMovementSuite` synchronously without spawning a dynamic refinement task.

6. **SuggestionCard queue indicator mismatch on 3x suites**:
   - **Input:** User clicks "Queue 3x Vibe" on a suggestion card.
   - **Expected:** The card status updates to show queue placement (e.g., `Queued #1`, `Ready #1`).
   - **Actual:** Card remained displaying "+1 Queue" without queue badge because it only matched exact prompt equality rather than movement suite origin.
   - **Root Cause:** `SuggestionCardsView` checked `$0.prompt == suggestions.<type>` without checking `$0.origin?.contains(SuggestionType.<type>.rawValue) == true`.

## 2. What I changed

- **`Sources/LyriaFlowKit/ViewModels/PlaybackCoordinator.swift`**:
  - Added error-resilient looping in `processQueueWorker()` so queue pre-generation proceeds past failed items.
  - Added foreground generation guard (`if isGenerating { return }`) and resumed `processQueueWorker()` upon completion in `generateAndPlay()`.
  - Added asynchronous dynamic suite refinement via `geminiEngine.generateMovementSuite(...)` when a Gemini API key is configured.
  - Fixed Auto-Play track completion handler to invoke `scheduleAutoPlaySuite(suggestions: currentSuggestions)` even when suggestions are temporarily nil.
- **`Sources/LyriaFlowKit/Views/TrackInspectorView.swift`**:
  - Implemented `liveTrack` computed property dynamically binding against `coordinator.tracks` and `coordinator.currentTrack` for real-time reactivity when toggling favorites or updating metadata.
- **`Sources/LyriaFlowKit/Views/SuggestionCardsView.swift`**:
  - Updated queue presence checks (`queueIndex` and `queueStatus`) to match both direct prompt equality and 3x suite origin tags.
- **`Sources/LyriaFlowKit/Views/NowPlayingView.swift`**:
  - Added `.contextMenu` to the Now Playing track metadata card for quick inspection ("Get Info"), clipboard prompt copy, favorite toggle, and Finder reveal.
- **`Tests/LyriaFlowTests/LyriaFlowTests.swift`**:
  - Added 4 new automated unit tests (bringing suite to 26 tests): `testGeminiGenerateMovementSuiteEmptyApiKeyFallback`, `testAutoPlaySuiteGenerationWithNilSuggestions`, `testTrackInspectorLiveFavoriteReactivity`, and `testSuggestionCardQueueMatchingSingleAndSuite`.

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - `make test` executed: 26 unit tests passed, 0 failures in 0.008s.
  - `make build` executed: clean compilation of all Swift targets with zero errors.
  - `make app` executed: production release bundle `LyriaFlow.app` generated cleanly in 5.66s.
- **Shallow Verification (manual only):**
  - Inspected view component layouts across `NowPlayingView`, `TrackInspectorView`, `SuggestionCardsView`, `UpNextQueueView`, and `HistorySidebarView`.
- **Unverified aspects:**
  - Live audio output from physical CoreAudio speakers on macOS hardware during multi-track playback.
  - Live remote HTTP calls to Gemini API when a valid user API key is provided at runtime.

## 4. Known Issues

- `Minor Robustness Risk` — Rapid successive clicking of "Queue 3x Vibe" across multiple cards adds tracks in multiples of 3; pre-generation operates strictly sequentially in FIFO order.
- `Shallow Verification` — Headless sandbox environment verifies UI view instantiation, property bindings, and data flow, but does not display interactive AppKit windows.

## 5. Remaining risk & next step

- **Verdict:** All requirements R1, R2, R3 and acceptance criteria are fully satisfied and hardened.
- **Next step:** Run `make run` to launch `LyriaFlow.app` in macOS GUI, verify visual playback of the 32-bar spectrum visualizer, click "Queue 3x Vibe" on suggestion cards, and open the Metadata Inspector via the `info.circle` button.
