import IOKit.ps
import SwiftUI

enum Hardware {
    /// True on MacBooks: an internal battery is present.
    static let hasBattery: Bool = {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { ps in
            (IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String
                == kIOPSInternalBatteryType
        }
    }()
}

// MARK: - Widget catalogue

enum WidgetCategory: String, CaseIterable, Identifiable {
    case apps = "Apps, Dateien & Schnellzugriff"
    case productivity = "Produktivität & Fokus"
    case system = "Mac-Steuerung & System"
    case utility = "Kreativ & Werkzeuge"
    case business = "Business & Entwickler"
    var id: String { rawValue }
}

struct ConfigField {
    enum Kind {
        case text, secure, multiline, number, directory
        case choice([(value: String, label: String)])
    }
    let key: String
    let label: String
    var placeholder: String = ""
    var kind: Kind = .text
    var help: String? = nil
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, weather, nowPlaying, apps, appSwitcher, bookmarks, fileShelf, downloads, finder, dropbox, shortcuts, search
    case pomodoro, timer, focus, water, calendar, reminders, progress, stopwatch, notes, mail
    case battery, cpu, memory, disk, cpuGraph, toggles, audio, clipboard, screenshots, voiceMemo, emoji, photos, panoramas
    case colorPicker, converter, github, developerUsage, metric
    case nexus, appleIntelligence, workspaces, launcher, quitApps, trash

    var id: String { rawValue }

    /// Widgets that make no sense on this Mac are hidden (battery on desktops).
    var isAvailable: Bool { self != .battery || Hardware.hasBattery }

    static var available: [WidgetKind] { allCases.filter(\.isAvailable) }

    var title: String {
        switch self {
        case .clock: "Uhr"
        case .weather: "Wetter"
        case .nowPlaying: "Musik"
        case .apps: "Apps & Ordner"
        case .appSwitcher: "App-Umschalter"
        case .bookmarks: "Lesezeichen"
        case .fileShelf: "Ablage"
        case .downloads: "Downloads"
        case .finder: "Finder"
        case .dropbox: "Dropbox"
        case .shortcuts: "Kurzbefehle"
        case .search: "Suche"
        case .pomodoro: "Pomodoro"
        case .timer: "Timer"
        case .focus: "Fokuszeit"
        case .water: "Trinken"
        case .calendar: "Kalender"
        case .reminders: "Erinnerungen"
        case .progress: "Fortschritt"
        case .stopwatch: "Stoppuhr"
        case .notes: "Notiz"
        case .mail: "Mail"
        case .battery: "Batterie"
        case .cpu: "CPU"
        case .memory: "Arbeitsspeicher"
        case .disk: "Festplatte"
        case .cpuGraph: "CPU-Verlauf"
        case .toggles: "Schnellschalter"
        case .audio: "Lautstärke"
        case .clipboard: "Copy & Paste"
        case .screenshots: "Bildschirmfotos"
        case .voiceMemo: "Sprachmemo"
        case .emoji: "Emoji"
        case .photos: "Fotos"
        case .panoramas: "Panorama-Hintergründe"
        case .colorPicker: "Farbpipette"
        case .converter: "Währungsrechner"
        case .github: "GitHub"
        case .developerUsage: "KI- und Entwickler-Kontingente"
        case .metric: "Kennzahl (JSON)"
        case .nexus: "Nexus-Suche & KI"
        case .appleIntelligence: "Apple Intelligence"
        case .workspaces: "Arbeitsbereiche"
        case .launcher: "App-Starter"
        case .quitApps: "Apps beenden"
        case .trash: "Papierkorb"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .nowPlaying: "music.note"
        case .apps: "square.grid.2x2"
        case .appSwitcher: "rectangle.stack"
        case .bookmarks: "bookmark"
        case .fileShelf: "tray"
        case .downloads: "arrow.down.circle"
        case .finder: "folder"
        case .dropbox: "shippingbox"
        case .shortcuts: "command"
        case .search: "magnifyingglass"
        case .pomodoro: "timer"
        case .timer: "timer.circle"
        case .focus: "moon.fill"
        case .water: "drop"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .progress: "circle.grid.3x3"
        case .stopwatch: "stopwatch"
        case .notes: "note.text"
        case .mail: "envelope"
        case .battery: "battery.75percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .cpuGraph: "waveform.path.ecg"
        case .toggles: "switch.2"
        case .audio: "speaker.wave.2"
        case .clipboard: "doc.on.clipboard"
        case .screenshots: "camera.viewfinder"
        case .voiceMemo: "waveform"
        case .emoji: "face.smiling"
        case .photos: "photo"
        case .panoramas: "pano.fill"
        case .colorPicker: "eyedropper"
        case .converter: "dollarsign.arrow.circlepath"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .developerUsage: "speedometer"
        case .metric: "chart.bar"
        case .nexus: "sparkle.magnifyingglass"
        case .appleIntelligence: "apple.intelligence"
        case .workspaces: "rectangle.3.group"
        case .launcher: "app.badge"
        case .quitApps: "xmark.app"
        case .trash: "trash"
        }
    }

