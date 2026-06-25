# Speak a reply → Kubera drafts it into the open Gmail thread

**Date:** 2026-06-25
**Status:** Design — pending review
**Primary repo:** `micbar` (new post-transcription action). No other repo changes required for v1.

## Goal

While an email thread is open in the Gmail PWA, the user speaks a raw, unpolished
reply. With one MicBar gesture, those raw words become a **polished, threaded
reply saved as a Gmail draft** in that exact thread — in the user's voice, aware
of the incoming email. The user later opens the draft in Gmail and sends.

## User flow

1. Gmail thread open in `Gmail.app` (the Chrome-PWA shim), frontmost.
2. Press **record** on MicBar and speak the raw reply.
3. Click MicBar's **Email reply** button.
4. MicBar sends a **complete prompt** to Kubera via `tg` (instructions + the open
   thread's URL/subject + the transcript).
5. Kubera does the rest as instructed in the prompt: resolves the thread via
   `gws`, drafts a threaded reply in the user's voice, **saves it as a draft**
   (never sends), and confirms in Telegram.
6. User opens Gmail, reviews the draft in the thread, sends.

## Architecture

Two components.

```
┌──────────────── laptop: MicBar "Email reply" action ────────────────┐
│  • record + transcribe (existing WhisperKit pipeline)               │
│  • read open Gmail thread  (AppleScript → Google Chrome) → url+subj  │
│  • compose the COMPLETE prompt (template lives in MicBar)           │
│  • send it to Kubera via the local tg  (/Users/l/bin/tg send)       │
└────────────────────────────────┬─────────────────────────────────────┘
                                  │ Telegram DM, as @aekym → Kubera bot (id 8692271780)
┌──────────────────────────── Kubera (Hermes) ────────────────────────┐
│  • resolve the thread via gws (subject search + URL)                │
│  • read incoming email, draft reply in Lars's voice                 │
│  • save as THREADED draft (threadId + In-Reply-To/References)       │
│  • reply in Telegram: "✓ draft saved"                               │
└──────────────────────────────────────────────────────────────────────┘
```

MicBar's local LLM (`ImproveWriting` / Ollama) is **not** used here — Kubera does
the polishing so it can see the incoming email and apply the user's learned voice.

## The prompt (composed in MicBar)

The full message MicBar sends to Kubera. The template lives in MicBar (a setting
later if it needs tuning; for v1 it's in code):

```
Draft a reply to the Gmail thread below and SAVE IT AS A DRAFT in that thread —
do NOT send. Write it in my voice, replying to the latest message in the thread.

Thread:  <url>
Subject: <subject>

My raw spoken notes for the reply (clean these up into a proper email):
<transcript>
```

Kubera already loads the `gws`-backed `google-workspace` skill and has drafted
email replies before, so the prompt alone is enough for v1.

## Reading the open thread (AppleScript, validated)

The `Gmail.app` PWA runs inside the Google Chrome engine, so scripting
`application "Google Chrome"` yields its window URL + title:

```applescript
tell application "Google Chrome"
  repeat with w in windows
    set u to URL of active tab of w
    if u starts with "https://mail.google.com/" then
      return u & linefeed & (title of active tab of w)
    end if
  end repeat
end tell
```

- The URL fragment (`#inbox/FMfcgz…`) is Gmail's web-permalink id, **not** the
  API `threadId` — so Kubera resolves the thread by the **subject** (primary) plus
  the URL, not by decoding the id. Title format is
  `"<subject> - me@aekym.com - aekym.com Mail"`; subject = everything before
  ` - me@aekym.com`.
- If several Gmail windows match, prefer the one whose fragment holds a thread id
  (`#…/<id>`) over a bare `#inbox`; else the frontmost.

## Transport

The laptop has a standalone, authenticated `tg` at **`/Users/l/bin/tg`** (native
binary, its own TDLib session logged in as `@aekym`, id 870724091 — no serve
socket/tunnel). So MicBar sends **locally**, no ssh and no outpost hop:

```
/Users/l/bin/tg send --id 8692271780 --message "<complete prompt>"
```

Because `tg` is the userbot (the user's own account), the DM lands at Kubera as
if the user sent it. Kubera's chat-id is **8692271780**.

MicBar invokes it via `Process` with an argv array — `["send", "--id",
"8692271780", "--message", prompt]` — so there is **no shell** in the path and
**no quoting problem**: the whole prompt, spaces/newlines/quotes and all, is one
argv element handed straight to the binary. (A laptop `tg` session and the
outpost `telegram`-container session coexist fine — Telegram permits multiple
sessions per account; both already run.)

## MicBar changes (`micbar` repo)

The app already has four post-transcription actions — **Copy / Paste / Edit /
Answer** — each a button in `RecordingPopover` with a `popoverDidRequestStop…`
handler in `AppDelegate`, dispatched after `stopAndTranscribe` returns the text.
The new action is a **fifth**, in that exact pattern:

- **`RecordingPopover.swift`** — add an **Email reply** button (mail glyph) beside
  the existing four.
- **`AppDelegate.swift`** — add `popoverDidRequestStopEmailReply()`, mirroring
  `popoverDidRequestStopAnswer()`. On the transcript: read the open Gmail
  `{url, subject}`, compose the prompt, send via `tg`, surface a success/error
  notification via the existing path.
- **New file `EmailReplyBridge.swift`** — small testable unit: AppleScript read,
  title→subject parse, prompt assembly, local `tg` invocation (via `Process`).
  Keeps `AppDelegate` thin (mirrors how `ImproveWriting.swift` isolates its
  logic).

No change to recording/transcription/WhisperKit/Ollama paths. Build per repo
convention: `make install` → `/Applications/MicBar.app`.

## Error handling

- **No open thread** (no Gmail window, or bare `#inbox`): abort before sending,
  notify "No open email thread."
- **`tg` failure:** non-zero exit → show the error; nothing half-sent.
- **Empty/no speech:** existing no-speech path; never sends.
- **Thread unresolvable by Kubera:** Kubera asks in Telegram rather than drafting
  into the wrong thread.
- Nothing is ever auto-sent, so a bad transcription costs at most a discarded
  draft.

## Validated live during design

- Local `/Users/l/bin/tg` is authenticated as `@aekym`; `tg send` reaches Kubera,
  which receives and acts (replied "pong" to a probe).
- AppleScript reads the PWA thread URL + subject ("Boro.Today LiteDeck").
- Kubera has `gws` and a history of drafted email replies.

## Key choices

- **Save as Gmail draft** (not auto-send / Telegram-approval): human gate, zero
  send risk, lands in the exact thread.
- **Kubera as the brain** (not a local model / `echo`): self-learning voice,
  already drafts email, image bundles `gws` to both write and save the draft.
- **Telegram via `tg`** (not SSH-exec / HTTP): the personas expose no API;
  Telegram is Kubera's native channel and preserves its memory/self-learning.
- **AppleScript** (not a Chrome extension): the PWA is scriptable via Google
  Chrome — no extension to build.
- **MicBar composes the whole prompt and sends it directly** (no intermediary
  helper): simplest path; the prompt template lives in the app.

## Out of scope (v1)

- Editing/sending from MicBar (done in Gmail).
- Non-Gmail clients; multi-account beyond subject/URL resolution.
- A hotkey outside MicBar; server-side prompt tuning (could be a setting later).
- A dedicated Kubera skill — the prompt suffices for v1; add one only if behavior
  proves inconsistent.
