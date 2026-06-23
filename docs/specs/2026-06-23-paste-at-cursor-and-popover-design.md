# Paste-at-Cursor + Recording Popover Redesign — Design

**Date:** 2026-06-23

## Goals

Two related changes to the recording popover:

1. **Replace "Stop, Improve & Copy"** with an **"Edit…"** action that stops,
   transcribes, and opens the History window so all transforms (Improve /
   Rewrite / Summarize / Answer / manual edit) happen in one place instead of
   being baked into the popover.
2. **Add a "Paste" action** that inserts the raw transcript **where the cursor
   was** before the menu-bar mic was clicked, instead of only putting it on the
   clipboard.
3. **Redesign the popover layout** so the buttons no longer look stretched and
   the hierarchy is clear.

## Decisions (from brainstorming)

- Primary action stays **Copy**; **Paste** is a secondary action.
- Paste inserts the **raw** transcript (no LLM wait; transforms live in History).
- Injection uses a **fallback chain** that avoids the clipboard when possible:
  AX insert-at-cursor → synthetic typing → clipboard + ⌘V (last resort).
- Layout **A revised** (see mockup): status at top, X to discard in the
  top-right corner.

## Layout

Recording-state popover, top to bottom (≈256 pt wide):

```
● Recording                0:12        ✕   ← status row + discard (top-right)
MacBook Pro Microphone                     ← device name (small, secondary)
[            Copy            ]             ← primary, accent-tinted, full width
[ ⎘ Paste ] [ ✎ Edit… ] [ ? Answer ]       ← secondary row, icon over label
```

- The **✕** (top-right) replaces the old "Cancel" text link; it discards the
  recording (current `cancelRecording()` behavior).
- The persistent History/clock icon is removed from the recording view — its
  job is now covered by **Edit…**, the ✕, and right-click on the menu-bar icon.
  (The processing view keeps its History icon as-is.)
- Buttons use SF Symbols: Copy `doc.on.doc`, Paste `arrow.down.doc` (or
  `text.insert`), Edit… `pencil`, Answer `bubble.left`.
- "Edit…" label chosen during brainstorming; the trailing ellipsis signals it
  opens another window.

## Components

### 1. `TextInjector.swift` (new)

Owns "put this text where the user's cursor was." Single responsibility, no UI.

- `captureFrontmostApp() -> NSRunningApplication?` — returns
  `NSWorkspace.shared.frontmostApplication`. Called by AppDelegate at record
  start, **before** MicBar activates/steals focus.
- `inject(_ text: String, into app: NSRunningApplication?) -> InjectionResult`
  where `InjectionResult` is `.inserted` / `.typed` / `.pasted` / `.copiedOnly`.
  Steps:
  1. Reactivate `app` (`app.activate()`) and wait briefly (~80–120 ms) for it to
     become frontmost and restore its focused field + caret.
  2. **Gate on Accessibility.** If `AXIsProcessTrusted()` is false: skip 3a–3c,
     copy to clipboard, return `.copiedOnly` (and let AppDelegate prompt).
  3. Try in order, returning on first success:
     - **3a. AX insert-at-cursor:** system-wide `AXUIElement` →
       `kAXFocusedUIElementAttribute` → set `kAXSelectedTextAttribute` to `text`
       (replaces selection / inserts at caret). Only when the attribute is
       settable.
     - **3b. Synthetic typing:** post key events via
       `CGEvent(keyboardEventSource:)` + `keyboardSetUnicodeString`, chunked, so
       no clipboard touch.
     - **3c. Clipboard + ⌘V:** save current pasteboard items, set the string,
       post ⌘V via `CGEvent`, then restore the saved pasteboard after a short
       delay.
- Needs **Accessibility** permission (covers both AX writes and posting
  `CGEvent`s to other apps). Prompt with
  `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.

### 2. `AppDelegate.swift`

- Add `private var previousApp: NSRunningApplication?`. Set it via
  `textInjector.captureFrontmostApp()` at the very start of `startRecording`,
  before `NSApp.activate` / `showPopover`.
- **`FinishMode`**: drop `.improve`; the inline-improve path is gone. Keep
  `.copy`, `.answer`; add `.paste`.
- Delegate methods:
  - `popoverDidRequestStopEdit()` → new `stopAndOpenHistory()`: set
    `.processing`, transcribe, `transcriptStore.addTranscript(raw:)`, then
    `historyWindowController.showWindow(tab: 0)`, set `.idle`. No LLM call.
  - `popoverDidRequestStopPaste()` → new `stopAndPaste()`: set `.processing`,
    transcribe raw, `textInjector.inject(text, into: previousApp)`,
    `addTranscript(raw:)`, notify with the result (e.g. "Pasted", "Typed",
    "Pasted via clipboard", or "Copied — grant Accessibility to paste"), set
    `.idle`.
  - Remove `popoverDidRequestStopImprove()`.
  - `popoverDidRequestStopCopy()`, `…StopAnswer()`, `…Cancel()`,
    `…OpenHistory()` unchanged. The ✕ maps to `…Cancel()`.

### 3. `RecordingPopover.swift`

- Rebuild `buildRecordingView()` for Layout A revised: top status row (red dot +
  "Recording" + right-aligned timer), ✕ button pinned top-right, device label,
  full-width primary **Copy**, then a 3-up secondary row (**Paste**, **Edit…**,
  **Answer**) with icon-over-label compact buttons.
- Protocol `RecordingPopoverDelegate`: replace
  `popoverDidRequestStopImprove()` with `popoverDidRequestStopEdit()` and add
  `popoverDidRequestStopPaste()`.
- Recompute `totalH` for the new layout. `waiting`/`recording` reuse this view;
  in `waiting` the timer shows "Starting…" as today.

### 4. Settings / permissions surfacing (scoped)

- Add an **Accessibility permission** row to the Settings tab (and/or
  `DependencyChecker`) showing granted/not-granted with a button to open
  *System Settings → Privacy & Security → Accessibility*. This is the one
  non-obvious requirement for Paste, so it's worth a visible indicator.

## Data flow (Paste)

```
click mic → captureFrontmostApp() → record → click Paste
  → recorder.stop() (raw text)
  → TextInjector.inject(text, into: previousApp)   [AX → typing → clipboard+⌘V]
  → addTranscript(raw:) → notify(result) → idle
```

## Error handling

- **No speech detected:** notify + return to idle (unchanged).
- **Accessibility not granted:** prompt once; this run copies to clipboard and
  notifies the user to grant permission, so nothing is lost.
- **AX/typing fail mid-chain:** fall through to the next method; clipboard + ⌘V
  is the guaranteed final step when Accessibility is granted.
- **Clipboard restore:** always restore the user's prior clipboard after the
  ⌘V fallback.

## Testing

- Pure logic is thin (mostly side-effecting OS calls), consistent with the
  codebase having no UI tests. Verification is a **manual checklist** run after
  `make install`:
  1. Focus a text field in TextEdit → mic → speak → **Paste** → text appears at
     the caret; prior clipboard intact.
  2. Repeat in a non-AX app (e.g. a terminal) → falls back to typing or
     clipboard+⌘V; text still lands.
  3. Revoke Accessibility → **Paste** → text is copied + notification prompts to
     grant; nothing lost.
  4. **Edit…** → History opens on Transcripts with the new transcript on top.
  5. **Copy** and **Answer** unchanged; ✕ discards.
- If any small pure helper emerges (e.g. text chunking for typing), add a unit
  test mirroring `ImproveWritingTests`.

## Out of scope

- Global hotkey, streaming/partial paste, per-app injection preferences,
  improved-text paste (raw only for now).
