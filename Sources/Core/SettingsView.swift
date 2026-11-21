import CoreGraphics
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case gallery, widgets, general, profiles, workspaces
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gallery: "Galerie"
        case .general: "Allgemein"
        case .widgets: "In der Leiste"
        case .profiles: "Profile"
        case .workspaces: "Arbeitsbereiche"
        }
    }
    var symbol: String {
        switch self {
        case .gallery: "square.grid.3x3.square"
        case .general: "gearshape"
        case .widgets: "dock.rectangle"
        case .profiles: "person.2.crop.square.stack"
        case .workspaces: "rectangle.3.group"
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var page: SettingsPage = .gallery
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNav.shared
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            NavigationSplitView {
                ZStack {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    shape.fill(.clear)
                        .glassEffect(
                            .regular.tint(Theme.tile.opacity(0.25 + (DockStore.shared.settings.glassTint ?? 0.18) * 0.6)),
                            in: shape
                        )
                        .padding(8)
                    List(SettingsPage.allCases, selection: Binding(get: { nav.page }, set: { if let p = $0 { nav.page = p } })) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
                }
                .background(.clear)
                .navigationSplitViewColumnWidth(180)
            } detail: {
                ZStack {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    shape.fill(.clear)
                        .glassEffect(
                            .regular.tint(Theme.tile.opacity(0.25 + (DockStore.shared.settings.glassTint ?? 0.18) * 0.6)),
                            in: shape
                        )
                        .padding(8)
                    Group {
                        switch nav.page {
                        case .gallery: WidgetGalleryView()
                        case .general: GeneralSettings()
                        case .widgets: WidgetSettings()
                        case .profiles: ProfileSettings()
                        case .workspaces: WorkspaceSettings()
                        }
                    }
                    .padding(8)
                }
                .background(.clear)
            }
            .background(.clear)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                AppIdentityBadge()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 980, minHeight: 640)
        .environment(\.locale, languageSettings.locale)
        .fontDesign(store.settings.fontDesign)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var screenCaptureAccess = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section("Sprache") {
                Picker("App-Sprache", selection: $languageSettings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Text(languageSettings.language == .system
                     ? "Verwendet die bevorzugte Sprache deines Macs."
                     : "Die ausgewählte Sprache wird sofort übernommen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Position") {
                Picker("Ort", selection: $store.settings.position) {
                    ForEach(DockPosition.allCases) { Text($0.label).tag($0) }
                }
                if store.settings.position == .free {
                    Text("Die Leiste lässt sich am Hintergrund mit der Maus verschieben.").font(.caption).foregroundStyle(.secondary)
                }
                Slider(value: $store.settings.margin, in: 0...80, step: 1) {
                    Text("Abstand zum Rand")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("80") }
                Text("Mindestabstand der Leiste zu allen Bildschirmrändern (\(Int(store.settings.margin)) pt).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Automatisch ausblenden (erscheint, wenn die Maus den Rand berührt)", isOn: $store.settings.autoHide)
                Toggle("Immer über anderen Fenstern", isOn: $store.settings.floatAbove)
            }
            Section("Farbschema") {
                Picker("Darstellung", selection: Binding(get: { store.settings.theme ?? "dark" },
                                                         set: { store.settings.theme = $0 })) {
                    ForEach(ThemeState.themes, id: \.id) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
                Toggle("Glas-Oberfläche (Liquid Glass)", isOn: Binding(get: { store.settings.glass ?? true },
                                                                       set: { store.settings.glass = $0 }))
                if store.settings.glass ?? true {
                    Slider(value: Binding(get: { store.settings.glassTint ?? 0.18 }, set: { store.settings.glassTint = $0 }),
                           in: 0...0.8) {
                        Text("Glas-Färbung")
                    } minimumValueLabel: { Text("klar") } maximumValueLabel: { Text("satt") }
                }
                if (store.settings.theme ?? "dark") == "custom" {
                    CustomColorRow(title: "Leiste", hex: $store.settings.customBar, fallback: "#0F0F10")
                    CustomColorRow(title: "Kacheln", hex: $store.settings.customTile, fallback: "#212124")
                    CustomColorRow(title: "Schriftfarbe", hex: $store.settings.customText, fallback: "#FFFFFF", allowAuto: true)
                }
                ThemePreview()
            }
            Section("Schriftart") {
                Picker("Schrift", selection: Binding(
                    get: { store.settings.fontStyle ?? .system },
                    set: { store.settings.fontStyle = $0 }
                )) {
                    ForEach(DockFontStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text("Beispiel: Crohniq Dock")
                    .font(.system(size: 16, weight: .semibold))
            }
            Section("Grösse & Leiste") {
                Slider(value: $store.settings.tileSize, in: 48...96, step: 2) {
                    Text("Kachelgrösse")
                } minimumValueLabel: { Text("S") } maximumValueLabel: { Text("L") }
                Toggle("Hintergrundleiste anzeigen", isOn: $store.settings.showBar)
                if store.settings.showBar && !(store.settings.glass ?? true) {
                    Slider(value: $store.settings.barOpacity, in: 0.3...1) { Text("Deckkraft der Leiste") }
                }
            }
            Section("Bedienung") {
                Toggle("Tastenkürzel ⌥⌘D blendet die Leiste ein/aus, ⌃⌥1–9 wechselt den Arbeitsbereich", isOn: $store.settings.hotkey)
                Toggle("Listen beim Überfahren aufrollen (Kalender, Erinnerungen, Notizen)",
                       isOn: Binding(get: { store.settings.hoverLists ?? true }, set: { store.settings.hoverLists = $0 }))
                Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Text("Widgets ordnest du direkt in der Leiste per Drag & Drop. Ein Rechtsklick auf ein Widget ändert die Grösse (Mini bis Max).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Freigaben") {
                PermissionRow(title: "Bedienungshilfen", detail: "Fenster in Arbeitsbereichen anordnen",
                              granted: WorkspaceManager.hasAccessibility) { WorkspaceManager.requestAccessibility() }
                PermissionRow(title: "Festplattenvollzugriff", detail: "Safari-Lesezeichen und Browserverlauf lesen",
                              granted: !SafariBookmarks.shared.accessDenied) { SafariBookmarks.openFullDiskAccessSettings() }
                PermissionRow(title: "Bildschirmaufnahme", detail: "Bildschirmvideos mit Systemton aufnehmen",
                              granted: screenCaptureAccess) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Allgemein")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenCaptureAccess = CGPreflightScreenCaptureAccess()
        }
    }
}

struct CustomColorRow: View {
    let title: String
    @Binding var hex: String?
    let fallback: String
    var allowAuto = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if allowAuto {
                Button("Automatisch") { hex = nil }.buttonStyle(.link).disabled(hex == nil)
            }
            Text(hex ?? (allowAuto ? "automatisch" : fallback)).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            ColorPicker("", selection: Binding(get: { Color(hex: hex ?? fallback) ?? .black },
                                               set: { hex = $0.hexString }), supportsOpacity: false)
                .labelsHidden()
            Button {
                NSColorSampler().show { c in
                    guard let c = c?.usingColorSpace(.sRGB) else { return }
                    hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
                }
            } label: { Image(systemName: "eyedropper") }
            .help("Farbe mit der Pipette vom Bildschirm aufnehmen")
        }
    }
}

struct ThemePreview: View {
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var theme = ThemeState.shared

    var body: some View {
        let p = theme.palette
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(["10:42", "26°", "Fokus"][i]).font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(["Fr 20. Nov.", "Zürich", "25:00"][i]).font(.caption).foregroundStyle(p.fg.opacity(0.55))
                }
                .padding(10)
                .frame(width: 96, height: 58, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(p.tile.opacity((store.settings.glass ?? true) ? 0.18 + (store.settings.glassTint ?? 0.18) * 0.8 : 1)))
            }
        }
        .padding(8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22)
            if store.settings.glass ?? true {
                Color.clear.glassEffect(.clear.tint(p.bar.opacity(store.settings.glassTint ?? 0.18)), in: shape)
            } else {
                shape.fill(p.bar)
            }
        }
        .foregroundStyle(p.fg)
        .environment(\.colorScheme, p.dark ? .dark : .light)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Erlauben …", action: action) }
        }
    }
}

