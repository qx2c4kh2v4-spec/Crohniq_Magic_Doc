import AppKit
import SwiftUI

/// The purchase / activation page for the add-on. Opened from a locked widget, the welcome card,
/// a promo bubble or the menu.
enum AddonUnlock {
    /// Download / giveaway page (GitHub Releases of the giveaway repo).
    static let downloadURL = URL(string: "https://github.com/qx2c4kh2v4-spec/Crohniq_Dock_GifAway/releases/latest")!
    /// Where the licences are sold (set once the shop is live).
    static let buyBaseURL = URL(string: "https://dock.crohniq.ch/#kaufen")!
    static let buyPremiumURL = URL(string: "https://dock.crohniq.ch/#kaufen")!
    static let basePrice = "2,99 €"
    static let premiumPrice = "9,99 €"
    private static var window: NSWindow?

    static func show(highlight: WidgetKind? = nil) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
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
                .frame(width: 560, height: 500).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.84), .black.opacity(0.78), .black.opacity(0.92)],
                                        startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            content
                .padding(28)
        }
        .frame(width: 560, height: 500)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("WelcomeIcon").resizable().scaledToFill().frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crohniq Dock freischalten")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1)],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("Eine Lizenz gilt für alle Macs deiner Familie.")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                }
            }

            trialBanner

            buyOptions

            codeEntry

            Button("Später", action: close).controlSize(.large).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var trialBanner: some View {
        if entitlements.inTrial {
            Label("Testphase: noch \(entitlements.trialDaysLeft) \(entitlements.trialDaysLeft == 1 ? "Tag" : "Tage") – alle Funktionen frei.",
                  systemImage: "clock.fill")
                .font(.callout.weight(.medium)).foregroundStyle(.white)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Label("Deine Testphase ist abgelaufen. Zum Weiternutzen eine Lizenz freischalten.",
                  systemImage: "lock.fill")
                .font(.callout.weight(.medium)).foregroundStyle(.orange)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var buyOptions: some View {
        HStack(spacing: 12) {
            buyCard(title: "Basis", price: AddonUnlock.basePrice,
                    desc: "Alle freien Widgets dauerhaft.", url: AddonUnlock.buyBaseURL, highlight: false)
            buyCard(title: "Premium", price: AddonUnlock.premiumPrice,
                    desc: "Alles frei – inkl. Kalender, KI, Fotos & mehr.", url: AddonUnlock.buyPremiumURL, highlight: true)
        }
    }

    private func buyCard(title: String, price: String, desc: String, url: URL, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.white)
                if highlight {
                    Text("alles").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.yellow))
                }
            }
            Text(price).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(desc).font(.caption).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Button {
                NSWorkspace.shared.open(url)
            } label: { Text("Kaufen").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.regular)
                .tint(highlight ? .blue : .gray)
        }
        .padding(13).frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(highlight ? .blue.opacity(0.6) : .white.opacity(0.12), lineWidth: highlight ? 1.5 : 1))
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schon einen Code? Hier einlösen:").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                TextField("Lizenzcode", text: $code)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .onSubmit(activate)
                Button("Freischalten", action: activate)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if failed {
                Label("Code nicht erkannt. Bitte prüfe die Eingabe.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
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
        failed = entitlements.activate(code) == nil
    }
}
