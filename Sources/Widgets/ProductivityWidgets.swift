import EventKit
import SwiftUI

// MARK: - Pomodoro

final class PomodoroState: ObservableObject {
    @Published var phase = 0          // 0 = Fokus, 1 = Pause
    @Published var running = false
    @Published var remaining: TimeInterval = 25 * 60
    @Published var round = 1
    private var endDate: Date?
    private var timer: Timer?

    func configure(work: Int) { if !running && phase == 0 { remaining = TimeInterval(work * 60) } }

    func toggle(work: Int, brk: Int) {
        if running {
            running = false
            timer?.invalidate()
            endDate = nil
        } else {
            running = true
            endDate = Date().addingTimeInterval(remaining)
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.tick(work: work, brk: brk)
            }
        }
    }

    private func tick(work: Int, brk: Int) {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            NSSound(named: "Glass")?.play()
            if phase == 0 {
                Notifier.notify("Fokus beendet", "Zeit für \(brk) Minuten Pause.")
                phase = 1
                remaining = TimeInterval(brk * 60)
            } else {
                Notifier.notify("Pause vorbei", "Weiter mit Runde \(round + 1).")
                phase = 0
                round += 1
                remaining = TimeInterval(work * 60)
            }
            endDate = Date().addingTimeInterval(remaining)
        }
    }

    func reset(work: Int) {
        running = false
        timer?.invalidate()
        phase = 0
        round = 1
        remaining = TimeInterval(work * 60)
    }

    func skip(work: Int, brk: Int) {
        let wasRunning = running
        if running { toggle(work: work, brk: brk) }
        if phase == 0 { phase = 1; remaining = TimeInterval(brk * 60) } else { phase = 0; round += 1; remaining = TimeInterval(work * 60) }
        if wasRunning { toggle(work: work, brk: brk) }
    }
}

struct PomodoroWidget: View {
    let w: WidgetInstance
    @StateObject private var st = PomodoroState()
    @Environment(\.dockScale) private var s