    var category: WidgetCategory {
        switch self {
        case .apps, .appSwitcher, .bookmarks, .fileShelf, .downloads, .finder, .dropbox, .shortcuts, .search, .nexus, .workspaces, .launcher, .trash: .apps
        case .clock, .quitApps, .pomodoro, .timer, .focus, .appleIntelligence, .water, .calendar, .reminders, .progress, .stopwatch, .mail: .productivity
        case .weather, .nowPlaying, .battery, .cpu, .memory, .disk, .cpuGraph, .toggles, .audio,
             .clipboard, .screenshots, .voiceMemo, .emoji, .photos, .panoramas, .quitApps: .system
        case .notes, .colorPicker, .converter: .utility
        case .github, .developerUsage, .metric: .business
        }
    }

    /// Allowed widths in tile units. The first entry is not necessarily the default.
    var sizes: [Int] {
        switch self {
        case .clock: [1, 2, 3]
        case .weather: [1, 2, 3, 4, 5]
        case .nowPlaying: [1, 2, 3, 4, 5]
        case .apps: [1, 2, 3, 4]
        case .appSwitcher: [1, 2, 3, 4, 5, 6]
        case .bookmarks: [1, 2, 3, 4, 5]
        case .fileShelf: [1, 2, 3, 4]
        case .downloads: [1, 2, 3]
        case .finder: [1, 2, 3]
        case .dropbox: [1, 2, 3, 4]
        case .shortcuts: [1, 2, 3, 4]
        case .search: [2, 3, 4, 5]
        case .pomodoro: [1, 2, 3]
        case .timer: [1, 2, 3]
        case .focus: [1, 2, 3]
        case .appleIntelligence: [2, 3, 4]
        case .water: [1, 2, 3]
        case .calendar: [1, 2, 3, 4]
        case .reminders: [1, 2, 3, 4]
        case .progress: [1, 2, 3]
        case .stopwatch: [1, 2, 3]
        case .notes: [1, 2, 3, 4]
        case .mail: [1, 2, 3]
        case .battery, .cpu, .memory, .disk: [1, 2, 3]
        case .cpuGraph: [1, 2, 3, 4]
        case .toggles: [1, 2, 3, 4, 5]
        case .audio: [1, 2, 3, 4]
        case .clipboard: [1, 2, 3]
        case .screenshots: [1, 2, 3]
        case .voiceMemo: [1, 2, 3]
        case .emoji: [1, 2, 3, 4]
        case .photos: [1, 2, 3]
        case .panoramas: [2, 3, 4, 5]
        case .colorPicker: [1, 2, 3]
        case .converter: [1, 2, 3, 4]
        case .github: [1, 2, 3, 4]
        case .developerUsage: [4]
        case .metric: [1, 2, 3]
        case .nexus: [2, 3, 4, 5, 6]
        case .workspaces: [1, 2, 3, 4, 5]
        case .launcher: [1, 2, 3]
        case .quitApps: [1, 2, 3, 4, 5]
        case .trash: [1, 2, 3]
        }
    }

    var defaultSize: Int {
        switch self {
        case .clock, .pomodoro, .timer, .focus, .water, .bookmarks, .fileShelf, .progress, .stopwatch, .metric: 2
        case .weather, .calendar, .reminders, .cpuGraph, .audio, .voiceMemo, .emoji, .converter, .github,
             .notes, .search, .appSwitcher: 3
        case .screenshots: 3
        case .nowPlaying, .toggles, .nexus: 4
        case .developerUsage: 4
        case .workspaces, .launcher, .dropbox, .shortcuts, .appleIntelligence: 3
        case .panoramas: 4
        default: 1
        }
    }

