import SwiftUI

@main
struct TypeRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
            Text("\(model.statisticsScopeTitle)按键：\(model.snapshot.realtime.keystrokesCount.formatted())")
            Divider()
            Button(actionTitle) {
                model.isMonitoringRunning ? model.stopMonitoring() : model.startMonitoring()
            }
            .disabled(model.isMonitoringStarting)
            Button("刷新统计") {
                Task { await model.refresh() }
            }
        }
        .padding(8)
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
}
