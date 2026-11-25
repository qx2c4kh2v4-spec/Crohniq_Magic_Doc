import SwiftUI

enum DropboxFiles {
    static func latest(in folder: URL, limit: Int) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let dated = try urls.map { url -> (URL, Date) in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values.contentModificationDate ?? .distantPast)
        }
        return Array(dated.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }
}

struct FinderWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s

    private let finderPath = "/System/Library/CoreServices/Finder.app"
    private let home = NSHomeDirectory()
    private let downloads = NSHomeDirectory() + "/Downloads"

    var body: some View {
        HStack(spacing: 8 * s) {
            Button { open(home) } label: {
                let icon = (w.isAppIcon ? DockStore.launcherIcon(size: 1, showsName: false) : 36) * s
                Image(nsImage: NSWorkspace.shared.icon(forFile: finderPath))
                    .resizable()
                    .frame(width: icon, height: icon)
            }
            .buttonStyle(.plain)
            .help("Finder öffnen")

            if w.size > 1 {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("Finder").font(.system(size: 12 * s, weight: .semibold))
                    Text("Dateien & Ordner").font(.system(size: 9 * s)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                CircleButton(symbol: "house.fill", size: 26) { open(home) }
                    .help("Benutzerordner")
                if w.size >= 3 {
                    CircleButton(symbol: "arrow.down.circle.fill", size: 26) { open(downloads) }
                        .help("Downloads")
                }
            }
        }
        .modifier(TilePaddingUnlessIcon(isIcon: w.isAppIcon, s: s))
        .onWidgetAction(w.id) { action in
            if action == "open" { open(home) }
        }
    }

    private func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}

struct DropboxWidget: View {
        let w: WidgetInstance
        @Environment(\.dockScale) private var s
        @State private var files: [URL] = []
        @State private var loadError: String?

        private var folderPath: String {
            (w.cfg("folder") as NSString).expandingTildeInPath
        }

        private var folderURL: URL {
            URL(fileURLWithPath: folderPath, isDirectory: true)
        }

        private var fileLimit: Int {
            min(max(w.cfgInt("count", 5), 1), 50)
        }

        var body: some View {
            Group {
                if w.size == 1 {
                    Button { open(folderURL) } label: {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 24 * s, weight: .medium))
                            .foregroundStyle(Color.blue)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(files.count)")
                                    .font(.system(size: 8 * s, weight: .bold))
                                    .foregroundStyle(Theme.fg)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Dropbox-Ordner öffnen")
                } else {
                    HStack(spacing: 8 * s) {
                        Button { open(folderURL) } label: {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 23 * s, weight: .medium))
                                .foregroundStyle(Color.blue)
                                .frame(width: 38 * s, height: 38 * s)
                        }
                        .buttonStyle(.plain)
                        .help("Dropbox-Ordner öffnen")

                        VStack(alignment: .leading, spacing: 3 * s) {
                            Text("Dropbox").font(.system(size: 12 * s, weight: .semibold))
                            if let loadError {
                                Text(loadError).font(.system(size: 9 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
                            } else {
                                Text("\(files.count) aktuelle Einträge")
                                    .font(.system(size: 9 * s)).foregroundStyle(Theme.secondary)
                            }
                            if w.size >= 3 {
                                ForEach(files.prefix(2), id: \.path) { file in
                                    Button { open(file) } label: {
                                        Label(file.lastPathComponent, systemImage: file.hasDirectoryPath ? "folder" : "doc")
                                            .font(.system(size: 9 * s))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        if !FileManager.default.fileExists(atPath: folderPath) {
                            Button {
                                AppDelegate.shared.openSettings(selecting: w.id)
                            } label: {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 15 * s, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help("Dropbox-Ordner auswählen")
                        }
                    }
                    .tilePadding(s)
                }
            }
            .task(id: folderPath) {
                while !Task.isCancelled {
                    refreshFiles()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onWidgetAction(w.id) { action in
                if action == "open" { open(folderURL) }
            }
        }

        private func refreshFiles() {
            do {
                files = try DropboxFiles.latest(in: folderURL, limit: fileLimit)
                loadError = nil
            } catch {
                files = []
                loadError = FileManager.default.fileExists(atPath: folderPath) ? "Zugriff nicht möglich" : "Ordner fehlt"
            }
        }

        private func open(_ url: URL) {
            NSWorkspace.shared.open(url)
        }
}

struct DropboxHoverList: View {
            let w: WidgetInstance
            @State private var files: [URL] = []
            @State private var error: String?

            private var folderPath: String { (w.cfg("folder") as NSString).expandingTildeInPath }
            private var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
            private var count: Int { min(max(w.cfgInt("count", 5), 1), 50) }

            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Dropbox · zuletzt geändert", systemImage: "shippingbox")
                            .font(.headline)
                        Spacer()
                        Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain)
                            .help("Dropbox-Dateien aktualisieren")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(Theme.secondary)
                    } else if files.isEmpty {
                        Text("Keine Dateien im Dropbox-Verzeichnis.").font(.callout).foregroundStyle(Theme.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(files, id: \.path) { file in
                                    Button { NSWorkspace.shared.open(file) } label: {
                                        Label(file.lastPathComponent, systemImage: file.hasDirectoryPath ? "folder" : "doc")
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                    Button("Dropbox-Ordner öffnen") { NSWorkspace.shared.open(folderURL) }
                        .buttonStyle(.plain)
                }
                .padding(12)
                .frame(width: 320)
                .task { refresh() }
            }

            private func refresh() {
                do {
                    files = try DropboxFiles.latest(in: folderURL, limit: count)
                    error = nil
                } catch {
                    files = []
                    self.error = FileManager.default.fileExists(atPath: folderPath)
                        ? "Dropbox-Verzeichnis kann nicht gelesen werden."
                        : "Dropbox-Verzeichnis fehlt. Bitte in den Widget-Einstellungen auswählen."
                }
            }
        }
