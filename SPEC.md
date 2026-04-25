# iOS 剪贴板历史应用 - 产品技术规格说明

## 1. 项目概述

一个仅供个人使用、通过 TestFlight 分发的 iOS 剪贴板历史应用。参考 macOS 上的 Paste，记录用户复制过的文本内容，方便回溯和重新粘贴。

**项目代号**：`ClipKeep`（暂定，可改）
**分发方式**：TestFlight 内部测试，自用
**最低系统版本**：iOS 16.0
**开发语言/框架**：Swift 5.9+ / SwiftUI

## 2. 目标与非目标

### 2.1 目标

记录用户在 iOS 设备上复制过的文本内容，提供一个可搜索、可置顶、可一键重新粘贴的历史列表。优先满足"找回 5 分钟前复制的那段文字"这个核心场景。

### 2.2 非目标（首版不做）

- 上架 App Store
- iCloud / 跨设备同步
- 图片、文件、富文本格式的剪贴板记录
- 多用户、协作、分享
- 智能分类、AI 摘要
- 复杂的标签系统
- 通用剪贴板（Universal Clipboard）的特殊处理
- 完整的本地化（中英文均支持即可）

## 3. 核心功能

### 3.1 剪贴板捕获

通过两个入口捕获剪贴板内容：

主 App 启动或回到前台时，读取一次 `UIPasteboard.general`，与最近一条对比，不同则入库。自定义键盘扩展被激活时（用户切到这个键盘），同样读取并入库。两个入口写入同一个 App Group 共享存储。

去重逻辑：如果新内容与历史最新一条完全相同（按文本 hash 比较），则不重复添加，仅刷新时间戳。

### 3.2 历史列表

主 App 主界面是一个倒序时间轴列表。每行显示：内容预览（最多 3 行）、复制时间（相对时间，如"5 分钟前"）、字符数。

支持的操作：

- 点击：复制回剪贴板，显示一个 Toast 提示"已复制"
- 长按：弹出菜单（复制 / 收藏 / 删除）
- 左滑：删除
- 右滑：置顶/收藏

### 3.3 搜索

顶部一个搜索框，按内容关键字过滤，实时响应。

### 3.4 收藏区

收藏的条目固定显示在列表顶部，不会被自动清理。普通条目超过 200 条时，按时间倒序保留最新 200 条，旧条目自动删除。

### 3.5 键盘扩展

一个简单的自定义键盘，提供：

- 顶部一行最近 5 条历史的横向滚动
- 下方完整列表，点击即插入到当前输入框
- 一个返回系统键盘的切换按钮
- 一个删除键

不实现完整的字母键盘，键盘扩展只用于快速粘贴历史，输入文字仍切回系统键盘。

### 3.6 设置页

最小化设置：

- 历史最大条数（默认 200，可选 100/200/500/1000）
- 清空所有历史
- 清空非收藏历史
- 关于页（版本号、build 号）

## 4. 技术架构

### 4.1 Target 结构

Xcode 工程包含三个 target：

- **ClipKeep**（主 App）：SwiftUI 应用主体
- **ClipKeepKeyboard**（键盘扩展）：Custom Keyboard Extension
- **ClipKeepCore**（共享 Framework）：数据模型、存储层、共用逻辑

### 4.2 数据共享

通过 App Group `group.com.{yourname}.clipkeep` 在主 App 和键盘扩展之间共享数据。

存储方案：使用 `UserDefaults(suiteName:)` 存储 JSON 编码的历史数组。条目数量在 200-1000 量级，UserDefaults 性能足够，无需引入 Core Data 或 SQLite。

如果未来要支持图片，再迁移到 App Group 容器目录下的 SQLite。

### 4.3 数据模型

```swift
struct ClipItem: Codable, Identifiable, Equatable {
    let id: UUID
    var content: String          // 纯文本内容
    var createdAt: Date          // 首次复制时间
    var updatedAt: Date          // 最近一次重复复制的时间
    var isPinned: Bool           // 是否收藏/置顶
    var contentHash: String      // 用于去重，content 的 SHA256 前 16 位
}
```

存储结构：

```
UserDefaults Key: "clip_items"
Value: [ClipItem] 的 JSON 编码
```

### 4.4 剪贴板读取策略

为了避免触发 iOS 的"已粘贴"横幅提示过于频繁：