    var body: some View {
        let work = w.cfgInt("work", 25), brk = w.cfgInt("break", 5)
        let total = TimeInterval((st.phase == 0 ? work : brk) * 60)
        let color: Color = st.phase == 0 ? .orange : .green
        let text = String(format: "%d:%02d", Int(st.remaining) / 60, Int(st.remaining) % 60)
        Group {
            if w.size == 1 {
                ZStack {
                    Ring(value: 1 - st.remaining / max(total, 1), color: color, lineWidth: 4 * s)
                    Text(text).font(.system(size: 13 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .padding(8 * s)
                .contentShape(Rectangle())
                .onTapGesture { st.toggle(work: work, brk: brk) }
            } else {
                HStack(spacing: 8 * s) {
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text(st.phase == 0 ? "Fokus \(st.round)" : "Pause")
                            .font(.system(size: 10 * s, weight: .medium)).foregroundStyle(color)
                        Text(text).font(.system(size: 26 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if w.size >= 3 { CircleButton(symbol: "forward.end.fill", size: 26) { st.skip(work: work, brk: brk) } }
                    CircleButton(symbol: "xmark", size: 26) { st.reset(work: work) }
                    CircleButton(symbol: st.running ? "pause.fill" : "play.fill", size: 34, fill: color) {
                        st.toggle(work: work, brk: brk)
                    }
                }
                .tilePadding(s)
                .overlay(alignment: .bottom) {
                    GeometryReader { g in
                        Capsule().fill(color).frame(width: g.size.width * (1 - st.remaining / max(total, 1)), height: 3 * s)
                    }
                    .frame(height: 3 * s)
                    .padding(.horizontal, 12 * s)
                    .padding(.bottom, 4 * s)
                }
            }
        }
        .onAppear { st.configure(work: work) }
        .onChange(of: work) { _, v in st.configure(work: v) }
    }
}

// MARK: - Drink water

struct WaterWidget: View {
    let w: WidgetInstance
    @ObservedObject private var ticker = Ticker.shared
    @Environment(\.dockScale) private var s

    private var today: String { Date().formatted(.iso8601.year().month().day()) }
    private var count: Int { w.cfg("day") == today ? w.cfgInt("count", 0) : 0 }

    @State private var hop = false
    @State private var bursts: [UUID] = []

    var body: some View {
        let goal = max(1, w.cfgInt("goal", 8))
        let frac = min(1, Double(count) / Double(goal))
        let night = WeatherService.shared.isNight(ticker.now)
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack {
                // Sky: day with sun, night with moon and twinkling stars
                LinearGradient(colors: night
                               ? [Color(red: 0.05, green: 0.07, blue: 0.2), Color(red: 0.2, green: 0.14, blue: 0.35)]
                               : [Color(red: 1.0, green: 0.83, blue: 0.52), Color(red: 0.98, green: 0.62, blue: 0.36)],
                               startPoint: .top, endPoint: .bottom)
                if night {
                    StarField(seed: 7, twinkle: ticker.now)
                    MoonShape().fill(Color(red: 1, green: 0.97, blue: 0.82))
                        .frame(width: H * 0.2, height: H * 0.2)
                        .shadow(color: .white.opacity(0.6), radius: 5)
                        .position(x: W * 0.86, y: H * 0.2)
                } else {
                    Circle().fill(Color(red: 1, green: 0.95, blue: 0.6))
                        .frame(width: H * 0.22, height: H * 0.22)
                        .shadow(color: .yellow.opacity(0.8), radius: 6)
                        .position(x: W * 0.86, y: H * 0.2)
                }
                // Dunes
                Dune(peak: 0.35, height: 0.42).fill(night ? Color(red: 0.32, green: 0.26, blue: 0.36) : Color(red: 0.95, green: 0.74, blue: 0.43))
                Dune(peak: 0.75, height: 0.28).fill(night ? Color(red: 0.24, green: 0.19, blue: 0.29) : Color(red: 0.89, green: 0.63, blue: 0.33))
                // Puddle grows with every glass; becomes an oasis at the goal
                let pw = W * (0.12 + 0.5 * frac), ph = H * (0.06 + 0.12 * frac)
                ZStack {
                    Ellipse().fill(LinearGradient(colors: night
                                                  ? [Color(red: 0.3, green: 0.45, blue: 0.75), Color(red: 0.08, green: 0.15, blue: 0.4)]
                                                  : [Color(red: 0.45, green: 0.8, blue: 1), Color(red: 0.12, green: 0.45, blue: 0.85)],
                                                  startPoint: .top, endPoint: .bottom))
                    Ellipse().fill(.white.opacity(night ? 0.8 : 0.55))
                        .frame(width: pw * (night ? 0.18 : 0.35), height: ph * 0.22)
                        .offset(x: night ? pw * 0.2 : -pw * 0.15, y: -ph * 0.15)
                        .opacity(ticker.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 2) < 1 ? 0.9 : 0.4)
                        .animation(.easeInOut(duration: 1), value: ticker.now)
                }
                .frame(width: pw, height: ph)
                .opacity(count == 0 ? 0.35 : 1)
                .position(x: W * 0.64, y: H * 0.86)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: count)
                if frac >= 1 {
                    Text("🌴").font(.system(size: H * 0.34)).position(x: W * 0.86, y: H * 0.66)
                        .brightness(night ? -0.35 : 0)
                        .transition(.scale.combined(with: .opacity))
                }
                // The camel: stands and hops by day, lies down and sleeps at night
                Text("🐪")
                    .font(.system(size: H * (w.size == 1 ? 0.46 : 0.52)))
                    .scaleEffect(x: -1, y: night && !hop ? 0.62 : 1, anchor: .bottom)
                    .brightness(night ? -0.3 : 0)
                    .rotationEffect(.degrees(hop ? -8 : 0))
                    .offset(y: hop ? -H * (night ? 0.06 : 0.12) : (night ? H * 0.08 : 0))
                    .position(x: W * (w.size == 1 ? 0.3 : 0.25), y: H * 0.66)
                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: hop)
                if night && !hop {
                    Text("z").font(.system(size: H * 0.13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                        .offset(y: ticker.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 2) < 1 ? -2 : -6)
                        .animation(.easeInOut(duration: 1), value: ticker.now)
                        .position(x: W * (w.size == 1 ? 0.48 : 0.4), y: H * 0.42)
                }
                ForEach(bursts, id: \.self) { id in
                    JoyBurst(symbol: frac >= 1 ? "❤️" : (id.hashValue % 2 == 0 ? "💧" : "❤️"))
                        .position(x: W * (w.size == 1 ? 0.38 : 0.32), y: H * 0.38)
                }
                // Counter
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(count)/\(goal)")
                        .font(.system(size: (w.size == 1 ? 12 : 15) * s, weight: .bold, design: .rounded))
                    if w.size > 1 {
                        Text(frac >= 1 ? "Oase erreicht!" : (night ? "Gute Nacht" : "Gläser heute")).font(.system(size: 9 * s, weight: .medium))
                    }
                }
                .foregroundStyle(night ? Color.white.opacity(0.9) : Color(red: 0.35, green: 0.18, blue: 0.05))
                .shadow(color: night ? .black.opacity(0.5) : .white.opacity(0.6), radius: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 8 * s).padding(.top, 6 * s)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { drink(1) }
        .onWidgetAction(w.id) { a in if a == "minus" { drink(-1) } else if a == "reset" { set(0) } }
        .help("Klicken = ein Glas Wasser · das Kamel freut sich")
        .onChange(of: ticker.now) { _, now in remind(now) }
    }

    private func drink(_ d: Int) {
        if d > 0 {
            hop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { hop = false }
            let id = UUID()
            bursts.append(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { bursts.removeAll { $0 == id } }
        }
        set(max(0, count + d))
        DockStore.shared.setConfig(w.id, "last", String(Date().timeIntervalSince1970))
    }

    private func set(_ n: Int) {
        DockStore.shared.update(w.id) {
            $0.config["day"] = today
            $0.config["count"] = String(n)
        }
    }

    private func remind(_ now: Date) {
        let interval = Double(w.cfgInt("interval", 45)) * 60
        guard interval > 0, Int(now.timeIntervalSince1970) % 30 == 0 else { return }
        let hour = Calendar.current.component(.hour, from: now)
        guard (8...21).contains(hour), count < w.cfgInt("goal", 8) else { return }
        let last = max(Double(w.cfg("last")) ?? 0, Double(w.cfg("lastReminder")) ?? 0)
        if now.timeIntervalSince1970 - last > interval {
            DockStore.shared.setConfig(w.id, "lastReminder", String(now.timeIntervalSince1970))
            Notifier.notify("Zeit für ein Glas Wasser 💧", "Heute: \(count) von \(w.cfgInt("goal", 8)) Gläsern.")
        }
    }
}

/// Rising heart or drop when the camel is happy.
struct JoyBurst: View {
    let symbol: String
    @State private var up = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 13))
            .offset(y: up ? -28 : 0)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.3 : 0.7)
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { up = true } }
    }
}

