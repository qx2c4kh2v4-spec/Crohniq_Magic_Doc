import SwiftUI
import UniformTypeIdentifiers

// MARK: - Clock

struct ClockWidget: View {
    let w: WidgetInstance
    @ObservedObject private var ticker = Ticker.shared
    @Environment(\.dockScale) private var s

    private var tz: TimeZone { TimeZone(identifier: w.cfg("timezone")) ?? .current }

    private func timeStyle(_ de: Locale) -> Date.FormatStyle {
        let base = Date.FormatStyle(date: .omitted, time: .omitted, locale: de, timeZone: tz)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return w.cfg("seconds") == "1" && w.size > 1 ? base.second(.twoDigits) : base
    }

    var body: some View {
        let now = ticker.now
        let de = AppLanguageSettings.shared.locale
        let time = now.formatted(timeStyle(de))
        let date = w.size == 1
            ? now.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: de, timeZone: tz)
                .weekday(.abbreviated).day(.twoDigits).month(.twoDigits))
            : now.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: de, timeZone: tz)
                .weekday(.abbreviated).day().month(.abbreviated))
        if w.cfg("style") == "analog" {
            HStack(spacing: 10 * s) {
                AnalogClockFace(date: now, timeZone: tz, showSeconds: w.cfg("seconds") != "0" || w.size == 1)
                    .padding(w.size == 1 ? 6 * s : 0)
                    .frame(width: (w.size == 1 ? 64 : 50) * s, height: (w.size == 1 ? 64 : 50) * s)
                if w.size > 1 {
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(time).font(.system(size: 17 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(w.cfg("label").isEmpty ? date : w.cfg("label"))
                            .font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, w.size == 1 ? 0 : 10 * s)
        } else {
        VStack(spacing: 2 * s) {
            Text(time)
                .font(.system(size: (w.size == 1 ? 19 : 30) * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(w.cfg("label").isEmpty ? date : w.cfg("label"))
                .font(.system(size: 11 * s))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
        }
        .tilePadding(s)
        }
    }

    private var styleToggle: some View {
        Button(w.cfg("style") == "analog" ? "Als Digitaluhr anzeigen" : "Als Analoguhr anzeigen") {
            DockStore.shared.setConfig(w.id, "style", w.cfg("style") == "analog" ? "digital" : "analog")
        }
    }
}

struct AnalogClockFace: View {
    let date: Date
    let timeZone: TimeZone
    var showSeconds = true

    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let sec = Double(c.second ?? 0)
        let min = Double(c.minute ?? 0) + sec / 60
        let hour = Double((c.hour ?? 0) % 12) + min / 60
        return GeometryReader { g in
            let r = min2(g.size.width, g.size.height) / 2
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                ForEach(0..<12) { i in
                    Capsule()
                        .fill(Color.black.opacity(i % 3 == 0 ? 0.85 : 0.35))
                        .frame(width: r * (i % 3 == 0 ? 0.07 : 0.04), height: r * (i % 3 == 0 ? 0.2 : 0.12))
                        .offset(y: -r * 0.8)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                hand(angle: hour * 30, length: r * 0.5, width: r * 0.09, color: .black)
                hand(angle: min * 6, length: r * 0.75, width: r * 0.06, color: .black)
                if showSeconds {
                    hand(angle: sec * 6, length: r * 0.82, width: r * 0.025, color: .orange)
                }
                Circle().fill(Color.orange).frame(width: r * 0.1, height: r * 0.1)
            }
            .frame(width: r * 2, height: r * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func min2(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a < b ? a : b }

    private func hand(angle: Double, length: CGFloat, width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2 + width / 2)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Weather

struct WeatherWidget: View {
    let w: WidgetInstance
    @ObservedObject private var service = WeatherService.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let city = w.cfg("city", "auto")
        Group {
            if let d = service.data[city] {
                HStack(spacing: 12 * s) {
                    VStack(alignment: w.size == 1 ? .center : .leading, spacing: 2 * s) {
                        if w.size == 1 {
                            Image(systemName: WeatherService.symbol(d.code)).symbolRenderingMode(.multicolor)
                                .font(.system(size: 16 * s))
                        }
                        Text("\(Int(d.temp.rounded()))°")
                            .font(.system(size: (w.size == 1 ? 18 : 30) * s, weight: .semibold, design: .rounded))
                        Text(w.size == 1 ? d.place : "\(d.place)")
                            .font(.system(size: 11 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    if w.size >= 2 {
                        Spacer(minLength: 0)
                        HStack(spacing: 10 * s) {
                            ForEach(Array(d.days.prefix(w.size == 2 ? 1 : w.size == 3 ? 3 : 5))) { day in
                                VStack(spacing: 3 * s) {
                                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguageSettings.shared.locale)))
                                        .font(.system(size: 10 * s, weight: .medium)).foregroundStyle(Theme.secondary)
                                    Image(systemName: WeatherService.symbol(day.code)).symbolRenderingMode(.multicolor)
                                        .font(.system(size: 14 * s))
                                        .frame(height: 16 * s)
                                    Text("\(Int(day.max.rounded()))°").font(.system(size: 11 * s, weight: .semibold))
                                }
                            }
                        }
                    }
                }
                .help("\(d.place): \(WeatherService.label(d.code)), Wind \(Int(d.wind)) km/h")
            } else if let err = service.errors[city] {
                Button {
                    if err == "denied" {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    } else {
                        AppDelegate.shared.openSettings(selecting: w.id)
                    }
                } label: {
                    VStack(spacing: 2 * s) {
                        Image(systemName: err == "denied" ? "location.slash" : "exclamationmark.triangle").font(.system(size: 15 * s))
                        if w.size > 1 {
                            Text(errorText(err)).font(.system(size: 9 * s)).multilineTextAlignment(.center).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help(errorText(err))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Weather.app")) }
        .task(id: city) {
            // Retry every minute until data is there, then rely on the service's 15-minute refresh.
            while !Task.isCancelled {
                if service.data[city] == nil { service.fetch(city) }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func errorText(_ e: String) -> String {
        switch e {
        case "denied": "Ortungsdienste für Crohniq Dock erlauben"
        case "unavailable": "Standort nicht verfügbar – Ort eintragen"
        case "notfound": "Ort nicht gefunden – Ort prüfen"
        default: "Keine Verbindung"
        }
    }
}

// MARK: - Now Playing

struct NowPlayingWidget: View {
    let w: WidgetInstance
    @ObservedObject private var np = NowPlaying.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            Group {
                if let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: 18 * s, weight: .semibold))
                    }
                }
            }
            .frame(width: (w.size == 1 ? 44 : 46) * s, height: (w.size == 1 ? 44 : 46) * s)
            .clipShape(RoundedRectangle(cornerRadius: 8 * s))
            .overlay {
                if w.size == 1 {
                    Image(systemName: np.playing ? "pause.fill" : "play.fill").font(.system(size: 16 * s, weight: .bold))
                        .shadow(radius: 3)
                }
            }
            .onTapGesture { w.size == 1 ? np.command("playpause") : np.openPlayer() }
            .help(np.title.isEmpty ? "Musik" : "\(np.title) – \(np.artist)")

            if w.size >= 3 {
                VStack(alignment: .leading, spacing: 3 * s) {
                    HStack(spacing: 4 * s) {
                        Text(np.title.isEmpty ? "Nichts wird abgespielt" : np.title)
                            .font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                        if let cur = np.current, !np.title.isEmpty {
                            Image(systemName: MusicLibrary.shared.isFavorite(cur) ? "star.fill" : "star")
                                .font(.system(size: 10 * s))
                                .foregroundStyle(MusicLibrary.shared.isFavorite(cur) ? .yellow : Theme.secondary)
                                .onTapGesture { MusicLibrary.shared.toggleFavorite(cur) }
                                .help("Titel merken")
                        }
                    }
                    Text(np.artist.isEmpty ? (np.player ?? "Musik") : np.artist)
                        .font(.system(size: 11 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fg.opacity(0.15))
                            Capsule().fill(Theme.fg.opacity(0.8))
                                .frame(width: g.size.width * (np.duration > 0 ? min(1, np.position / np.duration) : 0))
                        }
                    }
                    .frame(height: 4 * s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if w.size >= 2 {
            HStack(spacing: 6 * s) {
                if w.size >= 4 { CircleButton(symbol: "backward.fill", size: 28) { np.command("previous track") } }
                CircleButton(symbol: np.playing ? "pause.fill" : "play.fill", size: 34) { np.command("playpause") }
                CircleButton(symbol: "forward.fill", size: 28) { np.command("next track") }
            }
            }
            if w.size == 2 { Spacer(minLength: 0) }
        }
        .tilePadding(s)
    }
}

struct MusicMenu: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var np = NowPlaying.shared

    var body: some View {
        if let cur = np.current {
            Button(lib.isFavorite(cur) ? "★ Aus gemerkten Titeln entfernen" : "☆ Diesen Titel merken") { lib.toggleFavorite(cur) }
        }
        Menu("Playlisten (\(lib.playlists.count))") {
            ForEach(lib.playlists, id: \.self) { name in
                Button(name) { lib.play(playlist: name) }
            }
            if !lib.playlists.isEmpty { Divider() }
            Button(lib.refreshing ? "Wird geladen …" : "Playlisten aus Musik laden") { lib.refreshPlaylists() }
        }
        Menu("Gemerkte Titel (\(lib.favorites.count))") {
            if lib.favorites.isEmpty { Text("Noch keine – „Diesen Titel merken“ beim Abspielen") }
            ForEach(lib.favorites) { t in
                Button(t.label) { lib.play(t) }
            }
            if !lib.favorites.isEmpty {
                Divider()
                Menu("Entfernen") {
                    ForEach(lib.favorites) { t in Button(t.label) { lib.removeFavorite(t) } }
                }
            }
        }
        Menu("Zuletzt gespielt") {
            if lib.recent.isEmpty { Text("Noch nichts gespielt") }
            ForEach(lib.recent) { t in
                Button(t.label) { lib.play(t) }
            }
            if !lib.recent.isEmpty {
                Divider()
                Button("Verlauf leeren") { lib.clearRecent() }
            }
        }
    }
}

// MARK: - Apps & Folders

struct AppsWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var targeted = false

    private var paths: [String] {
        w.cfg("paths").split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        let items = paths
        let capacity = w.size == 1 ? 4 : w.size * 2 + (w.size - 1)
        let shown = Array(items.prefix(capacity))
        let iconSize: CGFloat = DockStore.gridIcon * s
        let columns = shown.isEmpty ? 1 : (w.size == 1 ? min(2, shown.count) : max(1, Int(ceil(Double(shown.count) / 2))))
        let rows = shown.isEmpty ? 1 : Int(ceil(Double(shown.count) / Double(columns)))
        Grid(horizontalSpacing: 3 * s, verticalSpacing: 3 * s) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        let idx = r * columns + c
                        if idx < shown.count {
                            let path = shown[idx]
                            Image(nsImage: fileIcon(path)).resizable()
                                .frame(width: iconSize, height: iconSize)
                                .help(FileManager.default.displayName(atPath: path))
                                .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                                .contextMenu {
                                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                    Button("Aus Widget entfernen") { remove(path) }
                                }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if items.isEmpty {
                Image(systemName: "plus.app").font(.system(size: 22 * s)).foregroundStyle(Theme.secondary)
                    .onTapGesture(perform: pick)
            }
            if targeted { RoundedRectangle(cornerRadius: 12 * s).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { add(url.path) }
                }
            }
            return true
        }
    }

    private func add(_ path: String) {
        var list = paths
        guard !list.contains(path) else { return }
        list.append(path)
        DockStore.shared.setConfig(w.id, "paths", list.joined(separator: "\n"))
    }

    private func remove(_ path: String) {
        DockStore.shared.setConfig(w.id, "paths", paths.filter { $0 != path }.joined(separator: "\n"))
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach { add($0.path) } }
    }
}

// MARK: - App switcher

struct AppSwitcherWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var apps: [NSRunningApplication] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        let icon = 34 * s
        let tileWidth = CGFloat(w.size * 64 + (w.size - 1) * 8)
        let capacity = max(1, Int((tileWidth - 14) / 40))
        HStack(spacing: 6 * s) {
            ForEach(apps.prefix(capacity), id: \.processIdentifier) { app in
                Image(nsImage: app.icon ?? NSImage()).resizable()
                    .frame(width: icon, height: icon)
                    .overlay(alignment: .bottom) {
                        if app.isActive { Circle().fill(Theme.fg).frame(width: 4 * s, height: 4 * s).offset(y: 6 * s) }
                    }
                    .help(app.localizedName ?? "")
                    .onTapGesture { app.activate() }
                    .contextMenu {
                        Button("Ausblenden") { app.hide() }
                        Button("Beenden") { app.terminate() }
                        Button("Sofort beenden (hart)") { app.forceTerminate() }
                    }
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private func reload() {
        let own = Bundle.main.bundleIdentifier
        let list = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own && $0.bundleIdentifier != "com.apple.finder" }
        if list.map(\.processIdentifier) != apps.map(\.processIdentifier) { apps = list }
    }
}

// MARK: - File shelf

struct FileShelfWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var targeted = false

    private var files: [String] {
        w.cfg("files").split(separator: "\n").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
    }

    var body: some View {
        let list = files
        HStack(spacing: 6 * s) {
            if list.isEmpty {
                VStack(spacing: 3 * s) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 18 * s))
                    if w.size > 1 { Text("Dateien hierher ziehen").font(.system(size: 10 * s)).foregroundStyle(Theme.secondary) }
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(list.suffix(w.size * 2), id: \.self) { path in
                    Image(nsImage: fileIcon(path)).resizable().frame(width: 34 * s, height: 34 * s)
                        .help(path)
                        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
                        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .contextMenu {
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            Button("Aus Ablage entfernen") { set(files.filter { $0 != path }) }
                        }
                }
                Spacer(minLength: 0)
                Button { set([]) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
                    .buttonStyle(.plain).help("Ablage leeren")
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14 * s).strokeBorder(Color.accentColor, lineWidth: 2) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        var l = files
                        if !l.contains(url.path) { l.append(url.path) }
                        set(l)
                    }
                }
            }
            return true
        }
    }

    private func set(_ l: [String]) { DockStore.shared.setConfig(w.id, "files", l.joined(separator: "\n")) }
}

