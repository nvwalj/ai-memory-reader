# AI Memory Reader — V3 Plan

## V3 范围

### V3.1: 导出 PDF
- 当前查看的 .md 文件可以导出为 PDF
- ⌘P 或菜单 File → Export PDF
- 保持 Markdown 渲染样式（标题、代码块、表格等）
- 支持选择保存路径
- 实现方式：用 NSHostingView 渲染 MarkdownUI 视图 → ImageRenderer 或 NSPrintOperation 生成 PDF

### V3.2: iCloud 设置同步
- 用 NSUbiquitousKeyValueStore 同步应用设置：
  - 最近打开的文件夹列表
  - 自定义 AI 源路径
  - 上次选中的源 ID
  - 上次选中的文件路径
- 不同步 .md 文件本身
- 无 iCloud 时降级到本地 UserDefaults

### V3.3: iPhone 真机验证 + 打磨
- 在 iPhone 模拟器/真机上验证 V2.2 的 iOS 代码
- 修复可能存在的布局/适配问题
- 确保 Files app 打开 .md 正常

## 里程碑

| 阶段 | 内容 | 预估 |
|---|---|---|
| V3.1 | 导出 PDF | 半天 |
| V3.2 | iCloud 设置同步 | 半天 |
| V3.3 | iPhone 验证打磨 | 半天 |

## 备注
- 表格斑马纹已在 V2 中实现（MarkdownUI .alternatingRows）
- MCP Server 暂不做
- 多窗口暂不做
- .md 文件同步不做（应由 AI 工具本身管理）

## 开发日志

### 2026-03-27 — V3 Plan 确认
- V3.1 导出 PDF + V3.2 iCloud 设置同步 + V3.3 iPhone 验证

### 2026-03-27 — V3.1 Export PDF ✅
- 新增 PDFExporter.swift（macOS only）
  - 用 NSHostingView + NSPrintOperation 渲染 MarkdownUI 视图为分页 PDF
  - NSSavePanel 让用户选择保存路径，默认文件名与 .md 同名
  - 强制 light mode，US Letter 纸张，40pt 边距
- 新增 ⌘P 快捷键和 File → Export PDF… 菜单项
- 通过 Notification (.exportPDF) 从菜单传递到 DetailView
- macOS build 验证通过

### 2026-03-27 — V3.2 iCloud Settings Sync ✅
- 新增 SettingsStore.swift — 封装 NSUbiquitousKeyValueStore + UserDefaults
  - iCloud 优先读取，不可用时降级到 UserDefaults
  - 双写：同时写入 iCloud 和 UserDefaults
  - 监听 didChangeExternallyNotification 实现 iCloud → local 同步
  - 首次启动自动迁移已有 UserDefaults 数据到 iCloud
- 替换了 AppState 和 AISource 中所有直接使用 UserDefaults 的地方：
  - recentFolders
  - customAISourcePaths
  - lastSelectedSourceID
  - lastLocalFolderPath
- 创建了 entitlements 文件（macOS + iOS），含 ubiquity-kvstore-identifier
  - 未在 build settings 中启用（需要 code signing），entitlements 文件随代码提供
  - 配置好 signing 后添加 CODE_SIGN_ENTITLEMENTS 即可
- Sendable 安全：SettingsStore 标记为 @unchecked Sendable
- macOS build 验证通过

### 2026-03-27 — V3.3 iPhone Verification ✅
- iOS Simulator build (iphonesimulator arm64) 编译通过，零错误
- iPhone 16e 模拟器上安装并启动成功
- 空状态 UI 显示正常：大标题、空状态提示、文件夹按钮都正确布局
- 无编译错误，无明显布局问题
- SettingsStore、PDFExporter 的 #if os(macOS) 正确隔离，iOS 端无影响

### V3 完成 🎉