/// Small stars at fixed pseudo-random spots that twinkle with the clock.
struct StarField: View {
    let seed: Int
    let twinkle: Date

    var body: some View {
        GeometryReader { g in
            let t = Int(twinkle.timeIntervalSince1970)
            ForEach(0..<18, id: \.self) { i in
                let x = Double((i * 73 + seed * 31) % 100) / 100
                let y = Double((i * 41 + seed * 17) % 55) / 100
                let size: CGFloat = i % 5 == 0 ? 2.2 : 1.3
                Circle().fill(.white)
                    .frame(width: size, height: size)
                    .opacity((t + i) % 3 == 0 ? 0.35 : 0.95)
                    .position(x: g.size.width * x, y: g.size.height * y + 2)
                    .animation(.easeInOut(duration: 0.8), value: t)
            }
        }
    }
}

/// Crescent moon.
struct MoonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(ellipseIn: r)
        let cut = Path(ellipseIn: r.offsetBy(dx: r.width * 0.32, dy: -r.height * 0.12))
        p = p.subtracting(cut)
        return p
    }
}

struct Dune: Shape {
    let peak: Double
    let height: Double

    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.maxY - r.height * height
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: top + r.height * height * 0.55))
        p.addQuadCurve(to: CGPoint(x: r.width * peak, y: top), control: CGPoint(x: r.width * peak * 0.5, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top + r.height * height * 0.5),
                       control: CGPoint(x: r.width * (peak + (1 - peak) * 0.5), y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Wave: Shape {
    var level: Double
    var phase: Double
    var animatableData: Double { get { level } set { level = newValue } }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.maxY - rect.height * CGFloat(level)
        let amp = level > 0 && level < 1 ? 3.0 : 0
        p.move(to: CGPoint(x: 0, y: y))
        for x in stride(from: 0, through: rect.width, by: 2) {
            let a = (Double(x) / Double(rect.width) + phase) * .pi * 2
            p.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(a) * amp)))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Calendar

struct CalendarWidget: View {
    let w: WidgetInstance
    @ObservedObject private var ek = EventStore.shared
    @ObservedObject private var ticker = Ticker.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            VStack(spacing: 0) {
                Text(ticker.now.formatted(.dateTime.day()))
                    .font(.system(size: 24 * s, weight: .semibold, design: .rounded))
                Text(ticker.now.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "de_CH"))))
                    .font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 40 * s)
            .padding(.vertical, 4 * s)
            .background(RoundedRectangle(cornerRadius: 8 * s).fill(Theme.tileHi))
            .overlay(alignment: .topTrailing) {
                if ek.todayCount > 0 {
                    Text("\(ek.todayCount)")
                        .font(.system(size: 9 * s, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 15 * s, minHeight: 15 * s)
                        .padding(.horizontal, ek.todayCount > 9 ? 3 * s : 0)
                        .background(Capsule().fill(.red))
                        .overlay(Capsule().strokeBorder(Theme.tile, lineWidth: 1.5))
                        .offset(x: 6 * s, y: -6 * s)
                        .help("\(ek.todayCount) Termine heute")
                }
            }
            .help(ek.events.first.map { "\($0.title ?? "") – \(timeText($0))" } ?? "Keine weiteren Termine")
            .onTapGesture { if w.size == 1 && !ek.eventsAuthorized { ek.requestEvents() } }

            if w.size == 1 {
                EmptyView()
            } else if !ek.eventsAuthorized {
                Button("Kalender erlauben") { ek.requestEvents() }.font(.system(size: 11 * s)).buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Spacer(minLength: 0)
            } else if ek.events.isEmpty {
                Text("Keine weiteren Termine").font(.system(size: 11 * s)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 3 * s) {
                    ForEach(ek.events.prefix(2), id: \.calendarItemIdentifier) { e in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.title ?? "").font(.system(size: 11 * s, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(Color(nsColor: e.calendar.color).mix(with: .white, by: 0.25))
                            Text(timeText(e)).font(.system(size: 10 * s)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let next = ek.events.first, let url = meetingURL(next), next.startDate.timeIntervalSinceNow < 600 {
                    CircleButton(symbol: "video.fill", size: 30, fill: .blue) { NSWorkspace.shared.open(url) }
                        .help("Meeting beitreten")
                } else if ek.events.count > 2 {
                    Text("+\(ek.events.count - 2)").font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .tilePadding(s)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        .onAppear { if ek.eventsAuthorized { ek.reloadEvents() } }
    }

    private func timeText(_ e: EKEvent) -> String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "de_CH"))
        let day = Calendar.current.isDateInToday(e.startDate) ? "" : "morgen "
        if e.startDate <= Date() { return "läuft · bis \(e.endDate.formatted(f))" }
        let mins = Int(e.startDate.timeIntervalSinceNow / 60)
        if mins < 60 { return "in \(mins) min · \(e.startDate.formatted(f))" }
        return "\(day)\(e.startDate.formatted(f)) – \(e.endDate.formatted(f))"
    }

    private func meetingURL(_ e: EKEvent) -> URL? {
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://[^\s<>"]*(zoom\.us|teams\.microsoft|teams\.live|meet\.google|webex)[^\s<>"]*"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(text[r]))
    }
}

// MARK: - Reminders

struct RemindersWidget: View {
    let w: WidgetInstance
    @ObservedObject private var ek = EventStore.shared
    @Environment(\.dockScale) private var s
    @State private var adding = false
    @State private var newTitle = ""

    var body: some View {
        Group {
            if w.size == 1 {
                VStack(spacing: 0) {
                    Text(ek.remindersAuthorized ? "\(ek.reminders.count)" : "–")
                        .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                    Text("offen").font(.system(size: 9 * s)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if ek.remindersAuthorized { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }
                    else { ek.requestReminders(list: w.cfg("list")) }
                }
                .help(ek.reminders.prefix(5).compactMap(\.title).joined(separator: "\n"))
            } else if !ek.remindersAuthorized {
                Button("Erinnerungen erlauben") { ek.requestReminders(list: w.cfg("list")) }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.system(size: 11 * s))
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3 * s) {
                        if ek.reminders.isEmpty {
                            Text("Alles erledigt ✓").font(.system(size: 11 * s)).foregroundStyle(Theme.secondary)
                        }
                        ForEach(ek.reminders.prefix(3), id: \.calendarItemIdentifier) { r in
                            HStack(spacing: 6 * s) {
                                Circle().strokeBorder(Color(nsColor: r.calendar.color), lineWidth: 1.5)
                                    .frame(width: 10 * s, height: 10 * s)
                                    .contentShape(Circle())
                                    .onTapGesture { withAnimation { ek.complete(r) } }
                                Text(r.title ?? "").font(.system(size: 11 * s, weight: .medium)).lineLimit(1)
                                if r.priority == 1 { Text("!").foregroundStyle(.orange).font(.system(size: 11 * s, weight: .bold)) }
                                Spacer(minLength: 4 * s)
                                if w.size >= 3, let due = r.dueDateComponents?.date {
                                    Text(dueText(due)).font(.system(size: 10 * s))
                                        .foregroundStyle(due < Date() ? .orange : Theme.secondary)
                                }
                            }
                        }
                    }
                    Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 11 * s, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                        .popover(isPresented: $adding) {
                            TextField("Neue Erinnerung", text: $newTitle)
                                .textFieldStyle(.roundedBorder).frame(width: 240).padding(10)
                                .onSubmit { ek.addReminder(newTitle); newTitle = ""; adding = false }
                        }
                }
            }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { if ek.remindersAuthorized { ek.requestReminders(list: w.cfg("list")) } }
    }

    private func dueText(_ d: Date) -> String {
        if d < Date() && !Calendar.current.isDateInToday(d) { return "Überfällig" }
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInTomorrow(d) { return "Morgen" }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_CH")))
    }
}

// MARK: - Progress

struct ProgressWidget: View {
    let w: WidgetInstance
    @ObservedObject private var ticker = Ticker.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        let (frac, label, total, done) = compute(ticker.now)
        Group {
            if w.size == 1 {
                ZStack {
                    Ring(value: frac, color: .mint, lineWidth: 4 * s)
                    Text("\(Int(frac * 100))%").font(.system(size: 13 * s, weight: .semibold, design: .rounded))
                }
                .padding(8 * s)
                .help(label)
            } else {
                VStack(alignment: .leading, spacing: 4 * s) {
                    let cols = w.size == 2 ? 14 : 22
                    let dots = min(total, cols * 3)
                    let filled = Int((Double(dots) * frac).rounded(.down))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2 * s), count: cols), spacing: 2 * s) {
                        ForEach(0..<dots, id: \.self) { i in
                            Circle().fill(i < filled ? Theme.fg : Theme.fg.opacity(0.18))
                                .frame(width: 5 * s, height: 5 * s)
                        }
                    }
                    HStack {
                        Text(label).font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(Int(frac * 100))%").font(.system(size: 10 * s, weight: .semibold))
                    }
                }
                .tilePadding(s)
                .help("\(done) von \(total)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { cycle() }
    }

    private func cycle() {
        let order = ["year", "month", "week", "day"]
        let i = order.firstIndex(of: w.cfg("mode", "year")) ?? 0
        DockStore.shared.setConfig(w.id, "mode", order[(i + 1) % order.count])
    }

    private func compute(_ now: Date) -> (Double, String, Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_CH")
        cal.firstWeekday = 2
        let de = Locale(identifier: "de_CH")
        switch w.cfg("mode", "year") {
        case "month":
            let iv = cal.dateInterval(of: .month, for: now)!
            let days = cal.range(of: .day, in: .month, for: now)!.count
            return (now.timeIntervalSince(iv.start) / iv.duration, now.formatted(.dateTime.month(.wide).year().locale(de)), days,
                    cal.component(.day, from: now))
        case "week":
            let iv = cal.dateInterval(of: .weekOfYear, for: now)!
            return (now.timeIntervalSince(iv.start) / iv.duration, "KW \(cal.component(.weekOfYear, from: now))", 7,
                    (cal.component(.weekday, from: now) + 5) % 7 + 1)
        case "day":
            let iv = cal.dateInterval(of: .day, for: now)!
            return (now.timeIntervalSince(iv.start) / iv.duration, "Heute", 24, cal.component(.hour, from: now))
        default:
            let iv = cal.dateInterval(of: .year, for: now)!
            let days = cal.range(of: .day, in: .year, for: now)!.count
            return (now.timeIntervalSince(iv.start) / iv.duration, "Jahr \(cal.component(.year, from: now))", days,
                    cal.ordinality(of: .day, in: .year, for: now) ?? 0)
        }
    }
}

