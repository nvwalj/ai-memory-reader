# Changelog

All notable changes to AI Memory Reader. Full release notes and downloads:
https://github.com/nvwalj/ai-memory-reader/releases

## v0.4.11 — 2026-06-10

**Double-clicking a file now also opens its folder.**

- Opening a file directly (Finder double-click, drag-drop, `aimr open`, URL
  scheme) used to show the lone file with the sidebar hidden. Now the file
  still opens instantly, and the sidebar then slides in with the file's parent
  directory loaded and the file selected — siblings (other memory files,
  configs, transcripts) are one click away, matching how multi-file drops
  already behave.
- The directory tree is built off the main thread, so the double-click fast
  path stays as fast as v0.4.9 made it. If the folder isn't readable (App
  Store build double-clicks grant access to the file only), the single-file
  view stays exactly as before.
- Files that don't look like memory files stay visible in the tree when opened
  directly, instead of being filtered out from their own folder view.

## v0.4.10 — 2026-06-03

**Fixed sidebar selection flicker / ghost highlight boxes.**

- The file-tree List carried `.id(fileChangeToken)`, so every filesystem event
  (recursive FSEvents) tore down and rebuilt the entire List — constantly on a
  live source like `~/.claude` where agents write session files. The recreation
  dropped first-responder (the selection redrew inactive-gray) and, colliding
  with the `selectedFile` object swap in `handleFileSystemChange`, left **ghost
  selection boxes** stuck on previously-selected rows.
- Fix: the tree is now reconciled **in place** (`FileTreeBuilder.merge`) — existing
  `FileNode` objects are reused wherever the path matches, so the List, its
  selection, expansion state, and scroll position survive filesystem events; only
  genuine file adds/removes mutate the tree. Removed `.id(fileChangeToken)` and the
  now-unused expand-path snapshot helpers. The detail view's content auto-reload
  (driven by `fileChangeToken`) is unchanged.
- Note: a selected row still greys when the sidebar loses focus — that is standard
  macOS inactive-selection behavior, not the bug that was fixed.

## v0.4.9 — 2026-06-02

**Faster launch.**

- Source detection (scanning `~/.claude`, `~/.codex`, `~/.cursor`, … for AI
  memory files) used to run **synchronously in `AppState.init`**, before the
  window appeared — slow when those folders are large (a busy
  `~/.claude/projects` can hold thousands of session files). It now runs off the
  main thread via `detectSourcesIfNeeded()` (invoked from the view's `.task`),
  so the window shows immediately and the sidebar source list fills in a moment
  later.
- **Double-clicking a `.md` file in Finder no longer waits on any directory scan
  at all** — `openSingleFile` shows the file right away, and a default source is
  only auto-selected when no file was opened directly.
- Fixed a pre-existing iOS build break: `rebuildCurrentTree` referenced
  `collectExpandedPaths` / `restoreExpandedPaths`, which were nested under
  `#if os(macOS)`. Those two are pure `FileNode` helpers and were moved out of
  the guard; `handleFileSystemChange` (FSEvents) stays macOS-only.

_Known follow-up (not in this release): the source-detection scan
(`AISource.containsSupportedFiles`) still walks the whole directory tree to
decide whether a source has memory files; a bounded/lazy version is planned._

## v0.4.8 — 2026-05-23

- Added **Qwen Code** (`~/.qwen`) and **Kimi CLI** (`~/.kimi`) as auto-discovered
  sources — 10 agents now.

## v0.4.7 — 2026-05-23

- `.mdx` file support (open via Finder, drag-drop, and the sidebar tree).
- Work-in-progress: Suggested Rules (promote repeated session corrections to
  `CLAUDE.md`).
