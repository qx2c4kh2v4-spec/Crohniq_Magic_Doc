import AppKit
import ApplicationServices
import Contacts
import CoreLocation
import EventKit
import Photos
import SwiftUI
import UserNotifications

// MARK: - Model

enum PermissionStatus: Equatable {
    case granted, missing, unknown, notInstalled

    var label: String {
        switch self {
        case .granted: "Erteilt"
        case .missing: "Fehlt"
        case .unknown: "Noch nicht geprüft"
        case .notInstalled: "App nicht installiert"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .missing: .orange
        case .unknown: .secondary
        case .notInstalled: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle"
        case .notInstalled: "minus.circle"
        }
    }
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, fullDisk, automation, signalKey, calendar, reminders, contacts, photos, location, notifications, screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Bedienungshilfen"
        case .fullDisk: "Festplattenvollzugriff"
        case .automation: "Automatisierung (Finder)"
        case .signalKey: "Signal-Schlüssel"
        case .calendar: "Kalender"
        case .reminders: "Erinnerungen"
        case .contacts: "Kontakte"
        case .photos: "Fotos"
        case .location: "Ortungsdienste"
        case .notifications: "Mitteilungen"
        case .screenRecording: "Bildschirmaufnahme"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .fullDisk: "internaldrive"
        case .automation: "gearshape.2"
        case .signalKey: "key.fill"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        case .photos: "photo.on.rectangle"
        case .location: "location.fill"
        case .notifications: "bell.badge"
        case .screenRecording: "record.circle"
        }
    }

    /// What the permission is used for.
    var purpose: String {
        switch self {
        case .accessibility: "Menüs der Apps im Dock lesen (Fenster, zuletzt verwendet), Fragen an ChatGPT abschicken und Fenster der Arbeitsbereiche anordnen."
        case .fullDisk: "WhatsApp-Chats sowie Safari-Verlauf und -Lesezeichen lesen. macOS schützt diese Daten anderer Apps besonders."
        case .automation: "Finder steuern: Papierkorb öffnen und leeren, Ordner anzeigen."
        case .signalKey: "Signal-Chats anzeigen. Signal verschlüsselt seine Datenbank; der Schlüssel liegt im Schlüsselbund."
        case .calendar: "Termine im Kalender-Widget und in der Liste anzeigen."
        case .reminders: "Erinnerungen anzeigen und abhaken."
        case .contacts: "Absender in der Mail-Liste bekannten Kontakten zuordnen."
        case .photos: "Fotos-Widget und Hintergrundbilder aus der Fotomediathek."
        case .location: "Wetter für den aktuellen Ort."
        case .notifications: "Hinweise, z. B. wenn ein Timer abläuft."
        case .screenRecording: "Bildschirmaufnahmen mit dem Bildschirmfoto-Widget."
        }
    }

    /// How the user grants it, shown in the guided setup.
    var steps: [String] {
        switch self {
        case .accessibility, .fullDisk, .screenRecording:
            ["„Freigeben“ klicken – die Systemeinstellungen öffnen sich.",
             "In der Liste „Crohniq Dock“ einschalten (fehlt es, mit + aus „Programme“ hinzufügen).",
             self == .accessibility ? "Hierher zurückkommen – der Schritt wird automatisch abgehakt."
                 : "Crohniq Dock neu starten, damit macOS die Freigabe übernimmt."]
        case .signalKey:
            ["„Freigeben“ klicken.",
             "Im Schlüsselbund-Dialog das Mac-Passwort eingeben und „Immer erlauben“ wählen."]
        case .automation:
            ["„Freigeben“ klicken.", "Im Dialog „OK“ wählen, damit Crohniq Dock den Finder steuern darf."]
        default:
            ["„Freigeben“ klicken.", "Im Dialog von macOS „Erlauben“ wählen.",
             "Wurde früher abgelehnt: in den Systemeinstellungen „Crohniq Dock“ einschalten."]
        }
    }

    /// Takes effect only after Crohniq Dock restarts.
    var needsRestart: Bool { self == .fullDisk || self == .screenRecording }

    var settingsURL: URL? {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .fullDisk: pane = "Privacy_AllFiles"
        case .automation: pane = "Privacy_Automation"
        case .calendar: pane = "Privacy_Calendars"
        case .reminders: pane = "Privacy_Reminders"
        case .contacts: pane = "Privacy_Contacts"
        case .photos: pane = "Privacy_Photos"
        case .location: pane = "Privacy_LocationServices"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .signalKey: return nil
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var status: [PermissionKind: PermissionStatus] = [:]
    @Published var signalError: String?
    private var locationManager: CLLocationManager?

    func refresh() {
        var s: [PermissionKind: PermissionStatus] = [:]
        s[.accessibility] = AXIsProcessTrusted() ? .granted : .missing
        s[.fullDisk] = Self.hasFullDiskAccess() ? .granted : .missing
        s[.signalKey] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SignalChats.bundleID) == nil
            ? .notInstalled : (SignalChats.hasKey ? .granted : (signalError == nil ? .unknown : .missing))
        s[.calendar] = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .granted : .missing
        s[.reminders] = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? .granted : .missing
        s[.contacts] = CNContactStore.authorizationStatus(for: .contacts) == .authorized ? .granted : .missing
        let photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        s[.photos] = photos == .authorized || photos == .limited ? .granted : .missing
        let location = CLLocationManager().authorizationStatus
        s[.location] = location == .authorizedAlways || location == .authorized ? .granted : .missing
        s[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .missing
        s[.automation] = status[.automation] ?? .unknown
        s[.notifications] = status[.notifications] ?? .unknown
        status = s

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = [.authorized, .provisional].contains(settings.authorizationStatus)
            Task { @MainActor in self.status[.notifications] = granted ? .granted : .missing }
        }
        DispatchQueue.global(qos: .utility).async {
            let result = Self.automationStatus(ask: false)
            Task { @MainActor in self.status[.automation] = result }
        }
    }

    func status(of kind: PermissionKind) -> PermissionStatus { status[kind] ?? .unknown }

    var relevant: [PermissionKind] { PermissionKind.allCases.filter { status(of: $0) != .notInstalled } }
    var grantedCount: Int { relevant.filter { status(of: $0) == .granted }.count }

    /// Asks macOS for the permission where an app can ask; otherwise opens the matching settings page.
    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings(kind) }
        case .fullDisk:
            openSettings(kind)
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(kind) }
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.automationStatus(ask: true)
                Task { @MainActor in
                    self.status[.automation] = result
                    if result == .missing { self.openSettings(kind) }
                }
            }
        case .signalKey:
            signalError = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let error = SignalChats.requestAccess()
                Task { @MainActor in self.signalError = error; self.refresh() }
            }
        case .calendar:
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                EventStore.shared.store.requestFullAccessToEvents { _, _ in Task { @MainActor in self.refresh() } }
            } else { openSettings(kind) }
        case .reminders:
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                EventStore.shared.store.requestFullAccessToReminders { _, _ in Task { @MainActor in self.refresh() } }
            } else { openSettings(kind) }
        case .contacts:
            if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
                CNContactStore().requestAccess(for: .contacts) { _, _ in Task { @MainActor in self.refresh() } }
            } else { openSettings(kind) }
        case .photos:
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in Task { @MainActor in self.refresh() } }
            } else { openSettings(kind) }
        case .location:
            let manager = CLLocationManager()
            if manager.authorizationStatus == .notDetermined {
                locationManager = manager
                manager.requestWhenInUseAuthorization()
            } else { openSettings(kind) }
        case .notifications:
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        Task { @MainActor in self.refresh() }
                    }
                } else {
                    Task { @MainActor in self.openSettings(kind) }
                }
            }
        }
    }

    func openSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// Restarts Crohniq Dock, so permissions that apply only at launch take effect.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Checks

    /// The user's TCC database is readable only with Full Disk Access.
    nonisolated static func hasFullDiskAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1))?.isEmpty == false
    }

    nonisolated static func automationStatus(ask: Bool) -> PermissionStatus {
        var address = AEAddressDesc()
        let bundleID = "com.apple.finder"
        let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &address) }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&address) }
        switch AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .unknown
        default: return .missing
        }
    }
}

