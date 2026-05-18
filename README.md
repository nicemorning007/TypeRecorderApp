# TypeRecorder

TypeRecorder 是一个 macOS 原生键盘输入记录 App。它不依赖后端服务，也不依赖外部数据库，核心能力全部在本机完成：监听键盘事件、写入本地文件、计算统计结果，并用 SwiftUI 和 SceneKit 展示输入习惯。

当前版本的功能边界已经重新调整为“本机记录 + 本机统计 + 本机可视化”。旧版兼容 HTTP 服务不再作为当前功能的一部分，主流程只围绕 App 内部的键盘监听器、存储层和界面快照展开。

## 当前功能

### 全局键盘记录

App 在获得 macOS 辅助功能或输入监控权限后，可以记录全局键盘事件。记录启动后，即使窗口失焦、最小化或只保留菜单栏入口，记录仍会继续。

记录内容包括：

- 事件 ID
- 事件时间
- 日期
- macOS keyCode
- 标准化按键名
- 可显示字符
- 距离上一次有效按键的间隔毫秒数
- 当前 App 会话 ID
- 字符类型

为了减少高频按键回调对系统输入体验的影响，记录线程只处理按键本身，不在每次按键时同步查询当前应用、窗口标题或输入法。数据模型中仍保留 `application`、`windowTitle`、`inputMethod` 字段，后续如果要扩展上下文统计，可以在低干扰方案成熟后继续接入。

### 权限自动刷新

键盘记录权限由 `KeyboardMonitor` 统一处理。当前实现会同时识别两类权限通路：

- 辅助功能：`AXIsProcessTrusted()`
- 输入监听：`CGPreflightListenEventAccess()`

用户点击“请求全局记录权限”后，App 会先静默刷新当前权限状态。如果已经授权，界面会立即更新；如果没有授权，App 会触发系统授权提示，并跳转到系统设置的相关隐私页面。

授权流程启动后，App 会短时间轮询权限状态，并监听 `NSApplication.didBecomeActiveNotification`。用户从系统设置切回 TypeRecorder 后，界面会主动刷新授权状态，正常情况下不需要重启 App。

### 统计总览

总览页展示当前统计口径下的核心数据：

- 按键次数：当前口径内记录到的全部按键事件数。
- 有效输入：总字符数减去删除键次数后的估算值。
- 总字符：当前实现中所有记录事件都会作为字符统计来源。
- 删除次数：`Backspace` 和 `Delete` 的次数。
- 最近输入：按全局事件 ID 倒序展示最近输入。
- 紧凑键盘热力图：快速查看高频按键。

### 用户称号等级体系

总览页左侧会根据“今日按键次数”展示当天称号和徽章。称号只按当天累计按键数命中区间计算，不展示下一等级门槛，保留一点探索感。

| 等级 | 今日按键次数 | 称号 | 展示文案 |
| --- | ---: | --- | --- |
| 1 | 0 | 今日挂机中 | 键盘：我今天放假？ |
| 2 | 1+ | 轻点两下 | 手指已上线，状态待热身 |
| 3 | 500+ | 摸鱼打字员 | 看起来在忙，其实刚开始 |
| 4 | 1,000+ | 办公室敲击者 | 今天已经有点声音了 |
| 5 | 3,000+ | 文档搬砖人 | 字不是自己出来的 |
| 6 | 6,000+ | 键盘冒烟选手 | 今日输出量有点东西 |
| 7 | 10,000+ | 指尖永动机 | 停不下来，根本停不下来 |
| 8 | 40,000+ | 人形输入法 | 想法刚出现，字已经到了 |
| 9 | 70,000+ | 键盘破坏者 | 今天的键盘承受了太多 |

### 二维键盘热力图

二维热力图按照 Mac 键盘布局渲染按键。每个按键会根据使用次数改变颜色深浅，并在键帽内显示次数。

热力图下方的频率统计表会展示：

- 按键显示名
- 字符类型
- 使用次数
- 最近使用时间

### 3D 键盘热力图

3D 热力图使用 SceneKit 绘制键盘柱状图：

