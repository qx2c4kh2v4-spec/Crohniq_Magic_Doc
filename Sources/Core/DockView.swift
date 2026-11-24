import SwiftUI
import UniformTypeIdentifiers

struct DockView: View {
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var themeState = ThemeState.shared
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @ObservedObject private var runningApps = RunningApps.shared
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @State private var dragging: UUID?

    var body: some View {
        let s = store.unit / 64
        let palette = themeState.palette
        let visibleWidgets = store.widgets(for: workspaceManager.activeID)
        let barShape = RoundedRectangle(cornerRadius: store.corner + store.barPadding, style: .continuous)
        let layout = store.vertical
            ? AnyLayout(VStackLayout(alignment: store.settings.position == .right ? .trailing : .leading, spacing: store.gap))
            : AnyLayout(HStackLayout(spacing: store.gap))
        VStack(spacing: store.showsHeader ? store.gap : 0) {
            if store.showsHeader, store.settings.position == .bottom {
                profileHeader(s: s)
            }
            layout {
                DockGrip(vertical: store.vertical)
                    .frame(width: store.vertical ? store.unit : store.grip, height: store.vertical ? store.grip : store.unit)
                if visibleWidgets.isEmpty {
                    Button { AppDelegate.shared.openSettings(page: .gallery) } label: {
                        Image(systemName: "plus").font(.system(size: 22 * s, weight: .semibold))
                            .frame(width: store.unit, height: store.unit)
                            .background(RoundedRectangle(cornerRadius: store.corner).fill(Theme.tile))
                    }.buttonStyle(.plain)
                }
                ForEach(visibleWidgets) { w in
                    TileContainer(instance: w)
                        .frame(width: store.width(for: w.size), height: store.unit)
                        .opacity(dragging == w.id ? 0.4 : 1)
                        .onDrag {
                            dragging = w.id
                            return NSItemProvider(object: ("crohniq-dock-widget:" + w.id.uuidString) as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDrop(target: w.id, dragging: $dragging))
                }
            }
            if store.showsHeader, store.settings.position != .bottom {
                profileHeader(s: s)
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { addCatalogWidget(from: $0) }
        .padding(store.barPadding)
        .contentShape(barShape)
        .contextMenu { BarMenu() }
        .modifier(BarSurface(shape: barShape, palette: palette, settings: store.settings))
        .id(palette.key + (Theme.glass ? "g" : "") + (store.settings.showBar ? "b" : ""))
        .frame(width: store.contentSize.width, height: store.contentSize.height)
        .environment(\.colorScheme, palette.dark ? .dark : .light)
        .environment(\.locale, languageSettings.locale)
        .environment(\.dockScale, s)
        .fontDesign(store.settings.fontDesign)
        .foregroundStyle(palette.fg)
    }

    @ViewBuilder
    private func profileHeader(s: CGFloat) -> some View {
        ZStack {
            HStack(spacing: store.gap) {
                Spacer(minLength: 0)
                if !workspaceManager.workspaces.isEmpty {
                    WorkspaceSymbolStrip()
                        .frame(width: store.workspaceSymbolStripWidth, height: store.profileStripHeight)
                    if !runningApps.apps.isEmpty {
                        RunningAppsHeader()
                            .frame(width: store.runningAppsHeaderWidth, height: store.profileStripHeight)
                    }
                }
                if !store.profiles.isEmpty {
                    ProfileSwitcher()
                        .frame(width: store.profileStripWidth, height: store.profileStripHeight)
                }
                Spacer(minLength: 0)
            }
            AppIdentityBadge(scale: s)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: store.contentSize.width - store.barPadding * 2,
               height: store.profileStripHeight)
    }
}

/// Workspace symbols to the left of the profiles. A click activates that workspace.
private struct WorkspaceSymbolStrip: View {
    @ObservedObject private var mgr = WorkspaceManager.shared
    @ObservedObject private var store = DockStore.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        HStack(spacing: 3 * s) {
            ForEach(Array(mgr.workspaces.enumerated()), id: \.element.id) { index, ws in
                let active = mgr.activeID == ws.id
                Button { mgr.apply(ws) } label: {
                    Image(systemName: ws.symbol)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(active ? Theme.fg : Theme.secondary)
                        .frame(width: 22 * s, height: 22 * s)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.35))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(workspaceHelp(ws, index: index))
                .accessibilityLabel("\(ws.name) aktivieren")
            }
        }
        .padding(.horizontal, 3 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { headerCapsule(glassTint: store.settings.glassTint, opacity: store.settings.barOpacity) }
        .clipShape(Capsule())
    }

    private func workspaceHelp(_ ws: Workspace, index: Int) -> String {
        let shortcut = index < 9 ? "  (⌃⌥\(index + 1))" : ""
        return "\(ws.name) aktivieren\(shortcut)"
    }
}

/// Running apps beside the workspace symbols, at the same symbol size.
private struct RunningAppsHeader: View {
    @ObservedObject private var running = RunningApps.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let count = running.apps.count
        let shown = min(count, 12)
        let iconWidth = (CGFloat(shown) * 22 + CGFloat(max(0, shown - 1)) * 4) * s
        HStack(spacing: 6 * s) {
            ScrollView(.horizontal) {
                HStack(spacing: 4 * s) {
                    ForEach(running.apps, id: \.processIdentifier) { app in
                        Menu {
                            RunningAppActions(app: app)
                        } label: {
                            Image(nsImage: app.icon ?? NSImage())
                                .resizable()
                                .frame(width: 22 * s, height: 22 * s)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("\(app.localizedName ?? "App"): beenden oder als Widget an einen Arbeitsbereich hängen")
                        .accessibilityLabel("\(app.localizedName ?? "App") beenden")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: iconWidth)

            Button(action: confirmQuitAll) {
                Text("Alle")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .frame(width: 34 * s, height: 22 * s)
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Theme.tileHi.opacity(0.7)))
            .help("Alle geöffneten Apps beenden")
            .accessibilityLabel("Alle Apps beenden")
        }
        .padding(.horizontal, 4 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmQuitAll() {
        let apps = running.apps
        guard !apps.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Alle \(apps.count) Apps beenden?"
        alert.informativeText = "Beenden gibt den Apps Zeit zum Sichern. Sofort beenden verwirft ungesicherte Änderungen."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Sofort beenden")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: running.quit(apps, force: false)
        case .alertSecondButtonReturn: running.quit(apps, force: true)
        default: break
        }
    }
}

private struct HeaderCapsule: View {
    var glassTint: Double?
    var opacity: Double

    var body: some View {
        if Theme.glass {
            Capsule().fill(.clear)
                .glassEffect(.clear.tint(Theme.tile.opacity((glassTint ?? 0.18) + 0.05)), in: Capsule())
        } else {
            Capsule().fill(Theme.bar.opacity(opacity))
        }
    }
}

private func headerCapsule(glassTint: Double?, opacity: Double) -> some View {
    HeaderCapsule(glassTint: glassTint, opacity: opacity)
}

struct AppIdentityBadge: View {
    var scale: CGFloat = 1

    private var buildInfo: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let buildDate = Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        return "Build \(version) (\(build)) · \(buildDate)"
    }

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 18 * scale, height: 18 * scale)
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text("Crohniq Dock")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .lineLimit(1)
                Text(buildInfo)
                    .font(.system(size: 7 * scale))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6 * scale)
        .frame(width: 172 * scale, height: 26 * scale, alignment: .leading)
        .background(Capsule().fill(.ultraThinMaterial))
        .help("Crohniq Dock · \(buildInfo)")
    }
}

