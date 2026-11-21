import CoreWLAN
import Combine
import CoreMedia
import ScreenCaptureKit
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
        VStack(spacing: 4 * s) {
            HStack(spacing: 4 * s) {
                Button { audio.setMuted(!audio.muted) } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : (audio.volume > 0.5 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"))
                        .font(.system(size: 14 * s))
                        .frame(width: 20 * s, height: 20 * s)
                }
                .buttonStyle(.plain)
                .help("Stumm schalten")
                if w.size > 1 {
                    Text(audio.deviceName).font(.system(size: 11 * s, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(Int(audio.volume * 100))%").font(.system(size: 11 * s, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                if w.size >= 4 {
                    CircleButton(symbol: "airpodspro", size: 30) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                    .help("Ausgabegerät wählen")
                }
            }
            VolumeSlider(value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }))
                .frame(maxWidth: .infinity)
                .frame(height: 22 * s)
        }
        .padding(.horizontal, min(6 * s, 8))
        .padding(.vertical, 4 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Lautstärke regeln · \(audio.deviceName)")
    }
}

struct VolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: 0...1)
            .tint(.accentColor)
            .accessibilityLabel("Lautstärke")
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

@MainActor
final class ScreenRecordingController: ObservableObject {
    static let shared = ScreenRecordingController()

    @Published private(set) var isStarting = false
    @Published private(set) var isRecording = false
    @Published private(set) var isStopping = false
    @Published private(set) var error: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputDelegate: ScreenRecordingOutputDelegate?

    func start() {
        guard !isStarting, !isRecording, !isStopping else { return }
        isStarting = true
        error = nil

        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first
                else {
                    throw NSError(domain: "ScreenRecording", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Kein Bildschirm zur Aufnahme gefunden."])
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
                configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.queueDepth = 5
                configuration.capturesAudio = true

                let outputURL = Self.makeOutputURL()
                let outputConfiguration = SCRecordingOutputConfiguration()
                outputConfiguration.outputURL = outputURL
                let delegate = ScreenRecordingOutputDelegate()
                let controller = self
                delegate.onStarted = { [weak controller] in
                    controller?.isStarting = false
                    controller?.isRecording = true
                }
                delegate.onFinished = { [weak controller] in
                    controller?.finishRecording()
                }
                delegate.onError = { [weak controller] error in
                    controller?.handleRecordingError(error)
                }

                let output = SCRecordingOutput(configuration: outputConfiguration, delegate: delegate)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                self.stream = stream
                self.recordingOutput = output
                self.outputDelegate = delegate

                try stream.addRecordingOutput(output)
                try await stream.startCapture()
            } catch {
                isStarting = false
                isRecording = false
                self.error = "Aufnahme fehlgeschlagen: \(error.localizedDescription). Prüfe ggf. die Bildschirmaufnahme-Berechtigung in den Systemeinstellungen."
                clearRecordingReferences()
            }
        }
    }

    func stop() {
        guard let stream, !isStopping else { return }
        isStopping = true
        Task {
            do {
                try await stream.stopCapture()
            } catch {
                self.error = "Aufnahme konnte nicht beendet werden: \(error.localizedDescription)"
                isStopping = false
            }
        }
    }

    private func handleRecordingError(_ error: Error) {
        self.error = "Videoaufnahme fehlgeschlagen: \(error.localizedDescription)"
        guard let stream else {
            clearRecordingReferences()
            return
        }
        isStopping = true
        Task {
            do {
                try await stream.stopCapture()
                clearRecordingReferences()
            } catch {
                self.error = "\(self.error ?? "Aufnahmefehler") \(error.localizedDescription)"
                isStopping = false
            }
        }
    }

    private func finishRecording() {
        isStarting = false
        isRecording = false
        isStopping = false
        clearRecordingReferences()
    }

    private func clearRecordingReferences() {
        stream = nil
        recordingOutput = nil
        outputDelegate = nil
        isStarting = false
        isRecording = false
        isStopping = false
    }

    private static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        let desktop = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        let stem = "Bildschirmvideo \(formatter.string(from: Date()))"
        var url = desktop.appendingPathComponent("\(stem).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("\(stem) \(suffix).mp4")
            suffix += 1
        }
        return url
    }
}

private final class ScreenRecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    var onStarted: (() -> Void)?
    var onFinished: (() -> Void)?
    var onError: ((Error) -> Void)?

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in self?.onStarted?() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in self?.onFinished?() }
    }
}

