# micbar

Native macOS menu bar app for speech-to-text. Click to record, stop to get a transcription on your clipboard. Optionally process through LLM-powered text operations before copying.

Built with Swift and AppKit. No Xcode IDE required.

## Prerequisites

- Swift toolchain (Xcode Command Line Tools)
- WhisperKit server on port 50060 — speech-to-text service (`brew install whisperkit-cli`)
- LLM proxy on port 8317 — powers all LLM-based text operations, optional (`brew install cliproxyapi`)

## Building & Running

```bash
make build   # Build release .app bundle
make install # Build and copy .app to /Applications
make clean   # Remove build artifacts
```

## Testing

```bash
swift test
```

## Usage

A microphone icon appears in the menu bar. Click it to open a popover with a record button.

- **Record** — starts native audio recording; icon shows a red recording indicator
- **Stop & Copy** — stops recording, copies transcription to clipboard
- **Stop, Improve & Copy** — stops recording, improves text via LLM, copies result to clipboard

The popover also links to a **History & Settings** window where you can:

- Browse and edit past transcriptions
- **Improve** — polish text for grammar and clarity
- **Summarize** — generate a concise summary
- **Key Points** — extract essentials as a bullet-point list
- **Answer** — treat the transcript as a question and get a response
- **Translate** — translate to/from configurable languages
- Check dependency health with install commands
- Configure translation languages
- Toggle Launch at Login

## Launch at Login

Managed via SMAppService (macOS 13+) from the Settings tab. No launchd plist needed.
