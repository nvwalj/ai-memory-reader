# AI Memory Reader

[中文文档](README_CN.md)

A native macOS & iOS app for browsing, reading, and editing AI agent memory files — beautifully rendered, instantly accessible.

![AI Memory Reader](home.png)

## Features

### Reading
- **Beautiful Markdown Rendering** — GitHub-style with code blocks, tables, lists, and more (powered by MarkdownUI)
- **Auto-Discover AI Sources** — Automatically detects OpenClaw memory directories
- **Today Panel** — Highlights today's memory file for quick access
- **File Tree Navigation** — Browse markdown files with an expandable sidebar
- **Table of Contents** — Right sidebar TOC with click-to-jump navigation
- **Dark & Light Themes** — Follows system appearance
- **File Watching** — Auto-refreshes when files change on disk
- **Full-Text Search** — Search across all files in the current directory

### Editing
- **Edit Mode** — Toggle between reading and editing with ⌘E
- **Syntax Highlighting** — Headers, bold, italic, code blocks, links
- **Line Numbers** — Built-in line number ruler
- **Auto-Save** — Saves automatically after 2 seconds of inactivity
- **Manual Save** — ⌘S with visual "Saved" confirmation

### AI Tool Integration
- **URL Scheme** — `aimemoryreader://open?path=/path/to/file.md&heading=Heading`
- **CLI** — `aimr open /path/to/file.md --heading "Title"`
- Let AI agents open and navigate to specific files and headings

### Cross-Platform
- **macOS** — Full-featured with sidebar, TOC, edit mode
- **iPhone** — Read-only with native navigation and Files app integration

## Supported AI Sources

| AI Source | Directory | Key Files |
|-----------|-----------|-----------|
| OpenClaw | `~/.openclaw/workspace/` | MEMORY.md, SOUL.md, AGENTS.md, memory/*.md |

Also supports opening any local folder or individual .md file.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nvwalj/ai-memory-reader.git
   cd ai-memory-reader
   ```

2. Generate the Xcode project (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)):
   ```bash
   xcodegen generate
   ```

3. Open in Xcode:
   ```bash
   open AIMemoryReader.xcodeproj
   ```

4. Build and run (⌘R)

### CLI Setup (optional)

Copy the `aimr` script to your PATH:
```bash
cp aimr /usr/local/bin/
chmod +x /usr/local/bin/aimr
```

Then use:
```bash
aimr open ~/.openclaw/workspace/MEMORY.md
aimr open ~/.openclaw/workspace/MEMORY.md --heading "About Me"
```

### Requirements

- macOS 15.0+ / iOS 17.0+
- Xcode 16.0+
- Swift 6.0

## Tech Stack

- **UI:** SwiftUI (NavigationSplitView on Mac, NavigationStack on iPhone)
- **Markdown:** [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) (GitHub theme)
- **Editor:** NSTextView with custom syntax highlighting
- **State:** @Observable macro
- **File Watching:** FSEvents
- **Project:** XcodeGen + SPM

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open file or folder |
| ⌘E | Toggle edit/read mode |
| ⌘S | Save (in edit mode) |
| ⌘F | Focus search |
| ⌘1 | Switch to OpenClaw source |
| ⌘2 | Open local files |

## License

MIT
