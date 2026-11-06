import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockVisibility()
        DispatchQueue.main.async {
            Self.centerMainWindowOnMouseScreen()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGlobalHotKey),
            name: .launchpadGlobalHotKeyPressed,
            object: nil
        )
        let enabled = UserDefaults.standard.object(forKey: SettingsKeys.globalHotKeyEnabled) as? Bool ?? true
        if enabled { GlobalHotKeyController.shared.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first(where: {
            let identifier = $0.identifier?.rawValue ?? ""
            return identifier.contains("launchpad") || ($0.title == "LaunchpadOS" && $0.canBecomeMain)
        })
    }

    static func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showMainWindowCenteredOnMouseScreen() {
        centerMainWindowOnMouseScreen()
        showMainWindow()
    }

    static func centerMainWindowOnMouseScreen() {
        guard let window = mainWindow,
              !window.styleMask.contains(.fullScreen),
              let screen = screenContainingMouse()
        else { return }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.minX + (visibleFrame.width - windowSize.width) / 2,
            y: visibleFrame.minY + (visibleFrame.height - windowSize.height) / 2
        )
        window.setFrameOrigin(origin)
    }

    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }

    static func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    static func applyDockVisibility() {
        let visible = UserDefaults.standard.object(forKey: SettingsKeys.showDockIcon) as? Bool ?? true
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    private func applyDockVisibility() {
        Self.applyDockVisibility()
    }

    @objc private func handleGlobalHotKey() {
        guard let window = Self.mainWindow else { return }

        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            Self.showMainWindowCenteredOnMouseScreen()
        }
    }
}
