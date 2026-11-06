import AppKit
import Carbon
import ServiceManagement
import SwiftUI

enum SettingsKeys {
    static let showDockIcon = "showDockIcon"
    static let hideAfterLaunch = "hideAfterLaunch"
    static let openFullScreen = "openFullScreen"
    static let globalHotKeyEnabled = "globalHotKeyEnabled"
    static let globalHotKeyKeyCode = "globalHotKeyKeyCode"
    static let globalHotKeyModifiers = "globalHotKeyModifiers"
    static let globalHotKeyDisplay = "globalHotKeyDisplay"
}

struct SettingsView: View {
    @EnvironmentObject private var model: LaunchpadModel
    @AppStorage(SettingsKeys.showDockIcon) private var showDockIcon = true
    @AppStorage(SettingsKeys.hideAfterLaunch) private var hideAfterLaunch = false
    @AppStorage(SettingsKeys.openFullScreen) private var openFullScreen = false
    @AppStorage(SettingsKeys.globalHotKeyEnabled) private var globalHotKeyEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            Form {
                Section("启动方式") {
                    Toggle("在 Dock 中显示图标", isOn: $showDockIcon)
                        .onChange(of: showDockIcon) { _, _ in
                            ApplicationDelegate.applyDockVisibility()
                        }
                    Toggle("登录时自动启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    Text("菜单栏图标始终保留，可从那里打开主界面、设置或退出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("窗口行为") {
                    Toggle("启动应用后隐藏 LaunchpadOS", isOn: $hideAfterLaunch)
                    Toggle("打开主界面时进入全屏", isOn: $openFullScreen)
                }

                Section("全局快捷键") {
                    Toggle("启用全局快捷键", isOn: $globalHotKeyEnabled)
                        .onChange(of: globalHotKeyEnabled) { _, enabled in
                            if enabled {
                                if !GlobalHotKeyController.shared.start() {
                                    globalHotKeyEnabled = false
                                    loginError = "该快捷键已被其他应用占用，无法注册。"
                                }
                            } else {
                                GlobalHotKeyController.shared.stop()
                            }
                        }
                    ShortcutRecorder(globalHotKeyEnabled: $globalHotKeyEnabled, errorMessage: $loginError)
                    Text("按一次呼出；窗口位于最前面时再按一次隐藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            VStack(spacing: 16) {
                if let icon = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "png") ?? "") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                }
                Text("LaunchpadOS")
                    .font(.title.bold())
                Text("原生 macOS 应用启动器")
                    .foregroundStyle(.secondary)
                Text("版本 0.4.7")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("重新扫描应用") { Task { await model.refreshApps() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 410)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = "登录启动设置失败：\(error.localizedDescription)"
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var globalHotKeyEnabled: Bool
    @Binding var errorMessage: String?
    @AppStorage(SettingsKeys.globalHotKeyDisplay) private var shortcutDisplay = "⌥ Space"
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text("快捷键")
            Spacer()
            Button(isRecording ? "请按新的组合键…" : shortcutDisplay) {
                beginRecording()
            }
            .frame(minWidth: 150)
        }
        .onDisappear { stopRecording() }
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
                errorMessage = "快捷键至少需要包含 ⌘、⌥ 或 ⌃。"
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            let modifiers = GlobalHotKeyController.carbonModifiers(from: flags)
            let defaults = UserDefaults.standard
            let oldKeyCode = defaults.object(forKey: SettingsKeys.globalHotKeyKeyCode) == nil
                ? 49
                : UInt32(defaults.integer(forKey: SettingsKeys.globalHotKeyKeyCode))
            let oldModifiers = defaults.object(forKey: SettingsKeys.globalHotKeyModifiers) == nil
                ? UInt32(optionKey)
                : UInt32(defaults.integer(forKey: SettingsKeys.globalHotKeyModifiers))

            if GlobalHotKeyController.shared.register(keyCode: keyCode, modifiers: modifiers) {
                defaults.set(keyCode, forKey: SettingsKeys.globalHotKeyKeyCode)
                defaults.set(modifiers, forKey: SettingsKeys.globalHotKeyModifiers)
                shortcutDisplay = GlobalHotKeyController.displayName(for: event)
                globalHotKeyEnabled = true
                errorMessage = nil
            } else {
                _ = GlobalHotKeyController.shared.register(keyCode: oldKeyCode, modifiers: oldModifiers)
                errorMessage = "该快捷键已被其他应用占用，请换一个组合。"
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}
