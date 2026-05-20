# Show HN — cctrack draft

Ready-to-submit at https://news.ycombinator.com/submit

---

**Title (80 char max — fits in 72):**
```
Show HN: Cctrack – See your Claude Code USD spend per project
```

**URL:**
```
https://github.com/nvwalj/claude-cost-tracker
```

**Text (optional — paste in the "text" field for richer post):**
```
I run Claude Code daily and couldn't see where the money was going — `claude --usage` only gives one global number. Claude Code already writes detailed NDJSON session telemetry to ~/.claude/projects/*.jsonl. cctrack is a single-file Python script that walks those files, totals input / output / cache-read / cache-write tokens per project (or per day, or per project-and-day), multiplies by Anthropic's published prices, and prints a table or JSON.

Sample:

    PROJECT                          COST USD   IN     OUT       CACHE-R    CACHE-W
    ~/Project/ai-memory-reader       $41.23   2,141  1,367,884  23,912,663  2,185,484
    ~/Project/mill                    $7.13      56     18,382   1,342,271    124,719
    TOTAL                            $49.16

Tested on my own data (one heavy week was $1,739; a normal month is closer to $400). MIT, single file, no API calls — reads only local files.

I built it because I was paying a lot for Sonnet/Opus and wanted to know which projects deserved the spend. Feedback welcome on the price tables (Anthropic doesn't publish prices in a parseable form, so I hand-coded the Claude 4.x rates).
```

---

## How to submit

1. Open https://news.ycombinator.com/submit
2. Verify you're logged in as `nvwalj`
3. Paste title, URL, and text
4. Submit
5. Within 1 minute: post a *substantive* first comment (your own perspective) — boosts ranking
6. Add the resulting HN URL to README.md badges section: `[![Show HN](https://img.shields.io/badge/Show%20HN-discuss-orange)](URL)`

## Timing tip

HN traffic peaks 9–11am PT (current time is 8:23am PT — submit now and it's prime). Sunday is the slowest day; weekdays are best. Today is Monday May 18 — good submit window.

## Why this works better than the AIMR HN attempt

Previous AIMR HN post got 3 points / 0 comments — AIMR is a niche-audience tool (Claude Code users only). cctrack solves a broader pain ("how much am I spending on Claude") that resonates with everyone burning tokens, including OpenAI/Gemini-curious devs. The dollar-figure framing is HN catnip.
