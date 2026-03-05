# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

mic_bar is a macOS menu bar app (using `rumps`) that records audio via an external `mictotext` CLI tool, then optionally pipes the transcription through an `improve-writing` CLI tool before copying to clipboard.

## Running

```bash
# Activate venv (Python 3.14)
source venv/bin/activate

# Run the app
python mic_bar.py
```

## Dependencies

- `rumps` - macOS menu bar framework
- External CLIs expected on PATH: `mictotext` (speech-to-text), `improve-writing` (text post-processing), `pbcopy` (macOS clipboard)

## Architecture

Single-file app (`mic_bar.py`). `MicBar` subclasses `rumps.App` and manages a `mictotext` subprocess. Recording starts a subprocess in its own process group; stopping sends SIGINT to that group and reads stdout. Menu items toggle between enabled/disabled states based on recording status.