// MARK: - Stopwatch

struct StopwatchWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var start: Date?
    @State private var accumulated: TimeInterval = 0

    var body: some View {
        timeline.onWidgetAction(w.id) { if $0 == "reset" { start = nil; accumulated = 0 } }
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let t = accumulated + (start.map { ctx.date.timeIntervalSince($0) } ?? 0)
            if w.size == 1 {
                VStack(spacing: 2 * s) {
                    Image(systemName: start == nil ? "stopwatch" : "pause.fill").font(.system(size: 13 * s))
                        .foregroundStyle(start == nil ? Theme.secondary : .blue)
                    Text(format(t)).font(.system(size: 12 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(4 * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
            } else {
            HStack(spacing: 8 * s) {
                Text(format(t)).font(.system(size: 24 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 0)
                CircleButton(symbol: "arrow.counterclockwise", size: 26) { start = nil; accumulated = 0 }
                CircleButton(symbol: start == nil ? "play.fill" : "pause.fill", size: 34, fill: .blue) { toggle() }
            }
            .tilePadding(s)
            }
        }
    }

    private func toggle() {
        if let st = start { accumulated += Date().timeIntervalSince(st); start = nil } else { start = Date() }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, sec = Int(t) % 60, tenth = Int(t * 10) % 10
        return m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, sec) : String(format: "%d:%02d.%d", m, sec, tenth)
    }
}

// MARK: - Notes

struct NotesWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var editing = false
    @State private var creating = false

    var body: some View {
        let text = w.cfg("text")
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        HStack(spacing: 10 * s) {
            Image(systemName: "note.text").font(.system(size: 18 * s))
                .frame(width: 34 * s, height: 34 * s)
                .background(RoundedRectangle(cornerRadius: 8 * s).fill(Color.yellow.opacity(0.85)))
                .foregroundStyle(.black.opacity(0.7))
                .onTapGesture { NotesLibrary.shared.refresh(force: true); NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app")) }
                .help("Notizen öffnen")
            if w.size > 1 {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(first.isEmpty ? "Schnellnotiz" : first).font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
                    Text(text.isEmpty ? "Klicken zum Schreiben" : text.split(separator: "\n").dropFirst().joined(separator: " "))
                        .font(.system(size: 10 * s)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture { NSApp.activate(ignoringOtherApps: true); editing = true }
                Spacer(minLength: 0)
            }
            CircleButton(symbol: "plus", size: w.size == 1 ? 20 : 28, fill: Color.yellow.opacity(0.85), tint: .black.opacity(0.75)) {
                creating = true
            }
            .help("Neue Notiz in der Notizen-App")
            .popover(isPresented: $creating, arrowEdge: .top) { NewNoteEditor(isPresented: $creating) }
        }
        .tilePadding(s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .popover(isPresented: $editing) {
            VStack(alignment: .leading) {
                Text("Schnellnotiz").font(.headline)
                TextEditor(text: DockStore.shared.binding(w.id, "text"))
                    .font(.system(size: 13))
                    .frame(width: 320, height: 220)
                HStack {
                    Button("In Notizen-App übernehmen") {
                        NotesLibrary.shared.create(w.cfg("text")) { ok in if ok { DockStore.shared.setConfig(w.id, "text", "") } }
                    }
                    .disabled(w.cfg("text").isEmpty)
                    Spacer()
                    Button("Kopieren") { copyToPasteboard(w.cfg("text")) }
                    Button("Leeren") { DockStore.shared.setConfig(w.id, "text", "") }
                }
            }
            .padding(10)
        }
    }
}

// MARK: - Mail

struct MailWidget: View {
    let w: WidgetInstance
    @Environment(\.dockScale) private var s
    @State private var unread: Int?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8 * s) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: fileIcon("/System/Applications/Mail.app")).resizable().frame(width: 38 * s, height: 38 * s)
                if let n = unread, n > 0 {
                    Text(n > 999 ? "999+" : "\(n)").font(.system(size: 10 * s, weight: .bold))
                        .padding(.horizontal, 4 * s).padding(.vertical, 1 * s)
                        .background(Capsule().fill(.red))
                        .offset(x: 6 * s, y: -4 * s)
                }
            }
            if w.size > 1 {
                VStack(alignment: .leading) {
                    Text("\(unread ?? 0)").font(.system(size: 20 * s, weight: .semibold, design: .rounded))
                    Text(unread == nil ? "Mail nicht offen" : "ungelesen").font(.system(size: 10 * s)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .tilePadding(s)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app")) }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        guard Script.isRunning("com.apple.mail") else { unread = nil; return }
        Script.run("tell application \"Mail\" to return unread count of inbox") { r in
            unread = r.map { Int($0.int32Value) }
        }
    }
}