    var defaultConfig: [String: String] {
        switch self {
        case .clock: ["style": "digital", "timezone": "", "label": "", "seconds": "0"]
        case .weather: ["city": "auto"]
        case .calendar: ["display": "standard"]
        case .apps: ["paths": ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app",
                               "/System/Applications/Mail.app", "/System/Applications/Music.app"].joined(separator: "\n")]
        case .finder: ["favorites": "", "fileCount": "10"]
        case .dropbox:
            ["folder": FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/CloudStorage/Dropbox")
                ? NSHomeDirectory() + "/Library/CloudStorage/Dropbox"
                : NSHomeDirectory() + "/Dropbox",
             "count": "5"]
        case .shortcuts: ["count": "5", "favorites": ""]
        case .photos: ["count": "5"]
        case .panoramas: ["count": "10", "interval": "300"]
        case .bookmarks: ["source": "safari", "folder": "", "items": "Google|https://www.google.com\nGitHub|https://github.com"]
        case .search: ["mode": "files", "engine": "google"]
        case .mail: ["count": "10", "mailFilter": "all"]
        case .pomodoro: ["work": "25", "break": "5"]
        case .timer: ["duration": "5"]
        case .focus: ["duration": "25", "label": "Fokus"]
        case .water: ["goal": "8", "interval": "45"]
        case .progress: ["mode": "year"]
        case .emoji: ["emojis": "😂✨✅🔥🥹🙏💡🚀❤️👍🎉😎"]
        case .converter: ["from": "EUR", "to": "CHF", "amount": "100"]
        case .github: ["user": "", "token": ""]
        case .metric: ["title": "Besucher · 7 Tage", "url": "", "path": "", "header": "", "prefix": "", "suffix": "", "interval": "15"]
        case .reminders: ["list": ""]
        case .launcher:
            ["apps": (["/Applications/Xcode.app"] + ["/Applications/Safari.app", "/Applications/Firefox.app"]
                .filter { FileManager.default.fileExists(atPath: $0) }).joined(separator: "\n"),
             "fileCount": "10", "safariView": "history", "forkLiftMode": "app", "forkLiftFolder": ""]
        default: [:]
        }
    }

