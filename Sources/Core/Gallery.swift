import SwiftUI
import UniformTypeIdentifiers

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
            "Öffne Apps, Projekte und Dropbox-Dateien, starte Apple-Kurzbefehle, suche Dateien in Nexus und wechsle Arbeitsbereiche."
        case .productivity:
            "Behalte deinen Tag im Blick – mit Terminen, Erinnerungen, Apple Intelligence, Fokuszeit, Pomodoro, Trink-Erinnerung, Fortschritt, Uhren und den letzten Mails."
        case .system:
            "Steuere deinen Mac schneller mit Systemwerten, Finder, Lautstärke, Copy & Paste, Bildschirmfotos samt Verlauf, Sprachmemos, Emoji, Wetter, Fotos und Musik."
        case .utility:
            "Farben aufnehmen, Währungen umrechnen, Ideen notieren – Alltagswerkzeuge, ohne extra Apps zu öffnen."
        case .business:
            "Verfolge Kennzahlen und GitHub-Aktivität oder öffne die Nutzungsübersichten von Claude, Codex, Copilot und Cursor."
        }
    }
}

struct WidgetCatalogItem: Identifiable {
    let id: String
    let kind: WidgetKind
    let title: String
    let detail: String
    let size: Int
    let config: [String: String]

    var dragPayload: String { "crohniq-widget:\(id)" }
    var category: WidgetCategory { kind.category }

    static func decodeDragPayload(_ payload: String) -> WidgetCatalogItem? {
        guard payload.hasPrefix("crohniq-widget:") else { return nil }
        let id = String(payload.dropFirst("crohniq-widget:".count))
        return WidgetCatalog.items.first { $0.id == id }
    }
}

enum WidgetCatalog {
    private static let variants: [WidgetCatalogItem] = [
        .init(id: "clock.digital", kind: .clock, title: "Digitaluhr", detail: "Uhrzeit und Datum",
              size: 2, config: ["style": "digital", "seconds": "0"]),
        .init(id: "clock.seconds", kind: .clock, title: "Uhr mit Sekunden", detail: "Digital mit Sekundenanzeige",
              size: 2, config: ["style": "digital", "seconds": "1"]),
        .init(id: "clock.analog", kind: .clock, title: "Analoguhr", detail: "Klassisches Zifferblatt",
              size: 2, config: ["style": "analog", "seconds": "0"]),
        .init(id: "clock.london", kind: .clock, title: "Weltuhr · London", detail: "Zeitzone Europe/London",
              size: 2, config: ["style": "digital", "timezone": "Europe/London", "label": "London"]),
        .init(id: "calendar.date", kind: .calendar, title: "Kalender · Datum", detail: "Kompakte Tageskachel",
              size: 1, config: ["display": "date"]),
        .init(id: "calendar.next", kind: .calendar, title: "Kalender · Nächster Termin", detail: "Zeigt den nächsten Termin",
              size: 2, config: ["display": "next"]),
        .init(id: "calendar.agenda", kind: .calendar, title: "Kalender · Agenda", detail: "Tagesübersicht mit Terminen",
              size: 4, config: ["display": "agenda"]),
        .init(id: "weather.current", kind: .weather, title: "Wetter · Aktuell", detail: "Kompakte Temperaturanzeige",
              size: 1, config: [:]),
        .init(id: "weather.forecast", kind: .weather, title: "Wetter · Vorschau", detail: "Mehr Platz für die Vorhersage",
              size: 4, config: [:]),
        .init(id: "music.mini", kind: .nowPlaying, title: "Musik · Mini", detail: "Kompakte Wiedergabe",
              size: 1, config: [:]),
        .init(id: "music.controls", kind: .nowPlaying, title: "Musik · Steuerung", detail: "Wiedergabe mit Bedienelementen",
              size: 4, config: [:]),
        .init(id: "ai.apple", kind: .appleIntelligence, title: "Apple Intelligence", detail: "Fragen direkt in der Widget-Leiste stellen",
              size: 3, config: [:])
    ]

