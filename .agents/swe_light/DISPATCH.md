## 2026-08-29T19:51:09Z
You are the SWE Light Orchestrator (teamwork_preview_swe) for this project.

The user request has been recorded verbatim in `/Users/ghchinoy/projects/LyriaFlow/.agents/ORIGINAL_REQUEST.md`.

Working directory: /Users/ghchinoy/projects/LyriaFlow
Integrity mode: development

Task:
Refactor the LyriaFlow macOS SwiftUI music player to strictly adhere to Apple macOS Human Interface Guidelines (HIG), removing the redundant vinyl disc in favor of a single, highly responsive 32-bar audio spectrum visualizer, and applying native macOS vibrancy materials and clean typographic hierarchy.

Requirements:
### R1. Apple macOS HIG Minimalist Theme & Vibrancy
Overhaul the UI styling to conform to Apple macOS Human Interface Guidelines:
- Replace flat/custom background fills with native macOS materials (.ultraThinMaterial, translucent window vibrancy, and standard system background tints).
- Establish clean SF Pro typographic hierarchy (.title2, .headline, .subheadline, .caption) across Now Playing, Sidebar, and Transport controls.
- Maintain a distraction-free, minimalist layout with standard macOS button styles, control margins, and keyboard focus.

### R2. Single Audio-Reactive 32-Bar Spectrum Visualizer
Remove the spinning vinyl record entirely and make the waveform visualizer the single, focused centerpiece:
- Implement a 32-bar adaptive audio spectrum that directly and visibly reacts to live audio metering (AVAudioPlayer.averagePower and peakPower).
- Provide fluid spring animations and frequency-band power weighting so bars actively bounce to beats, transients, and frequency dynamics during playback.
- Settle into a clean, subtle resting baseline when paused or stopped.

### R3. Preserved Full Architecture & Feature Integrity
Preserve all existing application functionality:
- Stdio JSON-RPC MCP client integration with mcp-lyria-go.
- Gemini next-track suggestion engine (Similar, Fun Twist, Wildcard).
- Up Next playlist queue with live status badges, reordering (▲/▼), and background pre-generation.
- Local track persistence in ~/Music/LyriaFlow/Tracks/.

Acceptance Criteria:
### HIG Compliance & Visualizer Reactivity
- [ ] Spinning vinyl disc is completely removed; only the 32-bar spectrum visualizer is displayed on the Now Playing stage.
- [ ] Visualizer bars actively and smoothly animate in real time in response to audio playback metering.
- [ ] Visualizer transitions smoothly to a clean resting state when playback is paused or finished.
- [ ] App adopts native macOS .ultraThinMaterial / system vibrancy and SF Pro typography.

### Build & Verification
- [ ] Automated unit test suite passes with zero failures (make test).
- [ ] App builds cleanly without warnings or errors (make build).
- [ ] App launches and displays immediately (make run).
- [ ] All queue operations (reordering, playing, clearing) and Gemini prompt suggestions remain fully functional.

Please manage your working directory in `.agents/swe_light/`, execute the SWE light workflow with implementer and reviewer rounds, verify all tests pass, and report back your completion / findings using `send_message` when done.