struct ScreenshotWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @ObservedObject private var recording = ScreenRecordingController.shared
    @State private var snapshots: [URL] = []
    @State private var recordings: [URL] = []
    @State private var showingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
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
                    .help("Letzte Bildschirmfotos und -videos anzeigen")
                    .popover(isPresented: $showingHistory) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Letzte Aufnahmen").font(.headline).padding(10)
                            Divider()
                            if snapshots.isEmpty && recordings.isEmpty {
                                Text("Noch keine Aufnahmen auf dem Schreibtisch.")
                                    .font(.callout).foregroundStyle(Theme.secondary)
                                    .padding(12)
                            }
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
                            if !recordings.isEmpty {
                                Divider().padding(.vertical, 4)
                                Text("Bildschirmvideos").font(.subheadline.weight(.semibold)).padding(.horizontal, 10)
                                ForEach(recordings, id: \.self) { url in
                                    Button {
                                        NSWorkspace.shared.open(url)
                                        showingHistory = false
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "video.fill").foregroundStyle(.red)
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
                    CircleButton(
                        symbol: recording.isStarting ? "ellipsis.circle" : recording.isRecording ? "stop.circle.fill" : "record.circle",
                        size: 28,
                        fill: recording.isRecording ? Color.red.opacity(0.4) : Color.red.opacity(0.22),
                        tint: .red
                    ) {
                        if recording.isRecording { recording.stop() } else { recording.start() }
                    }
                    .disabled(recording.isStarting || recording.isStopping)
                    .help(recording.isRecording ? "Bildschirmvideo stoppen" : "Bildschirmvideo mit Systemton aufnehmen")
                }
            }
            if w.size >= 3 {
                if let error = recording.error {
                    Text(error).font(.system(size: 8 * s)).foregroundStyle(.orange).lineLimit(2).help(error)
                } else if recording.isStarting {
                    Text("Aufnahme wird gestartet …").font(.system(size: 8 * s)).foregroundStyle(Theme.secondary)
                } else if recording.isRecording {
                    Text(recording.isStopping ? "Aufnahme wird beendet …" : "Aufnahme läuft · Stopp zum Beenden")
                        .font(.system(size: 8 * s)).foregroundStyle(.red)
                }
            }
        }
        .tilePadding(s)
        .onChange(of: recording.isRecording) { _, isRecording in
            if !isRecording { refreshSnapshots() }
        }
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
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: desktop,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        snapshots = entries
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
        recordings = entries
            .filter { url in
                let name = url.lastPathComponent
                return ["mov", "mp4"].contains(url.pathExtension.lowercased())
                    && (name.localizedCaseInsensitiveContains("Bildschirmvideo")
                        || name.localizedCaseInsensitiveContains("Bildschirmaufnahme")
                        || name.localizedCaseInsensitiveContains("Screen Recording"))
            }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .prefix(5)
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

    private var visibleAssets: [PHAsset] {
        let count = min(max(Int(w.cfg("count", "5")) ?? 5, 1), 12)
        return Array(library.assets.prefix(count))
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
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: min(3, visibleAssets.count)),
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

private enum PanoramaSlide: Identifiable {
    case photo(PHAsset)
    case wallpaper(URL)

    var id: String {
        switch self {
        case .photo(let asset): "photo:\(asset.localIdentifier)"
        case .wallpaper(let url): "wallpaper:\(url.path)"
        }
    }

    var label: String {
        switch self {
        case .photo: "Panorama"
        case .wallpaper: "Apple-Hintergrund"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "pano.fill"
        case .wallpaper: "apple.logo"
        }
    }
}

struct PanoramasHoverList: View {
    let count: Int
    @ObservedObject private var library = PhotoLibrary.shared
    @State private var status: String?

    private var slides: [PanoramaSlide] {
        let limit = min(max(count, 1), 50)
        let photos = library.panoramas
        let wallpapers = library.appleWallpapers
        var result: [PanoramaSlide] = []
        var photoIndex = 0
        var wallpaperIndex = 0

        while result.count < limit && (photoIndex < photos.count || wallpaperIndex < wallpapers.count) {
            if photoIndex < photos.count {
                result.append(.photo(photos[photoIndex]))
                photoIndex += 1
            }
            if result.count < limit, wallpaperIndex < wallpapers.count {
                result.append(.wallpaper(wallpapers[wallpaperIndex]))
                wallpaperIndex += 1
            }
        }
        return result
    }

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Hintergrundbilder", systemImage: "pano.fill")
                    .font(.headline)
                Spacer()
                Button {
                    library.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Bilder aktualisieren")
            }
            .padding(.horizontal, 12)

