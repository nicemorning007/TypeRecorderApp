import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

@MainActor
final class KeyboardMonitor: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var permissionGranted = KeyboardMonitor.hasKeyboardMonitoringAccess()
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var permissionRefreshToken: UUID?
    private var permissionRefreshStartedAt: Date?
    private let eventProcessor: KeyboardEventProcessor
    private let onCapture: @Sendable (KeystrokeCapture) -> Void

    init(onCapture: @escaping @Sendable (KeystrokeCapture) -> Void) {
        self.onCapture = onCapture
        eventProcessor = KeyboardEventProcessor(onCapture: onCapture)
        super.init()
        observeApplicationActivation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestPermission() {
        // 先做一次静默刷新：如果用户已经在系统设置里授权，按钮点击后应该立刻更新界面，
        // 不需要再弹系统提示或跳转设置页。
        if refreshPermissionState() {
            return
        }

        // NSEvent 的全局键盘记录依赖“辅助功能”信任。这里优先触发系统授权提示；
        // 如果系统因为已有列表项而不再弹窗，后续仍会打开隐私设置页并轮询最新状态。
        if requestAccessibilityAccess() || refreshPermissionState() {
            return
        }

        statusMessage = "已打开系统设置，请允许 TypeRecorder。授权后会自动刷新，不需要重启 App"
        openKeyboardPermissionSettings()
        startPermissionRefreshTimer()
    }

    @discardableResult
    func refreshPermissionState() -> Bool {
        let granted = Self.hasKeyboardMonitoringAccess()
        permissionGranted = granted
        if granted {
            lastError = nil
            statusMessage = "键盘全局记录权限已授权"
            stopPermissionRefreshTimer()
        }
        return granted
    }

    func start() {
        guard !isRunning, !isStarting else { return }

        // 先发布“启动中”，再把实际启动动作延后一轮主队列执行。
        // 这样权限检查或事件监听创建偏慢时，用户点击按钮后也能立刻看到 loading 动画。
        isStarting = true
        lastError = nil
        statusMessage = nil

        DispatchQueue.main.async { [weak self] in
            self?.performStart()
        }
    }

    private func performStart() {
        guard isStarting, !isRunning else { return }

        guard canStartWithCachedPermission() else {
            isStarting = false
            lastError = "需要在系统设置中授予辅助功能或输入监控权限。授权后会自动刷新，不需要重启 App"
            openKeyboardPermissionSettings()
            startPermissionRefreshTimer()
            return
        }

        eventProcessor.resetModifierState()

        // 这里只需要记录，不需要拦截或修改系统事件。
        // NSEvent monitor 不在系统事件分发链路上阻塞输入，比 CGEventTap 更适合低干扰记录。
        // 普通字符键会产生 keyDown；Command/Shift/Control/Option/fn/Caps Lock 这类修饰键
        // 在 macOS 里通常只产生 flagsChanged。组合键要把每个物理按键都统计进去，所以两类事件都监听。
        let monitoredEvents: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: monitoredEvents) { [eventProcessor] event in
            eventProcessor.enqueue(KeyboardEventPayload(event: event))
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: monitoredEvents) { [eventProcessor] event in
            eventProcessor.enqueue(KeyboardEventPayload(event: event))
            return event
        }

        guard globalMonitor != nil else {
            isStarting = false
            lastError = "全局键盘记录创建失败，请确认 TypeRecorder 已加入辅助功能或输入监控并重新启动"
            return
        }

        isStarting = false
        isRunning = true
        permissionGranted = true
        statusMessage = "记录已启动，窗口失焦、最小化或关闭后仍会继续记录"
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        eventProcessor.resetModifierState()
        publish {
            self.isStarting = false
            self.isRunning = false
            self.statusMessage = "记录已停止"
        }
    }

    private static func hasKeyboardMonitoringAccess() -> Bool {
        // 官方文档里 NSEvent 全局键盘事件依赖辅助功能信任；新系统还提供了
        // ListenEvent/Input Monitoring API。任一条通路可用时，都允许启动全局记录。
        AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }

    private func canStartWithCachedPermission() -> Bool {
        // 权限已经确认通过时，启动记录不再重复调用系统权限探测 API。
        // AXIsProcessTrusted/CGPreflightListenEventAccess 在部分机器上会卡主线程，
        // 之前一次启动会连续查三次，按钮看起来就像“服务启动很慢”。
        // 如果缓存状态是未授权，仍然现场查一次，保证用户刚在系统设置里授权后可以立即启动。
        if permissionGranted {
            return true
        }

        let granted = Self.hasKeyboardMonitoringAccess()
        permissionGranted = granted
        if granted {
            stopPermissionRefreshTimer()
        }
        return granted
    }

    private func requestAccessibilityAccess() -> Bool {
        // kAXTrustedCheckOptionPrompt 在 Swift 6 严格并发下会被视为共享可变全局变量。
        // 这里使用系统定义的稳定 key 字符串，效果等同于该常量。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func openKeyboardPermissionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Keyboard"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }

    private func observeApplicationActivation() {
        // 用户通常会在“系统设置”里完成授权后直接切回 TypeRecorder。
        // 监听 App 回到前台可以第一时间刷新 TCC 状态，避免“已经授权但界面还显示未授权”。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        _ = refreshPermissionState()
    }

    private func startPermissionRefreshTimer() {
        stopPermissionRefreshTimer()

        let token = UUID()
        permissionRefreshToken = token
        permissionRefreshStartedAt = Date()
        scheduleNextPermissionRefresh(token: token)
    }

    private func stopPermissionRefreshTimer() {
        permissionRefreshToken = nil
        permissionRefreshStartedAt = nil
    }

    private func scheduleNextPermissionRefresh(token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else {
                return
            }

            // 如果用户再次点击请求授权，旧 token 会失效，旧轮询回调直接退出。
            guard self.permissionRefreshToken == token else {
                return
            }

            // 授权写入 TCC 数据库和 App 可读到新状态之间可能有短暂延迟。
            // 这里在用户授权流程期间主动轮询，成功后立刻停表，避免长期占用资源。
            if self.refreshPermissionState() {
                return
            }

            if let startedAt = self.permissionRefreshStartedAt,
               Date().timeIntervalSince(startedAt) > 120 {
                self.stopPermissionRefreshTimer()
                self.statusMessage = "仍未检测到授权。请确认 TypeRecorder 已在辅助功能或输入监控中开启"
                return
            }

            self.scheduleNextPermissionRefresh(token: token)
        }
    }

    private func publish(_ changes: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            changes()
        }
    }
}

