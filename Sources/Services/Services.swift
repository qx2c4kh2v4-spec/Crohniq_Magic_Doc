import AppKit
import CryptoKit
import AVFoundation
import Combine
import CoreAudio
import AudioToolbox
import CoreLocation
import EventKit
import IOKit.ps
import IOKit.pwr_mgt
import UserNotifications

// MARK: - Helpers

enum Script {
    private static let queue = DispatchQueue(label: "ch.crohniq.dock.applescript")

    /// Runs AppleScript on a serial background queue and returns the result on the main queue.
    static func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var err: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
            DispatchQueue.main.async { completion?(err == nil ? result : nil) }
        }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func runAsync(_ path: String, _ args: [String], completion: ((String) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = run(path, args)
            DispatchQueue.main.async { completion?(out) }
        }
    }
}

enum Notifier {
    static func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Shared one-second tick for clocks and timers.
final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var now = Date()
    private var timer: Timer?
    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        timer?.tolerance = 0.05
    }
}

// MARK: - System stats

final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var memory: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var disk: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var battery: Double = 1
    @Published var charging = false
    @Published var hasBattery = false

    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        // CPU
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if r == KERN_SUCCESS {
            let t = info.cpu_ticks
            if let p = prevTicks {
                let user = Double(t.0 &- p.0), sys = Double(t.1 &- p.1), idle = Double(t.2 &- p.2), nice = Double(t.3 &- p.3)
                let total = user + sys + idle + nice
                if total > 0 { cpu = (user + sys + nice) / total }
            }
            prevTicks = t
            cpuHistory.append(cpu)
            if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
        }

        // Memory
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vr == KERN_SUCCESS {
            let page = Double(getpagesize())
            let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            memory = used / total
            memoryUsedGB = used / 1_073_741_824
        }

        // Disk
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 {
            disk = 1 - Double(free) / Double(total)
            diskFreeGB = Double(free) / 1_000_000_000
        }

        // Battery
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            hasBattery = false
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                      (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
                hasBattery = true
                let cur = d[kIOPSCurrentCapacityKey] as? Double ?? 0
                let max = d[kIOPSMaxCapacityKey] as? Double ?? 100
                battery = max > 0 ? cur / max : 0
                charging = (d[kIOPSIsChargingKey] as? Bool) ?? false || (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            }
        }
    }
}

// MARK: - Weather (Open-Meteo, no key required)

struct WeatherData: Codable {
    struct Day: Identifiable, Codable { var id: Date { date }; let date: Date; let code: Int; let max: Double; let min: Double }
    var place: String
    var temp: Double
    var code: Int
    var wind: Double
    var windDir: Double
    var days: [Day]
    var lat: Double? = nil
    var lon: Double? = nil
    /// Precipitation (mm) per 15 minutes for the next 2 hours.
    var rain15: [Double]? = nil
    var sunrise: Date? = nil
    var sunset: Date? = nil
}

