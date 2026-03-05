# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

micbar is a macOS menu bar app (using `rumps`) that records audio via an external `mictotext` CLI tool, then optionally pipes the transcription through an `improve-writing` CLI tool before copying to clipboard.

## Running

```bash
make run
```

## Dependencies

- `rumps` - macOS menu bar framework
- External CLIs expected on PATH: `mictotext` (speech-to-text), `improve-writing` (text post-processing), `pbcopy` (macOS clipboard)

## Architecture

Single-file app (`micbar.py`). `MicBar` subclasses `rumps.App` and manages a `mictotext` subprocess. Recording starts a subprocess in its own process group; stopping sends SIGINT to that group and reads stdout. Menu items toggle between enabled/disabled states based on recording status.

The launchd plist is generated from `com.aekym.micbar.plist.template` at install time via `make install`, substituting `__PROJECT_DIR__` and `__HOME__` with local paths.
