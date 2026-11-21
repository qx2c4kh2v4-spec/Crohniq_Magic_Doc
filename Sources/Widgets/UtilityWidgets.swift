import SwiftUI
import Foundation

// MARK: - Color picker

struct ColorPickerWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var copied = false

    private var history: [String] { w.cfg("history").split(separator: ",").map(String.init) }

    var body: some View {
        let colors = Array(history.prefix(w.size == 1 ? 3 : w.size * 3))
        HStack(spacing: 8 * s) {
            Grid(horizontalSpacing: 3 * s, verticalSpacing: 3 * s) {
                GridRow {
                    swatch(colors[safe: 0]); swatch(colors[safe: 1])
                }
                GridRow {
                    swatch(colors[safe: 2])
                    Image(systemName: copied ? "checkmark" : "eyedropper")
                        .font(.system(size: 11 * s, weight: .bold))
                        .frame(width: 20 * s, height: 20 * s)
                        .background(RoundedRectangle(cornerRadius: 5 * s).fill(Theme.tileHi))
                        .onTapGesture(perform: pick)
                }
            }
            if w.size > 1 {
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(colors.first ?? "Farbe wählen").font(.system(size: 12 * s, weight: .semibold, design: .monospaced))
                    HStack(spacing: 3 * s) {
                        ForEach(colors.dropFirst(3), id: \.self) { swatch($0, size: 14) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .help("Pipette: Farbe vom Bildschirm aufnehmen. Klick auf ein Feld kopiert den Hex-Wert.")
    }

    @ViewBuilder private func swatch(_ hex: String?, size: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: 5 * s)
            .fill(hex.flatMap(Color.init(hex:)) ?? Theme.fg.opacity(0.1))
            .frame(width: size * s, height: size * s)
            .onTapGesture {
                if let hex { copyToPasteboard(hex); flash() } else { pick() }
            }
    }

    private func flash() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }

    private func pick() {
        NSColorSampler().show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            copyToPasteboard(hex)
            var h = history.filter { $0 != hex }
            h.insert(hex, at: 0)
            DockStore.shared.setConfig(w.id, "history", h.prefix(12).joined(separator: ","))
            flash()
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Currency converter

final class RateCache: ObservableObject {
    static let shared = RateCache()
    @Published var rates: [String: Double] = [:]   // "EUR>CHF" -> rate
    private var fetched: [String: Date] = [:]

    func rate(_ from: String, _ to: String) -> Double? {
        if from == to { return 1 }
        let key = "\(from)>\(to)"
        if fetched[key].map({ Date().timeIntervalSince($0) > 3600 }) ?? true {
            fetched[key] = Date()
            Task {
                guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(from)&symbols=\(to)"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let r = (j["rates"] as? [String: Any])?[to] as? Double else { return }
                await MainActor.run { self.rates[key] = r }
            }
        }
        return rates[key]
    }
}

struct ConverterWidget: View {
    let w: WidgetInstance
    @ObservedObject private var cache = RateCache.shared
    @Environment(\.dockScale) private var s
    @FocusState private var focused: Bool

    var body: some View {
        let from = w.cfg("from", "EUR").uppercased(), to = w.cfg("to", "CHF").uppercased()
        let amount = Double(w.cfg("amount", "100").replacingOccurrences(of: ",", with: ".")) ?? 0
        let rate = cache.rate(from, to)
        let result = rate.map { (amount * $0).formatted(.number.precision(.fractionLength(2)).locale(AppLanguageSettings.shared.locale)) } ?? "…"
        HStack(spacing: 8 * s) {
            VStack(alignment: .leading, spacing: 0) {
                if w.size > 1 {
                    TextField("Betrag", text: DockStore.shared.binding(w.id, "amount"))
                        .textFieldStyle(.plain).font(.system(size: 12 * s)).foregroundStyle(Theme.secondary)
                        .focused($focused)
                        .onTapGesture { NSApp.activate(ignoringOtherApps: true); focused = true }
                }
                Text(result).font(.system(size: (w.size == 1 ? 14 : 24) * s, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if w.size == 1 { Text("\(from)→\(to)").font(.system(size: 9 * s)).foregroundStyle(Theme.secondary) }
            }
            if w.size > 1 {
                Spacer(minLength: 0)
                VStack(spacing: 2 * s) {
                    currencyTag(from)
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 9 * s, weight: .bold)).foregroundStyle(Theme.secondary)
                        .onTapGesture {
                            DockStore.shared.update(w.id) { $0.config["from"] = to; $0.config["to"] = from }
                        }
                    currencyTag(to)
                }
            }
        }
        .tilePadding(s)
        .help(rate.map { "1 \(from) = \(String(format: "%.4f", $0)) \(to) (EZB-Kurs)" } ?? "Kurs wird geladen …")
    }

    private func currencyTag(_ c: String) -> some View {
        Text(c).font(.system(size: 10 * s, weight: .bold))
            .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
            .background(RoundedRectangle(cornerRadius: 5 * s).fill(Theme.tileHi))
    }
}

// MARK: - GitHub

final class GitHubService: ObservableObject {
    struct Stats { var days: [Int] = []; var today = 0; var week = 0; var streak = 0; var followers = 0; var repos = 0; var error: String? }
    static let shared = GitHubService()
    @Published var stats: [String: Stats] = [:]
    private var fetched: [String: Date] = [:]

    func load(user: String, token: String) {
        guard !user.isEmpty else { return }
        if let f = fetched[user], Date().timeIntervalSince(f) < 900 { return }
        fetched[user] = Date()
        Task {
            var st = Stats()
            if !token.isEmpty {
                let q = #"{"query":"query($u:String!){user(login:$u){followers{totalCount} repositories{totalCount} contributionsCollection{contributionCalendar{weeks{contributionDays{contributionCount}}}}}}","variables":{"u":"\#(user)"}}"#
                var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
                req.httpMethod = "POST"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.httpBody = q.data(using: .utf8)
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let u = (j["data"] as? [String: Any])?["user"] as? [String: Any] {
                    st.followers = (u["followers"] as? [String: Any])?["totalCount"] as? Int ?? 0
                    st.repos = (u["repositories"] as? [String: Any])?["totalCount"] as? Int ?? 0
                    let weeks = (((u["contributionsCollection"] as? [String: Any])?["contributionCalendar"] as? [String: Any])?["weeks"] as? [[String: Any]]) ?? []
                    st.days = weeks.flatMap { ($0["contributionDays"] as? [[String: Any]] ?? []).map { $0["contributionCount"] as? Int ?? 0 } }
                    st.today = st.days.last ?? 0
                    st.week = st.days.suffix(7).reduce(0, +)
                    var streak = 0
                    for (i, d) in st.days.reversed().enumerated() {
                        if d > 0 { streak += 1 } else if i > 0 { break }
                    }
                    st.streak = streak
                } else {
                    st.error = "Token prüfen"
                }
            } else if let url = URL(string: "https://api.github.com/users/\(user)"),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                st.followers = j["followers"] as? Int ?? 0
                st.repos = j["public_repos"] as? Int ?? 0
            }
            await MainActor.run { self.stats[user] = st }
        }
    }
}

struct GitHubWidget: View {
    let w: WidgetInstance
    @ObservedObject private var gh = GitHubService.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let user = w.cfg("user")
        Group {
            if user.isEmpty {
                Button("GitHub-Benutzer eintragen") { AppDelegate.shared.openSettings(selecting: w.id) }
                    .buttonStyle(.plain).font(.system(size: 11 * s)).foregroundStyle(Color.accentColor)
            } else if let st = gh.stats[user] {
                if st.days.isEmpty || w.size == 1 {
                    VStack(alignment: w.size == 1 ? .center : .leading, spacing: 1 * s) {
                        Text(st.days.isEmpty ? "\(st.followers)" : "\(st.today)")
                            .font(.system(size: 20 * s, weight: .semibold, design: .rounded))
                        Text(st.days.isEmpty ? "Follower · \(st.repos) Repos" : "heute")
                            .font(.system(size: 9 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
                        if let e = st.error { Text(e).font(.system(size: 9 * s)).foregroundStyle(.orange) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4 * s) {
                        HStack(spacing: 8 * s) {
                            Text("**\(st.today)** heute").font(.system(size: 10 * s))
                            Text("**\(st.week)** Woche").font(.system(size: 10 * s))
                            Text("🔥 **\(st.streak)**").font(.system(size: 10 * s))
                            Spacer(minLength: 0)
                        }
                        let cols = w.size * 6
                        let recent = Array(st.days.suffix(cols * 3))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: cols), spacing: 2 * s) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, n in
                                RoundedRectangle(cornerRadius: 1.5 * s)
                                    .fill(n == 0 ? Theme.fg.opacity(0.1) : Color.green.opacity(min(1, 0.35 + Double(n) * 0.13)))
                                    .frame(height: 6 * s)
                            }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: "https://github.com/\(user)") { NSWorkspace.shared.open(u) } }
        .onAppear { gh.load(user: user, token: w.cfg("token")) }
        .onChange(of: user + w.cfg("token")) { _, _ in gh.load(user: user, token: w.cfg("token")) }
    }
}

@MainActor
final class DeveloperUsageStore: ObservableObject {
    static let shared = DeveloperUsageStore()

    struct Value {
        var primary = "Wird geladen …"
        var secondary = "Wird geladen …"
    }

    @Published private(set) var values: [DeveloperUsageProvider: Value] = [:]

    private init() {}

    func value(for provider: DeveloperUsageProvider) -> Value {
        values[provider] ?? Value()
    }

    func refresh() {
        Task { await refreshCodex() }
        Task { await refreshClaude() }
        values[.cursor] = Value(
            primary: "Kontingent:",
            secondary: "Im Cursor-Dashboard öffnen"
        )
    }

    private func refreshCodex() async {
        guard let auth = try? JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory() + "/.codex/auth.json")),
            options: []
        ) as? [String: Any],
        let tokens = auth["tokens"] as? [String: Any],
        let accessToken = tokens["access_token"] as? String else {
            await MainActor.run { values[.codex] = Value(primary: "Nicht angemeldet", secondary: "Codex-Dashboard öffnen") }
            return
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = json["rate_limit"] as? [String: Any] else {
            await MainActor.run { values[.codex] = Value(primary: "Nicht abrufbar", secondary: "Offizielles Dashboard öffnen") }
            return
        }

        let primary = rate["primary_window"] as? [String: Any]
        let used = Int((primary?["used_percent"] as? NSNumber)?.doubleValue ?? 0)
        let resetSeconds = Int((primary?["reset_after_seconds"] as? NSNumber)?.doubleValue ?? 0)
        let resetText = resetSeconds > 0
            ? "Reset in \(usageResetText(resetSeconds))"
            : "Zeitfenster"
        await MainActor.run {
            values[.codex] = Value(
                primary: "Verbraucht: \(used) %",
                secondary: resetText
            )
        }
    }

    private func refreshClaude() async {
        guard let credentials = loadClaudeCredentials() else {
            await MainActor.run { values[.claude] = Value(primary: "Nicht abrufbar", secondary: "Claude neu anmelden") }
            return
        }

        var accessToken = credentials.accessToken
        if credentials.expiresAt <= Date().timeIntervalSince1970 * 1000,
           let refreshed = await refreshClaudeToken(credentials) {
            accessToken = refreshed
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await MainActor.run { values[.claude] = Value(primary: "Nicht abrufbar", secondary: "Claude neu anmelden") }
            return
        }

        let fiveHour = (json["five_hour"] as? [String: Any])?["utilization"]
        let sevenDay = (json["seven_day"] as? [String: Any])?["utilization"]
        let shortUsed = Int((fiveHour as? NSNumber)?.doubleValue ?? 0)
        let weekUsed = Int((sevenDay as? NSNumber)?.doubleValue ?? 0)
        await MainActor.run {
            values[.claude] = Value(
                primary: "5 Std.: \(shortUsed) %",
                secondary: "Woche: \(weekUsed) %"
            )
        }
    }

    private struct ClaudeCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double
        let clientId: String
        let scopes: [String]
    }

    private func loadClaudeCredentials() -> ClaudeCredentials? {
        let names = ["Claude Code-credentials-5ea55c61", "Claude Code-credentials"]
        for name in names {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", name, "-w"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let accessToken = oauth["accessToken"] as? String,
                  let refreshToken = oauth["refreshToken"] as? String else { continue }
            return ClaudeCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0,
                clientId: (oauth["clientId"] as? String) ?? "9d1c250a-e61b-44d9-88ed-26761c68b7e8",
                scopes: (oauth["scopes"] as? [String]) ?? ["org:create_api_key", "user:profile", "user:inference"]
            )
        }
        return nil
    }

    private func refreshClaudeToken(_ credentials: ClaudeCredentials) async -> String? {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": credentials.clientId,
            "scope": credentials.scopes.joined(separator: " ")
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else { return nil }
        return accessToken
    }

    private func usageResetText(_ seconds: Int) -> String {
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600 { return "\(seconds / 3600)h" }
        return "\(seconds / 60)m"
    }
}