// MARK: - Widgets

private struct ProgramToWidgetDropDelegate: DropDelegate {
    let target: UUID
    let store: DockStore
    @Binding var highlightedRow: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) { highlightedRow = target }

    func dropExited(info: DropInfo) {
        if highlightedRow == target { highlightedRow = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        let insertAfter = info.location.y >= 16
        provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL, url.pathExtension.lowercased() == "app" else {
                DispatchQueue.main.async { highlightedRow = nil }
                return
            }
            DispatchQueue.main.async {
                guard let targetIndex = store.allActiveWidgets.firstIndex(where: { $0.id == target }) else {
                    highlightedRow = nil
                    return
                }
                let path = url.standardizedFileURL.path
                let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                let launcher = WidgetInstance(.launcher, size: 1, config: ["apps": path, "widgetName": name])
                store.insert(launcher, at: targetIndex + (insertAfter ? 1 : 0))
                highlightedRow = nil
            }
        }
        return true
    }
}

struct WidgetSettings: View {
    @ObservedObject private var store = DockStore.shared
    @State private var highlightedDropRow: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Profil „\(store.profiles[store.activeIndex].name)“").font(.headline)
                    Spacer()
                    Button {
                        SettingsNav.shared.page = .gallery
                    } label: { Label("Widget hinzufügen", systemImage: "plus") }
                }
                .padding(10)
                List(selection: $store.editingWidgetID) {
                    ForEach(store.allActiveWidgets) { w in
                        HStack(spacing: 10) {
                            Image(systemName: w.kind.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.15)))
                            Text(w.displayName).font(.body.weight(.medium))
                            Spacer()
                            Text(WidgetSize.name(w.size, in: w.kind.sizes)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .overlay {
                            if highlightedDropRow == w.id {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                        .onDrop(of: [.fileURL], delegate: ProgramToWidgetDropDelegate(
                            target: w.id, store: store, highlightedRow: $highlightedDropRow
                        ))
                        .tag(w.id)
                        .contextMenu { Button("Entfernen", role: .destructive) { store.remove(w.id) } }
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in idx.map { store.allActiveWidgets[$0].id }.forEach(store.remove) }
                }
                .scrollContentBackground(.hidden)
                .background(.clear)
            }
            .padding(8)
            .frame(minWidth: 300, idealWidth: 340)
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                Color.clear.glassEffect(
                    .regular.tint(Theme.tile.opacity(0.25 + (store.settings.glassTint ?? 0.18) * 0.6)),
                    in: shape
                )
            }

            VSplitView {
                Group {
                    if let id = store.editingWidgetID, let w = store.instance(id) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    if w.kind == .launcher {
                                        LauncherPreview(w: w)
                                    } else {
                                        PreviewTile(kind: w.kind) {}.id(w.id).allowsHitTesting(false)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20).padding(.top, 20)
                                WidgetEditor(w: w).id(id)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.point.left").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Widget links auswählen, um Grösse und Optionen einzustellen.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 220, idealHeight: 340)

                AddPanel()
                    .frame(minHeight: 220, idealHeight: 340)
            }
            .frame(minWidth: 460)
        }
        .navigationTitle("In der Leiste")
    }
}