final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published private(set) var data: [String: WeatherData] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var lastFetch: [String: Date] = [:]
    private var timer: Timer?

    private let cacheKey = "weather.cache.v1"

    private init() {
        // Show the last known weather immediately after a restart; it is refreshed right after.
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: WeatherData].self, from: d) {
            data = cached
        }
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.data.keys.forEach { self?.fetch($0, force: true) }
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }

    func fetch(_ city: String, force: Bool = false) {
        if !force, let last = lastFetch[city], Date().timeIntervalSince(last) < 600 { return }
        lastFetch[city] = Date()
        Task {
            do {
                let lat: Double, lon: Double, name: String
                if Self.isAuto(city) {
                    guard let loc = await LocationService.shared.current() else {
                        await MainActor.run {
                            self.lastFetch[city] = Date().addingTimeInterval(-540)
                            self.errors[city] = LocationService.shared.denied ? "denied" : "unavailable"
                        }
                        return
                    }
                    lat = loc.coordinate.latitude
                    lon = loc.coordinate.longitude
                    name = await LocationService.shared.placeName(for: loc) ?? "Hier"
                } else {
                    var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                    geo.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "de")]
                    let (gd, _) = try await URLSession.shared.data(from: geo.url!)
                    guard let gj = try JSONSerialization.jsonObject(with: gd) as? [String: Any],
                          let first = (gj["results"] as? [[String: Any]])?.first,
                          let la = first["latitude"] as? Double, let lo = first["longitude"] as? Double else {
                        await MainActor.run { self.errors[city] = "notfound" }
                        return
                    }
                    lat = la
                    lon = lo
                    name = first["name"] as? String ?? city
                }
                var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                f.queryItems = [
                    .init(name: "latitude", value: "\(lat)"), .init(name: "longitude", value: "\(lon)"),
                    .init(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"),
                    .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
                    .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "5"),
                    .init(name: "minutely_15", value: "precipitation"), .init(name: "forecast_minutely_15", value: "8"),
                ]
                let (fd, _) = try await URLSession.shared.data(from: f.url!)
                guard let fj = try JSONSerialization.jsonObject(with: fd) as? [String: Any],
                      let cur = fj["current"] as? [String: Any], let daily = fj["daily"] as? [String: Any] else { return }
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                let times = daily["time"] as? [String] ?? []
                let codes = daily["weather_code"] as? [Int] ?? []
                let maxs = daily["temperature_2m_max"] as? [Double] ?? []
                let mins = daily["temperature_2m_min"] as? [Double] ?? []
                var days: [WeatherData.Day] = []
                for i in times.indices where i < codes.count && i < maxs.count && i < mins.count {
                    days.append(.init(date: fmt.date(from: times[i]) ?? Date(), code: codes[i], max: maxs[i], min: mins[i]))
                }
                let wd = WeatherData(place: name, temp: cur["temperature_2m"] as? Double ?? 0,
                                     code: cur["weather_code"] as? Int ?? 0,
                                     wind: cur["wind_speed_10m"] as? Double ?? 0,
                                     windDir: cur["wind_direction_10m"] as? Double ?? 0, days: days,
                                     lat: lat, lon: lon,
                                     rain15: (fj["minutely_15"] as? [String: Any])?["precipitation"] as? [Double],
                                     sunrise: Self.localTime((daily["sunrise"] as? [String])?.first, fj["timezone"] as? String),
                                     sunset: Self.localTime((daily["sunset"] as? [String])?.first, fj["timezone"] as? String))
                await MainActor.run { self.data[city] = wd; self.errors[city] = nil; self.persist() }
            } catch {
                await MainActor.run {
                    self.lastFetch[city] = Date().addingTimeInterval(-500)
                    if self.data[city] == nil { self.errors[city] = "network" }
                }
            }
        }
    }

    static func localTime(_ s: String?, _ tz: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        return f.date(from: s)
    }

    /// Dark outside? Uses today's sunrise/sunset from any loaded forecast, else a simple clock rule.
    func isNight(_ now: Date = Date()) -> Bool {
        let cal = Calendar.current
        if let d = data.values.first(where: { $0.sunrise != nil && $0.sunset != nil }),
           let rise = d.sunrise, let set = d.sunset {
            // Shift stored times to today's date (the cache may be from an earlier day).
            func today(_ t: Date) -> Date {
                let c = cal.dateComponents([.hour, .minute], from: t)
                return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: now) ?? t
            }
            return now < today(rise) || now > today(set)
        }
        let h = cal.component(.hour, from: now)
        return h < 7 || h >= 18
    }

    static func isAuto(_ city: String) -> Bool {
        let c = city.trimmingCharacters(in: .whitespaces).lowercased()
        return c.isEmpty || c == "auto" || c == "standort"
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func label(_ code: Int) -> String {
        switch code {
        case 0: "Klar"
        case 1, 2: "Leicht bewölkt"
        case 3: "Bewölkt"
        case 45, 48: "Nebel"
        case 51...57: "Niesel"
        case 61...67, 80...82: "Regen"
        case 71...77, 85, 86: "Schnee"
        case 95...99: "Gewitter"
        default: "–"
        }
    }
}

// MARK: - Location (for "current location" weather)

