import CoreWLAN
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
            VStack(spacing: 3 * s) {
                Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 18 * s))
                Text("\(Int(audio.volume * 100))%").font(.system(size: 11 * s, weight: .semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { audio.setMuted(!audio.muted) }
            .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                audio.setVolume(Float(max(0, min(1, Double(audio.volume) - v.translation.height / 400))))
            })
            .help("Klick = stumm, ziehen = Lautstärke · \(audio.deviceName)")
        } else {
        HStack(spacing: 10 * s) {
            Button { audio.setMuted(!audio.muted) } label: {
                Image(systemName: audio.muted ? "speaker.slash.fill" : (audio.volume > 0.5 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 14 * s))
                    .frame(width: 22 * s)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(audio.deviceName).font(.system(size: 11 * s, weight: .medium)).lineLimit(1)
                VolumeSlider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }))
                    .frame(height: 14 * s)
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
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fg.opacity(0.15)).frame(height: 6)
                Capsule().fill(Theme.fg).frame(width: max(6, g.size.width * value), height: 6)
                Circle().fill(Theme.fg).frame(width: 12, height: 12).offset(x: max(0, g.size.width * value - 6))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = max(0, min(1, v.location.x / g.size.width))
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
                Text("Verlauf – Klick kopiert").font(.headline).padding(10)
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

    var body: some View {
        HStack(spacing: 8 * s) {
            CircleButton(symbol: "rectangle.dashed", size: 36, fill: Color.blue.opacity(0.25), tint: .blue) { capture(["-i"]) }
                .help("Bereich (⇧ = in Zwischenablage)")
            if w.size >= 2 {
                CircleButton(symbol: "macwindow", size: 36, fill: Color.green.opacity(0.22), tint: .green) { capture(["-iW"]) }
                    .help("Fenster")
                CircleButton(symbol: "display", size: 36, fill: Color.purple.opacity(0.25), tint: .purple) { capture([]) }
                    .help("Ganzer Bildschirm")
            }
            if w.size >= 3 {
                CircleButton(symbol: "record.circle", size: 36, fill: Color.red.opacity(0.22), tint: .red) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
                }
                .help("Bildschirmaufnahme")
            }
        }
        .tilePadding(s)
    }

    private func capture(_ args: [String]) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/Bildschirmfoto \(fmt.string(from: Date())).png"
        let clipboard = NSEvent.modifierFlags.contains(.shift)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Shell.runAsync("/usr/sbin/screencapture", args + (clipboard ? ["-c"] : [path]))
        }
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
    @Environment(\.dockScale) private var s
    @State private var current: URL?
    @State private var image: NSImage?
    @State private var pool: [URL] = []

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo.on.rectangle").font(.system(size: 22 * s)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if let current { NSWorkspace.shared.open(current) } }
        .onWidgetAction(w.id) { a in
            if a == "next" { next() }
            if a == "reveal", let current { NSWorkspace.shared.activateFileViewerSelecting([current]) }
        }
        .task(id: w.cfg("folder")) {
            await loadPool()
            while !Task.isCancelled {
                next()
                try? await Task.sleep(for: .seconds(max(1, w.cfgInt("interval", 10)) * 60))
            }
        }
    }

    private func loadPool() async {
        let folder = URL(fileURLWithPath: (w.cfg("folder") as NSString).expandingTildeInPath)
        let result: [URL] = await Task.detached(priority: .utility) {
            let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff"]
            var found: [URL] = []
            let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL, found.count < 800 {
                if exts.contains(u.pathExtension.lowercased()) { found.append(u) }
            }
            return found
        }.value
        pool = result
    }

    private func next() {
        guard let u = pool.randomElement() else { return }
        current = u
        Task.detached(priority: .utility) {
            let img = NSImage(contentsOf: u).map { thumbnail($0) }
            await MainActor.run { image = img }
        }
    }
}

private func thumbnail(_ img: NSImage) -> NSImage {
    let maxSide: CGFloat = 400
    let size = img.size
    guard size.width > maxSide || size.height > maxSide else { return img }
    let scale = maxSide / max(size.width, size.height)
    let target = NSSize(width: size.width * scale, height: size.height * scale)
    let out = NSImage(size: target)
    out.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: target))
    out.unlockFocus()
    return out
}
