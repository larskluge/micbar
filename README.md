# micbar

Native macOS menu bar app for speech-to-text. Click to record, stop to get a transcription on your clipboard. Optionally pipe through a writing improver before copying.

Built with Swift and AppKit. No Xcode IDE required.

## Prerequisites

- Swift toolchain (Xcode Command Line Tools)
- [`mictotext`](https://github.com/larskluge/mictotext) on PATH — speech-to-text CLI (requires `ffmpeg`, `whisperkit-cli`, and a WhisperKit server on port 50060)
- LLM proxy on port 8317 — OpenAI-compatible API for the "Improve" feature (optional)

## Building & Running

```bash
make build   # Build release .app bundle
make run     # Build and open the app
make clean   # Remove build artifacts
```

## Testing

```bash
swift test
```

## Usage

A microphone icon appears in the menu bar. Click it to open a popover with a record button.

- **Record** — starts `mictotext` in the background; icon shows a waiting state while initializing, then a red recording indicator
- **Stop & Copy** — stops recording, copies transcription to clipboard
- **Stop, Improve & Copy** — stops recording, improves text via LLM, copies result to clipboard

The popover also links to a **History & Settings** window where you can:

- Browse and edit past transcriptions
- Improve previous transcripts via LLM
- Check dependency health (CLI tools and service availability)
- Toggle Launch at Login

## Launch at Login

Managed via SMAppService (macOS 13+) from the Settings tab. No launchd plist needed.