/// Must be created on the main thread (done at app launch), otherwise CoreLocation never calls back.
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var cached: CLLocation?
    private var cachedAt = Date.distantPast
    private var names: [String: String] = [:]
    var denied: Bool { [.denied, .restricted].contains(manager.authorizationStatus) }

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    @MainActor
    func current() async -> CLLocation? {
        if let c = cached, Date().timeIntervalSince(cachedAt) < 1800 { return c }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            guard waiters.count == 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, !self.waiters.isEmpty else { return }
                self.finish(self.cached ?? self.manager.location)
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(nil)
            default:
                // A recent system fix is good enough and avoids waiting at launch.
                if let l = manager.location, Date().timeIntervalSince(l.timestamp) < 3600 { finish(l) }
                else { manager.requestLocation() }
            }
        }
    }

    func placeName(for loc: CLLocation) async -> String? {
        let key = String(format: "%.2f,%.2f", loc.coordinate.latitude, loc.coordinate.longitude)
        if let n = names[key] ?? UserDefaults.standard.string(forKey: "location.name.\(key)") { return n }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: AppLanguageSettings.shared.locale)
        let n = marks?.first.flatMap { $0.locality ?? $0.subAdministrativeArea ?? $0.name }
        if let n { names[key] = n; UserDefaults.standard.set(n, forKey: "location.name.\(key)") }
        return n
    }

    private static let lastKey = "location.last"

    /// Last location from a previous run, used while CoreLocation is not ready yet.
    private var persisted: CLLocation? {
        guard let a = UserDefaults.standard.array(forKey: Self.lastKey) as? [Double], a.count == 2 else { return nil }
        return CLLocation(latitude: a[0], longitude: a[1])
    }

    private func finish(_ loc: CLLocation?) {
        let loc = loc ?? persisted
        if let loc {
            cached = loc
            cachedAt = Date()
            UserDefaults.standard.set([loc.coordinate.latitude, loc.coordinate.longitude], forKey: Self.lastKey)
        }
        let w = waiters
        waiters = []
        w.forEach { $0.resume(returning: loc) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiters.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(cached)
    }
}

// MARK: - Now Playing (Music / Spotify via AppleScript)