- 使用 `UIPasteboard.general.changeCount` 判断剪贴板是否真的变化过，未变化则不读取内容
- 主 App 仅在 `scenePhase` 变为 `.active` 时读取一次
- 键盘扩展在 `viewWillAppear` 时读取一次
- 不做后台轮询

### 4.5 项目目录布局

```
ClipKeep/
├── ClipKeep.xcodeproj
├── ClipKeep/                    # 主 App target
│   ├── ClipKeepApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   │   ├── ClipListView.swift
│   │   ├── ClipRowView.swift
│   │   ├── SearchBar.swift
│   │   └── SettingsView.swift
│   ├── ViewModels/
│   │   └── ClipListViewModel.swift
│   └── Assets.xcassets
├── ClipKeepKeyboard/            # 键盘扩展 target
│   ├── KeyboardViewController.swift
│   ├── KeyboardView.swift
│   └── Info.plist
├── ClipKeepCore/                # 共享 Framework
│   ├── Models/
│   │   └── ClipItem.swift
│   ├── Storage/
│   │   ├── ClipStore.swift
│   │   └── AppGroup.swift
│   └── Pasteboard/
│       └── PasteboardReader.swift
├── SPEC.md
└── CLAUDE.md
```

## 5. 主要流程

### 5.1 首次启动

App 启动 → 检查是否首次启动 → 显示极简引导（一屏，说明键盘开启步骤） → 进入主界面 → 读取剪贴板。

### 5.2 复制后查看历史

用户在其他 App 复制文本 → 切回 ClipKeep → `scenePhase` 变 `.active` → 读取剪贴板 → 入库 → 刷新列表 → 用户看到最新条目在顶部。

### 5.3 键盘粘贴

用户在任意输入框 → 切到 ClipKeep 键盘 → 看到历史列表 → 点击某条 → `textDocumentProxy.insertText(item.content)` → 内容插入。

### 5.4 重新复制

用户在主 App 列表 → 点击某条 → `UIPasteboard.general.string = item.content` → Toast 提示 → 用户切回目标 App 粘贴。

## 6. UI 设计要点

整体风格：原生 SwiftUI，跟随系统深色/浅色模式，不做自定义主题。

主界面：`NavigationStack` + `List`，顶部 `searchable` 修饰器提供搜索，工具栏右侧一个齿轮图标进入设置。

列表行：内容预览用 `lineLimit(3)` + `truncationMode(.tail)`，时间用 `RelativeDateTimeFormatter`。收藏的条目左侧加一个填充的星形图标。

键盘扩展：高度约 270pt（与系统键盘一致），背景跟随 `UIInputViewController` 的 traitCollection，顶部一个分隔条，下方滚动列表。

## 7. 开发阶段

### 阶段 1：核心可用（目标 1-2 个周末）

Xcode 工程搭建、App Group 配置、ClipKeepCore 数据模型与存储、主 App 列表展示与读取剪贴板、点击复制回剪贴板。能在 Xcode 真机调试下使用。

### 阶段 2：键盘扩展（目标 1 个周末）

实现 ClipKeepKeyboard target、键盘 UI、点击插入文本、与主 App 共享数据验证。

### 阶段 3：完善功能（目标 1 个周末）

搜索、收藏置顶、删除、设置页、最大条数限制、首次启动引导。

### 阶段 4：上 TestFlight（目标半天）

配置 Apple Developer 账号、证书、上传 build 到 App Store Connect、配置内部测试组、自己加为 tester 安装。

## 8. 已知限制与权衡

- iOS 14+ 读剪贴板会有"已粘贴"横幅，无法消除，仅靠 `changeCount` 减少触发次数
- 键盘扩展需要用户手动开启"允许完全访问"，否则无法读剪贴板
- TestFlight build 90 天过期，需周期性重新上传
- `UIPasteboard` 拿不到来源 App，只能记录"什么时候被复制进剪贴板"
- 不处理来自密码管理器的敏感内容（首版不做过滤，自用场景风险可接受）

## 9. 后续可能的扩展

按优先级从高到低：iCloud 同步（CloudKit）、图片支持、Today/锁屏 Widget、Share Extension、Shortcuts 集成、URL Scheme 快速添加、内容标签分组。这些都不在首版范围内。
