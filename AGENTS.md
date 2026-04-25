# AGENTS.md

这个文件给 AI 编码助手（如 Codex）提供项目上下文。在这个仓库里写代码时，请先读这份文档。

## 项目背景

iOS 剪贴板历史应用，**仅供个人 TestFlight 自用**，不上架 App Store。参考 macOS 上的 Paste 应用。

完整产品规格见 `SPEC.md`。本文件只记录开发时的技术约定和坑。

## 技术栈

- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI（iOS 16+）
- **最低系统**：iOS 16.0
- **存储**：`UserDefaults(suiteName:)` + Codable JSON
- **依赖管理**：纯 SPM，不引入第三方库
- **构建工具**：Xcode 15+

## Target 结构

工程包含三个 target，**任何代码改动都要先想清楚属于哪个 target**：

| Target | 角色 | Bundle ID |
|---|---|---|
| `ClipKeep` | 主 App | `com.{yourname}.clipkeep` |
| `ClipKeepKeyboard` | 自定义键盘扩展 | `com.{yourname}.clipkeep.keyboard` |
| `ClipKeepCore` | 共享 Framework，被前两者引用 | `com.{yourname}.clipkeep.core` |

数据模型、存储层、剪贴板读取这类共用逻辑必须放在 `ClipKeepCore`。主 App 和键盘扩展只放各自的 UI 和入口逻辑。

## App Group 配置（关键）

主 App 与键盘扩展通过 App Group `group.com.{yourname}.clipkeep` 共享数据。

需要在以下三处都启用并选中同一个 App Group：

1. Apple Developer 后台的 App Group 注册
2. 主 App target 的 Signing & Capabilities → App Groups
3. 键盘扩展 target 的 Signing & Capabilities → App Groups

代码里**禁止**使用 `UserDefaults.standard`，必须用：

```swift
UserDefaults(suiteName: "group.com.{yourname}.clipkeep")
```

封装在 `ClipKeepCore/Storage/AppGroup.swift` 里，统一通过这个入口访问。

## iOS 平台关键约束

下面这些是反直觉但必须遵守的限制，写代码时容易踩：

**剪贴板读取会触发系统横幅**。iOS 14+ 每次读 `UIPasteboard.general.string` 都可能弹"已粘贴"提示。务必先检查 `changeCount`，未变化则不读 `string`。

**App 在后台无法访问剪贴板**。不要尝试用 BGTaskScheduler、定时器、推送等方式后台轮询，徒劳且会被系统杀。

**键盘扩展默认无法读剪贴板**。键盘扩展的 Info.plist 必须设置：

```xml
<key>NSExtensionAttributes</key>
<dict>
    <key>RequestsOpenAccess</key>
    <true/>
</dict>
```

并且用户要在系统设置里手动打开"允许完全访问"。

**键盘扩展内存限制严格**（约 48MB），不要在键盘里加载大量历史或图片。建议只展示最近 50 条。

**键盘扩展不能调用某些 API**，例如打开 URL、访问相机相册等。用 `UIApplication.shared` 之前要确认是否在扩展环境。

## 编码规范

**SwiftUI 优先**，能用 SwiftUI 实现的不用 UIKit。键盘扩展的 `UIInputViewController` 是 UIKit，但内部 UI 用 `UIHostingController` 嵌入 SwiftUI。

**View Model 用 `@Observable` 宏**（iOS 17+ 的方案），避免 `ObservableObject` 的样板代码。如果坚持 iOS 16 兼容，则用 `ObservableObject` + `@Published`。

**模型 struct 而非 class**，所有数据模型实现 `Codable` + `Identifiable` + `Equatable`。

**异步用 async/await**，不写新的 Combine 代码（订阅 `scenePhase` 等 SwiftUI 内置除外）。

**不要 force unwrap**（`!`），除了 `IBOutlet` 这种历史包袱（本项目应该没有）。用 `guard let` 或 `if let`。

**注释写"为什么"而不是"做什么"**。代码本身能说明做什么，注释解释取舍和坑。

## 常用命令

工程根目录在 `/Users/samxiao/ios_paste/`。

构建主 App（命令行）：

```bash
xcodebuild -project ClipKeep.xcodeproj \
  -scheme ClipKeep \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

跑单元测试：

```bash
xcodebuild test -project ClipKeep.xcodeproj \
  -scheme ClipKeep \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

archive 上 TestFlight（推荐用 Xcode GUI：Product → Archive → Distribute App → App Store Connect → Upload）。也可用 fastlane，但首版不引入。

## 容易出错的地方

**Bundle ID 必须配对**。键盘扩展的 Bundle ID 必须以主 App 的 Bundle ID 为前缀，例如 `com.foo.clipkeep.keyboard`，否则无法关联。

**键盘扩展的 deployment target** 要与主 App 一致或更低，否则上传会被拒。

**Info.plist 里 `NSExtensionPointIdentifier`** 必须是 `com.apple.keyboard-service`，不要改成别的。

**TestFlight build 号每次上传必须递增**。即便版本号没变，build 号（`CFBundleVersion`）必须 +1。

**App Group 改名后要清数据**。开发期间如果改了 App Group 标识符，旧数据无法读取，要么重装 App，要么写迁移逻辑（自用场景直接重装即可）。

**键盘扩展的预览**在 Xcode SwiftUI Preview 里很难跑起来，建议直接真机调试，选 ClipKeepKeyboard scheme 后选择宿主 App（Settings 或 Notes）。

## 测试约定

单元测试主要覆盖 `ClipKeepCore` 的：

- `ClipStore` 的增删改查、去重、容量限制
- `PasteboardReader` 的 `changeCount` 判断逻辑（用 mock）
- `ClipItem` 的 Codable 编解码

UI 测试不做（自用场景成本不划算）。

## 保密与安全

App Group 名称、Bundle ID 里的 `{yourname}` 部分根据自己的 Apple Developer 团队 ID 替换。**不要把团队 ID 提交到公开仓库**。

剪贴板内容可能含敏感信息（密码、token），存储时**不加密**（自用场景，设备本身已加密）。但不要把历史数据通过日志、网络请求等方式外传。这个 App 不应该有任何网络请求。

## 给 AI 助手的额外提示

- 改任何 `Info.plist`、`entitlements`、签名相关的配置时，先在回复里说明改动意图，不要静默改
- 写键盘扩展代码时，如果用到 `UIApplication`，先确认这个 API 在扩展环境是否可用
- 添加新依赖前先问一下，本项目尽量保持零依赖
- 涉及 App Group 路径、Bundle ID、Team ID 的代码，用占位符 `{yourname}` 写注释提醒，不要硬编码具体值
- 任务完成后，跑一次 `xcodebuild build` 验证编译通过
