import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum KeyboardFocus: Hashable {
        case search
        case app(String)
        case folder(String)
    }

    @EnvironmentObject private var model: LaunchpadModel
    @Environment(\.openSettings) private var openSettings
    @State private var showingLayoutManager = false
    @State private var showingAppPicker = false
    @State private var gridWidth: CGFloat = 900
    @FocusState private var keyboardFocus: KeyboardFocus?

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 144), spacing: 28)]

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.30, blue: 0.42).ignoresSafeArea()
            LinearGradient(
                colors: [Color.indigo.opacity(0.18), Color.cyan.opacity(0.08), Color.black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 18) {
                header
                if model.isLoading && model.apps.isEmpty {
                    Spacer()
                    ProgressView("正在扫描应用…").controlSize(.large)
                    Spacer()
                } else if model.searchText.isEmpty {
                    layoutGrid
                } else {
                    searchGrid
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 22)

            if let folderID = model.selectedFolderID {
                FolderOverlay(folderID: folderID)
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.selectedFolderID)
        .frame(minWidth: 900, minHeight: 620)
        .onPreferenceChange(GridWidthPreferenceKey.self) { gridWidth = $0 }
        .onMoveCommand(perform: moveKeyboardFocus)
        .background {
            BackspaceKeyMonitor(
                isEnabled: !model.isEditing && model.selectedFolderID == nil,
                action: focusSearchAndDeleteLastCharacter
            )
        }
        .sheet(isPresented: $showingLayoutManager) {
            LayoutManagerView().environmentObject(model)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView().environmentObject(model)
        }
        .alert("LaunchpadOS", isPresented: statusPresented) {
            Button("好") { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
        .onExitCommand {
            if model.isEditing {
                model.exitEditMode()
            } else {
                ApplicationDelegate.hideMainWindow()
            }
        }
        .onAppear {
            guard UserDefaults.standard.bool(forKey: SettingsKeys.openFullScreen),
                  let window = NSApp.keyWindow,
                  !window.styleMask.contains(.fullScreen)
            else { return }
            window.toggleFullScreen(nil)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isEditing ? "编辑启动台" : "LaunchpadOS")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(model.isEditing ? "拖动排序或归组，点减号移除" : "\(model.apps.count) 个应用 · 布局自动保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isEditing {
                Button("添加应用", systemImage: "plus.app") { showingAppPicker = true }
                Button("新建分组", systemImage: "folder.badge.plus") { model.createFolder() }
                Button("分组管理", systemImage: "slider.horizontal.3") { showingLayoutManager = true }
                Button {
                    model.exitEditMode()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("退出编辑模式（Esc）")
            } else {
                searchField
                optionsMenu
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索应用", text: $model.searchText)
                .textFieldStyle(.plain)
                .frame(width: 210)
                .focused($keyboardFocus, equals: .search)
                .onSubmit { focusFirstVisibleItem() }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18), in: Capsule())
    }

    private var optionsMenu: some View {
        Menu {
            Button("编辑启动台", systemImage: "square.and.pencil") { model.enterEditMode() }
            Button("添加应用…", systemImage: "plus.app") { showingAppPicker = true }
            Button("新建文件夹", systemImage: "folder.badge.plus") { model.createFolder() }
            Button("分组管理", systemImage: "slider.horizontal.3") { showingLayoutManager = true }
            Button("重新扫描应用", systemImage: "arrow.clockwise") { Task { await model.refreshApps() } }
            Button("进入全屏", systemImage: "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.toggleFullScreen(nil) }
            Divider()
            Button("重新导入旧 Launchpad 分组", systemImage: "square.and.arrow.down") { model.importLegacyLayout() }
            Divider()
            Button("设置…", systemImage: "gearshape") { openSettings() }
        } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title2)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var layoutGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(model.layout.items) { item in
                    if item.kind == .app, let appID = item.appID, let app = model.appsByID[appID] {
                        AppTile(
                            app: app,
                            removalAction: { model.hideApp(app.id) },
                            isKeyboardFocused: keyboardFocus == .app(app.id)
                        )
                            .focusable(!model.isEditing)
                            .focused($keyboardFocus, equals: .app(app.id))
                            .onKeyPress(.return) {
                                guard !model.isEditing else { return .ignored }
                                model.launch(app)
                                return .handled
                            }
                            .onDrag {
                                model.draggingItemID = item.id
                                model.draggingAppID = app.id
                                return NSItemProvider(object: item.id as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: RootDropDelegate(targetID: item.id, targetAppID: app.id, model: model)
                            )
                            .contextMenu {
                                Button("编辑启动台") { model.enterEditMode() }
                                Button("新建文件夹并移入") { model.createFolder(containing: app.id) }
                                Button("从启动台移除") { model.hideApp(app.id) }
                                Divider()
                                Button("在 Finder 中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                                }
                            }
                    } else if let folder = item.folder {
                        FolderTile(
                            folder: folder,
                            isKeyboardFocused: keyboardFocus == .folder(folder.id)
                        )
                            .focusable(!model.isEditing)
                            .focused($keyboardFocus, equals: .folder(folder.id))
                            .onKeyPress(.return) {
                                guard !model.isEditing else { return .ignored }
                                model.selectedFolderID = folder.id
                                return .handled
                            }
                            .onDrop(of: [.plainText], delegate: FolderDropDelegate(folderID: folder.id, model: model))
                            .contextMenu {
                                Button("打开") { model.selectedFolderID = folder.id }
                                Button("编辑启动台") { model.enterEditMode() }
                                Divider()
                                Button("删除文件夹") { model.deleteFolder(folder.id) }
                            }
                    }
                }
            }
            .padding(.vertical, 12)
            .background(gridWidthReader)
        }
        .scrollIndicators(.hidden)
    }

    private var searchGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(model.filteredApps) { app in
                    AppTile(app: app, isKeyboardFocused: keyboardFocus == .app(app.id))
                        .focusable()
                        .focused($keyboardFocus, equals: .app(app.id))
                        .onKeyPress(.return) {
                            model.launch(app)
                            return .handled
                        }
                }
            }
            .padding(.vertical, 12)
            .background(gridWidthReader)
        }
        .scrollIndicators(.hidden)
    }

    private var statusPresented: Binding<Bool> {
        Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })
    }

    private var gridWidthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: GridWidthPreferenceKey.self, value: proxy.size.width)
        }
    }

    private var visibleKeyboardItems: [KeyboardFocus] {
        if !model.searchText.isEmpty {
            return model.filteredApps.map { .app($0.id) }
        }
        return model.layout.items.compactMap { item in
            if let appID = item.appID, model.appsByID[appID] != nil { return .app(appID) }
            if let folder = item.folder { return .folder(folder.id) }
            return nil
        }
    }

    private func focusFirstVisibleItem() {
        guard let first = visibleKeyboardItems.first else { return }
        DispatchQueue.main.async { keyboardFocus = first }
    }

    private func focusSearchAndDeleteLastCharacter() {
        if !model.searchText.isEmpty {
            model.searchText.removeLast()
        }
        keyboardFocus = nil
        DispatchQueue.main.async { keyboardFocus = .search }
    }

    private func moveKeyboardFocus(_ direction: MoveCommandDirection) {
        guard model.selectedFolderID == nil,
              let current = keyboardFocus,
              current != .search
        else { return }

        let items = visibleKeyboardItems
        guard let currentIndex = items.firstIndex(of: current), !items.isEmpty else {
            focusFirstVisibleItem()
            return
        }

        let columnCount = max(1, Int((gridWidth + 28) / (112 + 28)))
        let candidate: Int
        switch direction {
        case .left: candidate = currentIndex - 1
        case .right: candidate = currentIndex + 1
        case .up: candidate = currentIndex - columnCount
        case .down: candidate = currentIndex + columnCount
        @unknown default: return
        }
        guard items.indices.contains(candidate) else { return }
        keyboardFocus = items[candidate]
    }
}