struct TrashWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var targeted = false
    @State private var trashCount = 0
    @State private var status = ""
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 2 * s) {
            ZStack(alignment: .topTrailing) {
                GoldTrashCan(full: trashCount > 0, targeted: targeted)
                    .frame(width: (w.size > 1 ? 32 : 38) * s, height: (w.size > 1 ? 38 : 46) * s)
                    .scaleEffect(targeted ? 1.1 : 1, anchor: .bottom)
                    .shadow(color: Color(red: 1, green: 0.8, blue: 0.3).opacity(targeted ? 0.8 : 0), radius: 10 * s)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
                    .animation(.easeInOut(duration: 0.3), value: trashCount > 0)
                if trashCount > 0 {
                    Text(trashCount > 99 ? "99+" : "\(trashCount)")
                        .font(.system(size: 7 * s, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3 * s)
                        .frame(minWidth: 12 * s, minHeight: 12 * s)
                        .background(Capsule().fill(Color.red).shadow(color: .black.opacity(0.3), radius: 1, y: 0.5))
                        .offset(x: 5 * s, y: -3 * s)
                }
            }
            if w.size > 1 {
                Text(status.isEmpty ? "Papierkorb" : status)
                    .font(.system(size: 8 * s, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .tilePadding(s)
        .help(trashCount == 0 ? "Papierkorb (leer)" : "Papierkorb – \(trashCount) Objekte")
        .onTapGesture {
            Script.run("tell application \"Finder\" to open trash") { _ in }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            var moved = 0
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    var resultingURL: NSURL?
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                        DispatchQueue.main.async {
                            moved += 1
                            status = moved == 1 ? "1 Datei bewegt" : "\(moved) Dateien bewegt"
                            refreshCount()
                        }
                    } catch {
                        DispatchQueue.main.async { status = "Verschieben fehlgeschlagen" }
                    }
                }
            }
            return true
        }
        .onAppear { refreshCount() }
        .onReceive(tick) { _ in refreshCount() }
        .contextMenu {
            Button("Papierkorb öffnen") {
                Script.run("tell application \"Finder\" to open trash") { _ in }
            }
            Button("Papierkorb entleeren …") {
                let alert = NSAlert()
                alert.messageText = "Papierkorb endgültig entleeren?"
                alert.informativeText = "\(trashCount) Objekte werden unwiderruflich gelöscht."
                alert.addButton(withTitle: "Entleeren")
                alert.addButton(withTitle: "Abbrechen")
                alert.buttons.first?.hasDestructiveAction = true
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Script.run("tell application \"Finder\" to empty trash") { _ in refreshCount() }
            }
            .disabled(trashCount == 0)
        }
    }

    private func refreshCount() {
        let trash = NSHomeDirectory() + "/.Trash"
        let items = (try? FileManager.default.contentsOfDirectory(atPath: trash)) ?? []
        let count = items.filter { $0 != ".DS_Store" }.count
        if count != trashCount { trashCount = count }
    }
}