struct DeveloperUsageWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var openError: String?
    @StateObject private var usage = DeveloperUsageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 5 * s) {
                Image(systemName: "speedometer")
                    .foregroundStyle(Color.accentColor)
                Text("Kontingente").font(.system(size: 10 * s, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    usage.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8 * s))
                }
                .buttonStyle(.plain)
                .help("Nutzung aktualisieren")
            }
            HStack(alignment: .top, spacing: 6 * s) {
                ForEach(DeveloperUsageProvider.allCases) { provider in
                    Button { open(provider) } label: {
                        VStack(alignment: .leading, spacing: 2 * s) {
                            HStack(spacing: 4 * s) {
                                Image(systemName: provider.symbol)
                                Text(provider.title).font(.system(size: 9 * s, weight: .medium))
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            let value = usage.value(for: provider)
                            Text(value.primary)
                                .font(.system(size: 7 * s, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                            Text(value.secondary)
                                .font(.system(size: 6 * s))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(provider.help)
                }
            }
            .frame(height: 34 * s)
            if let openError {
                Text(openError).font(.system(size: 8 * s)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { usage.refresh() }
        .help("Echte Kontingentdaten; Klick öffnet die offizielle Anbieterübersicht.")
    }

    private func open(_ provider: DeveloperUsageProvider) {
        guard let url = URL(string: provider.url) else {
            openError = "Die Anbieter-Adresse ist ungültig."
            return
        }
        guard NSWorkspace.shared.open(url) else {
            openError = "\(provider.title) konnte nicht geöffnet werden."
            return
        }
        openError = nil
    }
}

enum DeveloperUsageProvider: String, CaseIterable, Identifiable {
    case claude, codex, cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "sparkles"
        case .cursor: "cursorarrow.rays"
        }
    }

    var url: String {
        switch self {
        case .claude: "https://claude.ai/settings/usage"
        case .codex: "https://chatgpt.com/codex/settings/usage"
        case .cursor: "https://cursor.com/settings"
        }
    }

    var help: String {
        switch self {
        case .claude: "Claude-Plan und Verbrauch öffnen"
        case .codex: "Codex-Nutzungsübersicht öffnen"
        case .cursor: "Cursor-Kontoeinstellungen öffnen"
        }
    }
}

// MARK: - Generic JSON metric (Plausible, Stripe, Shopify, own APIs …)

final class MetricService: ObservableObject {
    static let shared = MetricService()
    @Published var values: [UUID: Double] = [:]
    @Published var errors: [UUID: String] = [:]
    private var fetched: [UUID: Date] = [:]

    func load(_ w: WidgetInstance, force: Bool = false) {
        let urlString = w.cfg("url")
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        let interval = Double(max(1, w.cfgInt("interval", 15))) * 60
        if !force, let f = fetched[w.id], Date().timeIntervalSince(f) < interval { return }
        fetched[w.id] = Date()
        var req = URLRequest(url: url)
        for line in w.cfg("header").split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { req.setValue(parts[1], forHTTPHeaderField: parts[0]) }
        }
        let path = w.cfg("path")
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                var node: Any? = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                for comp in path.split(separator: ".") where !comp.isEmpty {
                    if let i = Int(comp), let arr = node as? [Any] { node = arr.indices.contains(i) ? arr[i] : nil }
                    else { node = (node as? [String: Any])?[String(comp)] }
                }
                let value = (node as? NSNumber)?.doubleValue ?? (node as? String).flatMap(Double.init)
                await MainActor.run {
                    if let value { self.values[w.id] = value; self.errors[w.id] = nil } else { self.errors[w.id] = "Pfad prüfen" }
                }
            } catch {
                await MainActor.run { self.errors[w.id] = "Fehler" }
            }
        }
    }
}