    var configFields: [ConfigField] {
        switch self {
        case .clock:
            [ConfigField(key: "style", label: "Darstellung", kind: .choice([("digital", "Digital"), ("analog", "Analog")])),
             ConfigField(key: "label", label: "Bezeichnung", placeholder: "z. B. New York"),
             ConfigField(key: "timezone", label: "Zeitzone", placeholder: "leer = lokal, z. B. America/New_York"),
             ConfigField(key: "seconds", label: "Sekunden", kind: .choice([("0", "Aus"), ("1", "Ein")]))]
        case .weather:
            [ConfigField(key: "city", label: "Ort", placeholder: "auto",
                         help: "„auto“ oder leer = aktueller Standort (Ortungsdienste). Sonst einen Ort eintragen, z. B. „Winterthur“ oder „Konstanz, Deutschland“.")]
        case .calendar:
            [ConfigField(key: "display", label: "Anzeige", kind: .choice([
                ("standard", "Standard"), ("date", "Datum"), ("next", "Nächster Termin"), ("agenda", "Agenda")
            ]))]
        case .apps:
            [ConfigField(key: "paths", label: "Apps / Ordner (ein Pfad pro Zeile)", kind: .multiline,
                         help: "Du kannst auch Apps oder Ordner direkt auf das Widget ziehen.")]
        case .finder:
            [ConfigField(key: "favorites", label: "Favoriten-Verzeichnisse (ein Pfad pro Zeile)", kind: .multiline,
                         help: "Die Ordner erscheinen im aufgeklappten Finder-Widget und lassen sich dort direkt öffnen."),
             ConfigField(key: "fileCount", label: "Zuletzt geöffnete Dateien anzeigen", kind: .number,
                         help: "Anzahl der Einträge im Finder-Aufklappbereich (1–50).")]
        case .dropbox:
            [ConfigField(key: "folder", label: "Dropbox-Verzeichnis", kind: .directory,
                         help: "Wähle den synchronisierten Dropbox-Ordner auf diesem Mac."),
             ConfigField(key: "count", label: "Dateien anzeigen", kind: .number,
                         help: "Anzahl der zuletzt geänderten Dateien (1–50).")]
        case .shortcuts:
            [ConfigField(key: "count", label: "Kurzbefehle anzeigen", kind: .number,
                         help: "Anzahl der Schaltflächen im Widget (1–12).")]
        case .photos:
            [ConfigField(key: "count", label: "Letzte Fotos anzeigen", kind: .number,
                         help: "Anzahl der Fotos im Widget und Aufklappbereich (1–12).")]
        case .panoramas:
            [ConfigField(key: "count", label: "Bilder im Wechsel", kind: .number,
                         help: "Anzahl der Panorama-Fotos und Apple-Hintergrundbilder (1–50)."),
             ConfigField(key: "interval", label: "Hintergrund wechseln alle … Sekunden", kind: .number,
                         help: "Empfohlen: 300 Sekunden (5 Minuten). Minimum: 30 Sekunden.")]
        case .bookmarks:
            [ConfigField(key: "source", label: "Quelle", kind: .choice([("safari", "Safari-Lesezeichen"), ("custom", "Eigene Liste")])),
             ConfigField(key: "folder", label: "Safari-Ordner auf der Kachel", placeholder: "leer = Favoritenleiste",
                         help: "Safari braucht Festplattenvollzugriff (Systemeinstellungen › Datenschutz & Sicherheit). Das ▾ zeigt immer alle Ordner."),
             ConfigField(key: "items", label: "Eigene Liste (Name|URL pro Zeile)", kind: .multiline)]
        case .launcher:
            [ConfigField(key: "fileCount", label: "Standard-Dateiverlauf je App", kind: .number,
                         help: "Voreinstellung für Apps ohne eigene Anzahl (1–50)."),
             ConfigField(key: "safariView", label: "Safari zeigt", kind: .choice([("history", "Verlauf"), ("favorites", "Favoriten")])),
             ConfigField(key: "forkLiftMode", label: "ForkLift-Klick", kind: .choice([("app", "App sofort öffnen"), ("folder", "Dateien aus Verzeichnis anzeigen")])),
             ConfigField(key: "forkLiftFolder", label: "ForkLift-Verzeichnis", kind: .directory,
                         help: "Wird im Dateien-Modus verwendet.")]
        case .mail:
            [ConfigField(key: "mailFilter", label: "Mails anzeigen", kind: .choice([
                ("unread", "Nur neue (ungelesene)"),
                ("all", "Alle"),
                ("known", "Bekannte Absender (Kontakte)")
            ]))]
        case .nexus:
            [ConfigField(key: "mode", label: "Enter startet", kind: .choice([("search", "Nexus-Suche"), ("ai", "KI (Apple Intelligence)")]),
                         help: "Mit ✨ wechselst du jederzeit zwischen Suche und KI. Die KI läuft lokal auf dem Mac.")]
        case .search:
            [ConfigField(key: "mode", label: "Suchart", kind: .choice([("files", "Dateien (Spotlight)"), ("web", "Web & KI")])),
             ConfigField(key: "engine", label: "Suchmaschine / KI", kind: .choice(SearchEngine.available.filter { $0 != .files }.map { ($0.rawValue, $0.label) }),
                         help: "Apple Intelligence antwortet direkt an der Leiste. ChatGPT und Claude erscheinen nur, wenn die App installiert ist. Auf dem Symbol im Widget wechselst du jederzeit.")]
        case .pomodoro:
            [ConfigField(key: "work", label: "Fokus (Minuten)", kind: .number),
             ConfigField(key: "break", label: "Pause (Minuten)", kind: .number)]
        case .timer:
            [ConfigField(key: "duration", label: "Dauer (Minuten)", kind: .number,
                         help: "Countdown-Dauer von 1 bis 1440 Minuten.")]
        case .focus:
            [ConfigField(key: "label", label: "Bezeichnung", placeholder: "Fokus"),
             ConfigField(key: "duration", label: "Dauer (Minuten)", kind: .number,
                         help: "App-lokaler Fokus-Timer; schaltet keinen macOS-Fokusmodus um.")]
        case .water:
            [ConfigField(key: "goal", label: "Gläser pro Tag", kind: .number),
             ConfigField(key: "interval", label: "Erinnerung alle … Minuten (0 = aus)", kind: .number)]
        case .progress:
            [ConfigField(key: "mode", label: "Zeitraum", kind: .choice([("year", "Jahr"), ("month", "Monat"), ("week", "Woche"), ("day", "Tag")]))]
        case .reminders:
            [ConfigField(key: "list", label: "Liste", placeholder: "leer = alle Listen")]
        case .emoji:
            [ConfigField(key: "emojis", label: "Emojis", placeholder: "😂✨✅")]
        case .converter:
            [ConfigField(key: "from", label: "Von Währung", placeholder: "EUR"),
             ConfigField(key: "to", label: "Nach Währung", placeholder: "CHF")]
        case .github:
            [ConfigField(key: "user", label: "Benutzername"),
             ConfigField(key: "token", label: "Token (optional)", kind: .secure,
                         help: "Mit einem Personal Access Token (nur read:user) zeigt das Widget dein Beitrags-Raster und deine Serie.")]
        case .metric:
            [ConfigField(key: "title", label: "Bezeichnung"),
             ConfigField(key: "url", label: "URL (liefert JSON)", placeholder: "https://plausible.io/api/v1/stats/aggregate?..."),
             ConfigField(key: "path", label: "JSON-Pfad", placeholder: "results.visitors.value",
                         help: "Punkte trennen Ebenen, Zahlen wählen Listeneinträge, z. B. data.0.total"),
             ConfigField(key: "header", label: "Header (optional)", placeholder: "Authorization: Bearer …", kind: .secure),
             ConfigField(key: "prefix", label: "Präfix", placeholder: "$"),
             ConfigField(key: "suffix", label: "Suffix", placeholder: " CHF"),
             ConfigField(key: "interval", label: "Aktualisieren alle … Minuten", kind: .number)]
        default: []
        }
    }
}