/// A perforated metal bin in polished gold; crumpled paper peeks out when it holds something.
struct GoldTrashCan: View {
    let full: Bool
    let targeted: Bool

    private static let gold = Gradient(stops: [
        .init(color: Color(red: 0.36, green: 0.25, blue: 0.05), location: 0),
        .init(color: Color(red: 0.72, green: 0.52, blue: 0.14), location: 0.12),
        .init(color: Color(red: 0.98, green: 0.88, blue: 0.52), location: 0.32),
        .init(color: Color(red: 1.0, green: 0.96, blue: 0.78), location: 0.38),
        .init(color: Color(red: 0.88, green: 0.68, blue: 0.24), location: 0.55),
        .init(color: Color(red: 0.66, green: 0.46, blue: 0.11), location: 0.8),
        .init(color: Color(red: 0.32, green: 0.22, blue: 0.04), location: 1),
    ])

    var body: some View {
        Canvas { ctx, size in
            let W = size.width, H = size.height, cx = W / 2
            let topY = H * 0.17, rx = W * 0.47, ry = H * 0.085
            let botY = H * 0.92, rxb = W * 0.36, ryb = H * 0.06

            func ellipse(_ y: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGRect {
                CGRect(x: cx - a, y: y - b, width: 2 * a, height: 2 * b)
            }
            func frontArc(_ p: inout Path, y: CGFloat, a: CGFloat, b: CGFloat, leftToRight: Bool) {
                for i in 0...24 {
                    let t = CGFloat(i) / 24
                    let th = leftToRight ? .pi * (1 - t) : .pi * t
                    p.addLine(to: CGPoint(x: cx + a * cos(th), y: y + b * sin(th)))
                }
            }

            // Ground shadow
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: H * 0.03))
                l.fill(Path(ellipseIn: ellipse(botY + H * 0.02, rxb * 1.15, ryb * 0.9)), with: .color(.black.opacity(0.35)))
            }

