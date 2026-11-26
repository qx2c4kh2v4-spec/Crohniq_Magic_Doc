import AppKit
import SwiftUI

/// Explainer page: how to add a widget and what the parts of the dock are
/// (grip, widgets, workspaces, running apps).
enum DockGuide {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Dein Dock verstehen"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DockGuideView { window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DockGuideView: View {
    let close: () -> Void

    private struct Element: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let text: String
    }

    private let elements: [Element] = [
        Element(symbol: "ellipsis", title: "Der Griff",
                text: "Die drei Punkte ganz am Rand der Leiste. Zieh daran, um die Leiste an den unteren, oberen, linken oder rechten Bildschirmrand zu setzen. Ein Rechtsklick öffnet das Menü."),
        Element(symbol: "square.grid.2x2", title: "Widgets",
                text: "Die Kacheln – Uhr, Wetter, Musik und mehr. Fahr mit der Maus darüber, dann klappen passende Listen auf. Ein Rechtsklick ändert Grösse und Optionen."),
        Element(symbol: "rectangle.3.group", title: "Arbeitsbereiche",
                text: "Die Symbole im Kopf der Leiste. Ein Klick öffnet die zugehörigen Apps und ordnet ihre Fenster an – z. B. „Büro“ oder „Entwicklung“."),
        Element(symbol: "rectangle.stack", title: "Geöffnete Programme",
                text: "Zeigt deine laufenden Apps neben den Arbeitsbereichen. Ein Klick wechselt dorthin; über das Menü lässt sich eine App beenden."),
    ]

    private let steps = [
        "Auf „Galerie öffnen“ klicken – oder Rechtsklick auf die Leiste → „Widget hinzufügen“.",
        "Ein Widget anklicken oder direkt auf die Leiste ziehen.",
        "Zum Umsortieren ein Widget in der Leiste verschieben, zum Entfernen aus der Leiste herausziehen.",
        "Ein Rechtsklick auf ein Widget ändert die Grösse (Mini bis Max) und die Optionen.",
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("WelcomeBackground")
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 820, height: 600).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.86), .black.opacity(0.72), .black.opacity(0.9)],
                                        startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        addWidgetCard
                        elementsCard
                    }
                    .padding(.vertical, 20)
                }
                footer
            }
            .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 20)
        }
        .frame(width: 820, height: 600)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("WelcomeIcon").resizable().scaledToFill().frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dein Dock verstehen")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.85, blue: 1)],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Wie du Widgets einbaust und was die Teile der Leiste bedeuten.")
                    .font(.callout).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
    }

    private var addWidgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("So baust du ein Widget ein", systemImage: "plus.app.fill")
                .font(.headline).foregroundStyle(.white)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Circle().fill(.blue))
                    Text(text).font(.callout).foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            Button {
                AppDelegate.shared.openSettings(page: .gallery)
            } label: {
                Label("Galerie öffnen", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var elementsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Die Elemente deines Docks", systemImage: "dock.rectangle")
                .font(.headline).foregroundStyle(.white)
                .padding(.bottom, 12)
            ForEach(elements) { el in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: el.symbol).font(.system(size: 22))
                        .foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(el.title).font(.body.weight(.semibold)).foregroundStyle(.white)
                        Text(el.text).font(.callout).foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                if el.id != elements.last?.id { Divider().overlay(.white.opacity(0.12)) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var footer: some View {
        HStack {
            Button("Einrichtung & Freigaben") { HelpSetup.show() }.controlSize(.large)
            Spacer()
            Button("Fertig", action: close).keyboardShortcut(.defaultAction).controlSize(.large)
        }
    }
}
