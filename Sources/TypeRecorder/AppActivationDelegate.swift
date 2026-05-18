import AppKit

@MainActor
final class AppActivationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeHideDockIconPreference()
        observeWindowCreation()

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)

            // SwiftUI 的 WindowGroup 可能比 applicationDidFinishLaunching 稍晚创建窗口。
            // 延迟一小段时间再前置一次，避免 Xcode 运行后窗口创建了但停在后台。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.configureApplicationWindows()
                Self.showMainWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Self.showMainWindow() {
            return false
        }

        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard Self.isHidingDockIconEnabled(), Self.isApplicationContentWindow(sender) else {
            return true
        }

        sender.orderOut(nil)
        return false
    }

    @discardableResult
    static func showMainWindow() -> Bool {
        let windows = NSApplication.shared.windows.filter(isApplicationContentWindow)
        guard !windows.isEmpty else {
            return false
        }

        windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }

    static func showMainWindowAfterWindowCreation() {
        DispatchQueue.main.async {
            _ = showMainWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = showMainWindow()
            }
        }
    }

    private func observeHideDockIconPreference() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideDockIconPreferenceDidChange(_:)),
            name: .typeRecorderHideDockIconPreferenceDidChange,
            object: nil
        )
    }

    private func observeWindowCreation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func hideDockIconPreferenceDidChange(_ notification: Notification) {
        applyActivationPolicy(isEnabled: notification.userInfo?["isEnabled"] as? Bool)
    }

    @objc private func applicationWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        configureApplicationWindow(window)
    }

    private func configureApplicationWindows() {
        NSApplication.shared.windows.forEach(configureApplicationWindow)
    }

    private func configureApplicationWindow(_ window: NSWindow) {
        guard Self.isApplicationContentWindow(window) else {
            return
        }
        window.delegate = self
    }

    private func applyActivationPolicy(isEnabled: Bool? = nil) {
        let hidesDockIcon = isEnabled ?? Self.isHidingDockIconEnabled()
        NSApplication.shared.setActivationPolicy(hidesDockIcon ? .accessory : .regular)
    }

    private static func isHidingDockIconEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKeys.hidesDockIcon)
    }

    private static func isApplicationContentWindow(_ window: NSWindow) -> Bool {
        window.canBecomeKey && String(describing: type(of: window)) != "NSStatusBarWindow"
    }
}