- 每个按键对应一个柱体。
- 柱体越高，表示当前统计口径内使用次数越多。
- 颜色从低频的蓝绿色过渡到高频的橙红色。
- 没有数据的按键也保留低矮底座，保证键盘轮廓完整。
- 支持拖拽旋转、滚轮缩放、触控板缩放和重置视图。

### 事件明细

事件明细页展示最近 250 条输入记录，当前列包括：

- 时间
- 按键
- 编码

这部分用于核对记录链路是否正常，也方便观察按键标准化后的展示结果。

### 设置和数据管理

设置页提供：

- 启用或停止键盘记录。
- 请求全局记录权限。
- 查看权限状态、启动状态和错误信息。
- 开启或关闭“每日 0 时自动重置统计”。
- 清除今日数据。
- 清除历史所有数据。

“每日 0 时自动重置统计”只影响统计口径，不会删除历史文件。开启后界面默认只统计今日数据；关闭后界面合并全部历史数据展示累计结果。每天 0 点后，App 会自动刷新一次当前统计快照，让今日统计自然切换到新日期。

### 菜单栏入口

App 提供 `MenuBarExtra` 菜单栏入口。菜单栏中可以查看当前记录状态、当前统计口径下的按键数，并快速执行开始记录、停止记录和刷新统计。

## 实现路线

TypeRecorder 的主链路如下：

```text
macOS NSEvent
    ↓
KeyboardMonitor
    ↓
KeyboardEventProcessor
    ↓
KeystrokeCapture
    ↓
AppModel.recordQueue
    ↓
DatabaseStore
    ↓
AppSnapshot
    ↓
SwiftUI / SceneKit
```

### 1. App 状态中心

`AppModel` 是整个 App 的状态中心，负责连接键盘监听、存储层和界面。

启动时它会完成：

- 读取“每日 0 时自动重置统计”设置。
- 初始化 `DatabaseStore`，加载本地历史事件和会话。
- 初始化 `KeyboardMonitor`，接收按键捕获结果。
- 建立 `recordQueue`，保证所有记录写入串行执行。
- 监听 `KeyboardMonitor.objectWillChange`，把内部监听器状态转发给外层 SwiftUI 页面。
- 创建 0 点边界定时器，按统计口径刷新界面。

`KeyboardMonitor` 本身也是 `ObservableObject`，但页面主要观察的是 `AppModel`。因此当前版本专门用 Combine 转发监听器状态变化，避免启动、停止、授权状态已经变化但界面不立即刷新的问题。

### 2. 键盘监听

键盘监听在 `KeyboardMonitor` 中实现。它使用两类 `NSEvent` monitor：

- `addGlobalMonitorForEvents`：记录其他 App 中的按键。
- `addLocalMonitorForEvents`：记录 TypeRecorder 自己窗口内的按键。

监听的事件类型包括：

- `keyDown`
- `flagsChanged`

普通字符键主要通过 `keyDown` 进入记录链路。Command、Shift、Control、Option、fn、Caps Lock 等修饰键通常通过 `flagsChanged` 表达状态变化，所以必须额外监听。

这里没有使用 `CGEventTap` 拦截系统输入。TypeRecorder 只做记录，不阻止、不修改、不重放键盘事件，`NSEvent` monitor 更符合低干扰记录需求。

### 3. 修饰键去重

修饰键不能简单地把每一次 `flagsChanged` 都记成一次按键，否则按下和松开都会被计数。

当前规则是：

- Caps Lock 每次状态切换都记录一次。
- Shift、Command、Control、Option、fn 只记录按下阶段。
- 松开阶段只更新内部按下状态，不写入记录。
- 已经处于按下集合中的修饰键不会重复计数。
- 停止记录时会清空修饰键状态，避免下次启动继承旧状态。

这套逻辑在 `KeyboardEventProcessor.shouldRecord(...)` 中完成。

### 4. 按键标准化

系统事件进入处理器后，会被转换成 `KeyboardEventPayload`，再转换成统一的 `KeystrokeCapture`。