// MARK: - Instances & profiles

struct WidgetInstance: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: WidgetKind
    var size: Int
    var config: [String: String]

    init(_ kind: WidgetKind, size: Int? = nil, config: [String: String] = [:]) {
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.config = kind.defaultConfig.merging(config) { _, new in new }
    }

    func cfg(_ key: String, _ fallback: String = "") -> String {
        if let v = config[key], !v.isEmpty { return v }
        return kind.defaultConfig[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    var displayName: String {
        let name = (config["widgetName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? kind.title : name
    }

    var assignedWorkspaceIDs: Set<UUID>? {
        guard let value = config["workspaceIDs"] else { return nil }
        return Set(value.split(separator: "\n").compactMap { UUID(uuidString: String($0)) })
    }

    func cfgInt(_ key: String, _ fallback: Int) -> Int { Int(cfg(key)) ?? fallback }
}

struct DockProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var widgets: [WidgetInstance]
    var theme: String? = nil
}

enum DockProfilePreset: String, CaseIterable, Identifiable {
    case daily, developer, writing, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .developer: "Developer"
        case .writing: "Writing"
        case .focus: "Fokus"
        }
    }

    var theme: String {
        switch self {
        case .daily: "system"
        case .developer: "anthracite"
        case .writing: "light"
        case .focus: "dark"
        }
    }

    var widgets: [WidgetInstance] {
        let kinds: [WidgetKind]
        switch self {
        case .daily: kinds = [.clock, .calendar, .weather, .reminders, .mail, .photos, .dropbox, .shortcuts, .appleIntelligence]
        case .developer: kinds = [.clock, .launcher, .github, .developerUsage, .cpuGraph, .clipboard, .workspaces]
        case .writing: kinds = [.clock, .notes, .pomodoro, .calendar, .bookmarks]
        case .focus: kinds = [.clock, .focus, .pomodoro, .reminders, .water, .progress]
        }
        return kinds.filter(\.isAvailable).map { WidgetInstance($0) }
    }
}

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top, left, right, free
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottom: "Unten"
        case .top: "Oben"
        case .left: "Links"
        case .right: "Rechts"
        case .free: "Frei – bleibt, wo du sie ablegst"
        }
    }
    var isVertical: Bool { self == .left || self == .right }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case bulgarian = "bg"
    case catalan = "ca"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case estonian = "et"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hungarian = "hu"
    case icelandic = "is"
    case irish = "ga"
    case italian = "it"
    case latvian = "lv"
    case lithuanian = "lt"
    case luxembourgish = "lb"
    case maltese = "mt"
    case norwegian = "nb"
    case polish = "pl"
    case portuguese = "pt-PT"
    case romanian = "ro"
    case serbian = "sr"
    case slovak = "sk"
    case slovenian = "sl"
    case spanish = "es"
    case swedish = "sv"
    case ukrainian = "uk"
    case welsh = "cy"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System (macOS)"
        case .bulgarian: "български"
        case .catalan: "català"
        case .croatian: "hrvatski"
        case .czech: "čeština"
        case .danish: "dansk"
        case .dutch: "Nederlands"
        case .english: "English"
        case .estonian: "eesti"
        case .finnish: "suomi"
        case .french: "français"
        case .german: "Deutsch"
        case .greek: "Ελληνικά"
        case .hungarian: "magyar"
        case .icelandic: "íslenska"
        case .irish: "Gaeilge"
        case .italian: "italiano"
        case .latvian: "latviešu"
        case .lithuanian: "lietuvių"
        case .luxembourgish: "lëtzebuergesch"
        case .maltese: "Malti"
        case .norwegian: "norsk bokmål"
        case .polish: "polski"
        case .portuguese: "português (Portugal)"
        case .romanian: "română"
        case .serbian: "српски"
        case .slovak: "slovenčina"
        case .slovenian: "slovenščina"
        case .spanish: "español"
        case .swedish: "svenska"
        case .ukrainian: "українська"
        case .welsh: "Cymraeg"
        }
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()
    private let key = "app.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: key) }
    }

    var locale: Locale { language.locale }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
}

