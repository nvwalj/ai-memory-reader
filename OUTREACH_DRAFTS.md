# Outreach drafts — newsletter pitches for AIMR

Drop-in copy for nvwalj@gmail.com to send. Both newsletters have no submission form; pitching is by email.

---

## Email 1 — Console.dev

**To:** hello@console.dev
**Subject:** Submission: AI Memory Reader — native macOS viewer for CLAUDE.md / AGENTS.md files

Hi Console team,

I built **AI Memory Reader**, a native macOS app for browsing the CLAUDE.md, AGENTS.md, and AI-agent memory files that Claude Code, Codex, Cursor, Gemini, Continue, Copilot, Aider, and OpenClaw write across your projects. It's open source (GPL-3.0), free, and 3 MB.

Why I think it fits your criteria:

- **Primary user is a developer.** Anyone using Claude Code, Codex, or Cursor daily ends up with a `~/.claude/projects/` directory full of memory files. AIMR is the only native pane-of-glass for them.
- **Self-service.** Just download. No signup, no account, no cloud. Open source.
- **Part of the regular dev cycle.** AI coding assistants are writing memory files constantly. AIMR refreshes live as Claude writes.
- **Power-user features.** GitHub-style markdown, ⌘F find with character highlighting, ⌘E inline edit, JSON/JSONL viewer for Claude session telemetry, URL scheme + `aimr` CLI + Claude Code `/aimr` slash command, dark mode.
- **Quality.** Swift + SwiftUI, no Electron. Universal binary. Recently passed an internal security audit (privacy manifest shipped, zero network calls).
- **Active.** v0.4.2 shipped two days ago (May 17, 2026). v0.4.0 → v0.4.2 in one day after addressing audit feedback.
- **Pre-1.0** — currently 0.4.2, which fits your beta/preview criteria.

Links:
- Repo + README: https://github.com/nvwalj/ai-memory-reader
- Landing page: https://nvwalj.github.io/ai-memory-reader/
- Latest release: https://github.com/nvwalj/ai-memory-reader/releases/tag/v0.4.2
- Screenshot: https://github.com/nvwalj/ai-memory-reader/blob/main/home.png

Happy to answer anything. Thanks for considering.

— nvwalj

---

## Email 2 — TLDR Dev (Newsletter)

**To:** dan@tldrnewsletter.com
**Subject:** Devtool submission — AI Memory Reader (native macOS viewer for Claude/Codex/Cursor memory files)

Hi Dan,

Quick tool pitch for TLDR Dev: **AI Memory Reader** — a 3 MB native macOS app for browsing CLAUDE.md, AGENTS.md, and AI-agent memory files. It's the only native viewer that handles all 8 popular agents (Claude Code, Codex, Cursor, Gemini, Continue, Copilot, Aider, OpenClaw) in one place, plus pretty-prints Claude's NDJSON session telemetry.

Why now: AI coding assistants are writing structured memory files into every project, and most devs are opening them one at a time in TextEdit. AIMR auto-discovers them, watches for live writes, and renders GitHub-style markdown.

Free, open source, no telemetry, no signup. Pre-1.0 (v0.4.2). Built in Swift + SwiftUI.

- Repo: https://github.com/nvwalj/ai-memory-reader
- Landing: https://nvwalj.github.io/ai-memory-reader/
- Screenshot: https://github.com/nvwalj/ai-memory-reader/blob/main/home.png

Happy to send a 30-second screen recording if useful.

Thanks,
nvwalj

---

## How to send

1. Open https://mail.google.com (already in tab 1).
2. Compose → paste subject + body → send to recipient above.
3. Repeat for email 2. Different recipient, different subject.

Both newsletters routinely feature small open-source dev tools. Expected lead time to publication if accepted: 1–3 weeks. A single Console.dev or TLDR Dev mention typically drives 1k–10k visits.
