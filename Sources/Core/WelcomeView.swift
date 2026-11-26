import AppKit
import SwiftUI

/// Start page shown at launch (until switched off): what Crohniq Dock is, plus the free giveaway on GitHub.
enum Welcome {
    static let giveawayURL = URL(string: "https://github.com/qx2c4kh2v4-spec/Crohniq_Dock_GifAway")!
    private static let showKey = "welcome.showAtLaunch"

    /// On by default, so the page appears on the first launch.
    static var showAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: showKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showKey) }
    }

    private static let firstRunKey = "welcome.firstRunDone"
    /// True until the first launch has been acknowledged (used to open the setup help once).
    static var firstRun: Bool {
        if UserDefaults.standard.bool(forKey: firstRunKey) { return false }
        UserDefaults.standard.set(true, forKey: firstRunKey)
        return true
    }

    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Willkommen bei Crohniq Dock"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView { window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// "Version 1.0 · Build 32 · 26.11.2026" – the date is when this build was made.
    static var buildLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        let built = (try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        return "Version \(version) · Build \(build) · \(built.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))"
    }
}

struct WelcomeView: View {
    let close: () -> Void
    @State private var showAtLaunch = Welcome.showAtLaunch

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                header
                headline.padding(.top, 34)
                giveawayCard.padding(.top, 20)
                // Leaves the bar in the background picture visible.
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .frame(width: 820, height: 520)
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        Image("WelcomeBackground")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 820, height: 520)
            .clipped()
            .overlay(
                LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.35), .black.opacity(0.05), .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
            )
            .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("WelcomeIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Crohniq Dock").font(.headline).foregroundStyle(.white)
                Text(Welcome.buildLine).font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Willkommen bei Crohniq Dock")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            Text("Dein Mac – auf einen Blick. Termine, Musik, Wetter, Fokus und KI in einer gläsernen Leiste direkt über deinem Dock.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var giveawayCard: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "gift.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 1, green: 0.45, blue: 0.45)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("Premium kostenlos freischalten").font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("Als Giveaway schaltest du alle Zusatzfunktionen gratis frei – Kalender, KI, Erinnerungen und mehr. Code eingeben, fertig.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                close()
                AddonUnlock.show()
            } label: {
                Label("Jetzt freischalten", systemImage: "lock.open.fill")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }

    private var footer: some View {
        HStack {
            Toggle("Diese Seite beim Start anzeigen", isOn: $showAtLaunch)
                .toggleStyle(.checkbox)
                .foregroundStyle(.white.opacity(0.85))
                .onChange(of: showAtLaunch) { _, on in Welcome.showAtLaunch = on }
            Spacer()
            Button {
                close()
                DockGuide.show()
            } label: {
                Label("Dock verstehen", systemImage: "dock.rectangle")
            }
            .controlSize(.large)
            Button {
                close()
                HelpSetup.show()
            } label: {
                Label("Einrichtung & Hilfe", systemImage: "wand.and.stars")
            }
            .controlSize(.large)
            Button("Los geht’s") {
                close()
                // On the first launch, guide straight to permissions.
                if Welcome.firstRun { AppDelegate.shared.openSettings(page: .permissions) }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }
}
