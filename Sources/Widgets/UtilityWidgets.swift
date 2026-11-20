import SwiftUI

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
        let result = rate.map { (amount * $0).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_CH"))) } ?? "…"
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
        let de = Locale(identifier: "de_CH")
        if abs(v) >= 1_000_000 { return (v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(de)) + "M" }
        if v == v.rounded() { return Int(v).formatted(.number.locale(de)) }
        return v.formatted(.number.precision(.fractionLength(2)).locale(de))
    }
}
