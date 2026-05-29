# Rewrite Button — Design

**Date:** 2026-05-29

## Goal

Add a "Rewrite" action to each transcript card that turns a raw dictated
brainstorm — half-finished sentences, tangents, repetition — into a single
comprehensive, clearly-written message that flows well. Unlike "Improve" (a
light touch-up), Rewrite is free to reorganize, merge, and reorder ideas.

## Placement

A new "Rewrite" button in the transcript card action row, positioned between
**Improve** and **Summarize**.

## Changes

All four changes follow the existing per-operation pattern
(`Summarize`/`runSummarize`/`store.summarize`).

### 1. `ImproveWriting.swift`

Add `RewriteConfig` struct + `runRewrite(...)` function, mirroring
`SummarizeConfig`/`runSummarize`. System prompt:

> You are an expert editor. Detect which language the user's input is in and
> always respond in the same language. Return ONLY the rewritten text, nothing
> else — no XML tags, no explanations, no preamble.
>
> The user has dictated raw, unstructured thoughts via voice — a brainstorm
> full of half-finished sentences, tangents, and repetition. Rewrite it into a
> single comprehensive, well-structured message in clear language. Bring
> together all the points raised; reorganize and merge them so the result flows
> well; remove filler and false starts. Preserve every distinct idea and the
> user's intent and tone. Do not add new ideas or information. The result should
> read like a thoughtful message written for another person.

### 2. `TranscriptStore.swift`

Add `rewrite(id:)` mirroring `summarize(id:)`:
- pending label: `"Rewriting..."` (+ `" locally"` when local)
- chain label: `"Rewritten"`
- local-Ollama branch using `runOllamaCall` with `RewriteConfig().systemPrompt`

### 3. `HistoryView.swift`

Add a bordered "Rewrite" button calling `store.rewrite(id:)`, between the
Improve and Summarize buttons.

## Data flow & error handling

Identical to existing operations: operates on `record.latestText`, appends a
`ChainEntry` on success or sets `pendingError`. Inherits retry, local/remote
toggle, and progress UI for free via `runLLMOperation`.

## Testing

Existing `ImproveWritingTests` cover the shared parse/retry path that Rewrite
reuses. There are no per-operation/config-default tests in the suite, so no new
test is added for Rewrite — doing so would only duplicate already-covered
behavior and diverge from the codebase convention.
