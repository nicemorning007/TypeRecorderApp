import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot = AppSnapshot()
    @Published var selectedRoute: SidebarRoute? = .dashboard
    @Published var selectedDate = Date()
    @Published var lastStorageError: String?
    @Published var isDailyResetEnabled: Bool
    @Published var excludesFunctionalKeysFromStatistics: Bool
    @Published var includesEscapeReturnDeleteInStatistics: Bool
    @Published var hidesDockIcon: Bool
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var launchAtLoginStatusMessage: String?
    @Published private(set) var launchAtLoginLastError: String?
    @Published private(set) var isMonitoringRunning = false
    @Published private(set) var isMonitoringStarting = false
    @Published private(set) var isKeyboardPermissionGranted = false
    @Published private(set) var monitorStatusMessage: String?
    @Published private(set) var monitorLastError: String?

    let store: DatabaseStore
    let monitor: KeyboardMonitor

    private let recordQueue = DispatchQueue(label: "TypeRecorder.RecordQueue", qos: .utility)
    private var dailyBoundaryTimer: Timer?
    private var monitorStateSubscription: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppSettingsKeys.dailyResetEnabled) == nil {
            isDailyResetEnabled = true
            defaults.set(true, forKey: AppSettingsKeys.dailyResetEnabled)
        } else {
            isDailyResetEnabled = defaults.bool(forKey: AppSettingsKeys.dailyResetEnabled)
        }
        excludesFunctionalKeysFromStatistics = defaults.bool(forKey: AppSettingsKeys.excludesFunctionalKeysFromStatistics)
        includesEscapeReturnDeleteInStatistics = defaults.bool(forKey: AppSettingsKeys.includesEscapeReturnDeleteInStatistics)
        hidesDockIcon = defaults.bool(forKey: AppSettingsKeys.hidesDockIcon)
        launchesAtLogin = Self.isLaunchAtLoginEnabled()

        let createdStore: DatabaseStore
        do {
            createdStore = try DatabaseStore()
        } catch {
            fatalError("TypeRecorder 数据库初始化失败：\(error.localizedDescription)")
        }
        store = createdStore

        monitor = KeyboardMonitor { [createdStore, recordQueue] capture in
            // 按键事件必须串行写入：并发后台任务会让完成顺序和真实按键顺序不一致。
            recordQueue.async {
                do {
                    try createdStore.record(capture)
                } catch {
                    NSLog("TypeRecorder 记录按键失败：\(error.localizedDescription)")
                }
            }
        }

        observeMonitorStateChanges()
        syncMonitorState()
        scheduleDailyBoundaryRefresh()
    }

    var databasePath: String {
        store.path
    }

    var sessionID: String {
        snapshot.realtime.sessionID.isEmpty ? "未创建" : snapshot.realtime.sessionID
    }

    func startMonitoring() {
        // SwiftUI 的 Toggle/Button 可能正在 view update 中调用这里。
        // 延迟到下一轮主队列，避免同步发布 @Published 触发未定义行为警告。
        DispatchQueue.main.async { [weak self] in
            self?.monitor.start()
        }
    }

    func stopMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.monitor.stop()
        }
    }

    func requestKeyboardPermission() {
        DispatchQueue.main.async { [weak self] in
            self?.monitor.requestPermission()
        }
    }

    func refresh() async {
        do {
            let latestSnapshot = try await snapshotAfterPendingRecords()
            publish {
                if self.snapshot != latestSnapshot {
                    self.snapshot = latestSnapshot
                }
                self.lastStorageError = nil
            }
        } catch {
            publish {
                self.lastStorageError = error.localizedDescription
            }
        }
    }

    private func snapshotAfterPendingRecords() async throws -> AppSnapshot {
        let scope = currentStatisticsScope
        let filter = currentStatisticsFilter
        return try await withCheckedThrowingContinuation { continuation in
            // 刷新也排到记录队列里执行，保证它一定发生在已排队的按键写入之后。
            recordQueue.async { [store, scope, filter] in
                do {
                    continuation.resume(returning: try store.snapshot(scope: scope, filter: filter))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func refreshWhenShown() {
        Task {
            await refresh()
        }
    }

    func setDailyResetEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: AppSettingsKeys.dailyResetEnabled)
        publish {
            self.isDailyResetEnabled = isEnabled
        }
        Task {
            await refresh()
        }
    }

    func setExcludesFunctionalKeysFromStatistics(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: AppSettingsKeys.excludesFunctionalKeysFromStatistics)
        publish {
            self.excludesFunctionalKeysFromStatistics = isEnabled
        }
        Task {
            await refresh()
        }
    }

    func setIncludesEscapeReturnDeleteInStatistics(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: AppSettingsKeys.includesEscapeReturnDeleteInStatistics)
        publish {
            self.includesEscapeReturnDeleteInStatistics = isEnabled
        }
        Task {
            await refresh()
        }
    }

    func setHidesDockIcon(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: AppSettingsKeys.hidesDockIcon)
        NotificationCenter.default.post(
            name: .typeRecorderHideDockIconPreferenceDidChange,
            object: nil,
            userInfo: ["isEnabled": isEnabled]
        )
        publish {
            self.hidesDockIcon = isEnabled
        }
    }

    func refreshLaunchAtLoginStatus() {
        // 系统设置里的“登录时打开”状态可能被用户在 App 外部修改。
        // 每次设置页显示时重新读取系统状态，避免 Toggle 显示旧值。
        publish {
            self.launchesAtLogin = Self.isLaunchAtLoginEnabled()
            self.launchAtLoginStatusMessage = Self.launchAtLoginStatusDescription()
        }
    }

    func setLaunchesAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                // SMAppService.mainApp 会把当前 App 注册到 macOS 登录项。
                // 这是 macOS 13 之后推荐的主 App 自启动方式，不需要额外的 Helper App。
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            publish {
                self.launchesAtLogin = Self.isLaunchAtLoginEnabled()
                self.launchAtLoginStatusMessage = Self.launchAtLoginStatusDescription()
                self.launchAtLoginLastError = nil
            }
        } catch {
            publish {
                self.launchesAtLogin = Self.isLaunchAtLoginEnabled()
                self.launchAtLoginStatusMessage = Self.launchAtLoginStatusDescription()
                self.launchAtLoginLastError = "开机自启动设置失败：\(error.localizedDescription)"
            }
        }
    }

    func clearData(_ scope: DataClearScope) async {
        do {
            let latestSnapshot = try await clearDataAfterPendingRecords(scope)
            publish {
                self.snapshot = latestSnapshot
                self.lastStorageError = nil
            }
        } catch {
            publish {
                self.lastStorageError = error.localizedDescription
            }
        }
    }

    var statisticsScopeTitle: String {
        isDailyResetEnabled ? "今日数据" : "累计数据"
    }

    private var currentStatisticsScope: StatisticsScope {
        isDailyResetEnabled ? .today : .allDates
    }

    private var currentStatisticsFilter: StatisticsFilter {
        StatisticsFilter(
            excludesFunctionalKeys: excludesFunctionalKeysFromStatistics,
            includesEscapeReturnDelete: includesEscapeReturnDeleteInStatistics
        )
    }

    private func clearDataAfterPendingRecords(_ clearScope: DataClearScope) async throws -> AppSnapshot {
        let statsScope = currentStatisticsScope
        let filter = currentStatisticsFilter
        return try await withCheckedThrowingContinuation { continuation in
            // 清空动作也进入记录队列，保证用户点击前已经排队的按键先写入，再被本次清空处理掉。
            recordQueue.async { [store, clearScope, statsScope, filter] in
                do {
                    try store.clearData(clearScope)
                    continuation.resume(returning: try store.snapshot(scope: statsScope, filter: filter))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func publish(_ changes: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            changes()
        }
    }

    private func observeMonitorStateChanges() {
        // SwiftUI 页面观察的是 AppModel，不是内部的 KeyboardMonitor。
        // @Published 会在属性真正写入前先发 objectWillChange，所以这里不直接转发信号，
        // 而是延后一轮主队列同步一份 AppModel 自己的状态镜像，保证按钮和状态文案读到的是新值。
        monitorStateSubscription = monitor.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.syncMonitorState()
                }
            }
    }

    private func syncMonitorState() {
        let didStartRecording = !isMonitoringRunning && monitor.isRunning

        isMonitoringRunning = monitor.isRunning
        isMonitoringStarting = monitor.isStarting
        isKeyboardPermissionGranted = monitor.permissionGranted
        monitorStatusMessage = monitor.statusMessage
        monitorLastError = monitor.lastError

        if didStartRecording {
            Task {
                await refresh()
            }
        }
    }

    private static func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func launchAtLoginStatusDescription() -> String? {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已加入 macOS 登录项。"
        case .notRegistered:
            return "未加入 macOS 登录项。"
        case .requiresApproval:
            return "需要在系统设置的“登录项”中允许 TypeRecorder。"
        case .notFound:
            return "当前运行方式暂时无法注册登录项，请使用打包后的 App 再开启。"
        @unknown default:
            return "无法识别当前登录项状态，请稍后重试。"
        }
    }

    private func scheduleDailyBoundaryRefresh() {
        dailyBoundaryTimer?.invalidate()

        let calendar = Calendar.current
        let nextMidnight = calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60 * 60 * 24)
        let interval = max(1, nextMidnight.timeIntervalSinceNow)

        // 到 0 点后主动刷新界面；历史数据不被删除，真正的“重置”来自统计口径切到新日期。
        dailyBoundaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if self.isDailyResetEnabled {
                    await self.refresh()
                }
                self.scheduleDailyBoundaryRefresh()
            }
        }
    }
}