struct MetricWidget: View {
    let w: WidgetInstance
    @ObservedObject private var svc = MetricService.shared
    @Environment(\.dockScale) private var s
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            if w.cfg("url").isEmpty {
                Button("URL einrichten") { AppDelegate.shared.openSettings(selecting: w.id) }
                    .buttonStyle(.plain).font(.system(size: 11 * s)).foregroundStyle(Color.accentColor)
            } else {
                Text(svc.values[w.id].map { w.cfg("prefix") + format($0) + w.cfg("suffix") } ?? (svc.errors[w.id] ?? "…"))
                    .font(.system(size: (w.size == 1 ? 16 : 26) * s, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(w.cfg("title")).font(.system(size: 10 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { svc.load(w, force: true) }
        .onAppear { svc.load(w) }
        .onReceive(timer) { _ in svc.load(w) }
    }

    private func format(_ v: Double) -> String {
        let de = AppLanguageSettings.shared.locale
        if abs(v) >= 1_000_000 { return (v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(de)) + "M" }
        if v == v.rounded() { return Int(v).formatted(.number.locale(de)) }
        return v.formatted(.number.precision(.fractionLength(2)).locale(de))
    }
}

struct ShortcutRunSchedule {
    var mode: String
    var hour: Int
    var minute: Int

    init(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        mode = parts.first == "daily" ? "daily" : "click"
        let time = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : []
        hour = time.indices.contains(0) ? min(max(time[0], 0), 23) : 9
        minute = time.indices.contains(1) ? min(max(time[1], 0), 59) : 0
    }

    var rawValue: String {
        mode == "daily" ? "daily|\(String(format: "%02d:%02d", hour, minute))" : "click"
    }

    var pickerDate: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    mutating func setTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? hour
        minute = components.minute ?? minute
    }
}

final class ShortcutsCatalog: ObservableObject {
            static let shared = ShortcutsCatalog()

            @Published private(set) var names: [String] = []
            @Published private(set) var runningName: String?
            @Published private(set) var message: String?
            @Published private(set) var error: String?
            @Published private(set) var isLoading = false

            private let queue = DispatchQueue(label: "ch.crohniq.dock.shortcuts", qos: .utility, attributes: .concurrent)

            func refresh() {
                guard !isLoading else { return }
                isLoading = true
                queue.async { [weak self] in
                    let result = Result {
                        let output = try Self.execute(["list"], outputToPipe: true)
                        return output.split(whereSeparator: \.isNewline).map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty }
                    }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isLoading = false
                        switch result {
                        case .success(let names):
                            self.names = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                            self.error = nil
                        case .failure(let error):
                            self.error = error.localizedDescription
                        }
                    }
                }
            }

            func run(_ name: String, completion: ((Bool) -> Void)? = nil) {
                guard runningName == nil, names.contains(name) else {
                    completion?(false)
                    return
                }
                runningName = name
                message = nil
                error = nil
                queue.async { [weak self] in
                    let result = Result { try Self.execute(["run", name], outputToPipe: false) }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.runningName = nil
                        switch result {
                        case .success:
                            self.message = "„\(name)“ ausgeführt"
                            completion?(true)
                        case .failure(let error):
                            self.error = error.localizedDescription
                            completion?(false)
                        }
                    }
                }
            }