private struct GridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct BackspaceKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> BackspaceMonitorNSView {
        let view = BackspaceMonitorNSView()
        view.isEnabled = isEnabled
        view.action = action
        return view
    }

    func updateNSView(_ nsView: BackspaceMonitorNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: BackspaceMonitorNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class BackspaceMonitorNSView: NSView {
    var isEnabled = true
    var action: (() -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.isEnabled,
                  event.window === self.window,
                  event.keyCode == 51,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(event.window?.firstResponder is NSTextView)
            else { return event }

            self.action?()
            return nil
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

struct AppTile: View {
    @EnvironmentObject private var model: LaunchpadModel
    let app: CatalogApp
    var removalAction: (() -> Void)? = nil
    var isKeyboardFocused = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                CachedAppIcon(path: app.path, size: 76)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 118)
            }
            .frame(width: 120, height: 112)
            .contentShape(Rectangle())
            .rotationEffect(editRotation)
            .gesture(appGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !model.isEditing { model.launch(app) } }

            if model.isEditing, let removalAction {
                EditBadge(systemName: "minus") { removalAction() }
                    .offset(x: 3, y: 1)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isKeyboardFocused ? Color.white.opacity(0.95) : .clear, lineWidth: 3)
                .padding(-5)
        }
        .scaleEffect(isKeyboardFocused ? 1.045 : 1)
        .animation(.easeOut(duration: 0.12), value: isKeyboardFocused)
        .help(model.isEditing ? "拖动排序或归组" : app.path)
    }

    private var editRotation: Angle {
        guard model.isEditing else { return .zero }
        return .degrees(app.id.hashValue.isMultiple(of: 2) ? -0.65 : 0.65)
    }

    private var appGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.55)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first: model.enterEditMode()
                case .second: if !model.isEditing { model.launch(app) }
                }
            }
    }
}

