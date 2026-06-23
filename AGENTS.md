# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Overview

micbar is a native macOS menu bar app (Swift, AppKit) that records audio natively via AVFoundation, sends it to a WhisperKit server for transcription, then optionally runs the text through a local LLM (Ollama) before copying to clipboard.

## Building & Running

```bash
make build   # Build release .app bundle
make install # Build and copy .app to /Applications
make clean   # Remove build artifacts
```

**IMPORTANT:** Always use `make install` to build and deploy to `/Applications/MicBar.app`. Never run the app from the build directory — only ever open `/Applications/MicBar.app`. This avoids duplicate instances.

Requires Swift toolchain (Xcode Command Line Tools). No Xcode IDE needed.

## Dependencies

- Swift Package Manager (no external packages)
- WhisperKit server on localhost:50060 (speech-to-text)
- Ollama on localhost:11434 (local LLM for text operations, optional)

## Architecture

Swift Package (Package.swift) producing an AppKit executable, wrapped into a .app bundle by the Makefile.

### Source files (MicBar/)

- `main.swift` — Entry point. Sets up NSApplication with accessory activation policy.
- `AppDelegate.swift` — NSStatusBar menu bar UI, state machine (idle/waiting/recording/processing), popover management, notifications via UNUserNotificationCenter, Launch at Login via SMAppService. Left-click starts recording, right-click opens History & Settings.
- `RecordingPopover.swift` — NSViewController-based popover with recording (Copy / Paste / Edit / Answer buttons, timer) and processing states. AppKit layout, no SwiftUI.
- `Recorder.swift` — Orchestrates recording: starts AudioRecorder, stops it, sends WAV to TranscriptionClient, returns text.
- `AudioRecorder.swift` — Native audio capture via AVAudioEngine. Records at 16kHz mono PCM, produces WAV data.
- `TranscriptionClient.swift` — Sends WAV audio to WhisperKit server (localhost:50060) via multipart HTTP POST, parses JSON response.
- `ImproveWriting.swift` — System prompts for the text operations (improve/answer/rewrite/summarize/key-points/translate) plus `runOllamaCall`, which calls the local Ollama server (localhost:11434) via HTTP.
- `TranscriptStore.swift` — In-memory store of transcript records (raw + improved text + error state), observable for SwiftUI.
- `HistoryWindow.swift` — NSWindow hosting the SwiftUI History & Settings view, switches activation policy for proper window behavior.
- `HistoryView.swift` — SwiftUI views: tabbed layout with TranscriptsTab (transcript cards with edit/copy/improve) and SettingsTab (dependency health checker, Launch at Login).
- `DependencyChecker.swift` — ObservableObject that probes services (WhisperKit Server :50060, Local LLM (Ollama) :11434) with async health checks.
- `Logger.swift` — Singleton file logger writing to `~/Library/Logs/micbar.log` with serial DispatchQueue for thread safety.

### Key details

- `LSUIElement=true` in Info.plist — no dock icon
- Icons are 36x36 PNGs (Retina @2x for 18pt menu bar) in MicBar/Resources/
- Login item managed by SMAppService (macOS 13+), no launchd plist needed
- ProcessInfo.beginActivity with full QoS options ensures CPU priority for audio capture

Debug logs are written to `~/Library/Logs/micbar.log`.