            private static func execute(_ arguments: [String], outputToPipe: Bool) throws -> String {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = arguments
                let pipe = Pipe()
                if outputToPipe {
                    process.standardOutput = pipe
                    process.standardError = pipe
                } else {
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = pipe
                }
                try process.run()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "ShortcutsCLI", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Der Kurzbefehl konnte nicht ausgeführt werden." : output])
                }
                return output
            }
}

@MainActor
final class ShortcutsScheduler {
    static let shared = ShortcutsScheduler()

    private struct ScheduledRun {
        let name: String
        let key: String
        let day: String
    }

    private var timer: Timer?
    private var queue: [ScheduledRun] = []
    private var queuedKeys = Set<String>()
    private var isRunning = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        ShortcutsCatalog.shared.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkDueShortcuts()
        }
        checkDueShortcuts()
    }

    private func checkDueShortcuts() {
        let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        guard let year = now.year, let month = now.month, let dayNumber = now.day,
              let hour = now.hour, let minute = now.minute else { return }
        let day = String(format: "%04d-%02d-%02d", year, month, dayNumber)
        let catalog = ShortcutsCatalog.shared

        for profile in DockStore.shared.profiles {
            for widget in profile.widgets where widget.kind == .shortcuts {
                for name in ShortcutsWidget.selectedNames(widget, available: catalog.names) {
                    let configKey = "shortcutSchedule|\(name)"
                    let schedule = ShortcutRunSchedule(rawValue: widget.cfg(configKey, "click"))
                    guard schedule.mode == "daily", schedule.hour == hour, schedule.minute == minute else { continue }
                    let runKey = "shortcuts.lastRun.\(name)"
                    guard UserDefaults.standard.string(forKey: runKey) != day, !queuedKeys.contains(runKey) else { continue }
                    queuedKeys.insert(runKey)
                    queue.append(ScheduledRun(name: name, key: runKey, day: day))
                }
            }
        }
        runNext()
    }

    private func runNext() {
        guard !isRunning, ShortcutsCatalog.shared.runningName == nil, !queue.isEmpty else { return }
        let scheduled = queue.removeFirst()
        isRunning = true
        UserDefaults.standard.set(scheduled.day, forKey: scheduled.key)
        ShortcutsCatalog.shared.run(scheduled.name) { [weak self] _ in
            guard let self else { return }
            self.queuedKeys.remove(scheduled.key)
            self.isRunning = false
            self.runNext()
        }
    }
}