/// Right-click on the bar's edge: settings and quick options.
struct BarMenu: View {
    @ObservedObject private var store = DockStore.shared

    var body: some View {
        Button("Einstellungen …") { AppDelegate.shared.openSettings(page: .general) }
        Button("Widget hinzufügen …") { AppDelegate.shared.openSettings(page: .gallery) }
        Button("Arbeitsbereiche …") { AppDelegate.shared.openSettings(page: .workspaces) }
        Divider()
        Menu("Farbschema") {
            ForEach(ThemeState.themes, id: \.id) { t in
                Button {
                    store.settings.theme = t.id
                    if t.id == "custom" { AppDelegate.shared.openSettings(page: .general) }
                } label: {
                    if (store.settings.theme ?? "dark") == t.id { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                }
            }
        }
        Button((store.settings.glass ?? true) ? "Glas ausschalten" : "Glas einschalten") {
            store.settings.glass = !(store.settings.glass ?? true)
        }
        Menu("Leiste platzieren") {
            ForEach(DockPosition.allCases) { pos in
                Button {
                    store.settings.position = pos
                    store.settings.along = nil
                } label: {
                    if store.settings.position == pos { Label(pos.label, systemImage: "checkmark") } else { Text(pos.label) }
                }
            }
        }
        Menu("Profil") {
            ForEach(store.profiles) { p in
                Button {
                    store.switchProfile(p.id)
                } label: {
                    if p.id == store.activeProfileID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        }
        Toggle("Automatisch ausblenden", isOn: $store.settings.autoHide)
        Divider()
        Button("Leiste ausblenden (⌥⌘D)") { AppDelegate.shared.dock.hide() }
    }
}

private struct ProfileSwitcher: View {
    @ObservedObject private var store = DockStore.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4 * s) {
                ForEach(store.profiles) { profile in
                    Button {
                        store.switchProfile(profile.id)
                    } label: {
                        HStack(spacing: 4 * s) {
                            if profile.id == store.activeProfileID {
                                Image(systemName: "checkmark")
                            }
                            Text(profile.name).lineLimit(1)
                        }
                        .font(.system(size: 10 * s, weight: .semibold))
                        .foregroundStyle(profile.id == store.activeProfileID ? Theme.fg : Theme.secondary)
                        .padding(.horizontal, 9 * s)
                        .frame(height: 22 * s)
                        .background {
                            if profile.id == store.activeProfileID {
                                Capsule().fill(Theme.tileHi.opacity(0.82))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Profil „\(profile.name)“")
                }
                Button {
                    var name = "Profil \(store.profiles.count + 1)"
                    var suffix = 2
                    while store.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                        name = "Profil \(store.profiles.count + suffix)"
                        suffix += 1
                    }
                    store.addProfile(named: name, copyCurrent: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10 * s, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 24 * s, height: 22 * s)
                        .background(Capsule().fill(Theme.tileHi.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help("Neues Profil anlegen und aktuelles Dock kopieren")
                .accessibilityLabel("Neues Profil anlegen")
            }
            .padding(.horizontal, 3 * s)
        }
        .scrollIndicators(.hidden)
        .frame(height: 28 * s)
        .background {
            if Theme.glass {
                Capsule().fill(.clear)
                    .glassEffect(.clear.tint(Theme.tile.opacity((store.settings.glassTint ?? 0.18) + 0.05)), in: Capsule())
            } else {
                Capsule().fill(Theme.bar.opacity(store.settings.barOpacity))
            }
        }
        .clipShape(Capsule())
    }
}

/// Bar background. Glass is applied to the content itself so the tiles are always drawn on top of it.
private struct BarSurface: ViewModifier {
    let shape: RoundedRectangle
    let palette: Palette
    let settings: DockSettings

    func body(content: Content) -> some View {
        if !settings.showBar {
            content
        } else if settings.glass ?? true {
            content
                .glassEffect(.clear.tint(palette.bar.opacity(settings.glassTint ?? 0.18)), in: shape)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .allowsHitTesting(false))
        } else {
            content.background {
                shape.fill(palette.bar.opacity(settings.barOpacity))
                    .overlay(shape.strokeBorder(palette.fg.opacity(0.08), lineWidth: 1))
            }
        }
    }
}

private struct ReorderDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil || info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { DockStore.shared.moveWidget(d, before: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragging == nil ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dragging == nil else {
            dragging = nil
            return true
        }
        dragging = nil
        return addCatalogWidget(from: info.itemProviders(for: [.text]))
    }
}

private func addCatalogWidget(from providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let payload = object as? String,
              let item = WidgetCatalogItem.decodeDragPayload(payload) else { return }
        DispatchQueue.main.async {
            DockStore.shared.add(item.kind, size: item.size, config: item.config)
        }
    }
    return true
}

// MARK: - Theme (Hell, Dunkel, Anthrazit, System, Eigene)

struct Palette: Equatable {
    var bar: Color
    var tile: Color
    var tileHi: Color
    var fg: Color
    var dark: Bool
    var key: String
}

final class ThemeState: ObservableObject {
    static let shared = ThemeState()
    @Published var systemDark = ThemeState.readSystemDark()

    private init() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.systemDark = ThemeState.readSystemDark() }
        }
    }

