# LyriaFlow User Guide

This guide covers the operation, architecture, and configuration of LyriaFlow, a native macOS music player designed for on-the-fly music generation with Google Lyria AI and Gemini.

---

## Table of Contents

1. [Overview & Core Architecture](#1-overview--core-architecture)
2. [Prerequisites & Initial Setup](#2-prerequisites--initial-setup)
3. [Generating Music](#3-generating-music)
4. [Audio Playback & 32-Bar Spectrum Visualizer](#4-audio-playback--32-bar-spectrum-visualizer)
5. [Gemini Suggestions & 3-Movement Suites](#5-gemini-suggestions--3-movement-suites)
6. [Managing the Up Next Playlist Queue](#6-managing-the-up-next-playlist-queue)
7. [Track Persistence & Metadata Inspection](#7-track-persistence--metadata-inspection)
8. [Diagnostics & Troubleshooting](#8-diagnostics--troubleshooting)

---

## 1. Overview & Core Architecture

LyriaFlow is written in Swift and SwiftUI, built specifically for macOS 14 (Sonoma) and later. It interfaces with Google's generative audio models via the Model Context Protocol (MCP).

```
+-------------------------------------------------------------------------------+
|                            LyriaFlow (macOS App)                             |
|                                                                               |
|   +--------------------------+       +------------------------------------+   |
|   |   PlaybackCoordinator    | <---> |            AudioEngine             |   |
|   |       (@MainActor)       |       |  (AVAudioPlayer + Power Metering)  |   |
|   +--------------------------+       +------------------------------------+   |
|         ^              ^                                                      |
|         |              |                                                      |
|         v              v                                                      |
|  +--------------+  +------------------------+  +---------------------------+  |
|  |  MCPClient   |  | GeminiSuggestionEngine |  |     PersistenceStore      |  |
|  |   (Actor)    |  |       (REST API)       |  | (~/Music/LyriaFlow/Tracks)|  |
|  +--------------+  +------------------------+  +---------------------------+  |
|         |                                                                     |
+---------|---------------------------------------------------------------------+
          |  stdio JSON-RPC
          v
+------------------------------------+
|            mcp-lyria-go            |
|       (Vertex AI Subprocess)       |
+------------------------------------+
```

### Component Breakdown

- **`MCPClient`**: An isolated Swift actor that manages the lifecycle of the `mcp-lyria-go` background process over standard input and standard output pipes. It translates Swift async calls into JSON-RPC 2.0 requests.
- **`PlaybackCoordinator`**: The central `@MainActor` state machine. It manages track generation, queue ordering, auto-play progression, and UI state synchronization.
- **`AudioEngine`**: A wrapper around `AVAudioPlayer`. It meters audio power levels across 32 distinct frequency bands, handles seeking, and broadcasts playback events.
- **`GeminiSuggestionEngine`**: A client for Google AI Studio's Gemini REST API. It uses structured JSON output schemas to generate contextual musical prompt variations and 3-movement suites.
- **`PersistenceStore`**: Manages local JSON metadata in `~/Library/Application Support/LyriaFlow/tracks.json` and audio files in `~/Music/LyriaFlow/Tracks/`.
- **`AudioFormatDetector`**: Inspects file header magic bytes to verify audio container formats (MP3 vs WAV) and ensures C2PA provenance signatures remain intact.

---

## 2. Prerequisites & Initial Setup

### Requirements

- macOS 14.0 or higher.
- A compiled `mcp-lyria-go` binary.
- Google Cloud project access or a Gemini API key.

### Binary Location

By default, LyriaFlow searches for `mcp-lyria-go` in the following locations:

1. `/Users/<user>/go/bin/mcp-lyria-go`
2. `/usr/local/bin/mcp-lyria-go`
3. `/Users/<user>/.local/bin/mcp-lyria-go`

You can specify a custom binary path in the app settings.

### Environment Setup

Set your environment variables before launching the application:

```bash
# Google Cloud Vertex AI credentials for Lyria
export GOOGLE_APPLICATION_CREDENTIALS="/Users/you/.config/gcloud/application_default_credentials.json"
export GOOGLE_CLOUD_PROJECT="your-project-id"

# Optional: Gemini API key for dynamic suggestions
export GEMINI_API_KEY="AIzaSy..."
```

---

## 3. Generating Music

### Entering a Prompt

Type your description into the bottom prompt input bar. For best results with Lyria models, describe instruments, tempo, mood, and genre.

Example prompt:
```
Warm lo-fi ambient electronic music with soft Rhodes keys, lush analog synth pads, and a subtle syncopated beat
```

### Model Selection

LyriaFlow supports Google's Lyria 3 model family:

- **`lyria-3-clip-preview`**: Optimized for fast generation (~6-8 seconds) and short music clips.
- **`lyria-3-pro-preview`**: Optimized for richer harmonic complexity and higher fidelity.

Select your preferred model via the model picker next to the prompt bar or in Settings.

### Seed Control

LyriaFlow generates a random 32-bit integer seed for each track to ensure reproducibility. You can inspect and copy the seed of any track using the Track Inspector.

---

## 4. Audio Playback & 32-Bar Spectrum Visualizer

### Visualizer Mechanics

The central visualizer renders 32 adaptive frequency spectrum bars that react in real time to the audio output:

- **Low Bands (Bars 1-8)**: Tuned to basslines, kicks, and sub-frequencies.
- **Mid Bands (Bars 9-22)**: Tuned to melodies, vocals, guitars, and synthesizer leads.
- **High Bands (Bars 23-32)**: Tuned to hi-hats, cymbals, air, and high-frequency harmonics.

When playback pauses or stops, the bars smoothly settle into a resting baseline value of 0.04.

### Playback Controls

- **Play / Pause**: Click the center transport button or press the **Spacebar**.
- **Scrubbing**: Click or drag anywhere along the bottom progress bar.
- **Loop**: Toggle the repeat button (`repeat.1`) to loop the current track indefinitely.
- **Skip**: Click the forward button (`forward.end.fill`) to jump to the top item in the Up Next queue.
- **Volume**: Adjust the bottom right slider.

---

## 5. Gemini Suggestions & 3-Movement Suites

While a track plays, the Gemini engine analyzes the current prompt and produces three variations:

```
+-------------------------------------------------------------------------------+
|                        Gemini Next-Track Suggestions                          |
|                                                                               |
|  [Similar]                      [Fun Twist]                   [Wildcard]      |
|  "Smooth lo-fi jazz chill"      "Funky electro swing groove"  "Cyberpunk dub" |
|                                                                               |
|  [Play Now] [+1] [3x Vibe]      [Play Now] [+1] [3x Vibe]     [Play Now] ...  |
+-------------------------------------------------------------------------------+
```

### Actions on Suggestion Cards

- **Play Now**: Immediately generates and plays the prompt, replacing the current track.
- **+1 Queue**: Appends the single prompt to the Up Next playlist queue.
- **Queue 3x Vibe**: Generates and enqueues a coherent 3-movement suite that evolves across three tracks:
  - **Movement I (Atmospheric Build)**: Spacious introductory build with gentle rising tension.
  - **Movement II (Deep Groove)**: Core rhythm, punchy bassline, and full melodic arrangement.
  - **Movement III (Climax / Outro)**: High-energy melodic variations and harmonic resolution.

### Auto-Play Coherence

When you enable the **Auto-Play** toggle, the app maintains the current sonic theme across a 3-track suite before selecting a new style. This prevents abrupt genre hopping during extended listening sessions.

---

## 6. Managing the Up Next Playlist Queue

Access the queue by selecting the **Up Next** tab in the sidebar.

### Queue Status Indicators

- `⚡️ Ready` (Green): Audio generation is complete. The track is cached locally for instant, zero-latency playback.
- `⏳ Generating...` (Orange): The background worker is currently composing the audio file via `mcp-lyria-go`.
- `📋 Queued` (Purple): The track is waiting in line to be processed.
- `⚠️ Failed` (Red): Generation encountered an error (such as a network timeout or policy filter).

### Reordering & Editing Tracks

- **Move Up (▲) / Move Down (▼)**: Hover over any row to reveal reordering buttons.
- **Drag and Drop**: Grab any row to rearrange items in the list.
- **Play Immediately (▶)**: Jump straight to any queued track. If the track is already marked `Ready`, it starts playing instantly.
- **Remove (✕)**: Delete an item from the queue and free its temporary cached audio.
- **Clear Queue**: Click the "Clear" button in the header to purge all upcoming tracks.

---

## 7. Track Persistence & Metadata Inspection

### File Storage & C2PA Provenance

LyriaFlow stores audio files in your user library:

```
~/Music/LyriaFlow/Tracks/
```

Files are saved directly as native MP3 bitstreams. This preserves Google's embedded C2PA provenance manifest (stored in an ID3 `GEOB` frame) without re-encoding.

### Track Metadata Inspector

Click the info button `(i)` on the Now Playing stage or select **Get Info** from any track context menu to open the Track Inspector:

```
+-------------------------------------------------------------------------------+
|  Track Inspector                                                              |
|                                                                               |
|  Musical Prompt:                                                              |
|  "Warm lo-fi ambient electronic music with soft Rhodes keys"      [Copy]      |
|                                                                               |
|  Generation Specs:                                                            |
|  Lyria Model:   Lyria 3 Pro (lyria-3-pro-preview)                             |
|  Duration:      0:30 (30.0s)                                                  |
|  Format:        MP3 Audio (MPEG Layer 3)  [C2PA Signed]                       |
|  Seed:          482910492                                                     |
|  Created At:    Aug 29, 2026 at 4:30 PM                                       |
|                                                                               |
|  File Storage:                                                                |
|  Path: /Users/.../Music/LyriaFlow/Tracks/lyria_1788042480_D4A5.mp3            |
|  [Reveal in Finder]  [Copy Path]                                              |
+-------------------------------------------------------------------------------+
```

---

## 8. Diagnostics & Troubleshooting

### Application Logs

LyriaFlow records detailed diagnostic information, including MCP process communication and audio format detection, to:

```
~/Library/Logs/LyriaFlow/lyriaflow.log
```

To access logs from within the app:
1. Open **Settings** (gear icon in the sidebar).
2. Scroll to **Diagnostics & Logs**.
3. Click **Reveal Log** to locate the file in Finder, or **Copy Recent Logs** to copy entries to your clipboard.

### Common Issues and Resolutions

#### 1. MCP Server Offline / Red Status Indicator
- Verify that `mcp-lyria-go` is built and executable:
  ```bash
  ls -la ~/go/bin/mcp-lyria-go
  ```
- Open Settings, check the binary path, and click **Test / Ping**.

#### 2. Generation Error: "Request blocked for policy reason"
- Vertex AI audio filters reject prompts that include named artists or protected trademarks.
- Modify the prompt to describe sonic qualities, instruments, and genres instead of artist names.

#### 3. Missing API Key Warning
- If no Gemini API key is configured, LyriaFlow falls back to built-in musical variation templates.
- Add an API key in Settings under **Gemini AI Suggestions** to re-enable dynamic model suggestions.
