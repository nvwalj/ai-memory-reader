# Mac App Store metadata for AI Memory Reader

Drop-in copy for App Store Connect when the time comes to submit.

## Basics

- **App name:** AI Memory Reader
- **Subtitle (max 30 chars):** Native viewer for CLAUDE.md
- **Bundle ID:** `com.aitools.ai-memory-reader`
- **Primary category:** Developer Tools
- **Secondary category:** Productivity
- **Age rating:** 4+ (no objectionable content)
- **Price:** Free, or $4.99 one-time (decide before submission)
- **Pricing tier (if paid):** Tier 5 ($4.99)

## Promotional text (170 chars — shown at top of listing, can be updated without re-review)

> Browse and edit the CLAUDE.md, AGENTS.md, and AI-agent memory files scattered across your home directory. GitHub-style markdown, file watching, JSON viewer.

## Description (4000 chars max)

```
AI Memory Reader is the native macOS app for browsing every CLAUDE.md, AGENTS.md, and AI-agent memory file your AI coding assistants have written across your projects — beautifully rendered, instantly searchable, fast.

Built for engineers who use Claude Code, Codex, Cursor, Gemini, Continue, GitHub Copilot, Aider, or OpenClaw daily — and who are tired of opening these files in TextEdit one at a time.

KEY FEATURES

• Auto-discovery — Detects memory directories for 8 popular AI agents (Claude Code, Codex, Cursor, Gemini, Continue, GitHub Copilot, Aider, OpenClaw) and any custom folder you add.

• GitHub-style markdown — Powered by MarkdownUI. Code blocks, tables, lists, blockquotes, all rendered exactly like you see them on GitHub.

• Live file watching — When Claude (or any agent) writes a new memory entry, the app refreshes instantly. No reload button.

• Edit mode — Press ⌘E to switch from reading to editing. Syntax highlighting for headers, bold, italic, code, links. Auto-saves 2 seconds after the last keystroke, or ⌘S to save now.

• In-page find — ⌘F. Real character-level highlighting, not just "scroll to nearest match."

• Today panel — Highlights today's `memory/YYYY-MM-DD.md` if present, for projects that log per-day notes.

• JSON / JSONL viewer — Pretty-prints Claude Code's `~/.claude/projects/*.json` NDJSON session telemetry. Chunked rendering so multi-MB transcripts don't crash anything.

• URL scheme + CLI — Other tools can open files in AI Memory Reader via `aimemoryreader://open?path=…&heading=…` or the `aimr` CLI shell script. A companion Claude Code plugin ships the `/aimr` slash command.

• Dark and light themes — Follows the system appearance.

• Native — Built in Swift + SwiftUI. No Electron, no web view. 3 MB universal binary (Apple Silicon + Intel).

WHO THIS IS FOR

• Engineers who already use Claude Code daily and want a single pane of glass for all their CLAUDE.md files
• Tech leads rolling out memory conventions across a team
• Anyone curious what Claude has been writing about their projects in the background

WHAT IT WON'T DO

• Talk to your AI agents directly — this is a *viewer*, not a chat client
• Sync over iCloud — file watching is local only
• Convert memory files between agent formats — pull requests welcome on GitHub

The macOS app pairs with a free iPhone reader on the same App Store.
```

## Keywords (100 chars total, comma-separated)

```
claude,claude code,codex,cursor,gemini,markdown,memory,ai agent,llm,viewer
```

## What's New (release notes — first submission)

```
First release on the App Store. AI Memory Reader has been on GitHub for several months as version 0.4.2; this is the same code, sandboxed for the App Store. See LICENSING.md in the repo for details.
```

## URLs

- **Marketing URL:** https://nvwalj.github.io/ai-memory-reader/
- **Support URL:** https://github.com/nvwalj/ai-memory-reader/issues
- **Privacy policy URL:** https://nvwalj.github.io/ai-memory-reader/privacy.html (write this before submission — see below)

## Privacy policy (must be at the URL above before submission)

Single page covering:
- App is local-only
- Reads files in user-selected folders (sandbox)
- Persists folder bookmarks and theme preference in UserDefaults
- Optional iCloud KVStore sync for app settings (no document content)
- No analytics, no telemetry, no third-party SDKs
- No network calls
- No data collection of any kind

## App Privacy ("Nutrition label") answers in App Store Connect

- Data collected: **None**
- Data linked to user: **None**
- Tracking: **No**

## Screenshots (required: at least one set; recommended: 5 at 2560×1600)

1. Main window with sidebar + markdown preview (the existing `home.png` works, but at MAS resolution)
2. Edit mode with line numbers
3. Today panel highlighted
4. JSON viewer rendering a Claude session telemetry file
5. Dark mode of (1)

App Store automatically generates the iPhone screenshots from the App Preview videos, or you can supply separately.

## Review notes (private to Apple App Review)

```
Hello reviewer,

This app reads markdown and JSON files from user-selected folders. It has no network access, no telemetry, no third-party SDKs.

It has been distributed as a GitHub release under GPL-3.0 since [date] (currently v0.4.2 as of this submission). The source code submitted here is identical to the public repository: https://github.com/nvwalj/ai-memory-reader. See LICENSING.md in the repo for the dual-license arrangement.

To test:
1. Launch the app.
2. ⌘O to open a folder containing markdown or JSON files. Any folder works — for a quick test, point it at the macOS Documentation folder or any project's docs directory.
3. Click a .md file in the sidebar to see it rendered. ⌘E to enter edit mode.

No login required. No paywall. No in-app purchases.

Thank you for reviewing.
```

## Code changes still needed before submission

- [ ] Replace auto-detection of `~/.claude/`, `~/.codex/` etc. with a first-launch onboarding that asks for folder access via NSOpenPanel and persists security-scoped bookmarks. (Sandbox forbids direct home-directory access without user grant.)
- [ ] Persist the bookmark data in UserDefaults, restore it on launch.
- [ ] Add a "Grant access" affordance in the sidebar empty state.
- [ ] Generate 5 App Store screenshots at 2560×1600.
- [ ] Write `privacy.html` and publish to the GitHub Pages site.
- [ ] Cut a fresh build with the sandbox entitlements active and the privacy manifest bundled (verify with `codesign --display --entitlements - /path/to/AI\ Memory\ Reader.app`).
- [ ] Test that the app runs cleanly inside the sandbox (some FileManager calls may fail silently — exercise every code path).
