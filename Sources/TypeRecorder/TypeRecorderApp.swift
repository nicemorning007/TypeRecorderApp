import SwiftUI

@main
struct TypeRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("TypeRecorder", id: AppWindowID.main) {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 720)
                .onAppear {
                    model.refreshWhenShown()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("TypeRecorder", systemImage: model.isMonitoringRunning || model.isMonitoringStarting ? "keyboard.fill" : "keyboard") {
            MenuBarContent()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
            Text("\(model.statisticsScopeTitle)按键：\(model.snapshot.realtime.keystrokesCount.formatted())")
            Divider()
            Button("显示窗口") {
                showMainWindow()
            }
            Button(actionTitle) {
                model.isMonitoringRunning ? model.stopMonitoring() : model.startMonitoring()
            }
            .disabled(model.isMonitoringStarting)
        }
        .padding(8)
        .onAppear {
            // MenuBarExtra 使用 .menu 样式时，菜单内容会在用户点开菜单时进入显示流程。
            // 这里复用 AppModel 的排队刷新逻辑，保证菜单里看到的是已写入按键之后的最新统计。
            model.refreshWhenShown()
        }
    }

    private var statusText: String {
        if model.isMonitoringStarting {
            return "正在启动"
        }
        return model.isMonitoringRunning ? "正在记录" : "记录已停止"
    }

    private var actionTitle: String {
        if model.isMonitoringStarting {
            return "启动中..."
        }
        return model.isMonitoringRunning ? "停止记录" : "开始记录"
    }

    private func showMainWindow() {
        if !AppActivationDelegate.showMainWindow() {
            openWindow(id: AppWindowID.main)
            AppActivationDelegate.showMainWindowAfterWindowCreation()
        }
    }
}