struct LauncherPreview: View {
    let w: WidgetInstance

    private let unit: CGFloat = 60
    private let gap: CGFloat = 8

    var body: some View {
        let size = w.size
        let width = CGFloat(size) * unit + CGFloat(max(0, size - 1)) * gap
        let palette = ThemeState.shared.palette

        WidgetHost(instance: w)
            .frame(width: width, height: unit)
            .background(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous).fill(palette.tile))
            .clipShape(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous))
            .environment(\.dockScale, unit / 64)
            .environment(\.colorScheme, palette.dark ? .dark : .light)
            .foregroundStyle(palette.fg)
            .allowsHitTesting(false)
            .padding(5)
            .background(RoundedRectangle(cornerRadius: unit * 0.26 + 5, style: .continuous).fill(palette.bar))
            .id(w.id.uuidString + "|" + w.launcherApps.joined(separator: "|"))
    }
}

struct WidgetEditor: View {
    let w: WidgetInstance
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared

    var body: some View {
        Form {
            Picker("Grösse", selection: Binding(get: { w.size }, set: { v in store.update(w.id) { $0.size = v } })) {
                ForEach(w.kind.sizes, id: \.self) { Text(WidgetSize.name($0, in: w.kind.sizes)).tag($0) }
            }
            .pickerStyle(.segmented)
            if w.kind == .launcher {
                TextField(
                    "Widget-Name",
                    text: Binding(
                        get: { store.instance(w.id)?.config["widgetName"] ?? "" },
                        set: { store.setConfig(w.id, "widgetName", $0) }
                    ),
                    prompt: Text(w.kind.title)
                )
            }
            if !workspaceManager.workspaces.isEmpty {
                Section("Arbeitsbereiche") {
                    ForEach(workspaceManager.workspaces) { workspace in
                        Toggle(workspace.name, isOn: workspaceBinding(workspace.id))
                    }
                    Text("Das Widget wird nur in ausgewählten Arbeitsbereichen angezeigt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Tora / Aufklappansicht") {
                Toggle("Beim Überfahren anzeigen", isOn: unrollEnabledBinding)
                fieldView(ConfigField(
                    key: "unrollFolder",
                    label: "Ordner für Dateien und Unterordner",
                    kind: .directory,
                    help: "Leer lassen, um die widgeteigene Aufklappansicht zu verwenden."
                ))
                Stepper(value: unrollCountBinding, in: 1...50) {
                    Text("Einträge anzeigen: \(unrollCountBinding.wrappedValue)")
                }
                .help("Maximale Anzahl der Einträge aus dem gewählten Ordner (1–50).")
            }
            if w.kind == .launcher {
                Section("Apps im App-Starter") {
                    if w.launcherApps.isEmpty {
                        Text("Noch keine Apps hinzugefügt.").foregroundStyle(.secondary)
                    }
                    ForEach(w.launcherApps, id: \.self) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: fileIcon(app)).resizable().frame(width: 24, height: 24)
                            Text(FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: ""))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Stepper(value: appFileCountBinding(for: app), in: 1...50) {
                                Text("\(store.instance(w.id)?.fileCount(for: app) ?? w.fileCount(for: app))")
                                    .monospacedDigit()
                            }
                            .controlSize(.small)
                            .help("Anzahl der letzten Dateien für diese App")
                            Button(role: .destructive) {
                                LauncherStore.setApps(w.id, w.launcherApps.filter { $0 != app })
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("App aus dem App-Starter entfernen")
                        }
                    }
                }
            }
            if w.kind == .shortcuts {
                ShortcutsWidgetSettings(w: w)
            }
            ForEach(w.kind.configFields, id: \.key) { field in
                fieldView(field)
                if let help = field.help { Text(help).font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button("Entfernen", role: .destructive) { store.remove(w.id) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(minHeight: 300)
    }

    private func workspaceBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                guard let assigned = store.instance(w.id)?.assignedWorkspaceIDs else { return true }
                return assigned.contains(id)
            },
            set: { selected in
                guard let current = store.instance(w.id) else { return }
                var assigned = current.assignedWorkspaceIDs ?? Set(workspaceManager.workspaces.map(\.id))
                if selected { assigned.insert(id) } else { assigned.remove(id) }
                store.setConfig(w.id, "workspaceIDs", assigned.sorted { $0.uuidString < $1.uuidString }
                    .map(\.uuidString).joined(separator: "\n"))
            }
        )
    }

