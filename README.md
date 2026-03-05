# micbar

macOS menu bar app for speech-to-text. Click to record, stop to get a transcription on your clipboard. Optionally pipe through a writing improver before copying.

## Prerequisites

- Python 3.14+
- `mictotext` on PATH — speech-to-text CLI
- `improve-writing` on PATH — text post-processing CLI (optional, for the "Improve" action)

## Setup

```bash
python3 -m venv venv
source venv/bin/activate
pip install rumps
```

## Usage

### Run manually

```bash
make run
```

A microphone icon appears in the menu bar. The menu has three actions:

- **Start Recording** — starts `mictotext` in the background, icon turns red
- **Stop -> Clipboard** — stops recording, copies transcription to clipboard
- **Stop -> Improve -> Clipboard** — stops recording, pipes text through `improve-writing`, copies result to clipboard

### Install as a login service

The included launchd plist runs micbar automatically when you log in.

```bash
make install
```

This copies `com.aekym.micbar.plist` to `~/Library/LaunchAgents/` and loads it. The service starts on GUI login sessions (`Aqua`) and does not restart on exit.

To stop and remove the service:

```bash
make uninstall
```

To restart the service:

```bash
make restart
```

> **Note:** The plist contains hardcoded paths to the project directory. If you move the project, update the paths in `com.aekym.micbar.plist`.
