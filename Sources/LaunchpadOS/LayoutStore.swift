import Foundation

struct LayoutStore {
    let fileManager = FileManager.default

    var supportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchpadOS", isDirectory: true)
    }

    var layoutURL: URL {
        supportDirectory.appendingPathComponent("layout.json")
    }

    func load() -> LayoutState? {
        guard let data = try? Data(contentsOf: layoutURL) else { return nil }
        return try? JSONDecoder().decode(LayoutState.self, from: data)
    }

    func save(_ state: LayoutState) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: layoutURL, options: .atomic)
    }
}

enum LegacyLayoutImporter {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Launchpal/launchpad_data.json")
    }

    static func importLayout(from url: URL = defaultURL) throws -> LayoutState {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootPages = object as? [[String: Any]] else {
            throw ImportError.invalidRoot
        }

        var items: [LayoutItem] = []
        for page in rootPages {
            items.append(contentsOf: parsePage(page))
        }
        guard !items.isEmpty else { throw ImportError.emptyLayout }
        return LayoutState(items: deduplicating(items))
    }

    private static func parsePage(_ page: [String: Any]) -> [LayoutItem] {
        guard
            let content = page["content"] as? [String: Any],
            let pageContent = content["page"] as? [String: Any],
            let items = pageContent["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap(parseItem)
    }

    private static func parseItem(_ item: [String: Any]) -> LayoutItem? {
        guard let content = item["content"] as? [String: Any] else { return nil }

        if let app = content["app"] as? [String: Any],
           let payload = app["_0"] as? [String: Any],
           let bundleID = payload["bundleID"] as? String {
            return .app(bundleID)
        }

        if let folderContent = content["folder"] as? [String: Any],
           let pages = folderContent["pages"] as? [[String: Any]] {
            let name = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appIDs = pages.flatMap(parsePage).compactMap(\.appID)
            guard !appIDs.isEmpty else { return nil }
            return .folder(FolderRecord(name: name?.isEmpty == false ? name! : "文件夹", appIDs: unique(appIDs)))
        }

        return nil
    }

    private static func deduplicating(_ items: [LayoutItem]) -> [LayoutItem] {
        var seen = Set<String>()
        var result: [LayoutItem] = []
        for var item in items {
            if item.kind == .app, let appID = item.appID {
                guard seen.insert(appID).inserted else { continue }
            } else if var folder = item.folder {
                folder.appIDs = folder.appIDs.filter { seen.insert($0).inserted }
                guard !folder.appIDs.isEmpty else { continue }
                item.folder = folder
            }
            result.append(item)
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    enum ImportError: LocalizedError {
        case invalidRoot
        case emptyLayout

        var errorDescription: String? {
            switch self {
            case .invalidRoot: "旧布局文件格式无法识别"
            case .emptyLayout: "旧布局中没有找到应用或文件夹"
            }
        }
    }
}
