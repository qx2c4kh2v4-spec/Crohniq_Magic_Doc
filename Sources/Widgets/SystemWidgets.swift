import CoreWLAN
import Photos
import SwiftUI

// MARK: - Rings (battery, CPU, memory, disk)

struct RingStatWidget: View {
    let w: WidgetInstance
    @ObservedObject private var stats = SystemStats.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let (value, color, icon, label, detail) = info
        HStack(spacing: 10 * s) {
            ZStack {
                Ring(value: value, color: color, lineWidth: 4.5 * s)
                VStack(spacing: 0) {
                    Image(systemName: icon).font(.system(size: 9 * s, weight: .bold)).foregroundStyle(color)
                    Text("\(Int((value * 100).rounded()))").font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: 48 * s, height: 48 * s)
            if w.size > 1 {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(label).font(.system(size: 12 * s, weight: .semibold))
                    Text(detail).font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .help("\(label): \(detail)")
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
    }

    private var info: (Double, Color, String, String, String) {
        switch w.kind {
        case .battery:
            let c: Color = stats.battery < 0.2 ? .red : (stats.charging ? .green : .orange)
            return (stats.hasBattery ? stats.battery : 1, c, stats.charging ? "bolt.fill" : "battery.75percent", "Batterie",
                    stats.hasBattery ? (stats.charging ? "Lädt" : "Akku") : "Netzbetrieb")
        case .cpu:
            return (stats.cpu, .blue, "cpu", "CPU", "Auslastung")
        case .memory:
            return (stats.memory, .green, "memorychip", "Speicher", String(format: "%.1f GB belegt", stats.memoryUsedGB))
        default:
            return (stats.disk, .purple, "internaldrive", "Festplatte", String(format: "%.0f GB frei", stats.diskFreeGB))
        }
    }
}

struct CPUGraphWidget: View {
    let w: WidgetInstance
    @ObservedObject private var stats = SystemStats.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            HStack {
                Label("CPU", systemImage: "cpu").font(.system(size: 11 * s, weight: .medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(Int(stats.cpu * 100))%").font(.system(size: 15 * s, weight: .semibold, design: .rounded))
            }
            ZStack {
                Sparkline(values: stats.cpuHistory.map { $0 * 100 } + [100].prefix(0), closed: true)
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                Sparkline(values: stats.cpuHistory.map { $0 * 100 })
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5 * s, lineJoin: .round))
            }
        }
        .tilePadding(s)
    }
}

// MARK: - Quick toggles

struct TogglesWidget: View {
    let w: WidgetInstance
    @ObservedObject private var awake = KeepAwake.shared
    @Environment(\.dockScale) private var s
    @State private var dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    @State private var wifi = CWWiFiClient.shared().interface()?.powerOn() ?? false
    @State private var desktopHidden = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool == false

    var body: some View {
        let all: [(String, Bool, Color, String, () -> Void)] = [
            ("wifi", wifi, .blue, "WLAN", toggleWiFi),
            ("moon.fill", dark, .indigo, "Dunkelmodus", toggleDark),
            ("cup.and.saucer.fill", awake.active, .orange, "Wach halten", { awake.toggle() }),
            ("menubar.dock.rectangle", desktopHidden, .teal, "Schreibtisch-Symbole ausblenden", toggleDesktop),
            ("lock.fill", false, .gray, "Bildschirm sperren", lock),
        ]
        HStack(spacing: 8 * s) {
            ForEach(Array(all.prefix(w.size == 1 ? 1 : w.size + 1).enumerated()), id: \.offset) { _, t in
                Button(action: t.4) {
                    Image(systemName: t.0)
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(t.1 ? t.2 : Theme.fg.opacity(0.85))
                        .frame(width: 40 * s, height: 40 * s)
                        .background(Circle().fill(t.1 ? t.2.opacity(0.18) : Theme.tileHi))
                        .overlay(Circle().strokeBorder(t.1 ? t.2 : .clear, lineWidth: 2 * s))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(t.3)
            }
        }
        .tilePadding(s)
    }

    private func toggleWiFi() {
        guard let i = CWWiFiClient.shared().interface() else { return }
        do {
            try i.setPower(!i.powerOn())
            wifi = i.powerOn()
        } catch {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        }
    }

    private func toggleDark() {
        Script.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode") { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
        dark.toggle()
    }

    private func toggleDesktop() {
        desktopHidden.toggle()
        Shell.runAsync("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", desktopHidden ? "false" : "true"]) { _ in
            Shell.runAsync("/usr/bin/killall", ["Finder"])
        }
    }

