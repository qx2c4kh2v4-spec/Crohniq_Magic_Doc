import SwiftUI
import UniformTypeIdentifiers

/// Opens apps, optionally with documents, and reads the app's recent documents list.
enum AppLauncher {
    static func isSafari(_ app: String) -> Bool {
        Bundle(path: app)?.bundleIdentifier == "com.apple.Safari"
            || URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent.caseInsensitiveCompare("Safari") == .orderedSame
    }

    static func promptSafariSearch(app: String) {
        let alert = NSAlert()
        alert.messageText = "Google-Suche in Safari"
        alert.informativeText = "Suchbegriff eingeben oder Safari ohne Suche öffnen."
        alert.addButton(withTitle: "Google suchen")
        alert.addButton(withTitle: "Nur Safari öffnen")
        alert.addButton(withTitle: "Abbrechen")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == .alertFirstButtonReturn, !query.isEmpty else {
            open(app: app)
            return
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            Notifier.notify("Google-Suche fehlgeschlagen", "Der Suchbegriff konnte nicht in eine URL umgewandelt werden.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: app), configuration: configuration) { _, error in
            if let error { Notifier.notify("Safari konnte die Suche nicht öffnen", error.localizedDescription) }
        }
    }

    static func isForkLift(_ app: String) -> Bool {
        let bundleID = Bundle(path: app)?.bundleIdentifier?.lowercased()
        let name = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent.lowercased()
        return bundleID == "com.binarynights.forklift" || name.contains("forklift")
    }

    private static let xcodeProjectExtensions: Set<String> = ["xcodeproj", "xcworkspace", "playground"]

    static func open(app: String, files: [String] = [], newInstance: Bool = false) {
        let appURL = URL(fileURLWithPath: app)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        cfg.createsNewApplicationInstance = newInstance
        let urls = files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg)
        }
    }

    /// Recent documents macOS keeps per app (e.g. Xcode projects, Pages files).
    /// Finder has no per-app list; its toolbar uses the system-wide Recent Documents list.
    static func recentDocuments(bundleID: String, limit: Int = 12) -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        let files: [URL]
        if bundleID == "com.apple.finder" {
            files = ["sfl4", "sfl3", "sfl2"].map {
                base.appendingPathComponent("com.apple.LSSharedFileList.RecentDocuments.\($0)")
            }
        } else {
            let dir = base.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
            files = ["sfl4", "sfl3", "sfl2"].map { dir.appendingPathComponent("\(bundleID.lowercased()).\($0)") }
        }
        guard let file = files.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: file) else { return [] }
        guard let items = sharedFileListItems(in: data) else { return [] }
        var result: [URL] = []
        for item in items {
            guard let bm = item["Bookmark"] as? Data else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bm, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path),
                  !result.contains(url) else { continue }
            if bundleID == "com.apple.dt.Xcode", !xcodeProjectExtensions.contains(url.pathExtension.lowercased()) { continue }
            result.append(url)
            if result.count >= limit { break }
        }
        return result
    }

    private static func sharedFileListItems(in data: Data) -> [[String: Any]]? {
        let root: Any?
        if let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSData.self, NSNumber.self, NSUUID.self, NSDate.self],
            from: data) {
            root = decoded
        } else if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            unarchiver.requiresSecureCoding = false
            root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        } else {
            root = nil
        }
        let items: Any?
        if let dict = root as? [String: Any] {
            items = dict["items"]
        } else if let dict = root as? NSDictionary {
            items = dict["items"]
        } else {
            items = nil
        }
        if let list = items as? [[String: Any]] { return list }
        if let list = items as? NSArray {
            return list.compactMap { entry in
                if let dict = entry as? [String: Any] { return dict }
                guard let dict = entry as? NSDictionary else { return nil }
                var bridged: [String: Any] = [:]
                for (key, value) in dict {
                    guard let key = key as? String else { continue }
                    bridged[key] = value
                }
                return bridged
            }
        }
        return nil
    }
}


// MARK: - Several apps per launcher

