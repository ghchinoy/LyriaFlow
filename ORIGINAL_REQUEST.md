# Original User Request

## 2026-08-29T20:22:09Z

This is a single self-contained feature and UI polish; keep it small and focused.

Refactor LyriaFlow to declutter the main Now Playing view by removing duplicate queue strips, enhance the queue system with 3-track cohesive sonic theme progression (3-part movement suites and Auto-Play theme coherence), and ensure rich track metadata (prompt, model ID, timestamp, duration, suggestions) is fully persisted and inspectable.

Working directory: /Users/ghchinoy/projects/LyriaFlow
Integrity mode: development

## Requirements

### R1. Declutter Main Stage & Consolidate Queue to Sidebar
- Remove the redundant Up Next queue strip from the bottom of the Now Playing stage.
- Keep the main stage focused exclusively on the Hero 32-bar audio spectrum visualizer, current prompt title/tags, and the 3 Gemini suggestion cards.
- Retain the interactive Up Next queue within the dedicated Sidebar navigation tab (`Up Next` / `History`).

### R2. Coherent 3-Track Sonic Theme Progression
- Upgrade `GeminiSuggestionEngine` to support generating a coherent 3-part progressive suite (Movement I: Atmospheric Build, Movement II: Deep Groove, Movement III: Climax/Outro) based on any chosen vibe.
- Add a "Queue 3x Vibe" action button to each suggestion card to enqueue the 3-part sonic journey into the Up Next queue with sequential background pre-generation.
- When Auto-Play is enabled, maintain the chosen sonic theme across a 3-track coherent arc before branching into new genre departures.

### R3. Rich Track Metadata Persistence & Inspector
- Verify and ensure that each track record persistently stores: full text prompt, Lyria model ID (`lyria-3-clip-preview` or `lyria-3-pro-preview`), audio duration, creation date, seed, and Gemini suggestions.
- Add a clean "Get Info" / Metadata Inspector view/popover accessible from track context menus and Now Playing info badge showing all technical details.

## Acceptance Criteria

### UI Clarity & HIG Conformance
- [ ] Now Playing main canvas does not duplicate the Up Next queue list; the Up Next playlist remains in the Sidebar tab.
- [ ] Suggestion cards feature both a quick "+1 Queue" and a "Queue 3x Vibe" button.
- [ ] Clicking "Queue 3x Vibe" enqueues 3 coherent evolutionary variations into the Up Next playlist labeled with their movement parts.
- [ ] Auto-Play generates a 3-track coherent sonic suite rather than immediate random genre hopping.
- [ ] Track metadata (prompt, model ID, creation date, duration, seed) is stored persistently in tracks.json and viewable via track info.

### Build & Verification
- [ ] Automated unit test suite passes with zero failures (make test).
- [ ] App builds cleanly without warnings or errors (make build).
- [ ] App packages release bundle cleanly (make app).
- [ ] App launches smoothly via make run.
