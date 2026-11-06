import AppKit
import Foundation

enum AppCatalog {
    static func scan() -> [CatalogApp] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]

        var appsByID: [String: CatalogApp] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .nameKey]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let app = app(at: url) else { continue }
                let id = app.id

                if let existing = appsByID[id] {
                    if preferred(app.path, over: existing.path) {
                        appsByID[id] = app
                    }
                } else {
                    appsByID[id] = app
                }
            }
        }

        return appsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func app(at url: URL) -> CatalogApp? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else { return nil }
        let bundleID = bundle.bundleIdentifier
        let id = bundleID ?? url.standardizedFileURL.path
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return CatalogApp(id: id, name: displayName, bundleIdentifier: bundleID, path: url.path)
    }

    private static func preferred(_ candidate: String, over existing: String) -> Bool {
        func rank(_ path: String) -> Int {
            if path.hasPrefix("/Applications/") { return 0 }
            if path.contains("/Applications/") && !path.hasPrefix("/System/") { return 1 }
            return 2
        }
        return rank(candidate) < rank(existing)
    }
}

struct AppCatalogStore {
    private let fileManager = FileManager.default

    private var supportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchpadOS", isDirectory: true)
    }

    private var catalogURL: URL {
        supportDirectory.appendingPathComponent("catalog.json")
    }

    func load() -> [CatalogApp]? {
        guard let data = try? Data(contentsOf: catalogURL) else { return nil }
        return try? JSONDecoder().decode([CatalogApp].self, from: data)
    }

    func save(_ apps: [CatalogApp]) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(apps)
        try data.write(to: catalogURL, options: .atomic)
    }
}
