import AppKit
import SwiftUI

/// The purchase / activation page for the add-on. Opened from a locked widget, the welcome card,
/// a promo bubble or the menu.
enum AddonUnlock {
    /// Download / giveaway page (GitHub Releases of the giveaway repo).
    static let downloadURL = URL(string: "https://github.com/qx2c4kh2v4-spec/Crohniq_Dock_GifAway/releases/latest")!
    private static var window: NSWindow?

    static func show(highlight: WidgetKind? = nil) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Crohniq Dock freischalten"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: UnlockView(highlight: highlight) { window?.close() })
            window = w
        } else {
            (window?.contentView as? NSHostingView<UnlockView>)?.rootView = UnlockView(highlight: highlight) { window?.close() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct UnlockView: View {
    let highlight: WidgetKind?
    let close: () -> Void
    @ObservedObject private var entitlements = Entitlements.shared
    @State private var code = ""
    @State private var failed = false

    private var premiumKinds: [WidgetKind] { WidgetKind.allCases.filter(\.isPremium) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("WelcomeBackground")
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 560, height: 560).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.84), .black.opacity(0.78), .black.opacity(0.92)],
                                        startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            content
                .padding(28)
        }
        .frame(width: 560, height: 560)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        if entitlements.unlocked {
            unlockedState
        } else {
            lockedState
        }
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image("WelcomeIcon").resizable().scaledToFill().frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Premium freischalten")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1)],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("Diese Zusatzfunktionen schaltest du mit dem Code dauerhaft frei – auf allen Macs deiner Familie.")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let highlight {
                HStack(spacing: 10) {
                    Image(systemName: highlight.symbol).font(.title3).foregroundStyle(.yellow)
                    Text(highlight.promoPitch).font(.callout.weight(.medium)).foregroundStyle(.white)
                    Spacer()
                }
                .padding(12)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            featureGrid

            codeCard

            HStack {
                Button {
                    NSWorkspace.shared.open(AddonUnlock.downloadURL)
                } label: {
                    Label("Giveaway & Download öffnen", systemImage: "gift.fill")
                }
                .controlSize(.large)
                Spacer()
                Button("Später", action: close).controlSize(.large)
            }
        }
    }

    /// Shows the fixed unlock code with copy + one-click activation (plus a manual field).
    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dein Freischaltcode").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                Text(Activation.universal)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Activation.universal, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .controlSize(.large).help("Code kopieren")
            }
            Button {
                code = Activation.universal
                activate()
            } label: {
                Label("Jetzt freischalten", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            if failed {
                Label("Code nicht erkannt. Bitte prüfe die Eingabe.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }

    private var unlockedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Freigeschaltet – danke!").font(.title2.weight(.bold)).foregroundStyle(.white)
            Text("Alle Add-on-Funktionen sind jetzt aktiv. Neue Funktionen in späteren Updates schalten sich automatisch frei.")
                .font(.callout).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 400)
            Button("Schliessen", action: close).keyboardShortcut(.defaultAction).controlSize(.large).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(premiumKinds) { kind in
                HStack(spacing: 7) {
                    Image(systemName: kind.symbol).font(.caption).foregroundStyle(.white.opacity(0.9)).frame(width: 18)
                    Text(kind.title).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func activate() {
        if entitlements.activate(code) {
            failed = false
        } else {
            failed = true
        }
    }
}