            // Opening (dark inside)
            ctx.fill(Path(ellipseIn: ellipse(topY, rx, ry)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.08, blue: 0.01), Color(red: 0.3, green: 0.21, blue: 0.05)]),
                                           startPoint: CGPoint(x: cx, y: topY - ry), endPoint: CGPoint(x: cx, y: topY + ry)))

            // Rolled rim, back half (the paper sits in front of it)
            let rim = Path(ellipseIn: ellipse(topY, rx, ry))
            let goldAcross = GraphicsContext.Shading.linearGradient(Self.gold, startPoint: CGPoint(x: cx - rx, y: 0), endPoint: CGPoint(x: cx + rx, y: 0))
            ctx.stroke(rim, with: goldAcross, lineWidth: H * 0.055)

            // Crumpled paper
            if full {
                let blobs: [(CGFloat, CGFloat, CGFloat)] = [(-0.17, -0.02, 0.17), (0.15, -0.05, 0.16), (0.0, -0.1, 0.19)]
                for (k, b) in blobs.enumerated() {
                    let c = CGPoint(x: cx + b.0 * W, y: topY + b.1 * H)
                    let r = b.2 * W
                    var p = Path()
                    for i in 0..<11 {
                        let a = CGFloat(i) / 11 * 2 * .pi
                        let wobble = 0.78 + 0.22 * abs(sin(CGFloat(i * 7 + k * 3)))
                        let pt = CGPoint(x: c.x + r * wobble * cos(a), y: c.y + r * 0.85 * wobble * sin(a))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.8)]),
                                                     startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
                    var crease = Path()
                    crease.move(to: CGPoint(x: c.x - r * 0.5, y: c.y - r * 0.2))
                    crease.addLine(to: CGPoint(x: c.x + r * 0.1, y: c.y + r * 0.1))
                    crease.addLine(to: CGPoint(x: c.x + r * 0.45, y: c.y - r * 0.35))
                    ctx.stroke(crease, with: .color(.black.opacity(0.18)), lineWidth: max(0.5, W * 0.012))
                    ctx.stroke(p, with: .color(.black.opacity(0.12)), lineWidth: max(0.5, W * 0.01))
                }
            }

            // Body
            var body = Path()
            body.move(to: CGPoint(x: cx - rx, y: topY))
            body.addLine(to: CGPoint(x: cx - rxb, y: botY))
            frontArc(&body, y: botY, a: rxb, b: ryb, leftToRight: true)
            body.addLine(to: CGPoint(x: cx + rx, y: topY))
            frontArc(&body, y: topY, a: rx, b: ry, leftToRight: false)
            body.closeSubpath()
            ctx.fill(body, with: .linearGradient(Self.gold, startPoint: CGPoint(x: cx - rx, y: 0), endPoint: CGPoint(x: cx + rx, y: 0)))

            // Perforations, foreshortened around the cylinder
            ctx.drawLayer { l in
                l.clip(to: body)
                let rows = 7
                for row in 0..<rows {
                    let v = (CGFloat(row) + 0.9) / CGFloat(rows + 1)
                    let y0 = topY + (botY - topY) * v
                    let r = rx + (rxb - rx) * v
                    let ryv = ry + (ryb - ry) * v
                    let shift = row.isMultiple(of: 2) ? 0.0 : 0.5
                    for col in -5...5 {
                        let phi = (CGFloat(col) + CGFloat(shift)) * (.pi / 11)
                        guard abs(phi) < 1.35 else { continue }
                        let x = cx + r * sin(phi)
                        let y = y0 + ryv * cos(phi)
                        let hw = W * 0.032 * cos(phi), hh = H * 0.028
                        let hole = CGRect(x: x - hw, y: y - hh, width: 2 * hw, height: 2 * hh)
                        l.fill(Path(ellipseIn: hole.offsetBy(dx: 0, dy: hh * 0.35)), with: .color(Color(red: 1, green: 0.93, blue: 0.65).opacity(0.45)))
                        l.fill(Path(ellipseIn: hole), with: .color(Color(red: 0.22, green: 0.14, blue: 0.02).opacity(0.75)))
                    }
                }
                // Vertical sheen
                l.fill(Path(CGRect(x: cx - rx * 0.42, y: topY, width: rx * 0.14, height: botY - topY)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)]),
                                             startPoint: CGPoint(x: cx - rx * 0.42, y: 0), endPoint: CGPoint(x: cx - rx * 0.28, y: 0)))
            }

            // Foot band
            var foot = Path()
            foot.move(to: CGPoint(x: cx - rxb * 1.02, y: botY - H * 0.035))
            frontArc(&foot, y: botY - H * 0.035, a: rxb * 1.02, b: ryb, leftToRight: true)
            ctx.stroke(foot, with: .linearGradient(Self.gold, startPoint: CGPoint(x: cx - rxb, y: 0), endPoint: CGPoint(x: cx + rxb, y: 0)),
                       lineWidth: H * 0.05)
            ctx.stroke(body, with: .color(Color(red: 0.3, green: 0.2, blue: 0.03).opacity(0.6)), lineWidth: max(0.5, W * 0.012))

            // Rolled rim, front half
            var front = Path()
            front.move(to: CGPoint(x: cx - rx, y: topY))
            frontArc(&front, y: topY, a: rx, b: ry, leftToRight: true)
            ctx.stroke(front, with: goldAcross, style: StrokeStyle(lineWidth: H * 0.055, lineCap: .round))
            var gleam = Path()
            gleam.move(to: CGPoint(x: cx - rx * 0.97, y: topY - H * 0.012))
            frontArc(&gleam, y: topY - H * 0.012, a: rx * 0.97, b: ry * 0.85, leftToRight: true)
            ctx.stroke(gleam, with: .color(.white.opacity(targeted ? 0.85 : 0.55)), lineWidth: max(0.5, H * 0.012))
            if !full {
                var back = Path()
                back.addEllipse(in: ellipse(topY - H * 0.012, rx * 0.97, ry * 0.85))
                ctx.stroke(back, with: .color(.white.opacity(0.25)), lineWidth: max(0.5, H * 0.01))
            }
        }
    }
}

