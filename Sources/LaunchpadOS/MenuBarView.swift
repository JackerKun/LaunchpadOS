import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: LaunchpadModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 LaunchpadOS", systemImage: "square.grid.3x3.fill") {
            showLaunchpad()
        }
        .keyboardShortcut("l")

        Button("新建文件夹", systemImage: "folder.badge.plus") {
            model.createFolder()
            showLaunchpad()
        }

        Divider()

        Button("重新扫描应用", systemImage: "arrow.clockwise") {
            Task { await model.refreshApps() }
        }

        Button("重新导入旧分组", systemImage: "square.and.arrow.down") {
            model.importLegacyLayout()
        }

        Divider()

        SettingsLink {
            Label("设置…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Button("退出 LaunchpadOS", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showLaunchpad() {
        openWindow(id: "launchpad")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.title.contains("LaunchpadOS") }) else { return }
            window.makeKeyAndOrderFront(nil)
            if UserDefaults.standard.bool(forKey: SettingsKeys.openFullScreen),
               !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
}
