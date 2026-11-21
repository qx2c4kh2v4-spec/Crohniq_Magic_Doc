import SwiftUI

struct FinderWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s

    private let finderPath = "/System/Library/CoreServices/Finder.app"
    private let home = NSHomeDirectory()
    private let downloads = NSHomeDirectory() + "/Downloads"

    var body: some View {
        HStack(spacing: 8 * s) {
            Button { open(home) } label: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: finderPath))
                    .resizable()
                    .frame(width: 36 * s, height: 36 * s)
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
        .tilePadding(s)
        .onWidgetAction(w.id) { action in
            if action == "open" { open(home) }
        }
    }

    private func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
