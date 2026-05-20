# Product Hunt launch kit — AI Memory Reader

Ready-to-paste copy + a launch-day playbook. Product Hunt is free and a top-3 Product-of-the-Day can drive 10k–50k visits in 24 hours.

## When to launch

- **Best:** Tuesday or Wednesday, 12:01am PT (peak voting window opens at midnight PT)
- **Avoid:** Mondays (too crowded — fresh week), Fridays (low traffic), holidays
- **Today:** Monday May 18 — launch **Tuesday May 19 at 12:01 AM PT** is ideal. If user prefers more prep, push to Wednesday May 20.

## Required fields

### Name
```
AI Memory Reader
```

### Tagline (60 chars max — currently 57)
```
The native macOS viewer for CLAUDE.md and AGENTS.md files
```

Alternates:
- `Read every CLAUDE.md your AI agents write — natively, fast` (56)
- `Native macOS reader for AI agent memory files` (45)

### Description (260 chars max — currently 246)
```
A 3 MB native macOS app for browsing every CLAUDE.md, AGENTS.md, and AI-agent memory file your Claude Code, Codex, Cursor, Gemini, Continue, Copilot, Aider, or OpenClaw assistants write. GitHub-style markdown, live file watching, ⌘F find, ⌘E edit. Free + GPL.
```

### Topics (pick up to 4 from PH's list)
- Developer Tools
- macOS
- Open Source
- Artificial Intelligence

### Links
- **Website:** https://nvwalj.github.io/ai-memory-reader/
- **Get it:** https://github.com/nvwalj/ai-memory-reader/releases/latest

## Gallery (1270 × 760 — needs user to capture)

5 screenshots to take with the app open on user's Mac:

1. **Hero shot:** main window — sidebar with `~/.claude/projects/` expanded, a CLAUDE.md rendered on the right
2. **Edit mode:** ⌘E pressed, showing line numbers + the markdown source-edit syntax highlighting
3. **JSON viewer:** open a `~/.claude/projects/*.jsonl` file — show the pretty-printed session telemetry
4. **Today panel:** with a `memory/2026-05-18.md` highlighted
5. **Dark mode:** the hero shot but with system in dark mode

Capture command (run on user's Mac with AIMR open):
```bash
mkdir -p ~/Desktop/aimr-ph-shots
for i in 1 2 3 4 5; do
  echo "Position the app for shot $i, then press Enter"
  read
  screencapture -i ~/Desktop/aimr-ph-shots/shot-$i.png
done
```

Resize each to 1270×760 before uploading.

## Maker's first comment (paste right after publishing)

```
Hi everyone — I built AI Memory Reader because I use Claude Code daily and was tired of opening CLAUDE.md, AGENTS.md, and per-day memory files in TextEdit one at a time.

It auto-discovers memory directories for 8 popular AI agents (Claude Code, Codex, Cursor, Gemini, Continue, Copilot, Aider, OpenClaw), renders everything in GitHub-style markdown, and refreshes live when an agent writes a new entry.

A few features I'm most happy with:
• ⌘F in-page find with real character-level highlighting (not just "scroll to nearest")
• ⌘E to drop into edit mode with markdown syntax highlighting; auto-saves 2 seconds after the last keystroke
• Built-in JSONL viewer for Claude Code's ~/.claude/projects/*.jsonl session telemetry — chunked rendering so multi-MB transcripts don't stall
• URL scheme + aimr CLI shell script + companion /aimr slash command for Claude Code

Native Swift + SwiftUI, 3 MB universal binary, zero network calls, GPL-3.0. iPhone companion app coming via the same App Store ID.

Happy to answer anything — and if you find a bug, I'm fast on GitHub issues.
```

## Launch-day playbook

### Pre-launch (T -24h)

- [ ] Capture 5 screenshots (see above), resize to 1270×760
- [ ] Cold-DM 5–10 people in your network who'd plausibly upvote in the first hour — give them the PH URL the moment it goes live (NOT before — PH detects coordinated launches and demotes them)
- [ ] Schedule a Tweet for 12:01am PT linking the PH page

### T 0 (12:01 AM PT — minutes 0–60 are critical)

- [ ] Submit the product on Product Hunt
- [ ] Immediately post the Maker's comment (above)
- [ ] Tweet the PH link from @nvwalj
- [ ] Notify your prepared supporter list — "PH is live, link is X"
- [ ] Post in any Slack/Discord communities you're already in (Claude users, indie hackers)

### T +1h to T +6h

- [ ] Reply to every comment quickly (lateness penalizes ranking)
- [ ] Cross-post to:
  - r/ClaudeAI ("I made a native viewer for your CLAUDE.md files — Product Hunt today")
  - r/MacApps
  - HackerNews **only if not already submitted in the past 7 days** (cooldown rule)

### T +24h

- [ ] Final upvote push if you're close to top-5 for the day
- [ ] Final tweet with stats / thanks
- [ ] If you placed top-5: add the badge to README and landing page

## Realistic outcomes

- **Top 1 Product of the Day:** ~50k visits, ~1k stars, ~500 newsletter signups, gear up for a ~$300 Ko-fi day if you have a tip button
- **Top 5 Product of the Day:** ~10–15k visits, ~200 stars, ~50 signups
- **Top 10:** ~3k visits, ~50 stars
- **Below top 20:** ~1k visits, low conversion. Most launches end here.

The deciding factor is the first-hour velocity. Get 10 upvotes in the first 60 minutes and you're in the running. Get 30 upvotes and you're likely top-10.

## Things to NOT do (PH-killers)

- Do **NOT** ask people to "upvote me on PH" with the link before launch — PH's ranking algo penalizes vote-rigging detection
- Do **NOT** edit the product page after launch (it resets your timeline)
- Do **NOT** create new PH accounts just to upvote — instant ban + delisting