struct ShortcutsWidget: View {
    let w: WidgetInstance
    @ObservedObject private var catalog = ShortcutsCatalog.shared
    @Environment(\.dockScale) private var s

    private var visibleNames: [String] {
        let selected = Self.selectedNames(w, available: catalog.names)
        let count = min(max(w.cfgInt("count", 5), 1), 12)
        return Array(selected.prefix(min(count, w.size == 1 ? 1 : w.size == 2 ? 2 : 3)))
    }

    static func selectedNames(_ w: WidgetInstance, available: [String]) -> [String] {
        let configured = w.cfg("favorites").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if w.cfg("selectionMode") != "selected", configured.isEmpty { return available }
        return configured.compactMap { selected in
            available.first { $0.localizedCaseInsensitiveCompare(selected) == .orderedSame }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack(spacing: 5 * s) {
                Image(systemName: "command").foregroundStyle(Color.accentColor)
                Text("Kurzbefehle").font(.system(size: 10 * s, weight: .semibold))
                Spacer(minLength: 0)
                Button { catalog.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9 * s))
                }
                .buttonStyle(.plain)
                .help("Kurzbefehle neu laden")
            }
            if let error = catalog.error {
                Text(error).font(.system(size: 8 * s)).foregroundStyle(.orange).lineLimit(2)
            } else if visibleNames.isEmpty {
                Text(catalog.isLoading ? "Lade Kurzbefehle …" : "Keine passenden Kurzbefehle")
                    .font(.system(size: 9 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
            } else {
                ForEach(visibleNames, id: \.self) { name in
                    Button { catalog.run(name) } label: {
                        HStack(spacing: 5 * s) {
                            Image(systemName: catalog.runningName == name ? "ellipsis" : "play.fill")
                                .font(.system(size: 8 * s))
                                .foregroundStyle(Color.accentColor)
                            Text(name).font(.system(size: 9 * s, weight: .medium))
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(catalog.runningName != nil)
                    .help("„\(name)“ ausführen")
                }
            }
            if let message, w.size >= 3 {
                Text(message).font(.system(size: 8 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
        .tilePadding(s)
        .task {
            catalog.refresh()
            ShortcutsScheduler.shared.start()
        }
    }

    private var message: String? { catalog.message }
}

struct ShortcutsHoverList: View {
    let w: WidgetInstance
    @ObservedObject private var catalog = ShortcutsCatalog.shared

    private var names: [String] {
        let selected = ShortcutsWidget.selectedNames(w, available: catalog.names)
        let count = min(max(Int(w.cfg("unrollCount", "10")) ?? 10, 1), 50)
        return Array(selected.prefix(count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Kurzbefehle", systemImage: "command").font(.headline)
                Spacer()
                Button("Neu laden") { catalog.refresh() }.controlSize(.small)
            }
            .padding(.horizontal, 12)

            if let error = catalog.error {
                Text(error).font(.callout).foregroundStyle(.orange).padding(.horizontal, 12)
            } else if names.isEmpty {
                Text(catalog.isLoading ? "Kurzbefehle werden geladen …" : "Keine Kurzbefehle ausgewählt.")
                    .font(.callout).foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(names, id: \.self) { name in
                            let schedule = ShortcutRunSchedule(rawValue: w.cfg("shortcutSchedule|\(name)", "click"))
                            Button { catalog.run(name) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: catalog.runningName == name ? "ellipsis" : "play.fill")
                                        .foregroundStyle(Color.accentColor)
                                    Text(name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if schedule.mode == "daily" {
                                        Text("täglich \(String(format: "%02d:%02d", schedule.hour, schedule.minute))")
                                            .font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(catalog.runningName != nil)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 360)
            }
            if let message = catalog.message {
                Text(message).font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            }
        }
        .onAppear {
            catalog.refresh()
            ShortcutsScheduler.shared.start()
        }
    }
}

struct ShortcutsWidgetSettings: View {
    let w: WidgetInstance
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var catalog = ShortcutsCatalog.shared

    var body: some View {
        Section("Kurzbefehle auswählen") {
            HStack {
                Text("Nur ausgewählte Kurzbefehle erscheinen im Widget und in der Tora.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Aktualisieren") { catalog.refresh() }
            }
            if catalog.isLoading && catalog.names.isEmpty {
                ProgressView()
            } else if catalog.names.isEmpty {
                Text(catalog.error ?? "Keine Kurzbefehle gefunden.")
                    .foregroundStyle(catalog.error == nil ? Theme.secondary : Color.orange)
            } else {
                ForEach(catalog.names, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(name, isOn: selectionBinding(for: name))
                        if selectionBinding(for: name).wrappedValue {
                            HStack {
                                Picker("Ausführung", selection: scheduleModeBinding(for: name)) {
                                    Text("Nur per Klick").tag("click")
                                    Text("Täglich").tag("daily")
                                }
                                if ShortcutRunSchedule(rawValue: scheduleValue(for: name)).mode == "daily" {
                                    DatePicker(
                                        "Uhrzeit",
                                        selection: scheduleTimeBinding(for: name),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }
                            }
                            .padding(.leading, 22)
                        }
                    }
                }
            }
            if let error = catalog.error, !catalog.names.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Text("Tägliche Ausführung erfolgt zur gewählten Uhrzeit, solange Crohniq Dock läuft.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            catalog.refresh()
            ShortcutsScheduler.shared.start()
        }
    }

    private func selectionBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: {
                guard let current = store.instance(w.id) else { return false }
                return ShortcutsWidget.selectedNames(current, available: catalog.names).contains(name)
            },
            set: { selected in
                let current = store.instance(w.id) ?? w
                let configured = current.cfg("favorites").split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                var names = current.cfg("selectionMode") == "selected"
                    ? configured
                    : (configured.isEmpty ? catalog.names : configured)
                names.removeAll { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
                if selected { names.append(name) }
                store.setConfig(w.id, "selectionMode", "selected")
                store.setConfig(w.id, "favorites", names.joined(separator: "\n"))
            }
        )
    }

    private func scheduleValue(for name: String) -> String {
        store.instance(w.id)?.cfg("shortcutSchedule|\(name)", "click") ?? "click"
    }

    private func scheduleModeBinding(for name: String) -> Binding<String> {
        Binding(
            get: { ShortcutRunSchedule(rawValue: scheduleValue(for: name)).mode },
            set: { mode in
                var schedule = ShortcutRunSchedule(rawValue: scheduleValue(for: name))
                schedule.mode = mode
                store.setConfig(w.id, "shortcutSchedule|\(name)", schedule.rawValue)
            }
        )
    }

    private func scheduleTimeBinding(for name: String) -> Binding<Date> {
        Binding(
            get: { ShortcutRunSchedule(rawValue: scheduleValue(for: name)).pickerDate },
            set: { date in
                var schedule = ShortcutRunSchedule(rawValue: scheduleValue(for: name))
                schedule.setTime(date)
                store.setConfig(w.id, "shortcutSchedule|\(name)", schedule.rawValue)
            }
        )
    }
}
