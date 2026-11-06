import Foundation

struct CatalogApp: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let path: String
}

struct FolderRecord: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var appIDs: [String]

    init(id: String = UUID().uuidString, name: String, appIDs: [String] = []) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

struct LayoutItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case app
        case folder
    }

    var id: String
    var kind: Kind
    var appID: String?
    var folder: FolderRecord?

    static func app(_ appID: String) -> LayoutItem {
        LayoutItem(id: "app:\(appID)", kind: .app, appID: appID, folder: nil)
    }

    static func folder(_ folder: FolderRecord) -> LayoutItem {
        LayoutItem(id: "folder:\(folder.id)", kind: .folder, appID: nil, folder: folder)
    }
}

struct LayoutState: Codable, Equatable, Sendable {
    var version = 2
    var items: [LayoutItem] = []
    var hiddenAppIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case version
        case items
        case hiddenAppIDs
    }

    init(version: Int = 2, items: [LayoutItem] = [], hiddenAppIDs: [String] = []) {
        self.version = version
        self.items = items
        self.hiddenAppIDs = hiddenAppIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try container.decodeIfPresent([LayoutItem].self, forKey: .items) ?? []
        hiddenAppIDs = try container.decodeIfPresent([String].self, forKey: .hiddenAppIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(items, forKey: .items)
        try container.encode(hiddenAppIDs, forKey: .hiddenAppIDs)
    }
}
