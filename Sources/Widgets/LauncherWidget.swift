import SwiftUI
import UniformTypeIdentifiers

/// Opens apps, optionally with documents, and reads the app's recent documents list.
enum AppLauncher {
    static func open(app: String, files: [String] = []) {
        let appURL = URL(fileURLWithPath: app)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        let urls = files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg)
        }
    }

    /// Recent documents macOS keeps per app (e.g. Xcode projects, Pages files).
    static func recentDocuments(bundleID: String, limit: Int = 12) -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments")
        let candidates = ["sfl4", "sfl3", "sfl2"].map { base.appendingPathComponent("\(bundleID.lowercased()).\($0)") }
        guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: file) else { return [] }
        let root: Any?
        if let r = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSData.self, NSNumber.self, NSUUID.self, NSDate.self],
            from: data) {
            root = r
        } else if let u = try? NSKeyedUnarchiver(forReadingFrom: data) {
            u.requiresSecureCoding = false
            root = u.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        } else {
            root = nil
        }
        guard let dict = root as? [String: Any], let items = dict["items"] as? [[String: Any]] else { return [] }
        var result: [URL] = []
        for item in items {
            guard let bm = item["Bookmark"] as? Data else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bm, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path), !result.contains(url) {
                result.append(url)
                if result.count >= limit { break }
            }
        }
        return result
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
}

enum LauncherStore {
    static func setApps(_ id: UUID, _ apps: [String]) {
        var seen = Set<String>()
        DockStore.shared.setConfig(id, "apps", apps.filter { seen.insert($0).inserted }.joined(separator: "\n"))
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
        let capacity = w.size == 1 ? 4 : w.size * 2
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
                Grid(horizontalSpacing: 4 * s, verticalSpacing: 4 * s) {
                    GridRow { slot(shown[safe: 0], icon: 22); slot(shown[safe: 1], icon: 22) }
                    GridRow { slot(shown[safe: 2], icon: 22); slot(shown[safe: 3], icon: 22) }
                }
            } else {
                HStack(spacing: 6 * s) {
                    ForEach(shown, id: \.self) { app in slot(app, icon: w.size == 1 ? 44 : 38) }
                    if w.size > 1 && list.count < capacity {
                        Button { LauncherStore.pickApps(w) } label: {
                            Image(systemName: "plus").font(.system(size: 12 * s, weight: .bold))
                                .frame(width: 26 * s, height: 26 * s)
                                .background(Circle().fill(Theme.tileHi))
                        }
                        .buttonStyle(.plain)
                        .help("Weitere App hinzufügen")
                    }
                }
            }
        }
        .padding(6 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14 * s).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension == "app" else { return }
                    DispatchQueue.main.async { LauncherStore.setApps(w.id, w.launcherApps + [url.path]) }
                }
            }
            return true
        }
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

/// One app inside the launcher: click opens, hover unrolls its projects, files dropped on it are pinned to it.
struct AppSlot: View {
    let w: WidgetInstance
    let app: String
    let icon: CGFloat
    let showName: Bool
    @State private var targeted = false

    private var name: String { FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "") }

    var body: some View {
        VStack(spacing: 1) {
            Image(nsImage: fileIcon(app)).resizable().frame(width: icon, height: icon)
                .scaleEffect(targeted ? 1.12 : 1)
            if showName {
                Text(name).font(.system(size: 9)).lineLimit(1).frame(maxWidth: icon + 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { AppLauncher.open(app: app) }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        if url.pathExtension == "app" { LauncherStore.setApps(w.id, w.launcherApps + [url.path]) }
                        else { LauncherStore.setPinned(w.id, app: app, w.pinnedFiles(for: app) + [url.path]) }
                    }
                }
            }
            return true
        }
        .hoverUnroll(key: w.id.uuidString + app, width: 360) { AnyView(LauncherHoverList(w: w, app: app)) }
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

    private var pinned: [String] { DockStore.shared.instance(w.id)?.pinnedFiles(for: app) ?? w.pinnedFiles(for: app) }
    private var name: String { FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "") }

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
                    let pins = pinned.filter(matches)
                    let recents = recent.map(\.path).filter { !pinned.contains($0) }.filter(matches)
                    if !pins.isEmpty { title("Angeheftet"); ForEach(pins, id: \.self) { row($0, pinnedRow: true) } }
                    if !recents.isEmpty { title("Zuletzt verwendet"); ForEach(recents, id: \.self) { row($0, pinnedRow: false) } }
                    if pins.isEmpty && recents.isEmpty {
                        Text("Keine Dateien. Zieh Dateien auf das App-Symbol im Widget.").foregroundStyle(.secondary).padding(14)
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
            guard let bid = Bundle(path: app)?.bundleIdentifier else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let r = AppLauncher.recentDocuments(bundleID: bid, limit: 40)
                DispatchQueue.main.async { recent = r }
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