    static func readSystemDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static let themes: [(id: String, label: String)] = [
        ("system", "System"), ("light", "Hell"), ("dark", "Dunkel"), ("anthracite", "Anthrazit"), ("custom", "Eigene"),
    ]

    var palette: Palette {
        let st = DockStore.shared.settings
        var theme = st.theme ?? "dark"
        if theme == "system" { theme = systemDark ? "dark" : "light" }
        switch theme {
        case "light":
            return Palette(bar: Color(hex: "#EDEDF0")!, tile: Color(hex: "#FFFFFF")!, tileHi: Color(hex: "#E4E4E9")!,
                           fg: Color(hex: "#1C1C1E")!, dark: false, key: "light")
        case "anthracite":
            return Palette(bar: Color(hex: "#2A2E33")!, tile: Color(hex: "#3A3F45")!, tileHi: Color(hex: "#4B5158")!,
                           fg: .white, dark: true, key: "anthracite")
        case "custom":
            let tile = Color(hex: st.customTile ?? "") ?? Color(hex: "#212124")!
            let bar = Color(hex: st.customBar ?? "") ?? Color(hex: "#0F0F10")!
            let dark = Self.luminance(st.customTile ?? "#212124") < 0.55
            let fg = Color(hex: st.customText ?? "") ?? (dark ? .white : Color(hex: "#1C1C1E")!)
            return Palette(bar: bar, tile: tile, tileHi: tile.mix(with: fg, by: 0.12), fg: fg, dark: dark,
                           key: "custom\(st.customBar ?? "")\(st.customTile ?? "")\(st.customText ?? "")")
        default:
            return Palette(bar: Color(hex: "#0F0F10")!, tile: Color(hex: "#212124")!, tileHi: Color(hex: "#333336")!,
                           fg: .white, dark: true, key: "dark")
        }
    }