            if slides.isEmpty {
                Text("Keine Panorama-Fotos oder Apple-Hintergrundbilder gefunden.")
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 12)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(slides) { slide in
                        Button {
                            setWallpaper(slide)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                slideThumbnail(slide)
                                    .frame(height: 70)
                                Image(systemName: slide.symbol)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Capsule().fill(.black.opacity(0.55)))
                                    .padding(5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Als Hintergrund für alle Monitore verwenden")
                    }
                }
                .padding(.horizontal, 12)
            }

            if let status {
                Text(status).font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            }
        }
        .onAppear { library.refresh() }
    }

    @ViewBuilder
    private func slideThumbnail(_ slide: PanoramaSlide) -> some View {
        switch slide {
        case .photo(let asset):
            PhotoThumbnail(asset: asset, targetSize: CGSize(width: 168, height: 140))
        case .wallpaper(let url):
            AppleWallpaperThumbnail(url: url)
        }
    }

    private func setWallpaper(_ slide: PanoramaSlide) {
        switch slide {
        case .wallpaper(let url):
            apply(url)
        case .photo(let asset):
            PhotoLibrary.shared.requestImage(for: asset, size: CGSize(width: 3840, height: 2160)) { image in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
                    status = "Das Foto konnte nicht vorbereitet werden."
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("crohniq-wallpaper-\(UUID().uuidString).jpg")
                do {
                    try jpeg.write(to: url)
                    apply(url)
                } catch {
                    status = "Das Foto konnte nicht gespeichert werden."
                }
            }
        }
    }

    private func apply(_ url: URL) {
        var failed = false
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                failed = true
            }
        }
        status = failed ? "Einige Monitore konnten nicht aktualisiert werden." : "Hintergrundbild wurde gesetzt."
    }
}

struct PanoramasWidget: View {
    let w: WidgetInstance
    @ObservedObject private var library = PhotoLibrary.shared
    @State private var currentIndex = 0

    private var slides: [PanoramaSlide] {
        let count = min(max(w.cfgInt("count", 10), 1), 50)
        let photos = library.panoramas
        let wallpapers = library.appleWallpapers
        var result: [PanoramaSlide] = []
        var photoIndex = 0
        var wallpaperIndex = 0

        while result.count < count && (photoIndex < photos.count || wallpaperIndex < wallpapers.count) {
            if photoIndex < photos.count {
                result.append(.photo(photos[photoIndex]))
                photoIndex += 1
            }
            if result.count < count && wallpaperIndex < wallpapers.count {
                result.append(.wallpaper(wallpapers[wallpaperIndex]))
                wallpaperIndex += 1
            }
        }
        return result
    }

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
        let interval = min(max(w.cfgInt("interval", 30), 5), 3600)
        return Timer.publish(every: TimeInterval(interval), on: .main, in: .common).autoconnect()
    }

    var body: some View {
        GeometryReader { geometry in
            let visibleSlides = slides
            let index = visibleSlides.isEmpty ? 0 : currentIndex % visibleSlides.count
            ZStack(alignment: .bottomLeading) {
                if visibleSlides.isEmpty {
                    Rectangle()
                        .fill(Theme.tileHi)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 18, weight: .medium))
                                Text(library.authorization == .denied || library.authorization == .restricted
                                     ? "Fotos-Zugriff erlauben" : "Keine Panorama-Fotos gefunden")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(Theme.secondary)
                        }
                } else {
                    slideView(visibleSlides[index], size: geometry.size)
                        .id(visibleSlides[index].id)
                        .transition(.opacity)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    HStack(spacing: 5) {
                        Image(systemName: visibleSlides[index].symbol)
                        Text("\(visibleSlides[index].label) · \(index + 1)/\(visibleSlides.count)")
                        Spacer(minLength: 0)
                        if visibleSlides.count > 1 {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 7)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if slides.isEmpty && (library.authorization == .denied || library.authorization == .restricted) {
                    PhotoLibrary.openPrivacySettings()
                } else {
                    advance()
                }
            }
            .animation(.easeInOut(duration: 0.8), value: currentIndex)
        }
        .task { library.refresh() }
        .onReceive(timer) { _ in advance() }
    }

    @ViewBuilder
    private func slideView(_ slide: PanoramaSlide, size: CGSize) -> some View {
        switch slide {
        case .photo(let asset):
            PhotoThumbnail(asset: asset, targetSize: CGSize(width: size.width * 2, height: size.height * 2))
        case .wallpaper(let url):
            AppleWallpaperThumbnail(url: url)
        }
    }

    private func advance() {
        guard slides.count > 1 else { return }
        currentIndex = (currentIndex + 1) % slides.count
    }
}

private struct AppleWallpaperThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.tileHi)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

struct PhotosHoverList: View {
    let count: Int
    @ObservedObject private var library = PhotoLibrary.shared

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]
    private var limit: Int { min(max(count, 1), 12) }

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
                        ForEach(library.assets.prefix(limit), id: \.localIdentifier) { asset in
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