enum DockFontStyle: String, CaseIterable, Codable, Identifiable {
    case system, rounded, serif, monospaced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .rounded: "Rund"
        case .serif: "Serif"
        case .monospaced: "Monospace"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

struct DockSettings: Codable, Equatable {
    var position: DockPosition = .bottom
    var autoHide = false
    var tileSize: Double = 64
    var showBar = true
    var barOpacity: Double = 0.92
    var floatAbove = true
    var freeX: Double? = nil
    var freeY: Double? = nil
    var margin: Double = 6
    var hotkey = true
    /// Position along the edge (0…1, centre of the bar); nil = centred.
    var along: Double? = nil
    /// Index into NSScreen.screens; nil = main screen.
    var screenIndex: Int? = nil
    /// Orientation of a freely placed bar.
    var freeVertical: Bool? = nil
    /// "system", "light", "dark", "anthracite" or "custom".
    var theme: String? = nil
    /// Liquid Glass surface.
    var glass: Bool? = nil
    var customBar: String? = nil
    var customTile: String? = nil
    var customText: String? = nil
    var fontStyle: DockFontStyle? = nil
    var fontDesign: Font.Design { (fontStyle ?? .system).design }
    /// Unroll lists (calendar, reminders, notes) on hover.
    var hoverLists: Bool? = nil
    /// Tint strength of the glass (0 = clear glass).
    var glassTint: Double? = nil
}

// MARK: - Store

final class DockStore: ObservableObject {
    static let shared = DockStore()

    @Published var profiles: [DockProfile] { didSet { save() } }
    @Published var activeProfileID: UUID { didSet { save() } }
    @Published var settings: DockSettings {
        didSet {
            if profiles.indices.contains(activeIndex), profiles[activeIndex].theme != settings.theme {
                profiles[activeIndex].theme = settings.theme
            }
            save()
        }
    }
    @Published var editingWidgetID: UUID?

    private let key = "dock.state.v1"

