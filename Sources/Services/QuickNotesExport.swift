import Foundation

/// Legt die Schnellnotizen (Notizen-Widgets aller Profile) als `quicknotes.json` in den gemeinsamen
/// App-Group-Ordner – Crohniq Nexus IQ liest sie von dort und nimmt sie in den Index auf.
enum QuickNotesExport {
    static let appGroup = "FW84ZL64CN.ch.crohniq.shared"
    static let fileName = "quicknotes.json"

    struct Note: Codable, Equatable {
        var id: String
        var profile: String
        var text: String
        var modified: Date
    }

    private static let queue = DispatchQueue(label: "ch.crohniq.dock.quicknotes", qos: .utility)
    private static var pending: DispatchWorkItem?

    /// Gemeinsamer Ordner; ohne Berechtigung der bekannte Ort unter ~/Library/Group Containers.
    static var directory: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) { return url }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroup)", isDirectory: true)
    }

    /// Nach etwa einer Sekunde ohne weitere Änderung schreiben (Tippen in der Notiz speichert bei jedem Zeichen).
    static func schedule(_ profiles: [DockProfile]) {
        let snapshot = notes(in: profiles)
        let item = DispatchWorkItem { write(snapshot) }
        queue.async {
            pending?.cancel()
            pending = item
            queue.asyncAfter(deadline: .now() + 1, execute: item)
        }
    }

    /// Sofort schreiben (beim Start).
    static func writeNow(_ profiles: [DockProfile]) {
        let snapshot = notes(in: profiles)
        queue.async { write(snapshot) }
    }

    private static func notes(in profiles: [DockProfile]) -> [(id: String, profile: String, text: String)] {
        profiles.flatMap { profile in
            profile.widgets.compactMap { widget in
                guard widget.kind == .notes else { return nil }
                let text = (widget.config["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return (widget.id.uuidString, profile.name, text)
            }
        }
    }

    private static func write(_ current: [(id: String, profile: String, text: String)]) {
        let folder = directory
        let url = folder.appendingPathComponent(fileName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let previous = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([Note].self, from: $0) } ?? []
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        // Änderungsdatum bleibt, solange der Text gleich ist.
        let notes = current.map { item -> Note in
            if let old = byID[item.id], old.text == item.text {
                return Note(id: item.id, profile: item.profile, text: item.text, modified: old.modified)
            }
            return Note(id: item.id, profile: item.profile, text: item.text, modified: now)
        }
        guard notes != previous || !FileManager.default.fileExists(atPath: url.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(notes).write(to: url, options: .atomic)
        } catch {
            NSLog("Crohniq Dock: Schnellnotizen nicht geschrieben: \(error.localizedDescription)")
        }
    }
}