struct EditBadge: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
                .foregroundStyle(.black)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct FolderTile: View {
    @EnvironmentObject private var model: LaunchpadModel
    let folder: FolderRecord
    var isKeyboardFocused = false
    private let miniColumns = Array(repeating: GridItem(.fixed(25), spacing: 4), count: 3)

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                LazyVGrid(columns: miniColumns, spacing: 4) {
                    ForEach(Array(model.catalogApps(in: folder).prefix(9))) { app in
                        CachedAppIcon(path: app.path, size: 25)
                    }
                }
                .frame(width: 84, height: 76)
                .padding(8)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)

                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 118)
            }
            .frame(width: 120, height: 112)
            .contentShape(Rectangle())
            .rotationEffect(model.isEditing ? .degrees(folder.id.hashValue.isMultiple(of: 2) ? -0.65 : 0.65) : .zero)
            .gesture(folderGesture)

            if model.isEditing {
                EditBadge(systemName: "minus") { model.deleteFolder(folder.id) }
                    .offset(x: 3, y: 1)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isKeyboardFocused ? Color.white.opacity(0.95) : .clear, lineWidth: 3)
                .padding(-5)
        }
        .scaleEffect(isKeyboardFocused ? 1.045 : 1)
        .animation(.easeOut(duration: 0.12), value: isKeyboardFocused)
        .overlay {
            FirstActivationClickView {
                model.selectedFolderID = folder.id
            }
        }
    }

    private var folderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.55)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first: model.enterEditMode()
                case .second: model.selectedFolderID = folder.id
                }
            }
    }
}

struct FolderOverlay: View {
    @EnvironmentObject private var model: LaunchpadModel
    let folderID: String

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 42
            let verticalInset: CGFloat = 38
            let panelWidth = min(760, max(520, proxy.size.width - horizontalInset * 2))
            let panelHeight = min(580, max(400, proxy.size.height - verticalInset * 2))

            ZStack {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedFolderID = nil }

                FolderSheet(folderID: folderID)
                    .environmentObject(model)
                    .frame(width: panelWidth, height: panelHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.38), radius: 28, y: 12)
            }
        }
        .ignoresSafeArea()
    }
}

