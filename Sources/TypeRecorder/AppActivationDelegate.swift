import AppKit

final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Xcode 直接运行 SwiftPM executable 时，进程有时会按后台命令行程序启动。
        // 这里显式声明为普通 App，确保 Dock、菜单栏和 WindowGroup 都能正常显示。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)

            // SwiftUI 的 WindowGroup 可能比 applicationDidFinishLaunching 稍晚创建窗口。
            // 延迟一小段时间再前置一次，避免 Xcode 运行后窗口创建了但停在后台。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.windows
                    .filter { window in
                        window.canBecomeKey
                            && window.isVisible
                            && String(describing: type(of: window)) != "NSStatusBarWindow"
                    }
                    .forEach { window in
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                if NSApplication.shared.windows.contains(where: { $0.canBecomeKey && $0.isVisible }) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