    private var unrollEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.instance(w.id)?.config["unrollEnabled"] != "0" },
            set: { store.setConfig(w.id, "unrollEnabled", $0 ? "1" : "0") }
        )
    }

    private var unrollCountBinding: Binding<Int> {
        Binding(
            get: {
                let instance = store.instance(w.id)
                let raw = instance?.config["unrollCount"] ?? (w.kind == .mail ? instance?.config["count"] : nil)
                return min(max(Int(raw ?? "") ?? 10, 1), 50)
            },
            set: {
                store.setConfig(w.id, "unrollCount", String($0))
                if w.kind == .mail { store.setConfig(w.id, "count", String($0)) }
            }
        )
    }

    private func appFileCountBinding(for app: String) -> Binding<Int> {
        Binding(
            get: { store.instance(w.id)?.fileCount(for: app) ?? w.fileCount(for: app) },
            set: { store.setConfig(w.id, "fileCount|\(app)", String($0)) }
        )
    }

    @ViewBuilder private func fieldView(_ f: ConfigField) -> some View {
        let binding = Binding(get: { store.instance(w.id)?.config[f.key] ?? w.kind.defaultConfig[f.key] ?? "" },
                              set: { store.setConfig(w.id, f.key, $0) })
        switch f.kind {
        case .text, .number:
            TextField(f.label, text: binding, prompt: Text(f.placeholder))
        case .secure:
            SecureField(f.label, text: binding, prompt: Text(f.placeholder))
        case .multiline:
            VStack(alignment: .leading) {
                Text(f.label)
                TextEditor(text: binding).font(.system(.body, design: .monospaced)).frame(height: 90)
            }
        case .directory:
            HStack {
                TextField(f.label, text: binding, prompt: Text(f.placeholder))
                Button("Auswählen …") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    let currentPath = (binding.wrappedValue as NSString).expandingTildeInPath
                    if !currentPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: currentPath) }
                    NSApp.activate(ignoringOtherApps: true)
                    if panel.runModal() == .OK, let url = panel.url {
                        binding.wrappedValue = url.path
                    }
                }
            }
        case .choice(let options):
            Picker(f.label, selection: binding) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
    }
}