    static func luminance(_ hex: String) -> Double {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return 0 }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

enum Theme {
    static var palette: Palette { ThemeState.shared.palette }
    static var bar: Color { palette.bar }
    static var tile: Color { palette.tile }
    static var tileHi: Color { palette.tileHi }
    static var fg: Color { palette.fg }
    static var secondary: Color { palette.fg.opacity(0.55) }
    static var glass: Bool { DockStore.shared.settings.glass ?? true }
}

extension Color {
    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Each tile as its own piece of glass (when the bar is hidden); content stays on top.
private struct TileGlass: ViewModifier {
    let shape: RoundedRectangle
    let on: Bool
    let tint: Color

    func body(content: Content) -> some View {
        if on {
            content
                .glassEffect(.clear.tint(tint), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75).allowsHitTesting(false))
        } else {
            content
        }
    }
}

struct TileContainer: View {
    let instance: WidgetInstance
    @ObservedObject private var store = DockStore.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: store.corner, style: .continuous)
        WidgetHost(instance: instance)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(TileGlass(shape: shape, on: Theme.glass && !store.settings.showBar,
                                tint: Theme.tile.opacity((store.settings.glassTint ?? 0.18) + 0.05)))
            .background {
                if Theme.glass && !store.settings.showBar {
                    EmptyView()
                } else if Theme.glass {
                    // Glass bar: tiles are lightly tinted panes on the glass.
                    shape.fill(Theme.tile.opacity(0.18 + (store.settings.glassTint ?? 0.18) * 0.8))
                        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
                } else {
                    shape.fill(Theme.tile)
                }
            }
            .clipShape(shape)
            .hoverUnroll(
                id: instance.id,
                width: instance.kind == .weather ? 380 : 300,
                enabled: instance.cfg("unrollEnabled", "1") != "0" && hoverContent != nil
            ) {
                hoverContent ?? AnyView(EmptyView())
            }
            .contentShape(RoundedRectangle(cornerRadius: store.corner, style: .continuous))
            .contextMenu { menu }
    }

    /// List that unrolls while hovering this tile.
    private var hoverContent: AnyView? {
        let folder = (instance.cfg("unrollFolder") as NSString).expandingTildeInPath
        if !folder.isEmpty {
            let count = min(max(Int(instance.cfg("unrollCount", "10")) ?? 10, 1), 50)
            return AnyView(FolderHoverList(folder: folder, count: count))
        }
        switch instance.kind {
        case .calendar: return AnyView(CalendarHoverList())
        case .reminders: return AnyView(RemindersHoverList(list: instance.cfg("list")))
        case .notes: return AnyView(NotesHoverList())
        case .mail:
            let fallback = instance.cfg("count", "10")
            let count = min(max(Int(instance.cfg("unrollCount", fallback)) ?? 10, 1), 50)
            return AnyView(MailHoverList(count: count, filter: instance.cfg("mailFilter", "all")))
        case .clock: return AnyView(ClockHoverList(w: instance))
        case .weather: return AnyView(WeatherHoverList(city: instance.cfg("city", "auto")))
        case .nowPlaying: return AnyView(MusicHoverList())
        case .photos: return AnyView(PhotosHoverList(count: min(max(Int(instance.cfg("count", "5")) ?? 5, 1), 12)))
        case .panoramas: return AnyView(PanoramasHoverList(count: min(max(Int(instance.cfg("count", "10")) ?? 10, 1), 50)))
        case .shortcuts: return AnyView(ShortcutsHoverList(w: instance))
        case .dropbox: return AnyView(DropboxHoverList(w: instance))
        case .finder: return AnyView(FinderHoverList(w: instance))
        default: return nil
        }
    }

    /// Widget-specific entries, shown together with size and position in one menu.
    @ViewBuilder private var widgetItems: some View {
        let id = instance.id
        switch instance.kind {
        case .clock:
            Button(instance.cfg("style") == "analog" ? "Als Digitaluhr anzeigen" : "Als Analoguhr anzeigen") {
                store.setConfig(id, "style", instance.cfg("style") == "analog" ? "digital" : "analog")
            }
            Button("Weltuhr-Ort hinzufügen …") { WorldClocks.add(to: instance) }
            Divider()
        case .weather:
            Menu("Ort") {
                Button {
                    store.setConfig(id, "city", "auto")
                } label: {
                    if WeatherService.isAuto(instance.cfg("city", "auto")) { Label("Aktueller Standort", systemImage: "checkmark") }
                    else { Label("Aktueller Standort", systemImage: "location") }
                }
                let places = instance.cfg("places").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                if !places.isEmpty { Divider() }
                ForEach(places, id: \.self) { p in
                    Button {
                        store.setConfig(id, "city", p)
                    } label: {
                        if instance.cfg("city") == p { Label(p, systemImage: "checkmark") } else { Text(p) }
                    }
                }
                Divider()
                Button("Ort hinzufügen …") { WeatherPlaces.add(to: instance) }
                if !places.isEmpty {
                    Menu("Ort entfernen") {
                        ForEach(places, id: \.self) { p in
                            Button(p) { WeatherPlaces.remove(p, from: instance) }
                        }
                    }
                }
            }
            Divider()
        case .water:
            Button("Ein Glas abziehen") { WidgetAction.post(id, "minus") }
            Button("Heute zurücksetzen") { WidgetAction.post(id, "reset") }
            Divider()
        case .stopwatch:
            Button("Stoppuhr zurücksetzen") { WidgetAction.post(id, "reset") }
            Divider()
        case .timer:
            Button("Timer zurücksetzen") { WidgetAction.post(id, "reset") }
            Divider()
        case .voiceMemo:
            Button("Memo-Ordner öffnen") { NSWorkspace.shared.open(VoiceRecorder.folder) }
            Divider()
        case .screenshots:
            Button(ScreenRecordingController.shared.isRecording ? "Bildschirmvideo stoppen" : "Bildschirmvideo aufnehmen") {
                if ScreenRecordingController.shared.isRecording {
                    ScreenRecordingController.shared.stop()
                } else {
                    ScreenRecordingController.shared.start()
                }
            }
            Divider()
        case .photos:
            Button("Fotos öffnen") { WidgetAction.post(id, "reveal") }
            Divider()
        case .panoramas:
            Button("Fotos aktualisieren") { PhotoLibrary.shared.refresh(force: true) }
            Button("Fotos öffnen") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
            }
            Divider()
        case .finder:
            Button("Finder öffnen") { WidgetAction.post(id, "open") }
            Divider()
        case .dropbox:
            Button("Dropbox-Ordner öffnen") { WidgetAction.post(id, "open") }
            Divider()
        case .shortcuts:
            Button("Kurzbefehle öffnen") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            }
            Button("Kurzbefehle neu laden") { ShortcutsCatalog.shared.refresh() }
            Divider()
        case .launcher:
            Button("Apps hinzufügen …") { WidgetAction.post(id, "pickApp") }
            ForEach(instance.launcherApps, id: \.self) { app in
                let name = FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "")
                Menu(name) {
                    Button("Projekte auswählen …") { WidgetAction.post(id, "list:" + app) }
                    Button("Nach links") {
                        var l = instance.launcherApps
                        if let i = l.firstIndex(of: app), i > 0 { l.swapAt(i, i - 1); LauncherStore.setApps(id, l) }
                    }
                    Button("Nach rechts") {
                        var l = instance.launcherApps
                        if let i = l.firstIndex(of: app), i < l.count - 1 { l.swapAt(i, i + 1); LauncherStore.setApps(id, l) }
                    }
                    Button("Angeheftete Dateien leeren") { LauncherStore.setPinned(id, app: app, []) }
                    Button("Aus Starter entfernen", role: .destructive) {
                        LauncherStore.setApps(id, instance.launcherApps.filter { $0 != app })
                    }
                }
            }
            Divider()
        default:
            EmptyView()
        }
    }

    private func step(_ d: Int) {
        let sizes = instance.kind.sizes
        guard let i = sizes.firstIndex(of: instance.size), sizes.indices.contains(i + d) else { return }
        store.update(instance.id) { $0.size = sizes[i + d] }
    }

    @ViewBuilder private var menu: some View {
        if instance.kind == .nowPlaying {
            MusicMenu()
            Divider()
        }
        widgetItems
        Text(instance.displayName)
        if instance.kind.sizes.count > 1 {
            Menu("Grösse") {
                ForEach(instance.kind.sizes, id: \.self) { size in
                    Button {
                        store.update(instance.id) { $0.size = size }
                    } label: {
                        if size == instance.size { Label(sizeName(size, in: instance.kind.sizes), systemImage: "checkmark") }
                        else { Text(sizeName(size, in: instance.kind.sizes)) }
                    }
                }
            }
        }
        HStack {
            Button("Kleiner") { step(-1) }.disabled(instance.size == instance.kind.sizes.first)
            Button("Grösser") { step(1) }.disabled(instance.size == instance.kind.sizes.last)
        }
        Button(store.vertical ? "Nach oben" : "Nach links") { store.move(instance.id, by: -1) }
        Button(store.vertical ? "Nach unten" : "Nach rechts") { store.move(instance.id, by: 1) }
        Menu("Leiste platzieren") {
            ForEach(DockPosition.allCases) { pos in
                Button {
                    store.settings.position = pos
                    store.settings.along = nil
                } label: {
                    if store.settings.position == pos { Label(pos.label, systemImage: "checkmark") } else { Text(pos.label) }
                }
            }
        }
        Divider()
        Button("Widget einstellen …") { AppDelegate.shared.openSettings(selecting: instance.id) }
        Button("Widget hinzufügen …") { AppDelegate.shared.openSettings(page: .gallery) }
        Divider()
        Button("Entfernen", role: .destructive) { store.remove(instance.id) }
    }

    private func sizeName(_ n: Int, in sizes: [Int]) -> String { WidgetSize.name(n, in: sizes) }
}