// MARK: - View

/// Settings page that lists every permission and walks through the missing ones.
struct PermissionsView: View {
    @ObservedObject private var center = PermissionCenter.shared
    @State private var guided = false
    @State private var step: PermissionKind?
    @State private var skipped: Set<PermissionKind> = []
    private let tick = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if guided { guide } else { startCard }
                VStack(spacing: 0) {
                    ForEach(PermissionKind.allCases) { kind in
                        row(kind)
                        if kind != PermissionKind.allCases.last { Divider().padding(.leading, 52) }
                    }
                }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.opacity(0.35)))
                Text("Crohniq Dock liest nur auf diesem Mac und sendet nichts weiter. Jede Freigabe lässt sich in den Systemeinstellungen unter „Datenschutz & Sicherheit“ wieder entziehen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear { center.refresh() }
        .onReceive(tick) { _ in
            center.refresh()
            advanceIfDone()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.system(size: 34)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Freigaben").font(.title2.weight(.semibold))
                Text("\(center.grantedCount) von \(center.relevant.count) erteilt").foregroundStyle(.secondary)
                ProgressView(value: Double(center.grantedCount), total: Double(max(1, center.relevant.count)))
                    .frame(maxWidth: 260)
            }
            Spacer()
        }
    }

    private var openSteps: [PermissionKind] {
        center.relevant.filter { center.status(of: $0) != .granted && !skipped.contains($0) }
    }

    private var startCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(openSteps.isEmpty ? "Alles eingerichtet" : "Geführte Einrichtung").font(.headline)
                Text(openSteps.isEmpty
                     ? "Alle Freigaben sind erteilt oder bewusst übersprungen."
                     : "Schritt für Schritt durch die \(openSteps.count) fehlenden Freigaben – jede mit Erklärung, wofür sie gebraucht wird.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !openSteps.isEmpty {
                Button("Starten") {
                    skipped = []
                    step = openSteps.first
                    guided = true
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
    }

    @ViewBuilder private var guide: some View {
        if let kind = step {
            let status = center.status(of: kind)
            let all = center.relevant.filter { center.status(of: $0) != .granted || $0 == kind }
            let index = (all.firstIndex(of: kind) ?? 0) + 1
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Schritt \(index) von \(max(index, all.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Beenden") { guided = false; step = nil }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: kind.symbol).font(.system(size: 30)).foregroundStyle(.tint).frame(width: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kind.title).font(.title3.weight(.semibold))
                            Label(status.label, systemImage: status.symbol).font(.caption.weight(.semibold))
                                .foregroundStyle(status.color)
                        }
                        Text(kind.purpose).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(kind.steps.enumerated()), id: \.offset) { i, text in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                        .frame(width: 18, height: 18).background(Circle().fill(.tint))
                                    Text(text).font(.callout)
                                }
                            }
                        }
                        .padding(.top, 4)
                        if kind == .signalKey, let error = center.signalError {
                            Text(error).font(.callout).foregroundStyle(.orange)
                        }
                    }
                }
                HStack {
                    Button("Überspringen") { skip(kind) }
                    Spacer()
                    if status == .granted {
                        Label("Erledigt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Weiter") { next(after: kind) }.buttonStyle(.borderedProminent)
                    } else {
                        if kind.needsRestart {
                            Button("Crohniq Dock neu starten") { center.relaunch() }
                        }
                        Button("Freigeben") { center.request(kind) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.tint.opacity(0.12)))
            .animation(.easeInOut(duration: 0.25), value: status)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Fertig").font(.headline)
                    Text(skipped.isEmpty ? "Alle Freigaben sind erteilt." : "\(skipped.count) Freigaben übersprungen – sie lassen sich unten jederzeit nachholen.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schliessen") { guided = false }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.green.opacity(0.12)))
        }
    }

    private func row(_ kind: PermissionKind) -> some View {
        let status = center.status(of: kind)
        return HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.body.weight(.medium))
                Text(kind.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            Label(status.label, systemImage: status.symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(status.color)
                .fixedSize()
            if status == .missing || status == .unknown {
                Button("Freigeben") { center.request(kind) }.controlSize(.small)
            } else if status == .granted, kind.settingsURL != nil {
                Button { center.openSettings(kind) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("In den Systemeinstellungen anzeigen")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func skip(_ kind: PermissionKind) {
        skipped.insert(kind)
        next(after: kind)
    }

    private func next(after kind: PermissionKind) {
        withAnimation { step = openSteps.first { $0 != kind } }
    }

    /// Moves on by itself shortly after the current permission was granted.
    private func advanceIfDone() {
        guard guided, let kind = step, center.status(of: kind) == .granted, !kind.needsRestart else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if step == kind { next(after: kind) }
        }
    }
}
