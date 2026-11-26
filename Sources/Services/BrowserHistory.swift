import Foundation

struct BrowserVisit: Identifiable {
    let url: URL
    let title: String
    let visitedAt: Date
    var id: String { "\(url.absoluteString)|\(visitedAt.timeIntervalSince1970)" }
}

#if FULL_EDITION
enum BrowserHistory {
    static func load(bundleID: String, limit: Int = 10) -> (visits: [BrowserVisit], error: String?) {
        let database: URL
        let query: String
        let rowLimit = min(max(limit, 1), 50)

        switch bundleID {
        case "com.apple.Safari":
            database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Safari/History.db")
            query = """
            SELECT hi.url AS url,
                   COALESCE(NULLIF(latest.title, ''), hi.url) AS title,
                   latest.visit_time + 978307200 AS visitedAt
            FROM history_items hi
            JOIN history_visits latest ON latest.id = (
                SELECT hv.id FROM history_visits hv
                WHERE hv.history_item = hi.id
                ORDER BY hv.visit_time DESC
                LIMIT 1
            )
            WHERE hi.url NOT LIKE 'blob:%'
            ORDER BY latest.visit_time DESC
            LIMIT \(rowLimit);
            """
        case let id where id.hasPrefix("org.mozilla.firefox"):
            guard let profile = firefoxProfile() else {
                return ([], "Kein Firefox-Profil gefunden.")
            }
            database = profile
            query = """
            SELECT url, COALESCE(title, url) AS title,
                   last_visit_date / 1000000.0 AS visitedAt
            FROM moz_places
            WHERE last_visit_date > 0
            ORDER BY last_visit_date DESC
            LIMIT \(rowLimit);
            """
        default:
            return ([], nil)
        }

        guard FileManager.default.fileExists(atPath: database.path) else {
            return ([], "Kein Browserverlauf gefunden.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") else {
            return ([], "Das macOS-Werkzeug sqlite3 ist nicht verfügbar.")
        }
        guard let snapshot = snapshotDatabase(database) else {
            let name = bundleID == "com.apple.Safari" ? "Safari" : "Firefox"
            return ([], "\(name)-Verlauf ist gesperrt. Festplattenvollzugriff für Crohniq Dock erlauben.")
        }
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", snapshot.path, query]
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ([], detail?.isEmpty == false ? detail : "Browserverlauf kann nicht gelesen werden.")
            }
            if data.isEmpty { return ([], nil) }

            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let visits = rows.compactMap { row -> BrowserVisit? in
                guard let rawURL = row["url"] as? String, let url = URL(string: rawURL) else { return nil }
                let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? rawURL
                let timestamp = (row["visitedAt"] as? NSNumber)?.doubleValue ?? 0
                return BrowserVisit(url: url, title: title, visitedAt: Date(timeIntervalSince1970: timestamp))
            }
            return (visits, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    /// Copies the database plus its write-ahead log so a running browser does not block the read.
    static func snapshotDatabase(_ database: URL) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("crohniq-history-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(database.lastPathComponent)
            try FileManager.default.copyItem(at: database, to: destination)
            for suffix in ["-wal", "-shm"] {
                let source = URL(fileURLWithPath: database.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try? FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
            }
            return destination
        } catch {
            return nil
        }
    }

    private static func firefoxProfile() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return profiles
            .map { $0.appendingPathComponent("places.sqlite") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first
    }
}
#else
enum BrowserHistory {
    static func load(bundleID: String, limit: Int = 10) -> (visits: [BrowserVisit], error: String?) { ([], nil) }
}
#endif