struct WidgetHost: View {
    let instance: WidgetInstance

    var body: some View {
        switch instance.kind {
        case .clock: ClockWidget(w: instance)
        case .weather: WeatherWidget(w: instance)
        case .nowPlaying: NowPlayingWidget(w: instance)
        case .apps: AppsWidget(w: instance)
        case .appSwitcher: AppSwitcherWidget(w: instance)
        case .bookmarks: BookmarksWidget(w: instance)
        case .fileShelf: FileShelfWidget(w: instance)
        case .downloads: DownloadsWidget(w: instance)
        case .search: SearchWidget(w: instance)
        case .appleIntelligence: AppleIntelligenceWidget(w: instance)
        case .shortcuts: ShortcutsWidget(w: instance)
        case .pomodoro: PomodoroWidget(w: instance)
        case .timer: CountdownTimerWidget(w: instance)
        case .focus: FocusWidget(w: instance)
        case .water: WaterWidget(w: instance)
        case .calendar: CalendarWidget(w: instance)
        case .reminders: RemindersWidget(w: instance)
        case .progress: ProgressWidget(w: instance)
        case .stopwatch: StopwatchWidget(w: instance)
        case .notes: NotesWidget(w: instance)
        case .mail: MailWidget(w: instance)
        case .battery, .cpu, .memory, .disk: RingStatWidget(w: instance)
        case .cpuGraph: CPUGraphWidget(w: instance)
        case .toggles: TogglesWidget(w: instance)
        case .audio: AudioWidget(w: instance)
        case .clipboard: ClipboardWidget(w: instance)
        case .screenshots: ScreenshotWidget(w: instance)
        case .voiceMemo: VoiceMemoWidget(w: instance)
        case .emoji: EmojiWidget(w: instance)
        case .photos: PhotosWidget(w: instance)
        case .panoramas: PanoramasWidget(w: instance)
        case .finder: FinderWidget(w: instance)
        case .dropbox: DropboxWidget(w: instance)
        case .colorPicker: ColorPickerWidget(w: instance)
        case .converter: ConverterWidget(w: instance)
        case .github: GitHubWidget(w: instance)
        case .developerUsage: DeveloperUsageWidget(w: instance)
        case .metric: MetricWidget(w: instance)
        case .nexus: NexusWidget(w: instance)
        case .workspaces: WorkspacesWidget(w: instance)
        case .launcher: LauncherWidget(w: instance)
        case .quitApps: QuitAppsWidget(w: instance)
        case .trash: TrashWidget(w: instance)
        }
    }
}

