import AppKit

/// Messenger apps whose recent chats the launcher list can show.
enum Messenger: Equatable {
    case whatsapp, signal

    static func of(bundleID: String?) -> Messenger? {
        switch bundleID {
        case WhatsAppChats.bundleID: .whatsapp
        case SignalChats.bundleID: .signal
        default: nil
        }
    }

    var bundleID: String { self == .whatsapp ? WhatsAppChats.bundleID : SignalChats.bundleID }
    var label: String { self == .whatsapp ? "WhatsApp" : "Signal" }

    func loadChats(limit: Int) -> (chats: [WhatsAppChat], error: String?) {
        self == .whatsapp ? WhatsAppChats.load(limit: limit) : SignalChats.load(limit: limit)
    }
}

/// One chat from a messenger's local database (WhatsApp or Signal).
struct WhatsAppChat: Identifiable, Equatable {
    let session: Int
    let jid: String
    let name: String
    let preview: String
    let date: Date
    let unread: Int
    let isGroup: Bool
    var messenger: Messenger = .whatsapp
    /// Signal: phone number of a one-to-one chat.
    var e164: String? = nil
    var id: String { jid }

    /// WhatsApp phone number of a one-to-one chat (used to prepare a reply), nil otherwise.
    var phone: String? {
        guard messenger == .whatsapp, jid.hasSuffix("@s.whatsapp.net") else { return nil }
        return jid.split(separator: "@").first.map(String.init)
    }

    /// Opens WhatsApp at this chat when the number is known (optionally with a prepared text), otherwise just the app.
    func open(text: String = "") {
        if messenger == .signal {
            if let e164, let url = URL(string: "sgnl://signal.me/#p/\(e164)") {
                NSWorkspace.shared.open(url)
            } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SignalChats.bundleID) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        var components = URLComponents(string: "whatsapp://send")!
        if let phone {
            components.queryItems = [URLQueryItem(name: "phone", value: phone)]
                + (text.isEmpty ? [] : [URLQueryItem(name: "text", value: text)])
        }
        if phone != nil, let url = components.url {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WhatsAppChats.bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// One message of a conversation.
struct WhatsAppMessage: Identifiable {
    let id: Int
    let fromMe: Bool
    let sender: String
    let text: String
    let date: Date
    /// Local photo file, when WhatsApp downloaded it.
    let image: URL?
    let isSystem: Bool
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
            return ([], "macOS schützt die WhatsApp-Daten. Unter Systemeinstellungen › Datenschutz & Sicherheit › Festplattenvollzugriff „Crohniq Dock“ einschalten und das Dock danach neu starten.")
        }
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }

        // Session types: 0 = person, 1 = group. Status updates, broadcasts and communities are left out.
        let query = """
        SELECT s.Z_PK AS session,
               s.ZCONTACTJID AS jid,
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
                    session: (row["session"] as? NSNumber)?.intValue ?? 0,
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

    static var mediaFolder: URL { database.deletingLastPathComponent().appendingPathComponent("Message") }

    /// The latest messages of one chat, oldest first.
    static func messages(of chat: WhatsAppChat, limit: Int = 60) -> (messages: [WhatsAppMessage], error: String?) {
        if chat.messenger == .signal { return SignalChats.messages(of: chat, limit: limit) }
        guard let snapshot = BrowserHistory.snapshotDatabase(database) else {
            return ([], "macOS schützt die WhatsApp-Daten. Festplattenvollzugriff für Crohniq Dock einschalten.")
        }
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
        let query = """
        SELECT m.Z_PK AS id,
               COALESCE(m.ZISFROMME, 0) AS fromMe,
               COALESCE(m.ZMESSAGETYPE, 0) AS kind,
               COALESCE(m.ZTEXT, '') AS text,
               m.ZMESSAGEDATE + 978307200 AS date,
               COALESCE(NULLIF(gm.ZCONTACTNAME, ''), NULLIF(gm.ZFIRSTNAME, ''), NULLIF(pn.ZPUSHNAME, ''), NULLIF(m.ZPUSHNAME, ''), '') AS sender,
               COALESCE(mi.ZMEDIALOCALPATH, '') AS media,
               COALESCE(mi.ZTITLE, '') AS title
        FROM ZWAMESSAGE m
        LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
        LEFT JOIN ZWAPROFILEPUSHNAME pn ON pn.ZJID = gm.ZMEMBERJID
        LEFT JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
        WHERE m.ZCHATSESSION = \(chat.session) AND m.ZMESSAGEDATE IS NOT NULL
        ORDER BY m.ZMESSAGEDATE DESC
        LIMIT \(min(max(limit, 1), 200));
        """
        guard let rows = run(query, on: snapshot) else { return ([], "Die Unterhaltung kann nicht gelesen werden.") }
        let messages = rows.compactMap { row -> WhatsAppMessage? in
            let kind = (row["kind"] as? NSNumber)?.intValue ?? 0
            let text = (row["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let media = row["media"] as? String ?? ""
            let isSystem = kind == 6 || kind == 10
            if isSystem && text.isEmpty { return nil }
            return WhatsAppMessage(
                id: (row["id"] as? NSNumber)?.intValue ?? 0,
                fromMe: (row["fromMe"] as? NSNumber)?.intValue == 1,
                sender: chat.isGroup ? row["sender"] as? String ?? "" : "",
                text: kind == 0 || kind == 7 || isSystem ? text : preview(kind: kind, text: (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? text),
                date: Date(timeIntervalSince1970: (row["date"] as? NSNumber)?.doubleValue ?? 0),
                image: kind == 1 && !media.isEmpty ? mediaFolder.appendingPathComponent(media) : nil,
                isSystem: isSystem
            )
        }
        return (messages.reversed(), nil)
    }

    private static func run(_ query: String, on database: URL) -> [[String: Any]]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        if data.isEmpty { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
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