    private struct Persisted: Codable {
        var profiles: [DockProfile]
        var active: UUID
        var settings: DockSettings
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let p = try? JSONDecoder().decode(Persisted.self, from: data), !p.profiles.isEmpty {
            profiles = p.profiles
            activeProfileID = p.profiles.contains { $0.id == p.active } ? p.active : p.profiles[0].id
            settings = p.settings
            if profiles[activeIndex].theme == nil {
                profiles[activeIndex].theme = settings.theme
            }
            if !UserDefaults.standard.bool(forKey: "migrated.weatherAuto") {
                UserDefaults.standard.set(true, forKey: "migrated.weatherAuto")
                for i in profiles.indices {
                    for j in profiles[i].widgets.indices where profiles[i].widgets[j].kind == .weather
                        && profiles[i].widgets[j].config["city"] == "Zürich" {
                        profiles[i].widgets[j].config["city"] = "auto"
                    }
                }
            }
            if !Hardware.hasBattery {
                for i in profiles.indices { profiles[i].widgets.removeAll { !$0.kind.isAvailable } }
            }
            if !UserDefaults.standard.bool(forKey: "migrated.requestedWidgets") {
                UserDefaults.standard.set(true, forKey: "migrated.requestedWidgets")
                for kind in [WidgetKind.audio, .clipboard, .screenshots, .finder, .mail, .photos]
                    where !profiles[0].widgets.contains(where: { $0.kind == kind }) {
                    profiles[0].widgets.append(WidgetInstance(kind))
                }
                if let launcherIndex = profiles[0].widgets.firstIndex(where: { $0.kind == .launcher }) {
                    var launcher = profiles[0].widgets[launcherIndex]
                    var apps = launcher.launcherApps
                    for path in ["/Applications/Safari.app", "/Applications/Firefox.app"]
                        where FileManager.default.fileExists(atPath: path) && !apps.contains(path) {
                        apps.append(path)
                    }
                    launcher.config["apps"] = apps.joined(separator: "\n")
                    profiles[0].widgets[launcherIndex] = launcher
                }
                save()
            }
            if !UserDefaults.standard.bool(forKey: "migrated.shortcutsWidget") {
                UserDefaults.standard.set(true, forKey: "migrated.shortcutsWidget")
                if !profiles[0].widgets.contains(where: { $0.kind == .shortcuts }) {
                    profiles[0].widgets.append(WidgetInstance(.shortcuts))
                }
                save()
            }
        } else {
            let main = DockProfile(name: "Standard", widgets: [
                WidgetInstance(.clock), WidgetInstance(.weather), WidgetInstance(.nexus),
                WidgetInstance(.workspaces), WidgetInstance(.bookmarks), WidgetInstance(.launcher),
                WidgetInstance(Hardware.hasBattery ? .battery : .cpu), WidgetInstance(.calendar), WidgetInstance(.nowPlaying),
                WidgetInstance(.audio), WidgetInstance(.clipboard), WidgetInstance(.screenshots), WidgetInstance(.shortcuts),
                WidgetInstance(.finder), WidgetInstance(.mail), WidgetInstance(.photos),
            ])
            let focus = DockProfile(name: "Fokus", widgets: [
                WidgetInstance(.clock), WidgetInstance(.pomodoro), WidgetInstance(.reminders),
                WidgetInstance(.water), WidgetInstance(.progress),
            ])
            profiles = [main, focus]
            activeProfileID = main.id
            settings = DockSettings()
        }
    }

