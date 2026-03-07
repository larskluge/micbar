# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

micbar is a native macOS menu bar app (Swift, AppKit) that records audio via an external `mictotext` CLI tool, then optionally pipes the transcription through an `improve-writing` CLI tool before copying to clipboard.

## Building & Running

```bash
make build   # Build release .app bundle
make run     # Build and open the app
make clean   # Remove build artifacts
```

Requires Swift toolchain (Xcode Command Line Tools). No Xcode IDE needed.

## Dependencies

- Swift Package Manager (no external packages)
- External CLIs expected on PATH: `mictotext` (speech-to-text), `improve-writing` (text post-processing)

## Architecture

Swift Package (Package.swift) producing an AppKit executable, wrapped into a .app bundle by the Makefile.

### Source files (MicBar/)

- `main.swift` — Entry point. Sets up NSApplication with accessory activation policy.
- `AppDelegate.swift` — NSStatusBar menu bar UI, state machine (idle/waiting/recording/processing), menu item management, notifications via UNUserNotificationCenter, improve-writing subprocess, Launch at Login via SMAppService.
- `MicToTextProcess.swift` — Manages the `mictotext` subprocess using `posix_spawnp` with `POSIX_SPAWN_SETPGROUP` (own process group). Monitors stderr on a background DispatchQueue for "Recording now" readiness signal. Stops via `kill(-pid, SIGINT)`.
- `Logger.swift` — Singleton file logger writing to `~/Library/Logs/micbar.log` with serial DispatchQueue for thread safety.

### Key details

- `LSUIElement=true` in Info.plist — no dock icon
- Icons are 36x36 PNGs (Retina @2x for 18pt menu bar) in MicBar/Resources/
- Login item managed by SMAppService (macOS 13+), no launchd plist needed
- ProcessInfo.beginActivity with full QoS options ensures CPU priority for audio capture

Debug logs are written to `~/Library/Logs/micbar.log`.
