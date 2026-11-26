import SwiftUI

// MARK: - Safari bookmarks

struct BookmarkNode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL?
    let children: [BookmarkNode]
    var isFolder: Bool { url == nil }

    var allLeaves: [BookmarkNode] { isFolder ? children.flatMap(\.allLeaves) : [self] }
}

final class SafariBookmarks: ObservableObject {
    static let shared = SafariBookmarks()

    @Published private(set) var bar: [BookmarkNode] = []
    @Published private(set) var folders: [BookmarkNode] = []      // other top-level folders
    @Published private(set) var readingList: [BookmarkNode] = []
    @Published private(set) var accessDenied = false
    @Published private(set) var favicons: [String: NSImage] = [:]

    #if FULL_EDITION
    private let path = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
    #endif
    private var lastModified: Date?
    private var timer: Timer?
    private var loadingIcons = Set<String>()

    private init() {
        guard Edition.readsOtherAppsData else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.reload() }
    }

    func reload() {
        #if FULL_EDITION
        let mod = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if mod != nil, mod == lastModified, !accessDenied { return }
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            accessDenied = true
            return
        }
        accessDenied = false
        lastModified = mod
        var bar: [BookmarkNode] = [], folders: [BookmarkNode] = [], reading: [BookmarkNode] = []
        for child in root["Children"] as? [[String: Any]] ?? [] {
            let title = child["Title"] as? String ?? ""
            switch title {
            case "BookmarksBar": bar = Self.parseChildren(child)
            case "com.apple.ReadingList": reading = Self.parseChildren(child)
            case "BookmarksMenu":
                folders += Self.parseChildren(child)
            default:
                if let node = Self.parse(child) { folders.append(node) }
            }
        }
        self.bar = bar
        self.folders = folders
        self.readingList = reading
        #endif
    }

    private static func parseChildren(_ dict: [String: Any]) -> [BookmarkNode] {
        (dict["Children"] as? [[String: Any]] ?? []).compactMap(parse)
    }

    private static func parse(_ dict: [String: Any]) -> BookmarkNode? {
        switch dict["WebBookmarkType"] as? String {
        case "WebBookmarkTypeLeaf":
            guard let s = dict["URLString"] as? String, let url = URL(string: s) else { return nil }
            let title = (dict["URIDictionary"] as? [String: Any])?["title"] as? String ?? url.host ?? s
            return BookmarkNode(title: title, url: url, children: [])
        case "WebBookmarkTypeList":
            let title = dict["Title"] as? String ?? "Ordner"
            return BookmarkNode(title: title, url: nil, children: parseChildren(dict))
        default:
            return nil
        }
    }

    func favicon(for url: URL) -> NSImage? {
        guard let host = url.host else { return nil }
        if let img = favicons[host] { return img }
        if !loadingIcons.contains(host), let scheme = url.scheme, scheme.hasPrefix("http") {
            loadingIcons.insert(host)
            Task {
                var img: NSImage?
                for candidate in ["\(scheme)://\(host)/apple-touch-icon.png", "\(scheme)://\(host)/favicon.ico"] {
                    if let u = URL(string: candidate),
                       let (data, resp) = try? await URLSession.shared.data(from: u),
                       (resp as? HTTPURLResponse)?.statusCode == 200, let i = NSImage(data: data), i.isValid {
                        img = i
                        break
                    }
                }
                if let img { await MainActor.run { self.favicons[host] = img } }
            }
        }
        return nil
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

struct BookmarksWidget: View {
    let w: WidgetInstance
    @ObservedObject private var safari = SafariBookmarks.shared
    @Environment(\.dockScale) private var s

    private var useSafari: Bool { Edition.readsOtherAppsData && w.cfg("source", "safari") == "safari" }

    private var customItems: [BookmarkNode] {
        w.cfg("items").split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let u = URL(string: parts[1]) else { return nil }
            return BookmarkNode(title: parts[0], url: u, children: [])
        }
    }

    /// Links shown as icons on the tile.
    private var quick: [BookmarkNode] {
        guard useSafari else { return customItems }
        let folder = w.cfg("folder")
        if !folder.isEmpty,
           let f = (safari.bar + safari.folders).first(where: { $0.isFolder && $0.title == folder }) {
            return f.children.filter { !$0.isFolder }
        }
        return safari.bar.filter { !$0.isFolder }
    }

    var body: some View {
        let size = (w.size == 1 ? 20 : 26) * s
        let capacity = w.size == 1 ? 3 : w.size * 2 + 1
        HStack(spacing: 6 * s) {
            if useSafari && safari.accessDenied {
                Button {
                    SafariBookmarks.openFullDiskAccessSettings()
                } label: {
                    VStack(spacing: 2 * s) {
                        Image(systemName: "lock.shield").font(.system(size: 16 * s))
                        if w.size > 1 { Text("Festplattenvollzugriff erlauben").font(.system(size: 9 * s)).multilineTextAlignment(.center) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help("Safari-Lesezeichen brauchen Festplattenvollzugriff für Crohniq Dock")
            } else {
                let items = Array(quick.prefix(capacity))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 6 * s),
                                         count: max(1, w.size == 1 ? 2 : Int(ceil(Double(items.count + 1) / 2)))),
                          spacing: 6 * s) {
                    ForEach(items) { item in
                        BookmarkIcon(node: item, size: size)
                    }
                    allMenu(size: size)
                }
            }
        }
        .padding(6 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func allMenu(size: CGFloat) -> some View {
        Menu {
            if useSafari {
                Section("Favoriten") { ForEach(safari.bar) { BookmarkMenuItem(node: $0) } }
                if !safari.folders.isEmpty {
                    Section("Lesezeichen") { ForEach(safari.folders) { BookmarkMenuItem(node: $0) } }
                }
                if !safari.readingList.isEmpty {
                    Menu("Leseliste (\(safari.readingList.count))") {
                        ForEach(safari.readingList) { BookmarkMenuItem(node: $0) }
                    }
                }
                Divider()
                Button("Safari öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app")) }
            } else {
                ForEach(customItems) { BookmarkMenuItem(node: $0) }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.42, weight: .bold))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.28).fill(Theme.tileHi))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Alle Lesezeichen")
    }
}

struct BookmarkMenuItem: View {
    let node: BookmarkNode

    var body: some View {
        if node.isFolder {
            Menu(node.title) {
                ForEach(node.children) { BookmarkMenuItem(node: $0) }
                if node.allLeaves.count > 1 {
                    Divider()
                    Button("Alle in Tabs öffnen") { node.allLeaves.compactMap(\.url).forEach { NSWorkspace.shared.open($0) } }
                }
            }
        } else if let url = node.url {
            Button(node.title) { NSWorkspace.shared.open(url) }
        }
    }
}

struct BookmarkIcon: View {
    let node: BookmarkNode
    let size: CGFloat
    @ObservedObject private var safari = SafariBookmarks.shared

    var body: some View {
        Group {
            if let url = node.url, let icon = safari.favicons[url.host ?? ""] ?? safari.favicon(for: url) {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.28).fill(Color.white.opacity(0.9)))
            } else {
                Text(String(node.title.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.28).fill(color))
            }
        }
        .help("\(node.title)\n\(node.url?.absoluteString ?? "")")
        .contentShape(Rectangle())
        .onTapGesture { if let u = node.url { NSWorkspace.shared.open(u) } }
    }

    private var color: Color {
        let palette: [Color] = [.blue, .orange, .pink, .green, .purple, .red, .teal, .indigo, .mint]
        let h = node.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[h % palette.count]
    }
}