// MARK: - Shared building blocks

struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 28
    var fill: Color = Theme.tileHi
    var tint: Color = Theme.fg
    let action: () -> Void
    @Environment(\.dockScale) private var s

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42 * s, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size * s, height: size * s)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct Ring: View {
    let value: Double
    var color: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fg.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
        }
    }
}

struct Sparkline: Shape {
    let values: [Double]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        let maxV = max(values.max() ?? 1, 1)
        let step = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: rect.maxY - CGFloat(v / maxV) * rect.height)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

extension View {
    func tilePadding(_ s: CGFloat) -> some View { padding(.horizontal, 10 * s).padding(.vertical, 8 * s) }
}

func fileIcon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

enum WidgetSize {
    /// Mini … Max labels relative to the sizes a widget supports.
    static func name(_ n: Int, in sizes: [Int]) -> String {
        guard let i = sizes.firstIndex(of: n) else { return "\(n)×" }
        let label: String
        if i == 0 { label = "Mini" }
        else if i == sizes.count - 1 { label = "Max" }
        else if sizes.count == 3 { label = "Mittel" }
        else if sizes.count == 4 { label = i == 1 ? "Mittel" : "Gross" }
        else { label = ["Klein", "Mittel", "Gross", "Sehr gross"][min(i - 1, 3)] }
        return "\(label) (\(n)×)"
    }
}

