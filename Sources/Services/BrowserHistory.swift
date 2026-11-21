import Foundation

struct BrowserVisit: Identifiable {
    let url: URL
    let title: String
    let visitedAt: Date
    var id: String { "\(url.absoluteString)|\(visitedAt.timeIntervalSince1970)" }
}

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
            SELECT hi.url AS url, COALESCE(hi.title, hi.url) AS title,
                   MAX(hv.visit_time) + 978307200 AS visitedAt
            FROM history_items hi
            LEFT JOIN history_visits hv ON hv.history_item = hi.id
            GROUP BY hi.id
            ORDER BY MAX(hv.visit_time) DESC
            LIMIT \(rowLimit);
            """
        case "org.mozilla.firefox":
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
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
