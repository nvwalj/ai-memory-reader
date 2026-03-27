# AI Memory Reader

一款原生 macOS & iOS 应用，用于浏览、阅读和编辑 AI 代理的记忆文件 —— 渲染美观，随时可用。

![AI Memory Reader](home.png)

## 功能特性

### 阅读
- **精美 Markdown 渲染** — GitHub 风格，支持代码块、表格、列表等（基于 MarkdownUI）
- **自动发现 AI 源** — 自动检测 OpenClaw、Claude Code、Codex、Gemini、Continue、Cursor、Aider、GitHub Copilot 等 AI 工具目录
- **Today 面板** — 自动高亮今天的记忆文件
- **文件树导航** — 侧边栏可展开的文件目录
- **目录大纲** — 右侧 TOC 面板，点击跳转对应标题
- **深色 / 浅色主题** — 跟随系统外观
- **文件监听** — 文件变化时自动刷新
- **全文搜索** — 搜索当前目录下所有文件

### 编辑
- **编辑模式** — ⌘E 切换阅读/编辑
- **语法高亮** — 标题、粗体、斜体、代码块、链接
- **行号显示** — 内置行号标尺
- **自动保存** — 停止输入 2 秒后自动保存
- **手动保存** — ⌘S，带 "已保存" 视觉提示

### AI 工具集成
- **URL Scheme** — `aimemoryreader://open?path=/path/to/file.md&heading=标题`
- **命令行** — `aimr open /path/to/file.md --heading "标题"`
- 让 AI 代理直接打开并跳转到指定文件和标题

### 自定义源
- **"+" 按钮添加** — 在侧边栏点击 "+" 添加任意文件夹
- **持久化** — 自定义源保存在本地，下次启动自动加载
- **右键删除** — 右键自定义源可移除

### 跨平台
- **macOS** — 完整功能：侧边栏、目录大纲、编辑模式
- **iPhone** — 只读模式，原生导航，支持从文件 App 打开

## 支持的 AI 源

| AI 源 | 目录 | 关键文件 |
|-------|------|---------|
| OpenClaw | `~/.openclaw/workspace/` | MEMORY.md, SOUL.md, AGENTS.md, memory/*.md |
| Claude Code | `~/.claude/` | CLAUDE.md |
| Codex | `~/.codex/` | AGENTS.md, instructions.md |
| Gemini | `~/.gemini/` | GEMINI.md |
| Continue | `~/.continue/` | config.md |
| Cursor | `~/.cursor/` | rules |
| Aider | `~/.aider/` | 配置文件 |
| GitHub Copilot | `~/.config/github-copilot/` | 配置文件 |

仅显示本机上实际存在且包含 .md 文件的目录。也支持手动打开任意本地文件夹或单个 .md 文件。

## 安装

1. 克隆仓库：
   ```bash
   git clone https://github.com/nvwalj/ai-memory-reader.git
   cd ai-memory-reader
   ```

2. 生成 Xcode 项目（需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)）：
   ```bash
   xcodegen generate
   ```

3. 打开 Xcode：
   ```bash
   open AIMemoryReader.xcodeproj
   ```

4. 编译运行（⌘R）

### 命令行工具（可选）

将 `aimr` 脚本复制到 PATH：
```bash
cp aimr /usr/local/bin/
chmod +x /usr/local/bin/aimr
```

使用：
```bash
aimr open ~/.openclaw/workspace/MEMORY.md
aimr open ~/.openclaw/workspace/MEMORY.md --heading "关于我"
```

### 系统要求

- macOS 15.0+ / iOS 17.0+
- Xcode 16.0+
- Swift 6.0

## 技术栈

- **界面：** SwiftUI（Mac 用 NavigationSplitView，iPhone 用 NavigationStack）
- **Markdown：** [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)（GitHub 主题）
- **编辑器：** NSTextView + 自定义语法高亮
- **状态管理：** @Observable 宏
- **文件监听：** FSEvents
- **项目管理：** XcodeGen + SPM

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| ⌘O | 打开文件或文件夹 |
| ⌘E | 切换编辑/阅读模式 |
| ⌘S | 保存（编辑模式下） |
| ⌘F | 聚焦搜索 |
| ⌘1 | 切换到 OpenClaw 源 |
| ⌘2 | 打开本地文件 |

## 许可证

[GPL-3.0](LICENSE)