// MARK: - Grip: drag the bar to another screen edge

struct DockGrip: View {
    let vertical: Bool

    var body: some View {
        ZStack {
            GripArea()
            let dots = ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Theme.fg.opacity(0.4)).frame(width: 3.5, height: 3.5)
            }
            if vertical { HStack(spacing: 3.5) { dots }.allowsHitTesting(false) }
            else { VStack(spacing: 3.5) { dots }.allowsHitTesting(false) }
        }
        .help("Ziehen, um die Leiste nach unten, oben, links oder rechts zu setzen")
    }
}

private struct GripArea: NSViewRepresentable {
    func makeNSView(context: Context) -> GripNSView { GripNSView() }
    func updateNSView(_ nsView: GripNSView, context: Context) {}
}

final class GripNSView: NSView {
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let s = NSMenuItem(title: "Einstellungen …", action: #selector(openSettings), keyEquivalent: "")
        s.target = self
        m.addItem(s)
        let w = NSMenuItem(title: "Widget hinzufügen …", action: #selector(openWidgets), keyEquivalent: "")
        w.target = self
        m.addItem(w)
        return m
    }

    @objc private func openSettings() { AppDelegate.shared.openSettings(page: .general) }
    @objc private func openWidgets() { AppDelegate.shared.openSettings(page: .gallery) }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        startMouse = NSEvent.mouseLocation
        startOrigin = w.frame.origin
        NSCursor.closedHand.push()
        AppDelegate.shared.dock.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + m.x - startMouse.x, y: startOrigin.y + m.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        AppDelegate.shared.dock.endDrag()
    }
}


// MARK: - Menu actions routed to a widget's local state

enum WidgetAction {
    static let name = Notification.Name("CrohniqDockWidgetAction")
    static func post(_ id: UUID, _ action: String) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["id": id, "action": action])
    }
}

extension View {
    func onWidgetAction(_ id: UUID, perform: @escaping (String) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: WidgetAction.name)) { n in
            if (n.userInfo?["id"] as? UUID) == id, let a = n.userInfo?["action"] as? String { perform(a) }
        }
    }
}
