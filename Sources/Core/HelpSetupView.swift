import Combine
import AppKit
import SwiftUI

/// Second start page: how to set up Crohniq Dock and which macOS permissions it needs,
/// each with a button that opens the matching System Settings page.
enum HelpSetup {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Einrichtung & Freigaben"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HelpSetupView { window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpSetupView: View {
    let close: () -> Void
    @ObservedObject private var center = PermissionCenter.shared
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Permissions the widgets use directly (macOS asks right away).
    private var widgetKinds: [PermissionKind] {
        [.calendar, .reminders, .contacts, .photos, .location, .notifications].filter { PermissionKind.available.contains($0) }
    }
    /// Permissions for Dock, system control and the add-on modules (granted in System Settings).
    private var systemKinds: [PermissionKind] {
        [.accessibility, .automation, .screenRecording, .fullDisk, .signalKey].filter { PermissionKind.available.contains($0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("WelcomeBackground")
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 820, height: 600).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.86), .black.opacity(0.7), .black.opacity(0.9)],
                                        startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Für deine Widgets", "Kalender, Erinnerungen, Notizen, Kontakte, Fotos, Wetter und Mitteilungen. macOS fragt beim ersten Mal direkt.", widgetKinds)
                        section("Für Dock & System", "Fenster anordnen, den Finder steuern, Bildschirmfotos und die Zusatzmodule. Diese schaltest du in den Systemeinstellungen frei.", systemKinds)
                    }
                    .padding(.vertical, 20)
                }
                footer
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .frame(width: 820, height: 600)
        .environment(\.colorScheme, .dark)
        .onAppear { center.refresh() }
        .onReceive(tick) { _ in center.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("WelcomeIcon").resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("So richtest du Crohniq Dock ein")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1)],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Tippe bei jeder Freigabe auf „Öffnen“ – die passende Systemseite erscheint. Grün heißt erledigt.")
                    .font(.callout).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
    }

    private func section(_ title: String, _ subtitle: String, _ kinds: [PermissionKind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(kinds) { kind in
                    row(kind)
                    if kind != kinds.last { Divider().overlay(.white.opacity(0.12)).padding(.leading, 46) }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
    }

    private func row(_ kind: PermissionKind) -> some View {
        let status = center.status(of: kind)
        return HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.title3).foregroundStyle(.white.opacity(0.9)).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.body.weight(.medium)).foregroundStyle(.white)
                Text(kind.purpose).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if status == .granted {
                Label("Erteilt", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                    .foregroundStyle(.green).fixedSize()
            } else {
                Button("Öffnen") { center.request(kind) }.controlSize(.regular)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").foregroundStyle(.white.opacity(0.7))
            Text("Crohniq Dock liest nur auf diesem Mac und sendet nichts weiter.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                PermissionCenter.shared.relaunch()
            } label: {
                Label("Neu starten", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .help("Bedienungshilfen und Bildschirmaufnahme erkennt macOS erst nach einem Neustart.")
            Button("Dein Dock verstehen") { DockGuide.show() }.controlSize(.large)
            Button("Zu den Einstellungen") {
                AppDelegate.shared.openSettings(page: .permissions)
            }
            .controlSize(.large)
            Button("Fertig", action: close)
                .keyboardShortcut(.defaultAction).controlSize(.large)
        }
    }
}