// MARK: - Downloads

struct DownloadsWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var files: [URL] = []
    @State private var showList = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    var body: some View {
        HStack(spacing: 6 * s) {
            if w.size == 1 {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 26 * s)).foregroundStyle(Theme.fg.opacity(0.85))
            } else {
                ForEach(files.prefix(w.size * 2 - 1), id: \.self) { url in
                    Image(nsImage: fileIcon(url.path)).resizable().frame(width: 32 * s, height: 32 * s)
                        .help(url.lastPathComponent)
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .onTapGesture { NSWorkspace.shared.open(url) }
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { showList = true }
        .popover(isPresented: $showList) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Neueste Downloads").font(.headline).padding(.bottom, 4)
                ForEach(files.prefix(12), id: \.self) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack {
                            Image(nsImage: fileIcon(url.path)).resizable().frame(width: 20, height: 20)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                }
                Divider()
                Button("Ordner öffnen") { NSWorkspace.shared.open(Self.folder) }
            }
            .padding(12)
            .frame(width: 320)
        }
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private func reload() {
        DispatchQueue.global(qos: .utility).async {
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
            let sorted = urls.map { u -> (URL, Date) in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return (u, v?.addedToDirectoryDate ?? v?.contentModificationDate ?? .distantPast)
            }.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
            DispatchQueue.main.async { if sorted != files { files = Array(sorted) } }
        }
    }
}