    private func save() {
        let p = Persisted(profiles: profiles, active: activeProfileID, settings: settings)
        if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: key) }
    }

    var activeIndex: Int { profiles.firstIndex { $0.id == activeProfileID } ?? 0 }
    var allActiveWidgets: [WidgetInstance] { profiles[activeIndex].widgets }

    var activeWidgets: [WidgetInstance] {
        widgets(for: WorkspaceManager.shared.activeID)
    }

    func widgets(for workspaceID: UUID?) -> [WidgetInstance] {
        let widgets = allActiveWidgets
        guard let workspaceID else { return widgets }
        let existingIDs = Set(WorkspaceManager.shared.workspaces.map(\.id))
        return widgets.filter { widget in
            guard let assigned = widget.assignedWorkspaceIDs else { return true }
            return assigned.intersection(existingIDs).contains(workspaceID)
        }
    }

    func instance(_ id: UUID) -> WidgetInstance? { allActiveWidgets.first { $0.id == id } }

    func update(_ id: UUID, _ change: (inout WidgetInstance) -> Void) {
        let pi = activeIndex
        guard let wi = profiles[pi].widgets.firstIndex(where: { $0.id == id }) else { return }
        var w = profiles[pi].widgets[wi]
        change(&w)
        if w != profiles[pi].widgets[wi] { profiles[pi].widgets[wi] = w }
    }

    func setConfig(_ id: UUID, _ key: String, _ value: String) {
        update(id) { $0.config[key] = value }
    }

    func binding(_ id: UUID, _ key: String) -> Binding<String> {
        Binding(get: { self.instance(id)?.config[key] ?? "" },
                set: { self.setConfig(id, key, $0) })
    }

    func add(_ kind: WidgetKind, size: Int? = nil, config: [String: String] = [:]) {
        guard kind.isAvailable else { return }
        let w = WidgetInstance(kind, size: size, config: config)
        profiles[activeIndex].widgets.append(w)
        editingWidgetID = w.id
    }

    func insert(_ widget: WidgetInstance, at index: Int) {
        let profileIndex = activeIndex
        profiles[profileIndex].widgets.insert(widget, at: min(max(index, 0), profiles[profileIndex].widgets.count))
        editingWidgetID = widget.id
    }

    func remove(_ id: UUID) {
        profiles[activeIndex].widgets.removeAll { $0.id == id }
        if editingWidgetID == id { editingWidgetID = nil }
    }

    func move(_ id: UUID, by offset: Int) {
        var list = profiles[activeIndex].widgets
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        profiles[activeIndex].widgets = list
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        profiles[activeIndex].widgets.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func moveWidget(_ id: UUID, before target: UUID) {
        var list = profiles[activeIndex].widgets
        guard id != target, let from = list.firstIndex(where: { $0.id == id }) else { return }
        let item = list.remove(at: from)
        let to = list.firstIndex(where: { $0.id == target }) ?? list.count
        list.insert(item, at: to)
        profiles[activeIndex].widgets = list
    }

    func addProfile(named name: String, copyCurrent: Bool) {
        let widgets: [WidgetInstance] = copyCurrent ? activeWidgets.map { w -> WidgetInstance in var c = w; c.id = UUID(); return c } : []
        let p = DockProfile(name: name, widgets: widgets, theme: settings.theme)
        profiles.append(p)
        switchProfile(p.id)
    }

    func addProfile(_ preset: DockProfilePreset) {
        let baseName = preset.title
        var name = baseName
        var suffix = 2
        while profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(baseName) \(suffix)"
            suffix += 1
        }
        let profile = DockProfile(name: name, widgets: preset.widgets, theme: preset.theme)
        profiles.append(profile)
        switchProfile(profile.id)
    }

    func switchProfile(_ id: UUID) {
        guard let targetIndex = profiles.firstIndex(where: { $0.id == id }), id != activeProfileID else { return }
        if profiles.indices.contains(activeIndex) {
            profiles[activeIndex].theme = settings.theme
        }
        activeProfileID = id
        settings.theme = profiles[targetIndex].theme
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
            settings.theme = profiles[0].theme
        }
    }

    // Layout metrics
    var unit: CGFloat { CGFloat(settings.tileSize) }
    var gap: CGFloat { (unit * 0.125).rounded() }
    var barPadding: CGFloat { (unit * 0.125).rounded() }
    var corner: CGFloat { unit * 0.26 }
    var grip: CGFloat { (unit * 0.19).rounded() }
    var vertical: Bool { settings.position.isVertical || (settings.position == .free && settings.freeVertical == true) }

    func width(for units: Int) -> CGFloat {
        CGFloat(units) * unit + CGFloat(units - 1) * gap
    }

    var dockRowSize: CGSize {
        let ws = activeWidgets
        let units = ws.isEmpty ? [1] : ws.map(\.size)
        let widths = units.map { width(for: $0) }
        if vertical {
            let h = CGFloat(units.count) * unit + CGFloat(units.count) * gap + grip
            return CGSize(width: widths.max() ?? unit, height: h)
        }
        let w = widths.reduce(0, +) + CGFloat(units.count) * gap + grip
        return CGSize(width: w, height: unit)
    }

    var profileStripWidth: CGFloat {
        let scale = unit / 64
        let tabs = profiles.reduce(CGFloat.zero) { total, profile in
            let textWidth = CGFloat(profile.name.count) * 6.2
            let selectionMark: CGFloat = profile.id == activeProfileID ? 12 : 0
            return total + min(120, max(50, textWidth + selectionMark + 18))
        }
        let gaps = CGFloat(profiles.count + 1) * 4
        return (tabs + gaps + 24 + 6) * scale
    }

    var profileStripHeight: CGFloat { 28 * unit / 64 }

    var profileHeaderWidth: CGFloat {
        max(dockRowSize.width, profileStripWidth + gap + 172 * unit / 64)
    }

    var contentSize: CGSize {
        let row = dockRowSize
        let hasProfileStrip = !profiles.isEmpty
        let width = (hasProfileStrip ? profileHeaderWidth : row.width) + barPadding * 2
        let height = row.height + (hasProfileStrip ? profileStripHeight + gap : 0) + barPadding * 2
        return CGSize(width: width, height: height)
    }
}

// MARK: - Scale environment

private struct ScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    /// Tile size relative to the 64 pt base.
    var dockScale: CGFloat {
        get { self[ScaleKey.self] }
        set { self[ScaleKey.self] = newValue }
    }
}