    private func lock() {
        Shell.runAsync("/usr/bin/pmset", ["displaysleepnow"])
    }
}

// MARK: - Audio

struct AudioWidget: View {
    let w: WidgetInstance
    @ObservedObject private var audio = AudioControl.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        if w.size == 1 {
            VStack(spacing: 1 * s) {
                Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16 * s))
                VolumeSlider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }))
                    .frame(width: 16 * s, height: 28 * s)
                Text("\(Int(audio.volume * 100))%").font(.system(size: 11 * s, weight: .semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help("Vertikaler Regler: nach oben lauter, nach unten leiser · \(audio.deviceName)")
            .onTapGesture(count: 2) { audio.setMuted(!audio.muted) }
        } else {
            HStack(spacing: 10 * s) {
                Button { audio.setMuted(!audio.muted) } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : (audio.volume > 0.5 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"))
                        .font(.system(size: 14 * s))
                        .frame(width: 22 * s)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(audio.deviceName).font(.system(size: 11 * s, weight: .medium)).lineLimit(1)
                    VolumeSlider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }))
                        .frame(width: 16 * s, height: 38 * s)
                }
                Text("\(Int(audio.volume * 100))%").font(.system(size: 11 * s, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                if w.size >= 4 {
                    CircleButton(symbol: "airpodspro", size: 30) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                    .help("Ausgabegerät wählen")
                }
            }
            .tilePadding(s)
        }
    }
}

struct VolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            ZStack {
                Capsule().fill(Theme.fg.opacity(0.15)).frame(width: 6 * min(1, g.size.width / 12))
                Capsule().fill(Theme.fg)
                    .frame(width: 6 * min(1, g.size.width / 12), height: g.size.height * value)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Circle().fill(Theme.fg).frame(width: 12, height: 12)
                    .position(x: g.size.width / 2, y: g.size.height * (1 - value))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = max(0, min(1, 1 - v.location.y / g.size.height))
            })
        }
    }
}

// MARK: - Clipboard

struct ClipboardWidget: View {
    let w: WidgetInstance
    @ObservedObject private var clip = ClipboardHistory.shared
    @Environment(\.dockScale) private var s
    @State private var open = false

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 20 * s))
            if w.size > 1 {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("Zwischenablage").font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                    Text(clip.items.first ?? "leer").font(.system(size: 11 * s, weight: .medium)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { open = true }
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Copy & Paste – Klick kopiert").font(.headline).padding(10)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(clip.items, id: \.self) { item in
                            Button {
                                clip.copy(item)
                                open = false
                            } label: {
                                Text(item).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 380)
                if !clip.items.isEmpty {
                    Button("Verlauf leeren") { clip.items.removeAll() }.padding(10)
                }
            }
            .frame(width: 340)
        }
    }
}

// MARK: - Screenshots

