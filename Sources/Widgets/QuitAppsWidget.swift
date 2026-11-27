import SwiftUI

/// Lists running apps; quit normally (apps may ask to save) or force-quit (immediately, unsaved changes are lost).
final class RunningApps: ObservableObject {
    static let shared = RunningApps()
    @Published private(set) var apps: [NSRunningApplication] = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        reload()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        }
    }

    func reload() {
        let own = Bundle.main.bundleIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    /// Brings a running app to the front like a click in the system Dock: unhides it and, via a reopen,
    /// restores a minimised window or opens a new one if the app has none.
    func bringToFront(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        guard let url = app.bundleURL else { app.activate(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if error != nil { DispatchQueue.main.async { app.activate() } }
        }
    }

    func quit(_ list: [NSRunningApplication], force: Bool) {
        for app in list {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.reload() }
    }
}

/// Right-click menu for a running app that is not a menu-bar-only item.
struct RunningAppActions: View {
    let app: NSRunningApplication
    @ObservedObject private var running = RunningApps.shared
    @ObservedObject private var workspaces = WorkspaceManager.shared
    @ObservedObject private var store = DockStore.shared

    private var path: String? { app.bundleURL?.path }
    private var appName: String {
        app.localizedName ?? path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "App"
    }

    var body: some View {
        Text(appName)
        Button("Beenden") { running.quit([app], force: false) }
        Button("Sofort beenden") { running.quit([app], force: true) }
        Divider()
        Button("Ausblenden") { app.hide() }
        Button("Nach vorne holen") { running.bringToFront(app) }
        Divider()
        if workspaces.workspaces.isEmpty {
            Button("Arbeitsbereich anlegen …") { AppDelegate.shared.openSettings(page: .workspaces) }
        } else {
            Menu("Als Widget an Arbeitsbereich") {
                ForEach(workspaces.workspaces) { workspace in
                    let attached = path.map { store.launcherShows(appPath: $0, in: workspace.id) } ?? true
                    Button {
                        guard let path else { return }
                        store.pinAppAsWidget(path: path, name: appName, workspaceID: workspace.id)
                    } label: {
                        if attached {
                            Label("\(workspace.name) · schon angehängt", systemImage: workspace.symbol)
                        } else {
                            Label(workspace.name, systemImage: workspace.symbol)
                        }
                    }
                    .disabled(attached || path == nil)
                }
            }
        }
    }
}

struct QuitAppsWidget: View {
    let w: WidgetInstance
    @ObservedObject private var running = RunningApps.shared
    @Environment(\.dockScale) private var s
    @State private var open = false
    @State private var selection = Set<pid_t>()
    @State private var confirmForce = false

    var body: some View {
        HStack(spacing: 6 * s) {
            Button { openList() } label: {
                VStack(spacing: 2 * s) {
                    Image(systemName: "xmark.app.fill").font(.system(size: 20 * s)).foregroundStyle(.red.opacity(0.9))
                    Text("\(running.apps.count) offen").font(.system(size: 9 * s)).foregroundStyle(Theme.secondary)
                }
                .frame(width: 52 * s)
            }
            .buttonStyle(.plain)
            .help("Apps beenden …")

            if w.size >= 2 {
                ForEach(running.apps.prefix(w.size * 2 - 2), id: \.processIdentifier) { app in
                    Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 32 * s, height: 32 * s)
                        .contentShape(Rectangle())
                        .onTapGesture { running.bringToFront(app) }
                        .contextMenu { RunningAppActions(app: app) }
                        .help("\(app.localizedName ?? ""): klicken holt die App nach vorne, Rechtsklick zum Beenden")
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .popover(isPresented: $open, arrowEdge: .top) { list }
    }

    private func openList() {
        running.reload()
        selection = []
        open = true
    }

    private var selectedApps: [NSRunningApplication] {
        running.apps.filter { selection.contains($0.processIdentifier) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apps beenden").font(.title3.weight(.semibold))
                Spacer()
                Button("Alle") { selection = Set(running.apps.map(\.processIdentifier)) }
                Button("Keine") { selection = [] }
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(running.apps, id: \.processIdentifier) { app in
                        let on = selection.contains(app.processIdentifier)
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { on }, set: { v in
                                if v { selection.insert(app.processIdentifier) } else { selection.remove(app.processIdentifier) }
                            }))
                            .labelsHidden().toggleStyle(.checkbox).controlSize(.large)
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 28, height: 28)
                            Text(app.localizedName ?? "App").font(.body.weight(.medium))
                            if app.isHidden { Text("ausgeblendet").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Beenden") { running.quit([app], force: false) }.controlSize(.small)
                            Button("Hart") { running.quit([app], force: true) }.controlSize(.small).tint(.red)
                                .help("Sofort beenden – ungesicherte Änderungen gehen verloren")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(on ? Color.accentColor.opacity(0.12) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if on { selection.remove(app.processIdentifier) } else { selection.insert(app.processIdentifier) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 260, maxHeight: 480)
            Divider()
            HStack {
                Text("\(selection.count) ausgewählt").foregroundStyle(.secondary)
                Spacer()
                Button("Beenden") {
                    running.quit(selectedApps, force: false)
                    selection = []
                }
                .disabled(selection.isEmpty)
                .controlSize(.large)
                Button("Sofort beenden (hart)") { confirmForce = true }
                    .disabled(selection.isEmpty)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(14)
        }
        .frame(width: 520)
        .confirmationDialog("\(selection.count) Apps sofort beenden?", isPresented: $confirmForce) {
            Button("Sofort beenden", role: .destructive) {
                running.quit(selectedApps, force: true)
                selection = []
            }
        } message: {
            Text("Ungesicherte Änderungen in diesen Apps gehen verloren.")
        }
    }
}