struct WidgetGallery: View {
    @ObservedObject private var store = DockStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Widget hinzufügen").font(.headline)
                ForEach(WidgetCategory.allCases) { cat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cat.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                            ForEach(WidgetKind.available.filter { $0.category == cat }) { kind in
                                Button { store.add(kind) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: kind.symbol).frame(width: 18)
                                        Text(kind.title).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Profiles

struct ProfileSettings: View {
    @ObservedObject private var store = DockStore.shared
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Widget-Profile") {
                ForEach($store.profiles) { $p in
                    HStack {
                        Image(systemName: p.id == store.activeProfileID ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                            .onTapGesture { store.switchProfile(p.id) }
                        TextField("Name", text: $p.name)
                        Text("\(p.widgets.count) Widgets").foregroundStyle(.secondary).font(.caption)
                        Button(role: .destructive) { store.deleteProfile(p.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).disabled(store.profiles.count < 2)
                    }
                }
            }
            Section("Neues Profil") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Leer anlegen") { store.addProfile(named: name, copyCurrent: false); newName = "" }
                    Button("Aktuelles kopieren") { store.addProfile(named: name, copyCurrent: true); newName = "" }
                }
                Text("Profile wechselst du oberhalb des Docks, über das Menüleisten-Symbol oder automatisch mit einem Arbeitsbereich.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Profil-Vorlagen") {
                ForEach(DockProfilePreset.allCases) { preset in
                    Button {
                        store.addProfile(preset)
                    } label: {
                        Label("\(preset.title) hinzufügen", systemImage: "plus.circle")
                    }
                }
                Text("Jede Vorlage enthält eine passende Widget-Auswahl und ein eigenes Farbschema. Anschliessend kannst du Widgets frei ergänzen, entfernen und sortieren.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Profile")
    }

    private var name: String { newName.isEmpty ? "Profil \(store.profiles.count + 1)" : newName }
}

// MARK: - Workspaces (DockFlow-style)

struct WorkspaceSettings: View {
    @ObservedObject private var mgr = WorkspaceManager.shared
    @State private var selected: UUID?
    @State private var overwrite: Workspace?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(Array(mgr.workspaces.enumerated()), id: \.element.id) { i, ws in
                        HStack {
                            Image(systemName: ws.symbol).frame(width: 20)
                            Text(ws.name)
                            Spacer()
                            if i < 9 { Text("⌃⌥\(i + 1)").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag(ws.id)
                        .contextMenu {
                            Button("Aktuellen Desktop hier übernehmen …") { overwrite = ws }
                            Button("Wiederherstellen") { mgr.apply(ws) }
                            Divider()
                            Button("Löschen", role: .destructive) { mgr.workspaces.removeAll { $0.id == ws.id } }
                        }
                    }
                    .onMove { mgr.workspaces.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack {
                    Button {
                        let ws = Workspace(name: "Neuer Bereich")
                        mgr.workspaces.append(ws)
                        selected = ws.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let ws = mgr.saveDesktopAsNew() { selected = ws.id }
                    } label: { Label("Neu", systemImage: "camera.viewfinder") }
                    .help("Aktuellen Desktop als neuen Bereich speichern")
                    Button {
                        overwrite = mgr.workspaces.first { $0.id == selected }
                    } label: { Label("In Auswahl", systemImage: "arrow.down.doc") }
                    .disabled(selected == nil)
                    .help("Aktuellen Desktop in den ausgewählten Bereich übernehmen (ersetzt ihn)")
                    Spacer()
                    Button {
                        mgr.workspaces.removeAll { $0.id == selected }
                        selected = mgr.workspaces.first?.id
                    } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 220, maxWidth: 280)

            if let id = selected, let idx = mgr.workspaces.firstIndex(where: { $0.id == id }) {
                WorkspaceEditor(ws: $mgr.workspaces[idx]).id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Ein Arbeitsbereich startet die Apps, die du für ein Thema brauchst, öffnet ihre Dateien und ordnet die Fenster an.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Arbeitsbereiche")
        .onAppear { if selected == nil { selected = mgr.workspaces.first?.id } }
        .confirmationDialog("„\(overwrite?.name ?? "")“ mit dem aktuellen Desktop neu festlegen?",
                            isPresented: Binding(get: { overwrite != nil }, set: { if !$0 { overwrite = nil } })) {
            Button("Übernehmen") {
                if let ws = overwrite { mgr.saveDesktop(into: ws.id); selected = ws.id }
                overwrite = nil
            }
        } message: {
            Text("Die gespeicherten Apps und Fensterpositionen werden durch das ersetzt, was jetzt auf dem Bildschirm ist. Angehängte Dateien bleiben erhalten.")
        }
    }
}

struct WorkspaceEditor: View {
    @Binding var ws: Workspace
    @ObservedObject private var store = DockStore.shared
    @State private var hover: UUID?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Name", text: $ws.name)
                    TextField("Symbol", text: $ws.symbol).frame(width: 150)
                    Image(systemName: ws.symbol).frame(width: 20)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("So geht's: Öffne und ordne deine Apps genau so an, wie du den Desktop haben willst, und klicke auf „Aktuellen Desktop speichern“. Beim Wechsel zu diesem Bereich sieht er wieder genau so aus – mit allen Fenstern, Positionen und Grössen.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button {
                            if let snap = WorkspaceManager.shared.snapshotDesktop(keepingFilesFrom: ws.apps) { ws.apps = snap }
                        } label: { Label(ws.apps.isEmpty ? "Aktuellen Desktop speichern" : "Mit aktuellem Desktop neu festlegen",
                                         systemImage: "camera.viewfinder") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Spacer()
                        Button {
                            WorkspaceManager.shared.apply(ws)
                        } label: { Label("Wiederherstellen", systemImage: "play.fill") }
                        .controlSize(.large)
                    }
                    if !WorkspaceManager.hasAccessibility {
                        Label("Dafür braucht Crohniq Dock die Freigabe „Bedienungshilfen“.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout)
                    }
                }
            }

            Section("Bildschirm-Vorschau") {
                ScreenPreview(apps: ws.apps, highlighted: hover)
                    .frame(height: 170)
            }

            Section("Apps") {
                ForEach($ws.apps) { $app in
                    WorkspaceAppRow(app: $app) { ws.apps.removeAll { $0.id == app.id } }
                        .onHover { hover = $0 ? app.id : nil }
                }
                .onMove { ws.apps.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Button("App hinzufügen …", action: addApps)
                    Button("Nur Positionen dieser Apps aktualisieren") {
                        guard let snap = WorkspaceManager.shared.snapshotDesktop() else { return }
                        ws.apps = ws.apps.map { a in
                            var a = a
                            if let found = snap.first(where: { $0.path == a.path }) { a.windows = found.windows; a.frame = nil }
                            return a
                        }
                    }
                    .help("Übernimmt die aktuellen Fenster nur für die Apps in dieser Liste")
                }
            }

            Section("Beim Wechsel") {
                Picker("Andere Apps", selection: $ws.others) {
                    ForEach(OthersPolicy.allCases) { Text($0.label).tag($0) }
                }
                Picker("Widget-Profil", selection: $ws.dockProfileID) {
                    Text("Nicht ändern").tag(UUID?.none)
                    ForEach(store.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Toggle("Beim Überfahren in der Leiste aufrollen", isOn: Binding(get: { ws.showOnHover ?? true },
                                                                              set: { ws.showOnHover = $0 }))
                Toggle("macOS-Dock auf diese Apps umstellen", isOn: $ws.setNativeDock)
                if ws.setNativeDock || NativeDock.hasBackup {
                    HStack {
                        Text("Vor der ersten Änderung wird dein Dock gesichert.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Ursprüngliches Dock wiederherstellen") { NativeDock.restore() }.disabled(!NativeDock.hasBackup)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK {
            ws.apps += panel.urls.map { WorkspaceApp(path: $0.path) }
        }
    }
}

struct WorkspaceAppRow: View {
    @Binding var app: WorkspaceApp
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(nsImage: fileIcon(app.path)).resizable().frame(width: 22, height: 22)
                Text(app.name)
                Spacer()
                Menu(!app.windows.isEmpty ? "Wie gespeichert (\(app.windows.count) Fenster)" : (app.frame?.presetName ?? "Unverändert")) {
                    if !app.windows.isEmpty {
                        Text("Gespeichert: \(app.windows.count) Fenster")
                        Divider()
                    }
                    Section("Stattdessen fest anordnen") {
                        ForEach(FracRect.presets, id: \.0) { preset in
                            Button(preset.0) { app.frame = preset.1; app.windows = [] }
                        }
                    }
                }
                .frame(width: 210)
                if NSScreen.screens.count > 1 {
                    Picker("", selection: $app.screen) {
                        ForEach(NSScreen.screens.indices, id: \.self) { Text("Bildschirm \($0 + 1)").tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                Button(action: addFiles) { Image(systemName: "doc.badge.plus") }.buttonStyle(.borderless)
                    .help("Dateien, die mit der App geöffnet werden")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            ForEach(app.files, id: \.self) { f in
                HStack(spacing: 4) {
                    Image(nsImage: fileIcon(f)).resizable().frame(width: 14, height: 14)
                    Text((f as NSString).lastPathComponent).font(.caption)
                    Button { app.files.removeAll { $0 == f } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).font(.caption)
                }
                .padding(.leading, 30)
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if let bid = app.bundleID {
            let recent = AppLauncher.recentDocuments(bundleID: bid, limit: 1)
            panel.directoryURL = recent.first?.deletingLastPathComponent()
        }
        if panel.runModal() == .OK {
            app.files += panel.urls.map(\.path).filter { !app.files.contains($0) }
        }
    }
}

struct ScreenPreview: View {
    let apps: [WorkspaceApp]
    let highlighted: UUID?

    var body: some View {
        GeometryReader { g in
            let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 16, height: 10)
            let ratio = screen.width / screen.height
            let h = min(g.size.height, g.size.width / ratio)
            let w = h * ratio
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [.indigo.opacity(0.5), .teal.opacity(0.4)],
                                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                ForEach(previewItems, id: \.key) { item in
                    PreviewWindowBox(app: item.app, frame: item.frame, screenW: w, screenH: h,
                                     highlighted: highlighted == item.app.id)
                }
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity)
        }
    }

    private struct Item { let key: String; let app: WorkspaceApp; let frame: FracRect }

    /// Back-most windows first so the front-most app is drawn on top.
    private var previewItems: [Item] {
        var items: [Item] = []
        for app in apps.reversed() {
            if !app.windows.isEmpty {
                for (i, win) in app.windows.enumerated().reversed() {
                    let (f, screen) = WorkspaceManager.fracRect(fromAX: win.rect)
                    if screen == 0 { items.append(Item(key: "\(app.id)-\(i)", app: app, frame: f)) }
                }
            } else if let f = app.frame, app.screen == 0 {
                items.append(Item(key: app.id.uuidString, app: app, frame: f))
            }
        }
        return items
    }
}

private struct PreviewWindowBox: View {
    let app: WorkspaceApp
    let frame: FracRect
    let screenW: CGFloat
    let screenH: CGFloat
    let highlighted: Bool

    var body: some View {
        let bw: CGFloat = max(20, screenW * CGFloat(frame.w) - 3)
        let bh: CGFloat = max(20, screenH * CGFloat(frame.h) - 3)
        let x: CGFloat = screenW * CGFloat(frame.x) + 1.5
        let y: CGFloat = screenH * CGFloat(frame.y) + 1.5
        let border: Color = highlighted ? .accentColor : .black.opacity(0.2)
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: highlighted ? 2 : 1))
            .overlay {
                VStack(spacing: 2) {
                    Image(nsImage: fileIcon(app.path)).resizable().frame(width: 22, height: 22)
                    Text(app.name).font(.caption2).lineLimit(1)
                }
            }
            .frame(width: bw, height: bh)
            .offset(x: x, y: y)
    }

}