extension WidgetInstance {
    /// Apps of a launcher widget (older versions stored a single app under "app").
    var launcherApps: [String] {
        let list = (config["apps"] ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !list.isEmpty || config["apps"] != nil { return list }
        let single = cfg("app")
        return single.isEmpty ? [] : [single]
    }

    func pinnedFiles(for app: String) -> [String] {
        if let v = config["files|" + app] {
            return v.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if app == config["app"] {
            return cfg("files").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }

    func fileCount(for app: String) -> Int {
        let fallback = min(max(Int(cfg("fileCount", "10")) ?? 10, 1), 50)
        return min(max(Int(config["fileCount|" + app] ?? "") ?? fallback, 1), 50)
    }
}

enum LauncherStore {
    static func setApps(_ id: UUID, _ apps: [String]) {
        var seen = Set<String>()
        DockStore.shared.setConfig(id, "apps", apps.filter { seen.insert($0).inserted }.joined(separator: "\n"))
    }

    static func insertApp(_ id: UUID, _ path: String, before target: String) {
        guard path != target, let apps = DockStore.shared.instance(id)?.launcherApps else { return }
        insertApp(id, path, at: apps.firstIndex(of: target) ?? apps.count)
    }

    static func insertApp(_ id: UUID, _ path: String, at index: Int) {
        guard var apps = DockStore.shared.instance(id)?.launcherApps else { return }
        apps.removeAll { $0 == path }
        apps.insert(path, at: min(max(index, 0), apps.count))
        setApps(id, apps)
    }

    static func setPinned(_ id: UUID, app: String, _ files: [String]) {
        var seen = Set<String>()
        DockStore.shared.setConfig(id, "files|" + app, files.filter { seen.insert($0).inserted }.joined(separator: "\n"))
    }

    static func pickApps(_ w: WidgetInstance) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { setApps(w.id, w.launcherApps + panel.urls.map(\.path)) }
    }
}

struct AppChoice: Identifiable { let path: String; var id: String { path } }

struct LauncherWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var picker: AppChoice?
    @State private var targeted = false

    private var apps: [String] { w.launcherApps }

    var body: some View {
        let list = apps
        let capacity = w.size == 1 ? 4 : (w.size == 2 ? 2 : 3)
        let shown = Array(list.prefix(capacity))
        Group {
            if list.isEmpty {
                Button { LauncherStore.pickApps(w) } label: {
                    VStack(spacing: 2 * s) {
                        Image(systemName: "plus.app").font(.system(size: 22 * s))
                        if w.size > 1 { Text("Apps hinzufügen").font(.system(size: 10 * s)) }
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else if w.size == 1 && shown.count > 1 {
                let columns = min(2, shown.count)
                let rows = Int(ceil(Double(shown.count) / Double(columns)))
                Grid(horizontalSpacing: 3 * s, verticalSpacing: 3 * s) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                slot(shown[safe: row * columns + column], icon: 22)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 3 * s) {
                    ForEach(shown, id: \.self) { app in
                        slot(app, icon: w.size == 1 ? 44 : (w.size == 2 ? 34 : 38))
                    }
                    if w.size > 1 {
                        Button { LauncherStore.pickApps(w) } label: {
                            Image(systemName: "plus").font(.system(size: 12 * s, weight: .bold))
                                .frame(width: 24 * s, height: 24 * s)
                                .background(Circle().fill(Theme.tileHi))
                        }
                        .buttonStyle(.plain)
                        .help("Weitere App hinzufügen")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14 * s).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .onDrop(of: [.fileURL], delegate: LauncherAppDropDelegate(
            id: w.id, apps: list, capacity: capacity, size: w.size, scale: s, targeted: $targeted
        ))
        .onWidgetAction(w.id) { a in
            if a == "pickApp" { LauncherStore.pickApps(w) }
            else if a.hasPrefix("list:") { picker = AppChoice(path: String(a.dropFirst(5))) }
        }
        .popover(item: $picker, arrowEdge: .top) { choice in
            LauncherPicker(w: w, app: choice.path) { picker = nil }
        }
    }

    @ViewBuilder private func slot(_ app: String?, icon: CGFloat) -> some View {
        if let app {
            AppSlot(w: w, app: app, icon: icon * s, showName: w.size > 1 && apps.count <= w.size)
        } else {
            Color.clear.frame(width: icon * s, height: icon * s)
        }
    }
}

private struct LauncherAppDropDelegate: DropDelegate {
    let id: UUID
    let apps: [String]
    let capacity: Int
    let size: Int
    let scale: CGFloat
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let index = insertionIndex(at: info.location)
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL, url.pathExtension.lowercased() == "app" else { return }
                DispatchQueue.main.async {
                    LauncherStore.insertApp(id, url.standardizedFileURL.path, at: index)
                }
            }
        }
        targeted = false
        return true
    }

    private func insertionIndex(at location: CGPoint) -> Int {
        guard !apps.isEmpty else { return 0 }
        let width = DockStore.shared.width(for: size)
        let height = DockStore.shared.unit
        let slot: Int
        if size == 1 && apps.count > 1 {
            let column = location.x >= width / 2 ? 1 : 0
            let row = location.y >= height / 2 ? 1 : 0
            slot = row * 2 + column
        } else {
            let availableWidth = max(width, 1)
            let x = min(max(location.x, 0), availableWidth)
            slot = Int(x / availableWidth * CGFloat(capacity))
        }
        let lastVisibleSlot = apps.count >= capacity ? max(capacity - 1, 0) : apps.count
        return min(max(slot, 0), lastVisibleSlot)
    }
}

/// One app inside the launcher: click opens, hover unrolls its projects, files dropped on it are pinned to it.
struct AppSlot: View {
    let w: WidgetInstance
    let app: String
    let icon: CGFloat
    let showName: Bool
    @State private var targeted = false
    @State private var showFiles = false

    private var name: String { FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "") }
    private var opensFolder: Bool {
        AppLauncher.isForkLift(app) && w.cfg("forkLiftMode", "app") == "folder"
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(nsImage: fileIcon(app)).resizable().frame(width: icon, height: icon)
                .scaleEffect(targeted ? 1.12 : 1)
            if showName {
                Text(name).font(.system(size: 9)).lineLimit(1).frame(maxWidth: icon)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if opensFolder {
                HoverPanel.shared.close()
                showFiles = true
            }
            else if AppLauncher.isSafari(app) { AppLauncher.promptSafariSearch(app: app) }
            else { AppLauncher.open(app: app) }
        }
        .gesture(TapGesture().modifiers(.option).onEnded {
            AppLauncher.open(app: app, newInstance: true)
        })
        .contextMenu {
            Button("Neue Instanz öffnen") {
                AppLauncher.open(app: app, newInstance: true)
            }
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app)])
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        if url.pathExtension.lowercased() == "app" { LauncherStore.insertApp(w.id, url.path, before: app) }
                        else { LauncherStore.setPinned(w.id, app: app, w.pinnedFiles(for: app) + [url.path]) }
                    }
                }
            }
            return true
        }
        .hoverUnroll(key: w.id.uuidString + app, width: 360) { AnyView(LauncherHoverList(w: w, app: app)) }
        .popover(isPresented: $showFiles, arrowEdge: .top) {
            LauncherPicker(w: w, app: app) { showFiles = false }
        }
    }
}