final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    @Published var player: String?   // "Music" or "Spotify"
    @Published var current: SavedTrack?

    private var timer: Timer?
    private var lastTrackKey = ""

    private init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func activePlayer() -> String? {
        let spotify = Script.isRunning("com.spotify.client")
        let music = Script.isRunning("com.apple.Music")
        if spotify && !music { return "Spotify" }
        if music && !spotify { return "Music" }
        if spotify && music { return player ?? "Music" }
        return nil
    }

    func poll() {
        guard let app = activePlayer() else {
            player = nil; playing = false; title = ""; artist = ""; artwork = nil
            return
        }
        let src = """
        tell application "\(app)"
            if player state is stopped then return "stopped"
            set t to current track
            set d to duration of t
            set tid to ""
            try
                set tid to \(app == "Spotify" ? "id of t" : "persistent ID of t")
            end try
            return (player state as text) & "‖" & (name of t) & "‖" & (artist of t) & "‖" & (player position as text) & "‖" & (d as text) & "‖" & tid
        end tell
        """
        Script.run(src) { [weak self] result in
            guard let self else { return }
            self.player = app
            guard let s = result?.stringValue, s != "stopped" else {
                self.playing = false
                return
            }
            let parts = s.components(separatedBy: "‖")
            guard parts.count >= 5 else { return }
            self.playing = parts[0] == "playing"
            self.title = parts[1]
            self.artist = parts[2]
            self.position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            var dur = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            if app == "Spotify" { dur /= 1000 }
            self.duration = dur
            let key = app + parts[1] + parts[2]
            if key != self.lastTrackKey {
                self.lastTrackKey = key
                self.loadArtwork(app)
                let ref = parts.count > 5 ? parts[5] : ""
                self.current = SavedTrack(title: parts[1], artist: parts[2], player: app, ref: ref)
                if self.playing { MusicLibrary.shared.addRecent(self.current!) }
            }
        }
        // If both run, prefer the one that is playing.
        if Script.isRunning("com.spotify.client") && Script.isRunning("com.apple.Music") {
            let other = app == "Music" ? "Spotify" : "Music"
            Script.run("tell application \"\(other)\" to return player state as text") { [weak self] r in
                if r?.stringValue == "playing", self?.playing == false { self?.player = other }
            }
        }
    }

    private func loadArtwork(_ app: String) {
        if app == "Spotify" {
            Script.run("tell application \"Spotify\" to return artwork url of current track") { [weak self] r in
                guard let s = r?.stringValue, let url = URL(string: s) else { self?.artwork = nil; return }
                Task {
                    let img = (try? await URLSession.shared.data(from: url)).flatMap { NSImage(data: $0.0) }
                    await MainActor.run { self?.artwork = img }
                }
            }
        } else {
            Script.run("tell application \"Music\" to return raw data of artwork 1 of current track") { [weak self] r in
                self?.artwork = r.flatMap { NSImage(data: $0.data) }
            }
        }
    }

    func command(_ cmd: String) {
        guard let app = player ?? activePlayer() else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
            return
        }
        Script.run("tell application \"\(app)\" to \(cmd)") { [weak self] _ in self?.poll() }
    }

    func openPlayer() {
        let path = player == "Spotify" ? "/Applications/Spotify.app" : "/System/Applications/Music.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

// MARK: - Remembered playlists & tracks

struct SavedTrack: Codable, Hashable, Identifiable {
    var title: String
    var artist: String
    var player: String      // "Music" or "Spotify"
    var ref: String         // Music persistent ID or Spotify URI
    var id: String { player + ref + title + artist }
    var label: String { artist.isEmpty ? title : "\(title) – \(artist)" }
}

final class MusicLibrary: ObservableObject {
    static let shared = MusicLibrary()

    @Published private(set) var playlists: [String] = []
    @Published private(set) var favorites: [SavedTrack] = []
    @Published private(set) var recent: [SavedTrack] = []
    @Published private(set) var refreshing = false

    private let d = UserDefaults.standard

    private init() {
        playlists = d.stringArray(forKey: "music.playlists") ?? []
        favorites = load("music.favorites")
        recent = load("music.recent")
        if Script.isRunning("com.apple.Music") { refreshPlaylists() }
    }

    private func load(_ key: String) -> [SavedTrack] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedTrack].self, from: $0) } ?? []
    }

    private func store(_ list: [SavedTrack], _ key: String) {
        if let data = try? JSONEncoder().encode(list) { d.set(data, forKey: key) }
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Reads the user's playlists from the Music app (launches it if needed).
    func refreshPlaylists() {
        refreshing = true
        let src = """
        tell application "Music"
            set out to {}
            repeat with p in (every user playlist)
                try
                    if special kind of p is none then set end of out to name of p
                end try
            end repeat
            set AppleScript's text item delimiters to "‖"
            return out as text
        end tell
        """
        Script.run(src) { [weak self] r in
            guard let self else { return }
            self.refreshing = false
            guard let text = r?.stringValue else { return }
            var seen = Set<String>()
            let names = text.components(separatedBy: "‖").filter { !$0.isEmpty && seen.insert($0).inserted }
            self.playlists = names
            self.d.set(names, forKey: "music.playlists")
        }
    }

    func play(playlist: String) {
        Script.run("tell application \"Music\" to play user playlist \(Self.quote(playlist))") { _ in NowPlaying.shared.poll() }
    }

    func play(_ t: SavedTrack) {
        let src: String
        if t.player == "Spotify" {
            src = "tell application \"Spotify\" to play track \(Self.quote(t.ref))"
        } else {
            src = """
            tell application "Music"
                try
                    play (first track of library playlist 1 whose persistent ID is \(Self.quote(t.ref)))
                on error
                    play (first track of library playlist 1 whose name is \(Self.quote(t.title)) and artist is \(Self.quote(t.artist)))
                end try
            end tell
            """
        }
        Script.run(src) { _ in NowPlaying.shared.poll() }
    }

    func isFavorite(_ t: SavedTrack?) -> Bool { t.map { favorites.contains($0) } ?? false }

    func toggleFavorite(_ t: SavedTrack) {
        if let i = favorites.firstIndex(of: t) { favorites.remove(at: i) } else { favorites.insert(t, at: 0) }
        store(favorites, "music.favorites")
    }

    func removeFavorite(_ t: SavedTrack) {
        favorites.removeAll { $0 == t }
        store(favorites, "music.favorites")
    }

    func addRecent(_ t: SavedTrack) {
        recent.removeAll { $0 == t }
        recent.insert(t, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        store(recent, "music.recent")
    }

    func clearRecent() {
        recent = []
        store(recent, "music.recent")
    }
}

// MARK: - EventKit

final class EventStore: ObservableObject {
    static let shared = EventStore()
    let store = EKEventStore()

    @Published var events: [EKEvent] = []
    @Published var upcoming: [EKEvent] = []
    /// All events of today (incl. all-day ones) for the bubble on the calendar tile.
    @Published var todayCount = 0
    @Published var reminders: [EKReminder] = []
    @Published var eventsAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Published var remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    private var reminderList = ""
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reloadEvents(); self?.reloadReminders()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.reloadEvents() }
    }

    func requestEvents() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async { self?.eventsAuthorized = ok; self?.reloadEvents() }
        }
    }

    func requestReminders(list: String) {
        reminderList = list
        store.requestFullAccessToReminders { [weak self] ok, _ in
            DispatchQueue.main.async { self?.remindersAuthorized = ok; self?.reloadReminders() }
        }
    }

    func reloadEvents() {
        guard eventsAuthorized else { return }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: start))!
        let pred = store.predicateForEvents(withStart: start.addingTimeInterval(-3600 * 4), end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
        let dayStart = Calendar.current.startOfDay(for: start)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        todayCount = store.events(matching: store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)).count
    }

    /// Events of the next `days` days for the unrolled list.
    func loadUpcoming(days: Int = 7) {
        guard eventsAuthorized else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
        upcoming = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.endDate > Date() }
            .sorted { $0.startDate < $1.startDate }
    }

    func reloadReminders() {
        guard remindersAuthorized else { return }
        var cals: [EKCalendar]? = nil
        if !reminderList.isEmpty {
            cals = store.calendars(for: .reminder).filter { $0.title.localizedCaseInsensitiveCompare(reminderList) == .orderedSame }
            if cals?.isEmpty == true { cals = nil }
        }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        store.fetchReminders(matching: pred) { [weak self] items in
            let sorted = (items ?? []).sorted { a, b in
                let da = a.dueDateComponents?.date ?? .distantFuture
                let db = b.dueDateComponents?.date ?? .distantFuture
                return da == db ? (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast) : da < db
            }
            DispatchQueue.main.async { self?.reminders = sorted }
        }
    }

    func complete(_ r: EKReminder) {
        r.isCompleted = true
        try? store.save(r, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == r.calendarItemIdentifier }
    }

    func addReminder(_ title: String) {
        guard remindersAuthorized, !title.isEmpty else { return }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.calendars(for: .reminder).first { $0.title == reminderList } ?? store.defaultCalendarForNewReminders()
        try? store.save(r, commit: true)
        reloadReminders()
    }
}

