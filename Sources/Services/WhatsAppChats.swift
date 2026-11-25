import AppKit

/// One chat from the WhatsApp desktop app's local database.
struct WhatsAppChat: Identifiable {
    let jid: String
    let name: String
    let preview: String
    let date: Date
    let unread: Int
    let isGroup: Bool
    var id: String { jid }

    /// Opens WhatsApp at this chat when the number is known, otherwise just the app.
    func open() {
        if jid.hasSuffix("@s.whatsapp.net"), let phone = jid.split(separator: "@").first,
           let url = URL(string: "whatsapp://send?phone=\(phone)") {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WhatsAppChats.bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Reads the most recent chats from WhatsApp for Mac (read-only, from a snapshot of its SQLite store).
enum WhatsAppChats {
    static let bundleID = "net.whatsapp.WhatsApp"

    static var database: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
    }

    static func load(limit: Int = 12) -> (chats: [WhatsAppChat], error: String?) {
        guard FileManager.default.fileExists(atPath: database.path) else {
            return ([], "Keine WhatsApp-Chats gefunden.")
        }
        guard let snapshot = BrowserHistory.snapshotDatabase(database) else {
            return ([], "WhatsApp-Chats sind gesperrt. Zugriff auf Daten anderer Apps für Crohniq Dock erlauben.")
        }
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }

        // Session types: 0 = person, 1 = group. Status updates, broadcasts and communities are left out.
        let query = """
        SELECT s.ZCONTACTJID AS jid,
               COALESCE(NULLIF(s.ZPARTNERNAME, ''), s.ZCONTACTJID) AS name,
               s.ZSESSIONTYPE AS type,
               s.ZUNREADCOUNT AS unread,
               s.ZLASTMESSAGEDATE + 978307200 AS date,
               COALESCE(NULLIF(m.ZTEXT, ''), NULLIF(s.ZLASTMESSAGETEXT, ''), '') AS text,
               COALESCE(m.ZISFROMME, 0) AS fromMe,
               COALESCE(m.ZMESSAGETYPE, 0) AS kind,
               COALESCE(m.ZPUSHNAME, '') AS sender
        FROM ZWACHATSESSION s
        LEFT JOIN ZWAMESSAGE m ON m.Z_PK = s.ZLASTMESSAGE
        WHERE s.ZREMOVED = 0 AND COALESCE(s.ZHIDDEN, 0) = 0 AND COALESCE(s.ZARCHIVED, 0) = 0
          AND s.ZSESSIONTYPE IN (0, 1) AND s.ZLASTMESSAGEDATE IS NOT NULL
        ORDER BY s.ZLASTMESSAGEDATE DESC
        LIMIT \(min(max(limit, 1), 40));
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", snapshot.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return ([], "WhatsApp-Chats können nicht gelesen werden.") }
            if data.isEmpty { return ([], nil) }
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let chats = rows.compactMap { row -> WhatsAppChat? in
                guard let jid = row["jid"] as? String else { return nil }
                let isGroup = (row["type"] as? NSNumber)?.intValue == 1
                let fromMe = (row["fromMe"] as? NSNumber)?.intValue == 1
                var text = preview(kind: (row["kind"] as? NSNumber)?.intValue ?? 0, text: row["text"] as? String ?? "")
                if fromMe {
                    text = "Du: " + text
                } else if isGroup, let sender = row["sender"] as? String, !sender.isEmpty {
                    text = sender + ": " + text
                }
                return WhatsAppChat(
                    jid: jid,
                    name: row["name"] as? String ?? jid,
                    preview: text,
                    date: Date(timeIntervalSince1970: (row["date"] as? NSNumber)?.doubleValue ?? 0),
                    unread: max(0, (row["unread"] as? NSNumber)?.intValue ?? 0),
                    isGroup: isGroup
                )
            }
            return (chats, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    private static func preview(kind: Int, text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        switch kind {
        case 1: return clean.isEmpty ? "📷 Foto" : "📷 " + clean
        case 2: return clean.isEmpty ? "🎥 Video" : "🎥 " + clean
        case 3: return "🎤 Sprachnachricht"
        case 4: return "👤 Kontakt"
        case 5: return "📍 Standort"
        case 8: return clean.isEmpty ? "📄 Dokument" : "📄 " + clean
        case 15: return "Sticker"
        default: return clean.isEmpty ? "…" : clean
        }
    }
}