// MARK: - Search

struct SearchWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var query = ""
    @State private var results: [String] = []
    @State private var showResults = false
    @FocusState private var focused: Bool
    @StateObject private var ai = GeneralAI.shared
    @State private var showAI = false

    private var engine: SearchEngine { SearchEngine.of(w) }
    private var isWeb: Bool { engine != .files }

    var body: some View {
        HStack(spacing: 8 * s) {
            Menu {
                ForEach(SearchEngine.available) { e in
                    Button {
                        SearchEngine.set(e, for: w.id)
                    } label: {
                        if e == engine { Label(e.label, systemImage: "checkmark") } else { Label(e.label, systemImage: e.symbol) }
                    }
                }
            } label: {
                Image(systemName: engine.symbol).foregroundStyle(engine == .apple ? AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.secondary))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Suche: \(engine.label) – klicken zum Wechseln")
            TextField(engine.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13 * s))
                .focused($focused)
                .onSubmit(submit)
            CircleButton(symbol: "arrow.right", size: 24, fill: Theme.fg.opacity(0.2), action: submit)
        }
        .tilePadding(s)
        .padding(.horizontal, 4 * s)
        .contentShape(Rectangle())
        .onTapGesture { NSApp.activate(ignoringOtherApps: true); focused = true }
        .popover(isPresented: $showAI, arrowEdge: .top) {
            GeneralAIPanel(ai: ai, count: min(max(Int(w.cfg("unrollCount", "10")) ?? 10, 1), 50))
        }
        .popover(isPresented: $showResults, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if results.isEmpty {
                    Text("Keine Treffer").foregroundStyle(.secondary).padding(8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results, id: \.self) { path in
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                showResults = false
                            } label: {
                                HStack {
                                    Image(nsImage: fileIcon(path)).resizable().frame(width: 18, height: 18)
                                    VStack(alignment: .leading) {
                                        Text((path as NSString).lastPathComponent).lineLimit(1)
                                        Text((path as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.head)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            }
                            .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(10)
            .frame(width: 420)
        }
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        switch engine {
        case .apple:
            ai.ask(q)
            showAI = true
            query = ""
            return
        case .chatgpt:
            SearchEngine.askChatGPT(q)
            query = ""
            return
        case .claude:
            SearchEngine.askClaude(q)
            query = ""
            return
        default: break
        }
        if isWeb {
            engine.openWeb(q)
            query = ""
        } else {
            Shell.runAsync("/usr/bin/mdfind", ["-name", q]) { out in
                results = Array(out.split(separator: "\n").map(String.init)
                    .filter { !$0.contains("/Library/") && !$0.contains("/.") }
                    .prefix(40))
                showResults = true
            }
        }
    }
}
