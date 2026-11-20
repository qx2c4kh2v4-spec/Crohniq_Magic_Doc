import FoundationModels
import SwiftUI

/// Talks to Crohniq Nexus IQ through its `nexusiq://search?query=` URL scheme.
enum Nexus {
    static func search(_ query: String) {
        var c = URLComponents()
        c.scheme = "nexusiq"
        c.host = "search"
        c.queryItems = [URLQueryItem(name: "query", value: query)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    static func openApp() {
        let candidates = ["/Applications/Crohniq Nexus IQ.app", "/Applications/Crohnic FileIQ.app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ch.crohniq.fileiq") {
            NSWorkspace.shared.open(url)
        }
    }

    static var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ch.crohniq.fileiq").map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

@Generable
struct NexusPlan {
    @Guide(description: "Kurze, hilfreiche Antwort auf Deutsch (höchstens 4 Sätze). Bei reinen Suchaufträgen ein Satz, was gesucht wird.")
    var answer: String

    @Guide(description: "0 bis 4 knappe Suchbegriffe für die Dokument-, Mail- und Bildersuche in Nexus (Namen, Firmen, Belegarten, Jahreszahlen). Leer, wenn die Frage nichts mit eigenen Dokumenten, Mails oder Bildern zu tun hat.")
    var searchTerms: [String]
}

@MainActor
final class NexusAI: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String = ""
        var terms: [String] = []
        var failed = false
    }

    @Published var turns: [Turn] = []
    @Published var busy = false
    private var session: LanguageModelSession?

    var availabilityText: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence ist in den Systemeinstellungen ausgeschaltet."
        case .unavailable(.modelNotReady): return "Das Apple-Intelligence-Modell wird noch geladen. Bitte später erneut versuchen."
        case .unavailable(.deviceNotEligible): return "Dieser Mac unterstützt Apple Intelligence nicht."
        case .unavailable: return "Apple Intelligence ist nicht verfügbar."
        }
    }

    private func makeSession() -> LanguageModelSession {
        let today = Date().formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_CH")))
        return LanguageModelSession(instructions: """
        Du bist der Assistent in der Widget-Leiste „Crohniq Dock“. Heute ist der \(today).
        Der Nutzer verwaltet mit der App „Nexus IQ“ seine Dokumente, E-Mails, Belege und Bilder.
        Wenn eine Frage eigene Unterlagen betrifft (z. B. Rechnungen, Verträge, Mails von jemandem, Fotos von einem Ort),
        erzeuge passende Suchbegriffe für Nexus. Alle Begriffe müssen gemeinsam passen, also wenige und präzise Begriffe wählen.
        Allgemeine Fragen beantwortest du direkt und knapp auf Deutsch.
        """)
    }

    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        if let text = availabilityText {
            turns.append(Turn(question: q, answer: text, failed: true))
            return
        }
        if session == nil { session = makeSession() }
        turns.append(Turn(question: q))
        let index = turns.count - 1
        busy = true
        Task {
            do {
                let response = try await session!.respond(to: q, generating: NexusPlan.self)
                turns[index].answer = response.content.answer
                turns[index].terms = Array(response.content.searchTerms
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
            } catch {
                turns[index].answer = "Die KI konnte nicht antworten: \(error.localizedDescription)"
                turns[index].failed = true
                session = nil
            }
            busy = false
        }
    }

    func reset() {
        turns = []
        session = nil
    }
}

struct NexusWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @StateObject private var ai = NexusAI()
    @State private var query = ""
    @State private var aiMode = false
    @State private var showAI = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8 * s) {
            Group {
                if let icon = Nexus.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 30 * s, height: 30 * s)
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 16 * s))
                }
            }
            .onTapGesture { Nexus.openApp() }
            .help("Nexus IQ öffnen")

            TextField(aiMode ? "Frag die KI …" : "In Nexus suchen …", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13 * s))
                .focused($focused)
                .onSubmit(submit)

            Button {
                aiMode.toggle()
                if aiMode && !ai.turns.isEmpty { showAI = true }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(aiMode ? AnyShapeStyle(aiGradient) : AnyShapeStyle(Theme.secondary))
                    .frame(width: 28 * s, height: 28 * s)
                    .background(Circle().fill(aiMode ? Color.purple.opacity(0.22) : Theme.tileHi))
            }
            .buttonStyle(.plain)
            .help(aiMode ? "KI-Modus (Apple Intelligence) – klicken für Nexus-Suche" : "Nexus-Suche – klicken für KI-Modus")

            CircleButton(symbol: ai.busy ? "ellipsis" : "arrow.right", size: 26, fill: Theme.fg.opacity(0.2), action: submit)
        }
        .tilePadding(s)
        .padding(.horizontal, 2 * s)
        .overlay {
            if aiMode {
                RoundedRectangle(cornerRadius: DockStore.shared.corner, style: .continuous)
                    .strokeBorder(aiGradient, lineWidth: 1.5)
                    .opacity(ai.busy ? 1 : 0.6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NSApp.activate(ignoringOtherApps: true); focused = true }
        .onAppear { aiMode = w.cfg("mode") == "ai" }
        .popover(isPresented: $showAI, arrowEdge: .top) { aiPanel }
    }

    private var aiGradient: LinearGradient {
        LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if aiMode {
            ai.ask(q)
            showAI = true
        } else {
            Nexus.search(q)
        }
        query = ""
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Apple Intelligence", systemImage: "sparkles").font(.headline)
                Spacer()
                Button("Neu") { ai.reset() }.disabled(ai.turns.isEmpty)
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ai.turns) { t in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t.question).font(.callout.weight(.semibold))
                                if t.answer.isEmpty {
                                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Denkt nach …").foregroundStyle(.secondary) }
                                } else {
                                    Text(t.answer).textSelection(.enabled)
                                        .foregroundStyle(t.failed ? .orange : .primary)
                                }
                                if !t.terms.isEmpty {
                                    HStack(spacing: 6) {
                                        ForEach(t.terms, id: \.self) { term in
                                            Text(term).font(.caption)
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(Capsule().fill(Color.purple.opacity(0.18)))
                                        }
                                        Spacer()
                                        Button {
                                            Nexus.search(t.terms.joined(separator: " + "))
                                            showAI = false
                                        } label: {
                                            Label("In Nexus suchen", systemImage: "arrow.up.forward.app")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                if !t.answer.isEmpty && !t.failed {
                                    Button("Antwort kopieren") { copyToPasteboard(t.answer) }
                                        .buttonStyle(.link).font(.caption)
                                }
                            }
                            .id(t.id)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 380)
                .onChange(of: ai.turns.count) { _, _ in
                    if let last = ai.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                TextField("Nachfrage …", text: $query).textFieldStyle(.roundedBorder).onSubmit(submit)
                Button("Senden", action: submit).disabled(ai.busy)
            }
            .padding(10)
        }
        .frame(width: 440)
    }
}
