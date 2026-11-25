import AppKit
import Foundation
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

    /// The older ChatGPT app ("ChatGPT Classic").
    static let chatGPTID = "com.openai.chat"
    /// The current ChatGPT app (bundle id from its Codex base); takes a prompt via `codex://threads/new?prompt=`.
    static let chatGPTNewID = "com.openai.codex"

    /// The ChatGPT app to use: the current one when installed, otherwise ChatGPT Classic.
    static var chatGPTAppID: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: chatGPTNewID) != nil ? chatGPTNewID : chatGPTID
    }
    static let claudeID = "com.anthropic.claudefordesktop"

    var isAvailable: Bool {
        switch self {
        case .apple: true
        case .chatgpt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chatGPTAppID) != nil
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
        // Current ChatGPT app: opens a new chat with the question already in it.
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: chatGPTNewID) != nil {
            var link = URLComponents(string: "codex://threads/new")!
            link.queryItems = [URLQueryItem(name: "prompt", value: q)]
            if let url = link.url {
                NSWorkspace.shared.open(url)
                // Send it, if the question is only placed in the input field (needs Accessibility).
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard AXIsProcessTrusted(),
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == chatGPTNewID else { return }
                    key(36, [])
                }
                return
            }
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chatGPTID) else {
            // No app installed: the website takes the question as a parameter.
            let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            if let u = URL(string: "https://chatgpt.com/?q=\(enc)") { NSWorkspace.shared.open(u) }
            return
        }
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
    struct Turn: Identifiable, Codable { let id = UUID(); let question: String; var answer = ""; var failed = false }
    static let shared = GeneralAI()

    @Published var turns: [Turn] = []
    @Published var busy = false
    private var session: LanguageModelSession?
    private let historyKey = "ai.general.history"

    private init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([Turn].self, from: data) {
            turns = Array(saved.suffix(50))
        }
    }

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
        if turns.count > 50 { turns.removeFirst(turns.count - 50) }
        saveHistory()
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
            saveHistory()
            busy = false
        }
    }

    func reset() {
        turns = []
        session = nil
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(turns) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

struct GeneralAIPanel: View {
    @ObservedObject var ai: GeneralAI
    let count: Int
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
                    ForEach(ai.turns.suffix(min(max(count, 1), 50))) { t in
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

/// Question field for the Claude or ChatGPT app, laid out like the Apple Intelligence widget.
struct AIAppAskWidget: View {
    let w: WidgetInstance
    let engine: SearchEngine
    @State private var question = ""
    @State private var sent = false
    @FocusState private var focused: Bool
    @Environment(\.dockScale) private var s

    private var bundleID: String { engine == .claude ? SearchEngine.claudeID : SearchEngine.chatGPTAppID }
    private var tint: Color {
        engine == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.06, green: 0.64, blue: 0.5)
    }
    private var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var body: some View {
        HStack(spacing: 8 * s) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 24 * s, height: 24 * s)
                } else {
                    Image(systemName: engine.symbol).font(.system(size: 20 * s, weight: .medium)).foregroundStyle(tint)
                }
            }
            .onTapGesture { openApp() }
            .help("\(engine.label) öffnen")
            TextField(sent ? "Gesendet an \(engine.label) ✓" : "\(engine.label) fragen …", text: $question)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * s))
                .focused($focused)
                .onSubmit(submit)
                .onTapGesture {
                    NSApp.activate(ignoringOtherApps: true)
                    focused = true
                }
            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Frage an \(engine.label) senden")
        }
        .tilePadding(s)
    }

    private func submit() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if engine == .claude { SearchEngine.askClaude(prompt) } else { SearchEngine.askChatGPT(prompt) }
        question = ""
        focused = false
        sent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { sent = false }
    }

    private func openApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: engine == .claude ? "https://claude.ai/new" : "https://chatgpt.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AppleIntelligenceWidget: View {
    let w: WidgetInstance
    @StateObject private var ai = GeneralAI.shared
    @State private var question = ""
    @State private var showingAI = false
    @FocusState private var focused: Bool
    @Environment(\.dockScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 20 * s, weight: .medium))
                .foregroundStyle(.purple)
            TextField("Apple Intelligence fragen …", text: $question)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * s))
                .focused($focused)
                .onSubmit(submit)
                .onTapGesture {
                    NSApp.activate(ignoringOtherApps: true)
                    focused = true
                }
            Button(action: submit) {
                Image(systemName: ai.busy ? "ellipsis" : "paperplane.fill")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .disabled(ai.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Frage an Apple Intelligence senden")
        }
        .tilePadding(s)
        .popover(isPresented: $showingAI, arrowEdge: .top) {
            GeneralAIPanel(ai: ai, count: min(max(Int(w.cfg("unrollCount", "10")) ?? 10, 1), 50))
        }
    }

    private func submit() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        ai.ask(prompt)
        question = ""
        showingAI = true
    }
}