`KeyCodeLookup` 负责把 macOS keyCode 转成稳定按键名，例如：

- `Key.backspace`
- `Key.delete`
- `Key.enter`
- `Key.tab`
- `Key.space`
- `Key.cmd`
- `Key.shift`
- `Key.ctrl`
- `Key.alt`
- `Key.fn`
- `Key.caps_lock`
- `Key.up`
- `Key.down`
- `Key.left`
- `Key.right`
- `Key.f1` 到 `Key.f12`

界面展示时再通过 `KeyNameMapper` 转成人类可读名称，例如 `Key.backspace` 展示为 `Delete`，`Key.cmd` 展示为 `Command`，方向键展示为箭头。

字符类型由 `CharacterClassifier` 计算，分为：

- 中文
- 英文
- 数字
- 空格
- 标点
- 功能键

### 5. 串行写入

按键监听和事件处理都可能发生在不同队列上，但真正写入存储前会统一进入 `AppModel.recordQueue`。

这样做有三个目的：

- 保证写入顺序和真实按键顺序一致。
- 避免并发写文件导致数据竞争。
- 让刷新和清空也能排队执行，确保它们发生在已排队按键写入之后。

刷新统计时，`AppModel` 会把快照读取动作也排进 `recordQueue`。清空数据时，清空动作同样进入 `recordQueue`。因此用户看到的统计不会跳过已经进入队列的按键，也不会在清空后又冒出旧事件。

## 存储设计

数据全部保存在当前用户目录：

```text
~/Library/Application Support/TypeRecorder
```

目录结构：

```text
TypeRecorder/
  sessions.json
  events/
    2026-05-15.jsonl
    2026-05-16.jsonl
```

### 事件存储

按键事件按日期写入 `events/yyyy-MM-dd.jsonl`。每条事件是一个 JSON 对象，适合持续追加。

写入策略是“先写内存，再批量落盘”：

- 每次按键先加入内存缓存。
- UI 统计直接读取内存缓存，所以不需要每个按键都同步写磁盘。
- 待写事件达到 200 条时批量刷盘。
- 距离上次刷盘超过 10 秒时批量刷盘。
- 快照刷新、对象释放或强制持久化时会立即刷盘。

这能降低高频输入时的磁盘写入压力，同时保持界面统计及时更新。

### 会话存储

每次 App 启动会创建一个新的 `sessionID`，并维护当前会话数据：

- 开始时间
- 结束时间
- 持续时长
- 总按键数
- 总字符数
- Backspace 次数
- Delete 次数

会话文件是 `sessions.json`。它采用节流写入：

- 强制刷新时写入。
- 累计 50 次变更后写入。
- 距离上次写入超过 3 秒后写入。

### 历史加载

App 启动时会读取 `events` 目录下所有 `.jsonl` 文件，按日期构建内存缓存，并从历史最大事件 ID 后继续递增。

最近事件排序使用存储层全局递增的 `id`，不使用进程内 `sequence`。因为 `sequence` 每次启动都会从 1 开始，如果用它混排历史数据，新输入可能被旧记录压住。

## 统计逻辑

`DatabaseStore.snapshot(scope:)` 会把存储数据聚合成 `AppSnapshot`。

### 统计口径

当前有两种口径：

- 今日数据：只统计当天事件和当天会话。
- 累计数据：合并所有日期的事件和会话。

每日重置开关只控制口径，不删除数据。

### 实时统计

实时统计包括：

- `keystrokesCount`：事件总数。
- `charactersCount`：可打印事件数。
- `deletedCount`：删除键事件数。
- `validInputCount`：`charactersCount - deletedCount`，最低为 0。
- `startedAt`：当前会话开始时间。

### 频率统计

频率统计使用 `frequencyKey` 聚合：

- 有 `keyCharacter` 时按字符聚合。
- 没有 `keyCharacter` 时按 `keyName` 聚合。
- 次数高的排在前面。
- 次数相同时按展示名排序。
- 快照默认最多返回 300 项。

二维热力图、3D 热力图和频率统计表复用同一份频率数据。

## 文件说明

