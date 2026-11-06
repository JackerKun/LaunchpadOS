import AppKit
import SwiftUI

final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var loading = Set<String>()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LaunchpadOS.IconCache"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func cached(path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    static func notificationName(for path: String) -> Notification.Name {
        Notification.Name("LaunchpadOS.IconDidLoad.\(path.hashValue)")
    }

    func load(path: String) {
        guard cached(path: path) == nil else { return }

        lock.lock()
        let shouldLoad = loading.insert(path).inserted
        lock.unlock()
        guard shouldLoad else { return }

        queue.addOperation { [weak self] in
            autoreleasepool {
                let notificationName = Self.notificationName(for: path)
                let image = NSWorkspace.shared.icon(forFile: path)
                image.size = NSSize(width: 128, height: 128)
                self?.cache.setObject(image, forKey: path as NSString, cost: 128 * 128 * 4)
                self?.lock.lock()
                self?.loading.remove(path)
                self?.lock.unlock()
                OperationQueue.main.addOperation {
                    NotificationCenter.default.post(name: notificationName, object: nil)
                }
            }
        }
    }

    func prewarm(_ paths: [String]) {
        for path in paths where cached(path: path) == nil {
            load(path: path)
        }
    }
}

struct CachedAppIcon: View {
    let path: String
    let size: CGFloat
    @State private var image: NSImage?

    init(path: String, size: CGFloat) {
        self.path = path
        self.size = size
        _image = State(initialValue: AppIconCache.shared.cached(path: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: size * 0.38))
                            .foregroundStyle(.white.opacity(0.22))
                    }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard image == nil else { return }
            AppIconCache.shared.load(path: path)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppIconCache.notificationName(for: path))) { _ in
            guard image == nil else { return }
            image = AppIconCache.shared.cached(path: path)
        }
    }
}
