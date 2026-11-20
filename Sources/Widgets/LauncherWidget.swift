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

struct LauncherWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var showList = false
    @State private var recent: [URL] = []
    @State private var selection = Set<String>()
    @State private var targeted = false
    @State private var filter = ""

    private var appPath: String { w.cfg("app") }
    private var pinned: [String] {
        w.cfg("files").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var appName: String {
        appPath.isEmpty ? "App wählen" : FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        HStack(spacing: 10 * s) {
            Group {
                if appPath.isEmpty {
                    Image(systemName: "plus.app").font(.system(size: 26 * s)).foregroundStyle(Theme.secondary)
                } else {
                    Image(nsImage: fileIcon(appPath)).resizable().frame(width: 44 * s, height: 44 * s)
                }
            }
            .onTapGesture { appPath.isEmpty ? pickApp() : primaryAction() }
            .help(pinned.isEmpty ? "\(appName) öffnen" : "\(appName) – Dateien wählen")

            if w.size >= 2 {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(appName).font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                    let rows = Array(pinned.prefix(w.size >= 3 ? 3 : 2))
                    if rows.isEmpty {
                        Text("Klick öffnet · ▾ zuletzt").font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                    }
                    ForEach(rows, id: \.self) { path in
                        Button { AppLauncher.open(app: appPath, files: [path]) } label: {
                            HStack(spacing: 4 * s) {
                                Image(nsImage: fileIcon(path)).resizable().frame(width: 12 * s, height: 12 * s)
                                Text(displayName(path)).font(.system(size: 10 * s)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.fg.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }
            if !appPath.isEmpty && w.size >= 2 {
                Button { openList() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11 * s, weight: .bold))
                        .frame(width: 22 * s, height: 22 * s).background(Circle().fill(Theme.tileHi))
                }
                .buttonStyle(.plain)
                .help("Dateien & zuletzt verwendete Dokumente")
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14 * s).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: handleDrop)
        .onWidgetAction(w.id) { a in
            if a == "pickApp" { pickApp() } else if a == "pickFiles" { pickFiles() } else if a == "list" { openList() }
        }
        .popover(isPresented: $showList, arrowEdge: .top) { listPopover }
    }

    private func primaryAction() {
        if pinned.isEmpty || w.size >= 2 { AppLauncher.open(app: appPath) } else { openList() }
    }

    private func openList() {
        selection = []
        filter = ""
        if let bid = Bundle(path: appPath)?.bundleIdentifier {
            DispatchQueue.global(qos: .userInitiated).async {
                let r = AppLauncher.recentDocuments(bundleID: bid, limit: 40)
                DispatchQueue.main.async { recent = r.filter { !pinned.contains($0.path) } }
            }
        }
        showList = true
    }

    private var listPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: fileIcon(appPath)).resizable().frame(width: 32, height: 32)
                Text(appName).font(.title3.weight(.semibold))
                Spacer()
                Button("Nur App öffnen") { AppLauncher.open(app: appPath); showList = false }
                    .controlSize(.large)
            }
            .padding(14)
            TextField("Filtern …", text: $filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let pins = pinned.filter(matches)
                    let recents = recent.map(\.path).filter(matches)
                    if !pins.isEmpty {
                        sectionTitle("Angeheftet")
                        ForEach(pins, id: \.self) { fileRow($0, pinnedRow: true) }
                    }
                    if !recents.isEmpty {
                        sectionTitle("Zuletzt verwendet")
                        ForEach(recents, id: \.self) { fileRow($0, pinnedRow: false) }
                    }
                    if pinned.isEmpty && recent.isEmpty {
                        Text("Keine Dateien. Zieh Dateien auf das Widget oder füge sie hinzu.")
                            .foregroundStyle(.secondary).padding(10)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 300, maxHeight: 520)
            Divider()
            HStack {
                Button("Hinzufügen …", action: pickFiles)
                Spacer()
                Button("\(selection.count) öffnen") {
                    AppLauncher.open(app: appPath, files: Array(selection))
                    showList = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 640)
    }

    private func matches(_ path: String) -> Bool {
        filter.isEmpty || path.localizedCaseInsensitiveContains(filter)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
    }

    private func fileRow(_ path: String, pinnedRow: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { selection.contains(path) },
                                     set: { if $0 { selection.insert(path) } else { selection.remove(path) } }))
                .labelsHidden().toggleStyle(.checkbox).controlSize(.large)
            Image(nsImage: fileIcon(path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(path)).font(.body.weight(.medium)).lineLimit(1)
                Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button {
                if pinnedRow { setPinned(pinned.filter { $0 != path }) } else { setPinned(pinned + [path]) }
            } label: { Image(systemName: pinnedRow ? "pin.slash" : "pin") }
                .buttonStyle(.borderless)
                .help(pinnedRow ? "Lösen" : "Anheften")
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selection.contains(path) ? Color.accentColor.opacity(0.15) : .clear)
            .padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { AppLauncher.open(app: appPath, files: [path]); showList = false }
        .onTapGesture { if selection.contains(path) { selection.remove(path) } else { selection.insert(path) } }
    }

    private func displayName(_ path: String) -> String { (path as NSString).lastPathComponent }

    private func setPinned(_ l: [String]) {
        var seen = Set<String>()
        DockStore.shared.setConfig(w.id, "files", l.filter { seen.insert($0).inserted }.joined(separator: "\n"))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if url.pathExtension == "app" && appPath.isEmpty {
                        DockStore.shared.setConfig(w.id, "app", url.path)
                    } else {
                        setPinned(pinned + [url.path])
                    }
                }
            }
        }
        return true
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let u = panel.url { DockStore.shared.setConfig(w.id, "app", u.path) }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { setPinned(pinned + panel.urls.map(\.path)) }
    }
}
