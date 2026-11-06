import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppPickerView: View {
    @EnvironmentObject private var model: LaunchpadModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedAppIDs = Set<String>()
    @State private var destinationID = "__root__"

    private var filteredApps: [CatalogApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedFolderID: String? {
        destinationID == "__root__" ? nil : destinationID
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("添加应用")
                    .font(.title2.bold())
                Spacer()
                TextField("搜索应用", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            HStack {
                Text("添加到")
                Picker("添加到", selection: $destinationID) {
                    Text("主控制台").tag("__root__")
                    Divider()
                    ForEach(model.layout.items.compactMap(\.folder)) { folder in
                        Text(folder.name).tag(folder.id)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                Text("已选择 \(selectedAppIDs.count) 个")
                    .foregroundStyle(.secondary)
            }

            List(filteredApps, selection: $selectedAppIDs) { app in
                HStack(spacing: 10) {
                    CachedAppIcon(path: app.path, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                        Text(app.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: selectedAppIDs.contains(app.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedAppIDs.contains(app.id) ? Color.accentColor : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(app.id) }
                .tag(app.id)
            }

            HStack {
                Button("从 Finder 选择 .app…") { chooseApplications() }
                Spacer()
                Button("取消") { dismiss() }
                Button("添加所选") {
                    model.addApps(selectedAppIDs, to: selectedFolderID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAppIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 600)
        .onExitCommand { dismiss() }
    }

    private func toggle(_ appID: String) {
        if selectedAppIDs.contains(appID) {
            selectedAppIDs.remove(appID)
        } else {
            selectedAppIDs.insert(appID)
        }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加的 macOS 应用"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        model.importApplications(at: panel.urls, to: selectedFolderID)
        dismiss()
    }
}
