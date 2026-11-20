import SwiftUI
import UniformTypeIdentifiers

/// Lower half of "In der Leiste": add widgets, or browse installed programs like the Finder.
struct AddPanel: View {
    enum Tab: String, CaseIterable { case widgets = "Widgets", programs = "Programme" }
    @State private var tab: Tab = .widgets

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            .padding(10)
            Divider()
            switch tab {
            case .widgets: CompactGallery()
            case .programs: ProgramBrowser()
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
    }
}

// MARK: - Widgets tab

struct CompactGallery: View {
    @ObservedObject private var store = DockStore.shared
    @State private var added: WidgetKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(WidgetCategory.allCases) { cat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cat.headline).font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(WidgetKind.available.filter { $0.category == cat }) { kind in
                                VStack(spacing: 3) {
                                    PreviewTile(kind: kind) { add(kind) }
                                    Text(kind.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .overlay(alignment: .bottom) {
            if let k = added {
                Label("„\(k.title)“ hinzugefügt", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
    }

    private func add(_ kind: WidgetKind) {
        store.add(kind)
        withAnimation { added = kind }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { if added == kind { added = nil } } }
    }
}

// MARK: - Programs tab (Finder-like)

final class InstalledApps: ObservableObject {
    static let shared = InstalledApps()
    struct App: Identifiable, Hashable { let path: String; let name: String; var id: String { path } }
    @Published private(set) var apps: [App] = []
    @Published private(set) var loading = false

    func load() {
        guard apps.isEmpty, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                         "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            var found: [String: App] = [:]
            func scan(_ dir: String, depth: Int) {
                guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
                for item in items where !item.hasPrefix(".") {
                    let path = (dir as NSString).appendingPathComponent(item)
                    if item.hasSuffix(".app") {
                        let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                        found[path] = App(path: path, name: name)
                    } else if depth > 0 {
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { scan(path, depth: depth - 1) }
                    }
                }
            }
            roots.forEach { scan($0, depth: 1) }
            let sorted = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.apps = sorted
                self.loading = false
            }
        }
    }
}

struct ProgramBrowser: View {
    @ObservedObject private var installed = InstalledApps.shared
    @ObservedObject private var store = DockStore.shared
    @State private var query = ""
    @State private var asList = false
    @State private var selection: String?
    @State private var info: String?

    private var filtered: [InstalledApps.App] {
        query.isEmpty ? installed.apps : installed.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Target: the selected launcher widget, otherwise a new one.
    private var targetLauncher: WidgetInstance? {
        if let id = store.editingWidgetID, let w = store.instance(id), w.kind == .launcher { return w }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Programme suchen", text: $query).textFieldStyle(.plain)
                Spacer()
                Text(targetLauncher != nil ? "＋ fügt zum ausgewählten App-Starter hinzu" : "＋ legt einen App-Starter an")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $asList) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 80)
                .help("Symbole / Liste")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if installed.loading && installed.apps.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if asList {
                listView
            } else {
                gridView
            }
        }
        .overlay(alignment: .bottom) {
            if let info {
                Label(info, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 10)
            }
        }
        .onAppear { installed.load() }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 12) {
                ForEach(filtered) { app in
                    VStack(spacing: 4) {
                        Image(nsImage: fileIcon(app.path)).resizable().frame(width: 48, height: 48)
                        Text(app.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                            .frame(height: 28, alignment: .top)
                    }
                    .padding(6)
                    .frame(width: 92)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selection == app.path ? Color.accentColor.opacity(0.2) : .clear))
                    .overlay(alignment: .topTrailing) { addButton(app).opacity(selection == app.path ? 1 : 0) }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { add(app) }
                    .onTapGesture { selection = app.path }
                    .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: app.path)) ?? NSItemProvider() }
                    .contextMenu { menu(app) }
                }
            }
            .padding(12)
        }
    }

    private var listView: some View {
        List(filtered, selection: $selection) { app in
            HStack(spacing: 8) {
                Image(nsImage: fileIcon(app.path)).resizable().frame(width: 20, height: 20)
                Text(app.name)
                Spacer()
                Text((app.path as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.secondary)
                addButton(app)
            }
            .tag(app.path)
            .onTapGesture(count: 2) { add(app) }
            .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: app.path)) ?? NSItemProvider() }
            .contextMenu { menu(app) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func addButton(_ app: InstalledApps.App) -> some View {
        Button { add(app) } label: {
            Image(systemName: "plus.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
        .help("Zur Leiste hinzufügen")
    }

    @ViewBuilder private func menu(_ app: InstalledApps.App) -> some View {
        Button("Öffnen") { AppLauncher.open(app: app.path) }
        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
        Divider()
        let launchers = store.activeWidgets.filter { $0.kind == .launcher }
        ForEach(launchers) { l in
            Button("Zu App-Starter (\(l.launcherApps.count) Apps) hinzufügen") { addTo(l, app) }
        }
        Button("Als neuen App-Starter hinzufügen") { addNew(app) }
    }

    private func add(_ app: InstalledApps.App) {
        if let l = targetLauncher { addTo(l, app) } else { addNew(app) }
    }

    private func addTo(_ l: WidgetInstance, _ app: InstalledApps.App) {
        LauncherStore.setApps(l.id, l.launcherApps + [app.path])
        flash("„\(app.name)“ zum App-Starter hinzugefügt")
    }

    private func addNew(_ app: InstalledApps.App) {
        let w = WidgetInstance(.launcher, size: 1, config: ["apps": app.path])
        store.profiles[store.activeIndex].widgets.append(w)
        store.editingWidgetID = w.id
        flash("„\(app.name)“ in die Leiste gelegt")
    }

    private func flash(_ text: String) {
        withAnimation { info = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { if info == text { info = nil } } }
    }
}
