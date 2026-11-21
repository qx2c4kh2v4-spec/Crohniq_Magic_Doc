import SwiftUI

// MARK: - Widget gallery (category cards with live previews)

extension WidgetCategory {
    var headline: String {
        switch self {
        case .apps: "Apps, Dateien & Schnellzugriff"
        case .productivity: "Produktivität & Tagesfokus"
        case .system: "Mac-Steuerung & Systemwerkzeuge"
        case .utility: "Kreativ- & Hilfswerkzeuge"
        case .business: "Business & Entwickler"
        }
    }

    var blurb: String {
        switch self {
        case .apps:
            "Öffne deine Lieblings-Apps und Projekte, suche Dateien und in Nexus, halte Dateien in der Ablage, wechsle Arbeitsbereiche und hab alles Wichtige nur einen Klick entfernt."
        case .productivity:
            "Behalte deinen Tag im Blick – mit Terminen, Erinnerungen, Pomodoro, Trink-Erinnerung, Fortschritt, Uhren und Mail."
        case .system:
            "Steuere deinen Mac schneller mit Systemwerten, Finder, Lautstärke, Copy & Paste, Bildschirmfotos samt Verlauf, Sprachmemos, Emoji, Wetter, Fotos und Musik."
        case .utility:
            "Farben aufnehmen, Währungen umrechnen, Ideen notieren – Alltagswerkzeuge, ohne extra Apps zu öffnen."
        case .business:
            "Verfolge Kennzahlen aus deinen Diensten und deine GitHub-Aktivität direkt in der Leiste."
        }
    }
}

struct WidgetGalleryView: View {
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var theme = ThemeState.shared
    @State private var added: WidgetKind?
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .overlay(alignment: .bottom) {
            if let k = added {
                Label("„\(k.title)“ hinzugefügt", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Widgets").font(.system(size: 34, weight: .bold))
                    Text("Klicke auf ein Widget, um es in die Leiste „\(store.profiles[store.activeIndex].name)“ aufzunehmen. Grösse und Reihenfolge änderst du danach direkt in der Leiste.")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 22, alignment: .top)], spacing: 22) {
                    ForEach(WidgetCategory.allCases) { cat in card(cat) }
                }
            }
            .padding(28)
    }

    private func card(_ cat: WidgetCategory) -> some View {
        let kinds = WidgetKind.available.filter { $0.category == cat }
        return VStack(alignment: .leading, spacing: 14) {
            Text(cat.headline).font(.system(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(cat.blurb).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Text("Enthält: " + kinds.map(\.title).joined(separator: ", ") + ".")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 10) {
                ForEach(kinds) { kind in
                    PreviewTile(kind: kind) { add(kind) }
                }
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func add(_ kind: WidgetKind) {
        store.add(kind)
        withAnimation(.spring(response: 0.35)) { added = kind }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if added == kind { added = nil } }
        }
    }
}

/// A real, non-interactive rendering of the widget at its default size.
struct PreviewTile: View {
    let kind: WidgetKind
    let onAdd: () -> Void
    @State private var hover = false
    @State private var instance: WidgetInstance

    private let unit: CGFloat = 60
    private let gap: CGFloat = 8

    init(kind: WidgetKind, onAdd: @escaping () -> Void) {
        self.kind = kind
        self.onAdd = onAdd
        _instance = State(initialValue: WidgetInstance(kind))
    }

    var body: some View {
        let p = ThemeState.shared.palette
        let size = previewSize
        let w = CGFloat(size) * unit + CGFloat(size - 1) * gap
        Button(action: onAdd) {
            WidgetHost(instance: instance)
                .frame(width: w, height: unit)
                .background(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous).fill(p.tile))
                .clipShape(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous))
                .environment(\.dockScale, unit / 64)
                .environment(\.colorScheme, p.dark ? .dark : .light)
                .foregroundStyle(p.fg)
                .allowsHitTesting(false)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: unit * 0.26 + 5, style: .continuous).fill(p.bar))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 6, y: -6)
                        .opacity(hover ? 1 : 0)
                }
                .scaleEffect(hover ? 1.04 : 1)
                .shadow(color: .black.opacity(hover ? 0.25 : 0.08), radius: hover ? 8 : 3, y: 2)
                .animation(.spring(response: 0.25), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(kind.title) hinzufügen")
    }

    /// Wide widgets are previewed a bit smaller so the cards stay balanced.
    private var previewSize: Int {
        let s = kind.defaultSize
        return min(s, kind.sizes.last ?? s, 4)
    }
}

/// Wraps its children into lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