/// Large chooser: pinned and recent documents of one app, several can be opened at once.
struct LauncherPicker: View {
    let w: WidgetInstance
    let app: String
    let close: () -> Void
    @State private var recent: [URL] = []
    @State private var selection = Set<String>()
    @State private var filter = ""
    @State private var directoryFiles: [URL] = []

    private var pinned: [String] { DockStore.shared.instance(w.id)?.pinnedFiles(for: app) ?? w.pinnedFiles(for: app) }
    private var name: String { FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "") }
    private var limit: Int { w.fileCount(for: app) }
    private var showsFolder: Bool { AppLauncher.isForkLift(app) && w.cfg("forkLiftMode", "app") == "folder" }
    private var forkLiftFolder: String { (w.cfg("forkLiftFolder") as NSString).expandingTildeInPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: fileIcon(app)).resizable().frame(width: 32, height: 32)
                Text(name).font(.title3.weight(.semibold))
                Spacer()
                Button("Nur App öffnen") { AppLauncher.open(app: app); close() }.controlSize(.large)
            }
            .padding(14)
            TextField("Filtern …", text: $filter).textFieldStyle(.roundedBorder).controlSize(.large)
                .padding(.horizontal, 14).padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if showsFolder {
                        title("Verzeichnis: \(forkLiftFolder.isEmpty ? "nicht ausgewählt" : forkLiftFolder)")
                        if forkLiftFolder.isEmpty {
                            Text("Wähle in den Widget-Einstellungen ein Verzeichnis aus.").foregroundStyle(.secondary).padding(14)
                        } else if directoryFiles.isEmpty {
                            Text("Keine Dateien in diesem Verzeichnis.").foregroundStyle(.secondary).padding(14)
                        }
                        ForEach(directoryFiles.map(\.path).filter(matches).prefix(limit), id: \.self) { row($0, pinnedRow: false) }
                    } else {
                        let pins = pinned.filter(matches).prefix(limit)
                        let recents = recent.map(\.path).filter { !pinned.contains($0) }.filter(matches)
                        if !pins.isEmpty { title("Angeheftet"); ForEach(pins, id: \.self) { row($0, pinnedRow: true) } }
                        if !recents.isEmpty { title("Zuletzt verwendet"); ForEach(recents.prefix(limit), id: \.self) { row($0, pinnedRow: false) } }
                    }
                    if (showsFolder && directoryFiles.isEmpty) || (!showsFolder && pinned.isEmpty && recent.isEmpty) {
                        if !showsFolder {
                        Text("Keine Dateien. Zieh Dateien auf das App-Symbol im Widget.").foregroundStyle(.secondary).padding(14)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 300, maxHeight: 520)
            Divider()
            HStack {
                Button("Aus Starter entfernen", role: .destructive) {
                    LauncherStore.setApps(w.id, w.launcherApps.filter { $0 != app })
                    close()
                }
                Spacer()
                Button("\(selection.count) öffnen") { AppLauncher.open(app: app, files: Array(selection)); close() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(selection.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 640)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Bundle(path: app).map { AppLauncher.recentDocuments(bundleID: $0.bundleIdentifier ?? "", limit: limit) } ?? []
                let files: [URL]
                if showsFolder, !forkLiftFolder.isEmpty {
                    files = (try? FileManager.default.contentsOfDirectory(
                        at: URL(fileURLWithPath: forkLiftFolder, isDirectory: true),
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ))?.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
                } else {
                    files = []
                }
                DispatchQueue.main.async {
                    recent = r
                    directoryFiles = files
                }
            }
        }
    }

    private func matches(_ p: String) -> Bool { filter.isEmpty || p.localizedCaseInsensitiveContains(filter) }

    private func title(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 10)
    }

    private func row(_ path: String, pinnedRow: Bool) -> some View {
        let on = selection.contains(path)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { on }, set: { if $0 { selection.insert(path) } else { selection.remove(path) } }))
                .labelsHidden().toggleStyle(.checkbox).controlSize(.large)
            Image(nsImage: fileIcon(path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent).font(.body.weight(.medium)).lineLimit(1)
                Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button {
                let l = pinned
                LauncherStore.setPinned(w.id, app: app, pinnedRow ? l.filter { $0 != path } : l + [path])
            } label: { Image(systemName: pinnedRow ? "pin.slash" : "pin") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor.opacity(0.15) : .clear).padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { AppLauncher.open(app: app, files: [path]); close() }
        .onTapGesture { if on { selection.remove(path) } else { selection.insert(path) } }
    }
}