struct ScreenshotWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var snapshots: [URL] = []
    @State private var showingHistory = false

    var body: some View {
        HStack(spacing: (w.size == 1 ? 8 : 4) * s) {
            if w.size > 1 {
                Button { showingHistory = true } label: {
                    if let latest = snapshots.first, let image = NSImage(contentsOf: latest) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28 * s, height: 28 * s)
                            .clipShape(RoundedRectangle(cornerRadius: 5 * s))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 16 * s))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 28 * s, height: 28 * s)
                    }
                }
                .buttonStyle(.plain)
                .help("Letzte Bildschirmfotos anzeigen")
                .popover(isPresented: $showingHistory) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Letzte Bildschirmfotos").font(.headline).padding(10)
                        Divider()
                        if snapshots.isEmpty {
                            Text("Noch keine Bildschirmfotos auf dem Schreibtisch.")
                                .font(.callout).foregroundStyle(Theme.secondary)
                                .padding(12)
                        } else {
                            ForEach(snapshots, id: \.self) { url in
                                Button {
                                    NSWorkspace.shared.open(url)
                                    showingHistory = false
                                } label: {
                                    HStack(spacing: 8) {
                                        if let image = NSImage(contentsOf: url) {
                                            Image(nsImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 48, height: 32)
                                                .clipped()
                                        }
                                        Text(url.deletingPathExtension().lastPathComponent)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 300)
                }
            }
            CircleButton(symbol: "rectangle.dashed", size: w.size == 1 ? 36 : 24,
                         fill: Color.blue.opacity(0.25), tint: .blue) { capture(["-i"]) }
                .help("Bereich (⇧ = in Zwischenablage)")
            if w.size >= 2 {
                CircleButton(symbol: "macwindow", size: 24, fill: Color.green.opacity(0.22), tint: .green) { capture(["-iW"]) }
                    .help("Fenster")
                CircleButton(symbol: "display", size: 24, fill: Color.purple.opacity(0.25), tint: .purple) { capture([]) }
                    .help("Ganzer Bildschirm")
            }
            if w.size >= 3 {
                CircleButton(symbol: "record.circle", size: 28, fill: Color.red.opacity(0.22), tint: .red) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
                }
                .help("Bildschirmaufnahme")
            }
        }
        .tilePadding(s)
        .task {
            refreshSnapshots()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                refreshSnapshots()
            }
        }
    }

    private func capture(_ args: [String]) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/Bildschirmfoto \(fmt.string(from: Date())).png"
        let clipboard = NSEvent.modifierFlags.contains(.shift)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Shell.runAsync("/usr/sbin/screencapture", args + (clipboard ? ["-c"] : [path])) { _ in
                refreshSnapshots()
            }
        }
    }

    private func refreshSnapshots() {
        let desktop = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        snapshots = ((try? FileManager.default.contentsOfDirectory(
            at: desktop,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { url in
                let name = url.lastPathComponent
                return imageExtensions.contains(url.pathExtension.lowercased())
                    && (name.localizedCaseInsensitiveContains("Bildschirmfoto")
                        || name.localizedCaseInsensitiveContains("Screenshot")
                        || name.localizedCaseInsensitiveContains("Screen Shot"))
            }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .prefix(8)
            .map { $0 }
    }
}

// MARK: - Voice memo

struct VoiceMemoWidget: View {
    let w: WidgetInstance
    @ObservedObject private var rec = VoiceRecorder.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            if w.size == 1 {
                VStack(spacing: 2 * s) {
                    CircleButton(symbol: rec.recording ? "stop.fill" : "mic.fill", size: 32, fill: .red) { rec.toggle() }
                    Text(String(format: "%d:%02d", Int(rec.elapsed) / 60, Int(rec.elapsed) % 60))
                        .font(.system(size: 10 * s, weight: .semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            } else {
            Text(String(format: "%d:%02d", Int(rec.elapsed) / 60, Int(rec.elapsed) % 60))
                .font(.system(size: 20 * s, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(alignment: .center, spacing: 2 * s) {
                ForEach(Array(rec.levels.suffix(w.size == 2 ? 10 : 22).enumerated()), id: \.offset) { _, l in
                    Capsule().fill(rec.recording ? Color.red : Theme.fg.opacity(0.3))
                        .frame(width: 2.5 * s, height: max(3, 30 * s * l))
                }
            }
            .frame(maxWidth: .infinity)
            CircleButton(symbol: rec.recording ? "stop.fill" : "mic.fill", size: 34, fill: .red) { rec.toggle() }
            }
        }
        .tilePadding(s)
    }
}

// MARK: - Emoji

struct EmojiWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var copied: String?

    var body: some View {
        let emojis = w.cfg("emojis").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let perRow = w.size * 2
        let shown = Array(emojis.prefix(perRow * 2 - 1))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: perRow), spacing: 2 * s) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, e in
                Text(copied == e ? "✓" : e).font(.system(size: 17 * s))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyToPasteboard(e)
                        copied = e
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if copied == e { copied = nil } }
                    }
            }
            Image(systemName: "plus").font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.orderFrontCharacterPalette(nil) }
        }
        .tilePadding(s)
        .help("Klick kopiert das Emoji")
    }
}