// MARK: - Clipboard history

/// One entry of the clipboard history: text, copied files, or an image (kept as a PNG on disk).
struct ClipEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, files, image }
    var id = UUID()
    var kind: Kind
    /// Text, file paths separated by newlines, or the image's content hash.
    var value: String
    var width = 0
    var height = 0
    var date = Date()

    var paths: [String] { value.split(separator: "\n").map(String.init) }
    var imageURL: URL { ClipboardHistory.folder.appendingPathComponent(id.uuidString + ".png") }

    /// One-line label for lists and the widget.
    var title: String {
        switch kind {
        case .text: value
        case .files: paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        case .image: width > 0 ? "Bild · \(width) × \(height)" : "Bild"
        }
    }
}

final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()
    private static let key = "clipboard.history.v2"
    private static let limit = 40
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Crohniq Dock/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @Published private(set) var items: [ClipEntry] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }
    private var changeCount = -1
    private var timer: Timer?
    private let thumbs = NSCache<NSString, NSImage>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([ClipEntry].self, from: data) {
            items = saved.filter { $0.kind != .image || FileManager.default.fileExists(atPath: $0.imageURL.path) }
        } else if let old = UserDefaults.standard.stringArray(forKey: "clipboard.history.v1") {
            items = old.map { ClipEntry(kind: .text, value: $0) }
        }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.check() }
    }

    /// Starts recording at launch, so copies are kept even before the widget is shown.
    func start() {}

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        // Passwords and other concealed content stay out of the history.
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            add(ClipEntry(kind: .files, value: urls.map(\.path).joined(separator: "\n")))
            return
        }
        let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasImage = pb.availableType(from: [.png, .tiff]) != nil
        if hasImage, text.isEmpty || pb.availableType(from: [.png, .tiff, .string]) != .string,
           let image = NSImage(pasteboard: pb), let entry = saveImage(image) {
            add(entry)
            return
        }
        guard !text.isEmpty, text.count < 50_000 else { return }
        add(ClipEntry(kind: .text, value: text))
    }

    private func saveImage(_ image: NSImage) -> ClipEntry? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]), png.count < 60_000_000 else { return nil }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if let existing = items.first(where: { $0.kind == .image && $0.value == hash }) { return existing }
        let entry = ClipEntry(kind: .image, value: hash, width: rep.pixelsWide, height: rep.pixelsHigh)
        do { try png.write(to: entry.imageURL) } catch { return nil }
        return entry
    }

    private func add(_ entry: ClipEntry) {
        var list = items
        if let i = list.firstIndex(where: { $0.kind == entry.kind && $0.value == entry.value }) {
            var moved = list.remove(at: i)
            moved.date = Date()
            list.insert(moved, at: 0)
        } else {
            list.insert(entry, at: 0)
        }
        while list.count > Self.limit { deleteFile(list.removeLast()) }
        items = list
    }

    /// A small preview of an image entry, cached.
    func thumbnail(_ entry: ClipEntry) -> NSImage? {
        guard entry.kind == .image else { return nil }
        if let cached = thumbs.object(forKey: entry.id.uuidString as NSString) { return cached }
        guard let src = CGImageSourceCreateWithURL(entry.imageURL as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 520,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbs.setObject(image, forKey: entry.id.uuidString as NSString)
        return image
    }

    /// Puts the entry back on the clipboard and moves it to the top.
    func copy(_ entry: ClipEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch entry.kind {
        case .text: pb.setString(entry.value, forType: .string)
        case .files: pb.writeObjects(entry.paths.map { URL(fileURLWithPath: $0) as NSURL })
        case .image:
            if let image = NSImage(contentsOf: entry.imageURL) { pb.writeObjects([image]) }
        }
        changeCount = pb.changeCount
        add(entry)
    }

    func copy(_ s: String) { copy(ClipEntry(kind: .text, value: s)) }

    func remove(_ entry: ClipEntry) {
        deleteFile(entry)
        items.removeAll { $0.id == entry.id }
    }

    func clear() {
        items.forEach(deleteFile)
        items = []
    }

    private func deleteFile(_ entry: ClipEntry) {
        guard entry.kind == .image else { return }
        try? FileManager.default.removeItem(at: entry.imageURL)
        thumbs.removeObject(forKey: entry.id.uuidString as NSString)
    }
}

