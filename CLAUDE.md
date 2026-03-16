# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

micbar is a native macOS menu bar app (Swift, AppKit) that records audio via an external `mictotext` CLI tool, then optionally improves the transcription via an LLM proxy before copying to clipboard.

## Building & Running

```bash
make build   # Build release .app bundle
make run     # Build and open the app
make clean   # Remove build artifacts
```

Requires Swift toolchain (Xcode Command Line Tools). No Xcode IDE needed.

## Dependencies

- Swift Package Manager (no external packages)
- External CLIs expected on PATH: `mictotext` (speech-to-text)
- LLM proxy on localhost:8317 (OpenAI-compatible API for text improvement, optional)

## Architecture

Swift Package (Package.swift) producing an AppKit executable, wrapped into a .app bundle by the Makefile.

### Source files (MicBar/)

- `main.swift` — Entry point. Sets up NSApplication with accessory activation policy.
- `AppDelegate.swift` — NSStatusBar menu bar UI, state machine (idle/waiting/recording/processing), popover management, notifications via UNUserNotificationCenter, Launch at Login via SMAppService. Left-click starts recording, right-click opens History & Settings.
- `RecordingPopover.swift` — NSViewController-based popover with recording (stop/improve buttons, timer) and processing states. AppKit layout, no SwiftUI.
- `MicToTextProcess.swift` — Manages the `mictotext` subprocess using `posix_spawnp` with `POSIX_SPAWN_SETPGROUP` (own process group). Monitors stderr on a background DispatchQueue for "Recording now" readiness signal. Stops via `kill(-pid, SIGINT)`. Has `resolveExecutable()` for PATH-based CLI lookup.
- `ImproveWriting.swift` — Calls LLM proxy (localhost:8317) directly via HTTP using OpenAI-compatible chat completions API. No external CLI dependency.
- `TranscriptStore.swift` — In-memory store of transcript records (raw + improved text + error state), observable for SwiftUI.
- `HistoryWindow.swift` — NSWindow hosting the SwiftUI History & Settings view, switches activation policy for proper window behavior.
- `HistoryView.swift` — SwiftUI views: tabbed layout with TranscriptsTab (transcript cards with edit/copy/improve) and SettingsTab (dependency health checker, Launch at Login).
- `DependencyChecker.swift` — ObservableObject that probes CLI tools (mictotext, ffmpeg, whisperkit-cli) and services (WhisperKit Server :50060, LLM proxy :8317) with async health checks.
- `Logger.swift` — Singleton file logger writing to `~/Library/Logs/micbar.log` with serial DispatchQueue for thread safety.

### Key details

- `LSUIElement=true` in Info.plist — no dock icon
- Icons are 36x36 PNGs (Retina @2x for 18pt menu bar) in MicBar/Resources/
- Login item managed by SMAppService (macOS 13+), no launchd plist needed
- ProcessInfo.beginActivity with full QoS options ensures CPU priority for audio capture

Debug logs are written to `~/Library/Logs/micbar.log`.