```text
Sources/TypeRecorder/TypeRecorderApp.swift
```

App 入口，创建主窗口、菜单栏入口和全局 `AppModel`。

```text
Sources/TypeRecorder/AppActivationDelegate.swift
```

处理 macOS App 激活策略，保证 Xcode 直接运行时窗口可以正常前置。

```text
Sources/TypeRecorder/AppModel.swift
```

应用状态中心，负责监听器、存储层、统计快照、状态转发、每日刷新和数据清理。

```text
Sources/TypeRecorder/KeyboardMonitor.swift
```

处理权限申请、权限自动刷新、全局/本地事件监听、修饰键去重和按键捕获。

```text
Sources/TypeRecorder/DatabaseStore.swift
```

负责本地事件存储、JSONL 批量写入、会话持久化、历史加载、统计聚合和清空数据。

```text
Sources/TypeRecorder/Models.swift
```

定义路由、事件模型、统计模型、字符分类、按键展示名映射和日期格式化工具。

```text
Sources/TypeRecorder/RootView.swift
```

实现总览、二维热力图、3D 热力图、事件明细、设置页和通用 UI 组件。

```text
Scripts/package_app.sh
Scripts/package_dmg.sh
Scripts/sign_app.sh
```

负责 release 构建、`.app` 打包、`.dmg` 打包和代码签名。

## 编译和运行

### 环境要求

- macOS 26 或更高版本。
- Swift 6.3 或更高版本。
- 支持 macOS 26 SDK 的 Xcode。

### SwiftPM 编译

```bash
swift build
```

### SwiftPM 运行

```bash
swift run TypeRecorder
```

### Xcode 调试

推荐用 Xcode 工程调试，这样运行目标是稳定 Bundle ID 的 `.app`：

```text
TypeRecorder.xcodeproj
```

打开后选择 Scheme `TypeRecorder`，运行目标选择 `My Mac`，然后 `Cmd + R`。

## 打包

### 打包 `.app`

```bash
chmod +x Scripts/package_app.sh Scripts/sign_app.sh
Scripts/package_app.sh
```

产物：

```text
dist/TypeRecorder.app
```

### 打包 `.dmg`

```bash
chmod +x Scripts/package_dmg.sh Scripts/sign_app.sh
Scripts/package_dmg.sh
```

产物：

```text
dist/TypeRecorder.app
dist/TypeRecorder.dmg
```

### 签名说明

辅助功能和输入监控授权会绑定 App 的代码签名身份。为了让升级版本尽量复用已有授权，`Scripts/sign_app.sh` 会按下面优先级选择签名身份：

1. 使用 `TYPE_RECORDER_CODESIGN_IDENTITY` 指定的证书。
2. 使用本机钥匙串中第一个可用的代码签名证书。
3. 没有证书时退回 ad-hoc 签名。

ad-hoc 签名适合本机测试，但升级后可能需要重新授权辅助功能或输入监控。正式分发时建议使用稳定证书：

```bash
TYPE_RECORDER_CODESIGN_IDENTITY="Developer ID Application: ..." Scripts/package_dmg.sh
```

## 权限说明

首次记录其他 App 的输入时，需要在系统设置中授予 TypeRecorder 全局记录相关权限。常见路径是：

```text
系统设置 -> 隐私与安全性 -> 辅助功能
系统设置 -> 隐私与安全性 -> 输入监控
```

未授权时，App 仍能打开界面、查看历史数据、清空数据和操作设置，但不会记录其他 App 的全局按键。

## 隐私和数据边界

TypeRecorder 当前只把数据写入本机用户目录，不会主动上传到远程服务器。当前功能不需要启动后端服务，也不暴露本地 HTTP 接口。

需要明确的是，键盘记录类 App 具有敏感性：

- App 会记录按键名和可显示字符。
- 数据保存在 `~/Library/Application Support/TypeRecorder`。
- 清空数据会删除对应范围内的本机事件文件和会话统计。
- 如果未来扩展应用名、窗口标题、输入法或同步能力，需要单独评估隐私提示和记录线程性能。