// MARK: - Photos

struct PhotosWidget: View {
    let w: WidgetInstance
    @ObservedObject private var library = PhotoLibrary.shared
    @Environment(\.dockScale) private var s
    @State private var offset = 0

    private var visibleAssets: [PHAsset] {
        let count = min(w.size == 1 ? 1 : w.size * 2, library.assets.count)
        guard count > 0 else { return [] }
        return (0..<count).map { library.assets[(offset + $0) % library.assets.count] }
    }

    var body: some View {
        Group {
            if library.authorization == .denied || library.authorization == .restricted {
                Button {
                    PhotoLibrary.openPrivacySettings()
                } label: {
                    VStack(spacing: 4 * s) {
                        Image(systemName: "lock.photo").font(.system(size: 18 * s))
                        if w.size > 1 {
                            Text("Fotos-Zugriff erlauben").font(.system(size: 9 * s))
                        }
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else if visibleAssets.isEmpty {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22 * s))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: min(w.size, visibleAssets.count)),
                    spacing: 2 * s
                ) {
                    ForEach(visibleAssets, id: \.localIdentifier) { asset in
                        PhotoThumbnail(
                            asset: asset,
                            targetSize: CGSize(width: 180 * s, height: 100 * s)
                        )
                        .frame(height: 27 * s)
                        .clipShape(RoundedRectangle(cornerRadius: 4 * s))
                    }
                }
                .padding(4 * s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { openPhotos() }
        .onWidgetAction(w.id) { a in
            if a == "next", !library.assets.isEmpty { offset = (offset + 1) % library.assets.count }
            if a == "reveal" { openPhotos() }
        }
        .task {
            guard DockStore.shared.instance(w.id) != nil else { return }
            library.refresh()
        }
    }

    private func openPhotos() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
    }
}

struct PhotosHoverList: View {
    @ObservedObject private var library = PhotoLibrary.shared

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Fotomediathek", systemImage: "photo.on.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    library.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Fotomediathek aktualisieren")
            }
            .padding(.horizontal, 12)

            if library.authorization == .denied || library.authorization == .restricted {
                Button("Zugriff in den Systemeinstellungen erlauben") {
                    PhotoLibrary.openPrivacySettings()
                }
                .buttonStyle(.link)
                .padding(.horizontal, 12)
            } else if library.assets.isEmpty {
                Text("Keine Fotos gefunden.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(library.assets.prefix(18), id: \.localIdentifier) { asset in
                            PhotoHoverCell(asset: asset)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 340)
            }
        }
        .task { library.refresh() }
    }
}

private struct PhotoHoverCell: View {
    let asset: PHAsset
    @State private var hovered = false

    var body: some View {
        PhotoThumbnail(asset: asset, targetSize: CGSize(width: 240, height: 180))
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(hovered ? 1.16 : 1)
            .zIndex(hovered ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: hovered)
            .onHover { hovered = $0 }
            .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app")) }
        }
}
