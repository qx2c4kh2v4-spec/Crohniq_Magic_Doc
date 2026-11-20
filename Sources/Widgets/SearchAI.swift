import AppKit
import FoundationModels
import SwiftUI

/// Search targets: web engines plus AI assistants that are installed / available on this Mac.
enum SearchEngine: String, CaseIterable, Identifiable {
    case files, google, duckduckgo, bing, perplexity, apple, chatgpt, claude
    var id: String { rawValue }

    var label: String {
        switch self {
        case .files: "Dateien (Spotlight)"
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        case .perplexity: "Perplexity"
        case .apple: "Apple Intelligence"
        case .chatgpt: "ChatGPT"
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .files: "magnifyingglass"
        case .apple: "apple.intelligence"
        case .chatgpt: "bubble.left.and.text.bubble.right"
        case .claude: "sparkle"
        default: "globe"
        }
    }

    var placeholder: String {
        switch self {
        case .files: "Dateien finden …"
        case .apple, .chatgpt, .claude: "\(label) fragen …"
        default: "Mit \(label) suchen …"
        }
    }

    static let chatGPTID = "com.openai.chat"
    static let claudeID = "com.anthropic.claudefordesktop"

    var isAvailable: Bool {
        switch self {
        case .apple: SystemLanguageModel.default.availability == .available
        case .chatgpt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chatGPTID) != nil
        case .claude: NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeID) != nil
        default: true
        }
    }

    static var available: [SearchEngine] { allCases.filter(\.isAvailable) }

    /// Engine of a search widget (older configs used mode + engine).
    static func of(_ w: WidgetInstance) -> SearchEngine {
        if w.cfg("mode") != "web" { return .files }
        return SearchEngine(rawValue: w.cfg("engine")) ?? .google
    }

    static func set(_ e: SearchEngine, for id: UUID) {
        DockStore.shared.update(id) {
            $0.config["mode"] = e == .files ? "files" : "web"
            if e != .files { $0.config["engine"] = e.rawValue }
        }
    }

    // MARK: Sending a question

    func openWeb(_ q: String) {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let base: String
        switch self {
        case .duckduckgo: base = "https://duckduckgo.com/?q="
        case .bing: base = "https://www.bing.com/search?q="
        case .perplexity: base = "https://www.perplexity.ai/search?q="
        default: base = "https://www.google.com/search?q="
        }
        if let u = URL(string: base + enc) { NSWorkspace.shared.open(u) }
    }

    /// Claude desktop app accepts a prefilled new chat via its URL scheme.
    static func askClaude(_ q: String) {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let u = URL(string: "claude://claude.ai/new?q=\(enc)"),
           NSWorkspace.shared.urlForApplication(toOpen: u) != nil {
            NSWorkspace.shared.open(u)
        } else if let u = URL(string: "https://claude.ai/new?q=\(enc)") {
            NSWorkspace.shared.open(u)
        }
    }

    /// ChatGPT app has no query URL: open it, start a new chat and paste the question (needs Accessibility).
    static func askChatGPT(_ q: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chatGPTID) else { return }
        copyToPasteboard(q)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: cfg) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard AXIsProcessTrusted() else {
                    Notifier.notify("Frage in der Zwischenablage", "In ChatGPT mit ⌘V einfügen. Für automatisches Einfügen Bedienungshilfen erlauben.")
                    return
                }
                key(45, .maskCommand)                 // ⌘N new chat
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    key(9, .maskCommand)              // ⌘V paste
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { key(36, []) }   // Return
                }
            }
        }
    }

    private static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}

/// General questions answered on-device by Apple Intelligence.
@MainActor
final class GeneralAI: ObservableObject {
    struct Turn: Identifiable { let id = UUID(); let question: String; var answer = ""; var failed = false }
    @Published var turns: [Turn] = []
    @Published var busy = false
    private var session: LanguageModelSession?

    func ask(_ q: String) {
        guard !q.isEmpty, !busy else { return }
        guard SystemLanguageModel.default.availability == .available else {
            turns.append(Turn(question: q, answer: "Apple Intelligence ist auf diesem Mac nicht verfügbar.", failed: true))
            return
        }
        if session == nil {
            session = LanguageModelSession(instructions: "Du bist ein hilfreicher Assistent. Antworte knapp und auf Deutsch, ausser der Nutzer schreibt in einer anderen Sprache.")
        }
        turns.append(Turn(question: q))
        let i = turns.count - 1
        busy = true
        Task {
            do {
                let r = try await session!.respond(to: q)
                turns[i].answer = r.content
            } catch {
                turns[i].answer = "Keine Antwort: \(error.localizedDescription)"
                turns[i].failed = true
                session = nil
            }
            busy = false
        }
    }

    func reset() { turns = []; session = nil }
}

struct GeneralAIPanel: View {
    @ObservedObject var ai: GeneralAI
    @State private var followUp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Apple Intelligence", systemImage: "apple.intelligence").font(.headline)
                Spacer()
                Button("Neu") { ai.reset() }.disabled(ai.turns.isEmpty)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ai.turns) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.question).font(.callout.weight(.semibold))
                            if t.answer.isEmpty {
                                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Denkt nach …").foregroundStyle(.secondary) }
                            } else {
                                Text(t.answer).textSelection(.enabled).foregroundStyle(t.failed ? .orange : .primary)
                                if !t.failed {
                                    Button("Antwort kopieren") { copyToPasteboard(t.answer) }.buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 380)
            Divider()
            HStack {
                TextField("Nachfrage …", text: $followUp).textFieldStyle(.roundedBorder)
                    .onSubmit { ai.ask(followUp); followUp = "" }
                Button("Senden") { ai.ask(followUp); followUp = "" }.disabled(ai.busy || followUp.isEmpty)
            }
            .padding(10)
        }
        .frame(width: 440)
    }
}