private enum KeyboardEventKind: Sendable {
    case keyDown
    case flagsChanged
}

private struct KeyboardEventPayload: Sendable {
    let timestamp: Date
    let kind: KeyboardEventKind
    let keyCode: UInt16
    let keyName: String
    let keyCharacter: String?
    let isModifierActive: Bool

    init(event: NSEvent) {
        timestamp = Date()
        kind = event.type == .flagsChanged ? .flagsChanged : .keyDown
        keyCode = event.keyCode
        keyName = KeyCodeLookup.keyName(for: event)
        keyCharacter = KeyCodeLookup.character(for: event)
        isModifierActive = KeyCodeLookup.isModifierActive(for: event)
    }
}

private final class KeyboardEventProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TypeRecorder.KeyboardEventProcessor", qos: .userInitiated)
    private let onCapture: @Sendable (KeystrokeCapture) -> Void
    private var lastEventTime: Date?
    private var nextSequence: Int64 = 1
    private var pressedModifierKeyCodes = Set<UInt16>()
    private var lastCapsLockIsActive: Bool?
    private var isWaitingForCapsLockRelease = false

    init(onCapture: @escaping @Sendable (KeystrokeCapture) -> Void) {
        self.onCapture = onCapture
    }

    func enqueue(_ payload: KeyboardEventPayload) {
        queue.async { [weak self] in
            self?.process(payload)
        }
    }

    func resetModifierState() {
        queue.async { [weak self] in
            // 停止后重新开始记录时，不能继承上一轮修饰键状态。
            // Caps Lock 有单独的按压配对状态，也需要一起清空，否则新一轮第一次按键可能被误判为重复事件。
            self?.pressedModifierKeyCodes.removeAll()
            self?.lastCapsLockIsActive = nil
            self?.isWaitingForCapsLockRelease = false
        }
    }

    private func process(_ payload: KeyboardEventPayload) {
        guard shouldRecord(payload) else {
            return
        }

        let interval = lastEventTime.map { max(0, Int(payload.timestamp.timeIntervalSince($0) * 1000)) }
        lastEventTime = payload.timestamp

        let sequence = nextSequence
        nextSequence += 1

        // 记录线程只记录按键本身，不再查询额外系统上下文。
        // 这些系统查询会明显增加全局输入记录的开销，导致打字和系统动画卡顿。
        onCapture(
            KeystrokeCapture(
                sequence: sequence,
                timestamp: payload.timestamp,
                keyCode: Int(payload.keyCode),
                keyName: payload.keyName,
                keyCharacter: payload.keyCharacter,
                intervalMilliseconds: interval
            )
        )
    }

    private func shouldRecord(_ payload: KeyboardEventPayload) -> Bool {
        switch payload.kind {
        case .keyDown:
            return true

        case .flagsChanged:
            guard KeyCodeLookup.isModifierKeyCode(payload.keyCode) else {
                return false
            }

            // Caps Lock 的 flagsChanged 表示锁定状态切换，不像 Shift/Command 那样有稳定的“按下/松开”配对。
            // 一些键盘/系统版本会在一次物理按压里发出多条 flagsChanged。这里走 Caps Lock 专用去重：
            // - Caps Lock 作为大写锁定使用时，锁定状态变化代表一次真实按压；
            // - Caps Lock 作为输入法切换键使用时，锁定状态可能完全不变，所以不能只看 .capsLock；
            // - 遇到同状态的下一条 Caps Lock 事件时，把它当作同一次物理按压的释放/重复事件吞掉。
            if payload.keyName == "Key.caps_lock" {
                return shouldRecordCapsLock(payload)
            }

            // 其他修饰键在按下和松开时都会发 flagsChanged。这里只记录按下阶段：
            // - 当前 flags 已包含该键，说明这是按下或从未同步过的按住状态；
            // - pressedModifierKeyCodes 已存在时不再重复计数，避免长按或系统重复事件把一次按下算多次；
            // - 当前 flags 不包含该键时只更新内部状态，不写入按键记录。
            if payload.isModifierActive {
                return pressedModifierKeyCodes.insert(payload.keyCode).inserted
            }

            pressedModifierKeyCodes.remove(payload.keyCode)
            return false
        }
    }

    private func shouldRecordCapsLock(_ payload: KeyboardEventPayload) -> Bool {
        defer {
            lastCapsLockIsActive = payload.isModifierActive
        }

        if let lastCapsLockIsActive, lastCapsLockIsActive != payload.isModifierActive {
            // 大写锁定状态发生变化时，说明这是一次新的 Caps Lock 物理按压。
            // 先标记等待释放，下一条同状态事件如果只是释放阶段，就不会被重复记录。
            isWaitingForCapsLockRelease = true
            return true
        }

        if isWaitingForCapsLockRelease {
            isWaitingForCapsLockRelease = false
            return false
        }

        // 输入法切换场景下，Caps Lock 事件可能不会改变 .capsLock 状态。
        // 此时按“记录一条、吞掉下一条同状态事件”的方式，把按下/释放配对成一次按键。
        isWaitingForCapsLockRelease = true
        return true
    }
}