struct FolderSheet: View {
    @EnvironmentObject private var model: LaunchpadModel
    let folderID: String
    @State private var name = ""
    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 24)]

    var body: some View {
        VStack(spacing: 16) {
            TextField("文件夹名称", text: $name)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit { model.renameFolder(folderID, to: name) }
                .onChange(of: name) { _, value in model.renameFolder(folderID, to: value) }

            if let folder = model.folder(withID: folderID) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(model.catalogApps(in: folder)) { app in
                            AppTile(
                                app: app,
                                removalAction: model.isEditing ? { model.removeAppFromFolder(app.id, folderID: folderID) } : nil
                            )
                            .onDrag {
                                model.draggingAppID = app.id
                                return NSItemProvider(object: app.id as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: FolderAppDropDelegate(targetAppID: app.id, folderID: folderID, model: model)
                            )
                            .contextMenu {
                                Button("移出文件夹") { model.removeAppFromFolder(app.id, folderID: folderID) }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .popover))
        .onAppear { name = model.folder(withID: folderID)?.name ?? "文件夹" }
        .onExitCommand { model.selectedFolderID = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.selectedFolderID = nil
        }
    }
}

struct FirstActivationClickView: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> FirstActivationClickNSView {
        let view = FirstActivationClickNSView()
        view.action = context.coordinator.action
        return view
    }

    func updateNSView(_ nsView: FirstActivationClickNSView, context: Context) {
        context.coordinator.action = action
        nsView.action = context.coordinator.action
    }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}

final class FirstActivationClickNSView: NSView {
    var action: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !NSApp.isActive || window?.isKeyWindow == false else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        action?()
    }
}

struct LayoutManagerView: View {
    @EnvironmentObject private var model: LaunchpadModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("分组管理").font(.title2.bold())
                Spacer()
                Button("新建分组") { model.createFolder() }
                Button("关闭") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            List {
                Section("分组") {
                    ForEach(model.layout.items.compactMap(\.folder)) { folder in
                        HStack {
                            TextField(
                                "分组名称",
                                text: Binding(
                                    get: { model.folder(withID: folder.id)?.name ?? folder.name },
                                    set: { model.renameFolder(folder.id, to: $0) }
                                )
                            )
                            Text("\(folder.appIDs.count) 个应用").foregroundStyle(.secondary)
                            Button("删除", role: .destructive) { model.deleteFolder(folder.id) }
                        }
                    }
                }

                Section("已从启动台移除") {
                    if model.layout.hiddenAppIDs.isEmpty {
                        Text("没有已移除的应用").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.layout.hiddenAppIDs, id: \.self) { appID in
                            HStack {
                                if let app = model.appsByID[appID] {
                                    CachedAppIcon(path: app.path, size: 28)
                                    Text(app.name)
                                } else {
                                    Text(appID)
                                }
                                Spacer()
                                Button("恢复") { model.restoreHiddenApp(appID) }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

struct RootDropDelegate: DropDelegate {
    let targetID: String
    let targetAppID: String
    let model: LaunchpadModel

    func dropEntered(info: DropInfo) {
        guard let sourceID = model.draggingItemID else { return }
        if !model.isEditing || !isGroupingZone(info.location) {
            model.moveRootItem(sourceID, before: targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if model.isEditing,
           isGroupingZone(info.location),
           let sourceAppID = model.draggingAppID,
           sourceAppID != targetAppID {
            model.createFolder(grouping: sourceAppID, with: targetAppID)
        } else {
            model.finishDragging()
        }
        return true
    }

    private func isGroupingZone(_ point: CGPoint) -> Bool {
        (24...96).contains(point.x) && (8...92).contains(point.y)
    }
}

struct FolderDropDelegate: DropDelegate {
    let folderID: String
    let model: LaunchpadModel

    func validateDrop(info: DropInfo) -> Bool { model.draggingAppID != nil }

    func performDrop(info: DropInfo) -> Bool {
        guard let appID = model.draggingAppID else { return false }
        model.moveApp(appID, into: folderID)
        return true
    }
}

struct FolderAppDropDelegate: DropDelegate {
    let targetAppID: String
    let folderID: String
    let model: LaunchpadModel

    func dropEntered(info: DropInfo) {
        guard let sourceAppID = model.draggingAppID else { return }
        model.moveFolderApp(sourceAppID, before: targetAppID, folderID: folderID)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.finishDragging()
        return true
    }
}
