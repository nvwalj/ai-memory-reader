# Changelog

All notable changes to AI Memory Reader. Full release notes and downloads:
https://github.com/nvwalj/ai-memory-reader/releases

## Unreleased

**iPhone: read any GitHub repository's documents.**

- Add a repository by pasting `owner/repo` or any github.com link — including a
  link to a branch or a folder, like `.../tree/main/docs`, which scopes the
  browse to that folder. Until now the iOS app had no content source at all:
  source auto-discovery returns nothing on iOS, so it could only open a file
  you handed it through the document picker.
- Browses every readable document — Markdown, `.txt`, JSON/JSONL, YAML, TOML,
  and bare `README`/`LICENSE`/`CHANGELOG`. Folders holding nothing readable are
  pruned, so a repo doesn't open onto a wall of `src/` and `node_modules/`.
  A **AI Memory Files Only** switch narrows it to the same rule the macOS
  sidebar uses in strict mode.
- **Works offline.** The listing and every document you open are cached and
  read back without a connection; a repo you've opened before never waits on
  the network again. Blobs are keyed by their git SHA, so refreshing only
  downloads what actually changed.
- **Links navigate in place**, with the same rules as the macOS reader:
  relative and `../` paths, root-relative `/docs/guide.md`, `#heading` and
  `file.md#heading`, `[[wiki links]]`, and folder links. Images in a README
  load from GitHub's raw CDN.
- Search a whole repository by filename or path, refresh by pull-to-refresh,
  and open the current file on github.com or share its link.
- **Private repositories** work with a GitHub token added in Settings, stored
  in the device Keychain — never synced, never sent anywhere but api.github.com.
  Public browsing needs no setup; a token also lifts the API limit from 60 to
  5,000 requests an hour. Settings shows how much is cached and can clear it.
- The app reopens where you left off, and `aimemoryreader://repo?owner=…&name=…&path=…&heading=…`
  opens a specific document — the iOS counterpart of the macOS URL scheme.

**Both platforms**

- HTML comments are no longer rendered as visible text. CommonMark passes
  `<!-- … -->` through as raw HTML and the renderer drew it literally, which is
  loud in AI memory files, where comments are notes addressed to agents. They
  now hide, the way every other Markdown surface hides them — except inside a
  fenced block, so a document explaining the syntax still shows it. The file on
  disk is untouched; edit mode still shows the comment.

## v0.5.4 — 2026-08-15

**Links between local files now navigate inside the app.**

- Clicking a link to another file — `[User profile](user_profile.md)`,
  `../CLAUDE.md`, `notes/2026-08-10.md`, an absolute path, a `~/` path — opens
  it in the reader and selects it in the sidebar. Before, it was handed to the
  system, which bounced you out to whatever app owns `.md`.
- `[[wiki links]]` are clickable. Claude's memory files cross-reference each
  other with `[[name]]`, and Obsidian vaults use the same syntax; CommonMark
  renders both as dead brackets. `[[target|label]]` works too. The rewrite is
  display-only — edit mode still shows the file's real text.
- Wiki links resolve even when the slug doesn't match the filename. Claude
  writes `[[user-profile]]` for a file stored as `user_profile.md`; separators
  and case are ignored when matching, and a bare `[[notes]]` finds `notes.md`.
- `#heading` links jump within the file, and `file.md#heading` jumps to a
  heading in another file. Anchors are matched the way GitHub slugifies
  headings, so links written for GitHub land in the right place here.
- **Back** (⌘[) and **Forward** (⌘]) in the View menu, because links that
  navigate in place need a way back. Sidebar clicks and search hits share the
  same history.
- Links to a folder load it in the sidebar. Links to files the reader can't
  display — images, PDFs, source files — still go to the system, as before.
- A link that points at nothing now says so, instead of silently doing nothing.

## v0.5.3 — 2026-08-06

**Fixed the app freezing when you open a file inside a large folder.**

- Opening a file in a folder with many subdirectories — a project root, a
  Downloads folder, anything near `node_modules` — froze the window while AIMR
  walked the directory to fill the sidebar. The walk ran on the main thread, so
  the freeze lasted as long as the scan: on a 200,000-entry folder, about
  **2.6–3.5 seconds** of an unresponsive app. The directory scan now runs off
  the main thread and the UI keeps working throughout; the main thread's share
  of the same scan dropped to **2–3 milliseconds**.
- The same path was used by every tree load, so this also fixes the stall when
  opening a large folder with ⌘O, when toggling "Show All JSON/JSONL Files",
  and — the one most people felt without naming it — on **every filesystem
  change** in a busy source like `~/.claude/projects`, where an agent writing
  session logs triggered a rebuild after each burst of writes.
- Scans are now cancelled when you navigate away, so switching folders no
  longer waits for the previous scan to finish.
- The sidebar shows "Scanning folder…" while a scan is in flight, instead of
  the "No folder opened" empty state, which read as a failure.
- Also fixed a hot-path inefficiency in the same code: whether an entry is a
  directory was being looked up inside the sort comparator, i.e. O(n log n)
  times per directory instead of once per entry.

## v0.5.2 — 2026-07-23

**Opened files and folders now appear in the sidebar's Recent list.**

- The Recent list used to track only folders opened through the Open dialog.
  Now every file you open — double-clicking in Finder, dragging it in, the Open
  dialog, or an `aimemoryreader://` link — and every folder you open lands there
  too, most-recent first. Click any entry to reopen it: files reopen in
  single-file view, folders reload the tree.
- The list keeps the last 10 items and de-duplicates, so revisiting something
  just moves it back to the top. Existing recents (including iCloud-synced
  copies) carry over untouched.

## v0.5.1 — 2026-06-21

**Fixed Chinese / IME input inserting stray line breaks.**

- Typing with a Chinese / Japanese / Korean input method no longer inserts a
  random newline when you press Return to confirm a candidate. Re-applying
  syntax highlighting mid-composition was cancelling the active IME session; the
  editor now leaves text untouched while a composition is in flight and
  reformats once it commits.
- Undo (Ctrl+Z) works correctly again after IME typing.

## v0.5.0 — 2026-06-13

**Signed with an Apple Developer ID and notarized by Apple.**

- Download, unzip, double-click — no more "unidentified developer" / "cannot
  verify" warning, and no need for the right-click-Open or `xattr` workaround
  earlier builds required. Universal binary (Apple Silicon + Intel), macOS 13+.

## v0.4.13 — 2026-06-10

**Fixed "Check for Updates" failing with a hostname error.**

- The v0.4.11 and v0.4.12 GitHub zips were accidentally built with the Mac App
  Store sandbox profile, which has no network permission — so the update
  checker couldn't reach api.github.com and reported "A server with the
  specified hostname could not be found." The GitHub build is now unsandboxed
  again (as it was through v0.4.10), and the release pipeline is codified in
  `scripts/build-release-zip.sh` with a guard that refuses sandboxed output.
- Side benefit: the folder-context feature from v0.4.11/12 no longer needs any
  grant prompt in this build — double-clicking a file shows its folder
  immediately, for any readable folder.

## v0.4.12 — 2026-06-10

**Fixed: folder context now works for folders AIMR couldn't already read.**

- v0.4.11's "double-click opens the folder too" silently did nothing when the
  file's folder wasn't covered by an existing access grant (sandbox rules —
  most personal notes folders). Now AIMR asks once, with the folder
  pre-selected: grant it and the sidebar fills in; pick a parent folder to
  cover more notes at once. Decline and it won't ask again for that folder.
- Grants persist (security-scoped bookmarks), so it's one click per folder,
  ever. Also hardened the opened-file match against path normalization
  differences.

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