enum KeyCodeLookup {
    private static let specialNames: [UInt16: String] = [
        36: "Key.enter",
        48: "Key.tab",
        49: "Key.space",
        51: "Key.backspace",
        53: "Key.esc",
        54: "Key.cmd_r",
        55: "Key.cmd",
        56: "Key.shift",
        57: "Key.caps_lock",
        58: "Key.alt",
        59: "Key.ctrl",
        60: "Key.shift_r",
        61: "Key.alt_r",
        62: "Key.ctrl_r",
        63: "Key.fn",
        115: "Key.home",
        116: "Key.page_up",
        117: "Key.delete",
        119: "Key.end",
        121: "Key.page_down",
        123: "Key.left",
        124: "Key.right",
        125: "Key.down",
        126: "Key.up"
    ]

    private static let functionNames: [UInt16: String] = [
        122: "Key.f1",
        120: "Key.f2",
        99: "Key.f3",
        118: "Key.f4",
        96: "Key.f5",
        97: "Key.f6",
        98: "Key.f7",
        100: "Key.f8",
        101: "Key.f9",
        109: "Key.f10",
        103: "Key.f11",
        111: "Key.f12"
    ]

    static func keyName(for event: NSEvent) -> String {
        let keyCode = event.keyCode
        if let functionName = functionNames[keyCode] {
            return functionName
        }
        if let specialName = specialNames[keyCode] {
            return specialName
        }
        if let character = event.charactersIgnoringModifiers, !character.isEmpty {
            return character.lowercased()
        }
        return "Key.vk_\(keyCode)"
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    static func isModifierActive(for event: NSEvent) -> Bool {
        switch event.keyCode {
        case 54, 55:
            return event.modifierFlags.contains(.command)
        case 56, 60:
            return event.modifierFlags.contains(.shift)
        case 58, 61:
            return event.modifierFlags.contains(.option)
        case 59, 62:
            return event.modifierFlags.contains(.control)
        case 57:
            return event.modifierFlags.contains(.capsLock)
        case 63:
            return event.modifierFlags.contains(.function)
        default:
            return false
        }
    }

    static func character(for event: NSEvent) -> String? {
        let keyCode = event.keyCode
        if specialNames[keyCode] != nil || functionNames[keyCode] != nil {
            return nil
        }
        guard let text = event.characters, !text.isEmpty else {
            return nil
        }
        if text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return event.charactersIgnoringModifiers?.lowercased()
        }
        return text
    }
}