    static var items: [WidgetCatalogItem] {
        let variantKinds: Set<WidgetKind> = [.clock, .calendar, .weather, .nowPlaying, .appleIntelligence]
        let defaults = WidgetKind.available
            .filter { !variantKinds.contains($0) }
            .map {
                WidgetCatalogItem(id: "default.\($0.rawValue)", kind: $0, title: $0.title,
                                  detail: $0.category.blurb, size: $0.defaultSize, config: [:])
            }
        return (variants.filter { $0.kind.isAvailable } + defaults)
            .sorted {
                if $0.category != $1.category {
                    return (WidgetCategory.allCases.firstIndex(of: $0.category) ?? Int.max)
                        < (WidgetCategory.allCases.firstIndex(of: $1.category) ?? Int.max)
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

struct WidgetGalleryView: View {
    var scrolls = true

    var body: some View {
        WidgetCatalogBrowser(compact: false, scrolls: scrolls)
    }
}

struct WidgetCatalogBrowser: View {
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var theme = ThemeState.shared
    @State private var selectedCategory: WidgetCategory?
    @State private var query = ""
    @State private var added: String?

    let compact: Bool
    var scrolls = true

    private var entries: [WidgetCatalogItem] {
        WidgetCatalog.items.filter { item in
            (selectedCategory == nil || item.category == selectedCategory)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.detail.localizedCaseInsensitiveContains(query)
                    || item.category.headline.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(compact ? "Widgets" : "Widget-Galerie")
                    .font(.system(size: compact ? 18 : 28, weight: .bold))
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Widgets suchen", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                .frame(maxWidth: compact ? 180 : 340)
            }
            .padding(compact ? 12 : 20)
            Divider()
            HStack(spacing: 0) {
                categorySidebar
                Divider()
                resultsPanel
            }
        }
        .overlay(alignment: .bottom) {
            if let added {
                Label("„\(added)“ hinzugefügt", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.clear)
    }

    private var categorySidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                categoryButton(nil, title: "Alle Widgets", symbol: "square.grid.2x2")
                ForEach(WidgetCategory.allCases) { category in
                    categoryButton(category, title: category.headline, symbol: categorySymbol(category))
                }
            }
            .padding(compact ? 8 : 12)
        }
        .frame(width: compact ? 142 : 190)
    }

    private var resultsPanel: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let grid = LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: compact ? 190 : 250), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(entries) { item in
                        catalogCard(item)
                    }
                }
                .padding(compact ? 12 : 20)
                if scrolls || compact {
                    ScrollView { grid }
                } else {
                    ScrollView { grid }.scrollDisabled(true)
                }
            }
        }
    }

    private func categoryButton(_ category: WidgetCategory?, title: String, symbol: String) -> some View {
        let selected = selectedCategory == category
        let count = category.map { c in WidgetCatalog.items.filter { $0.category == c }.count } ?? WidgetCatalog.items.count
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func catalogCard(_ item: WidgetCatalogItem) -> some View {
        let palette = theme.palette
        let size = min(item.size, 4)
        let unit: CGFloat = compact ? 48 : 52
        let width = CGFloat(size) * unit + CGFloat(size - 1) * 6
        return Button {
            add(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHost(instance: WidgetInstance(item.kind, size: size, config: item.config))
                    .frame(width: width, height: unit)
                    .background(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous).fill(palette.tile))
                    .clipShape(RoundedRectangle(cornerRadius: unit * 0.26, style: .continuous))
                    .environment(\.dockScale, unit / 64)
                    .environment(\.colorScheme, palette.dark ? .dark : .light)
                    .foregroundStyle(palette.fg)
                    .allowsHitTesting(false)
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: item.dragPayload as NSString) }
        .help("Klicken zum Hinzufügen oder Widget ins Dock ziehen")
    }

    private func categorySymbol(_ category: WidgetCategory) -> String {
        switch category {
        case .apps: "app.dashed"
        case .productivity: "calendar"
        case .system: "switch.2"
        case .utility: "wand.and.stars"
        case .business: "chart.bar"
        }
    }

    private func add(_ item: WidgetCatalogItem) {
        store.add(item.kind, size: item.size, config: item.config)
        withAnimation(.spring(response: 0.35)) { added = item.title }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if added == item.title { added = nil } }
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