// MARK: - Audio (CoreAudio)

final class AudioControl: ObservableObject {
    static let shared = AudioControl()
    @Published var volume: Float = 0.5
    @Published var muted = false
    @Published var deviceName = ""
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private var device: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    func refresh() {
        let dev = device
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr, abs(vol - volume) > 0.01 { volume = vol }

        var mute = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyMute
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &mute) == noErr { muted = mute != 0 }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr, let n = name?.takeRetainedValue() {
            deviceName = n as String
        }
    }

    func setVolume(_ v: Float) {
        volume = v
        var vol = Float32(v)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        if muted && v > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        muted = m
        var val = UInt32(m ? 1 : 0)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
    }
}

// MARK: - Keep awake

final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    @Published private(set) var active = false
    private var assertion: IOPMAssertionID = 0

    func toggle() {
        if active {
            IOPMAssertionRelease(assertion)
            active = false
        } else {
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Crohniq Dock – wach halten" as CFString, &assertion)
            active = ok == kIOReturnSuccess
        }
    }
}

// MARK: - Voice recorder

final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = VoiceRecorder()
    @Published var recording = false
    @Published var elapsed: TimeInterval = 0
    @Published var levels: [Double] = Array(repeating: 0.05, count: 24)
    @Published var lastFile: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    static var folder: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Crohniq Dock Memos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func toggle() { recording ? stop() : start() }

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Self.folder.appendingPathComponent("Memo \(fmt.string(from: Date())).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.isMeteringEnabled = true
        r.delegate = self
        r.record()
        recorder = r
        lastFile = url
        recording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            let db = Double(r.averagePower(forChannel: 0))
            let level = max(0.05, min(1, (db + 50) / 50))
            self.levels.append(level)
            self.levels.removeFirst()
            self.elapsed = r.currentTime
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        recording = false
        levels = Array(repeating: 0.05, count: 24)
        if let f = lastFile { Notifier.notify("Sprachmemo gespeichert", f.lastPathComponent) }
    }
}
