import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LaunchpadModel: ObservableObject {
    @Published private(set) var apps: [CatalogApp] = []
    private(set) var appsByID: [String: CatalogApp] = [:]
    @Published private(set) var layout = LayoutState()
    @Published var searchText = ""
    @Published var selectedFolderID: String?
    @Published var isEditing = false
    @Published var isLoading = false
    @Published var statusMessage: String?

    var draggingItemID: String?
    var draggingAppID: String?

    private let store = LayoutStore()
    private let catalogStore = AppCatalogStore()
    private var hasLoadedPersistedLayout = false

    init() {
        if let saved = store.load() {
            layout = saved
            hasLoadedPersistedLayout = true
        } else if FileManager.default.fileExists(atPath: LegacyLayoutImporter.defaultURL.path),
                  let imported = try? LegacyLayoutImporter.importLayout() {
            layout = imported
            statusMessage = "已自动恢复旧 Launchpad 分组"
            save()
        }

        if let cachedApps = catalogStore.load(), !cachedApps.isEmpty {
            appsByID = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.id, $0) })
            apps = cachedApps
            reconcileLayout()
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            await refreshApps()
        }
    }

    var filteredApps: [CatalogApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func refreshApps() async {
        isLoading = apps.isEmpty
        let scanned = await Task.detached(priority: .utility) { AppCatalog.scan() }.value
        var merged = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
        for app in apps where merged[app.id] == nil && FileManager.default.fileExists(atPath: app.path) {
            merged[app.id] = app
        }
        let updatedApps = merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        appsByID = merged
        apps = updatedApps
        try? catalogStore.save(updatedApps)
        reconcileLayout()
        isLoading = false
    }

    func launch(_ app: CatalogApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in self.statusMessage = "无法打开 \(app.name)：\(error.localizedDescription)" }
            } else if UserDefaults.standard.bool(forKey: SettingsKeys.hideAfterLaunch) {
                Task { @MainActor in NSApp.hide(nil) }
            }
        }
    }

    func importLegacyLayout() {
        do {
            layout = try LegacyLayoutImporter.importLayout()
            reconcileLayout()
            statusMessage = "旧 Launchpad 页面和文件夹已导入"
            save()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createFolder(containing appID: String? = nil) {
        if let appID { removeAppEverywhere(appID) }
        let folder = FolderRecord(name: "新建文件夹", appIDs: appID.map { [$0] } ?? [])
        layout.items.append(.folder(folder))
        selectedFolderID = folder.id
        save()
    }

    func addApps(_ appIDs: Set<String>, to folderID: String?) {
        guard !appIDs.isEmpty else { return }
        for appID in appIDs {
            removeAppEverywhere(appID)
            layout.hiddenAppIDs.removeAll { $0 == appID }
        }

        let orderedIDs = apps.map(\.id).filter(appIDs.contains)
        if let folderID, let index = folderIndex(folderID), var folder = layout.items[index].folder {
            for appID in orderedIDs where !folder.appIDs.contains(appID) {
                folder.appIDs.append(appID)
            }
            layout.items[index].folder = folder
        } else {
            layout.items.append(contentsOf: orderedIDs.map(LayoutItem.app))
        }
        removeEmptyFolders()
        save()
    }

    func importApplications(at urls: [URL], to folderID: String?) {
        let imported = urls.compactMap(AppCatalog.app(at:))
        guard !imported.isEmpty else {
            statusMessage = "没有找到可添加的 macOS 应用"
            return
        }
        for app in imported { appsByID[app.id] = app }
        apps = appsByID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try? catalogStore.save(apps)
        addApps(Set(imported.map(\.id)), to: folderID)
    }

    func createFolder(grouping sourceAppID: String, with targetAppID: String) {
        guard sourceAppID != targetAppID else { return }
        let targetIndex = layout.items.firstIndex { $0.appID == targetAppID } ?? layout.items.endIndex
        removeAppEverywhere(sourceAppID)
        removeAppEverywhere(targetAppID)
        let sourceName = appsByID[sourceAppID]?.name ?? ""
        let targetName = appsByID[targetAppID]?.name ?? ""
        let suggestedName = commonFolderName(sourceName, targetName)
        let folder = FolderRecord(name: suggestedName, appIDs: [targetAppID, sourceAppID])
        layout.items.insert(.folder(folder), at: min(targetIndex, layout.items.endIndex))
        selectedFolderID = folder.id
        finishDragging()
    }

    func enterEditMode() {
        withAnimation(.easeOut(duration: 0.16)) { isEditing = true }
    }

    func exitEditMode() {
        withAnimation(.easeOut(duration: 0.16)) { isEditing = false }
        finishDragging()
    }

    func hideApp(_ appID: String) {
        removeAppEverywhere(appID)
        if !layout.hiddenAppIDs.contains(appID) { layout.hiddenAppIDs.append(appID) }
        removeEmptyFolders()
        save()
    }

    func restoreHiddenApp(_ appID: String) {
        layout.hiddenAppIDs.removeAll { $0 == appID }
        if !layout.items.contains(where: { $0.appID == appID }) {
            layout.items.append(.app(appID))
        }
        save()
    }

    func renameFolder(_ folderID: String, to name: String) {
        mutateFolder(folderID) { folder in
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            folder.name = clean.isEmpty ? "文件夹" : clean
        }
    }

    func deleteFolder(_ folderID: String) {
        guard let index = folderIndex(folderID), let folder = layout.items[index].folder else { return }
        layout.items.remove(at: index)
        layout.items.append(contentsOf: folder.appIDs.map(LayoutItem.app))
        selectedFolderID = nil
        save()
    }

    func moveApp(_ appID: String, into folderID: String) {
        removeAppEverywhere(appID)
        mutateFolder(folderID) { folder in
            if !folder.appIDs.contains(appID) { folder.appIDs.append(appID) }
        }
        draggingItemID = nil
        draggingAppID = nil
    }

    func removeAppFromFolder(_ appID: String, folderID: String) {
        mutateFolder(folderID) { $0.appIDs.removeAll { $0 == appID } }
        if !layout.items.contains(where: { $0.appID == appID }) {
            layout.items.append(.app(appID))
        }
        save()
    }

    func moveFolderApp(_ sourceAppID: String, before targetAppID: String, folderID: String) {
        mutateFolder(folderID, saveImmediately: false) { folder in
            guard sourceAppID != targetAppID,
                  let source = folder.appIDs.firstIndex(of: sourceAppID),
                  let target = folder.appIDs.firstIndex(of: targetAppID)
            else { return }
            let appID = folder.appIDs.remove(at: source)
            folder.appIDs.insert(appID, at: target > source ? target - 1 : target)
        }
    }

    func moveRootItem(_ sourceID: String, before targetID: String) {
        guard sourceID != targetID,
              let source = layout.items.firstIndex(where: { $0.id == sourceID }),
              let target = layout.items.firstIndex(where: { $0.id == targetID })
        else { return }
        layout.items.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
    }

    func finishDragging() {
        draggingItemID = nil
        draggingAppID = nil
        save()
    }

    func folder(withID id: String) -> FolderRecord? {
        guard let index = folderIndex(id) else { return nil }
        return layout.items[index].folder
    }

    func catalogApps(in folder: FolderRecord) -> [CatalogApp] {
        let lookup = appsByID
        return folder.appIDs.compactMap { lookup[$0] }
    }

    private func reconcileLayout() {
        let knownIDs = Set(apps.map(\.id))
        let hiddenIDs = Set(layout.hiddenAppIDs)
        var represented = Set<String>()

        for item in layout.items {
            if let appID = item.appID { represented.insert(appID) }
            if let folder = item.folder { represented.formUnion(folder.appIDs) }
        }

        if layout.items.isEmpty && !hasLoadedPersistedLayout {
            layout.items = apps.map { .app($0.id) }
        } else {
            for app in apps where !represented.contains(app.id) && !hiddenIDs.contains(app.id) {
                layout.items.append(.app(app.id))
            }
            // Keep missing IDs in the saved layout so temporarily unavailable apps
            // return to their original folder when reinstalled or remounted.
            _ = knownIDs
        }
        save()
    }

    private func folderIndex(_ folderID: String) -> Int? {
        layout.items.firstIndex { $0.folder?.id == folderID }
    }

    private func mutateFolder(
        _ folderID: String,
        saveImmediately: Bool = true,
        mutation: (inout FolderRecord) -> Void
    ) {
        guard let index = folderIndex(folderID), var folder = layout.items[index].folder else { return }
        mutation(&folder)
        layout.items[index].folder = folder
        if saveImmediately { save() }
    }

    private func removeAppEverywhere(_ appID: String) {
        layout.items.removeAll { $0.kind == .app && $0.appID == appID }
        for index in layout.items.indices where layout.items[index].kind == .folder {
            layout.items[index].folder?.appIDs.removeAll { $0 == appID }
        }
    }

    private func removeEmptyFolders() {
        layout.items.removeAll { $0.kind == .folder && ($0.folder?.appIDs.isEmpty ?? true) }
    }

    private func commonFolderName(_ first: String, _ second: String) -> String {
        let firstWord = first.split(separator: " ").first.map(String.init) ?? ""
        let secondWord = second.split(separator: " ").first.map(String.init) ?? ""
        return firstWord.caseInsensitiveCompare(secondWord) == .orderedSame && !firstWord.isEmpty
            ? firstWord
            : "新建文件夹"
    }

    private func save() {
        do { try store.save(layout) }
        catch { statusMessage = "布局保存失败：\(error.localizedDescription)" }
    }
}
