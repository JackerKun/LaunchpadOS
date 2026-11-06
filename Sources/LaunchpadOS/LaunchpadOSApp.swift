import AppKit
import SwiftUI

@main
struct LaunchpadOSApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    @StateObject private var model = LaunchpadModel()

    var body: some Scene {
        Window("LaunchpadOS", id: "launchpad") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button(model.isEditing ? "退出编辑模式" : "隐藏 LaunchpadOS") {
                    if model.isEditing {
                        model.exitEditMode()
                    } else {
                        ApplicationDelegate.hideMainWindow()
                    }
                }
                .keyboardShortcut(.cancelAction)
                Divider()
                Button("重新扫描应用") { Task { await model.refreshApps() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("导入旧 Launchpad 分组") { model.importLegacyLayout() }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Image(systemName: "square.grid.3x3.fill")
                .accessibilityLabel("LaunchpadOS")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
