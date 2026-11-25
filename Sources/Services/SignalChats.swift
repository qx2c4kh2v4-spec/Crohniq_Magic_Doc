import AppKit
import CommonCrypto
import Security

/// Reads recent chats from Signal Desktop. Its database is encrypted with SQLCipher; the key is
/// protected by the macOS keychain ("Signal Safe Storage"), so macOS asks once before it is used.
/// The database is decrypted into a private temporary copy, queried read-only and deleted right away.
enum SignalChats {
    static let bundleID = "org.whispersystems.signal-desktop"

    private static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Signal")
    }

    /// The SQLCipher key, kept in memory only for this session.
    private static var cachedKey: Data?
    private static let lock = NSLock()

    static func load(limit: Int = 12) -> (chats: [WhatsAppChat], error: String?) {
        let decrypted: URL
        switch decryptedDatabase() {
        case .success(let url): decrypted = url
        case .failure(let message): return ([], message.text)
        }
        defer { try? FileManager.default.removeItem(at: decrypted.deletingLastPathComponent()) }

        let query = """
        SELECT c.id AS id,
               COALESCE(NULLIF(c.name, ''), NULLIF(json_extract(c.json, '$.profileFullName'), ''),
                        NULLIF(c.profileName, ''), NULLIF(c.e164, ''), 'Unbekannt') AS name,
               c.type AS type,
               COALESCE(c.e164, '') AS e164,
               COALESCE(json_extract(c.json, '$.lastMessage'), '') AS preview,
               COALESCE(json_extract(c.json, '$.lastMessageAuthor'), '') AS author,
               COALESCE(json_extract(c.json, '$.unreadCount'), 0) AS unread,
               c.active_at / 1000.0 AS date
        FROM conversations c
        WHERE c.active_at IS NOT NULL AND c.active_at > 0
          AND COALESCE(json_extract(c.json, '$.isArchived'), 0) = 0
          AND c.type IN ('private', 'group')
        ORDER BY c.active_at DESC
        LIMIT \(min(max(limit, 1), 40));
        """
        guard let rows = run(query, on: decrypted) else { return ([], "Signal-Chats können nicht gelesen werden.") }
        let chats = rows.compactMap { row -> WhatsAppChat? in
            guard let id = row["id"] as? String else { return nil }
            let isGroup = row["type"] as? String == "group"
            var preview = (row["preview"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
            if preview.isEmpty { preview = "…" }
            if isGroup, let author = row["author"] as? String, !author.isEmpty { preview = author + ": " + preview }
            return WhatsAppChat(
                session: 0, jid: id,
                name: row["name"] as? String ?? "Unbekannt",
                preview: preview,
                date: Date(timeIntervalSince1970: (row["date"] as? NSNumber)?.doubleValue ?? 0),
                unread: max(0, (row["unread"] as? NSNumber)?.intValue ?? 0),
                isGroup: isGroup,
                messenger: .signal,
                e164: (row["e164"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        return (chats, nil)
    }

    static func messages(of chat: WhatsAppChat, limit: Int = 60) -> (messages: [WhatsAppMessage], error: String?) {
        let decrypted: URL
        switch decryptedDatabase() {
        case .success(let url): decrypted = url
        case .failure(let message): return ([], message.text)
        }
        defer { try? FileManager.default.removeItem(at: decrypted.deletingLastPathComponent()) }

        let id = chat.jid.replacingOccurrences(of: "'", with: "''")
        let query = """
        SELECT m.rowid AS id,
               m.type AS type,
               COALESCE(m.body, json_extract(m.json, '$.body'), '') AS body,
               COALESCE(m.sent_at, m.received_at) / 1000.0 AS date,
               COALESCE(json_extract(m.json, '$.attachments[0].contentType'), '') AS attachment,
               COALESCE(NULLIF(a.name, ''), NULLIF(json_extract(a.json, '$.profileFullName'), ''),
                        NULLIF(a.profileName, ''), '') AS sender
        FROM messages m
        LEFT JOIN conversations a ON a.serviceId = json_extract(m.json, '$.sourceServiceId')
        WHERE m.conversationId = '\(id)'
          AND m.type IN ('incoming', 'outgoing')
          AND COALESCE(json_extract(m.json, '$.isStory'), 0) = 0
        ORDER BY COALESCE(m.sent_at, m.received_at) DESC
        LIMIT \(min(max(limit, 1), 200));
        """
        guard let rows = run(query, on: decrypted) else { return ([], "Die Unterhaltung kann nicht gelesen werden.") }
        let messages = rows.map { row -> WhatsAppMessage in
            let fromMe = row["type"] as? String == "outgoing"
            var text = (row["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let attachment = row["attachment"] as? String ?? ""
            if !attachment.isEmpty {
                let label = attachment.hasPrefix("image/") ? "📷 Foto"
                    : attachment.hasPrefix("video/") ? "🎥 Video"
                    : attachment.hasPrefix("audio/") ? "🎤 Sprachnachricht" : "📄 Dokument"
                text = text.isEmpty ? label : label + " " + text
            }
            return WhatsAppMessage(
                id: (row["id"] as? NSNumber)?.intValue ?? 0,
                fromMe: fromMe,
                sender: chat.isGroup && !fromMe ? row["sender"] as? String ?? "" : "",
                text: text.isEmpty ? "…" : text,
                date: Date(timeIntervalSince1970: (row["date"] as? NSNumber)?.doubleValue ?? 0),
                image: nil,
                isSystem: false
            )
        }
        return (messages.reversed(), nil)
    }

    // MARK: - Key

    /// The key was already released by the keychain in this session.
    static var hasKey: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedKey != nil
    }

    /// Asks the keychain for the key (macOS shows its dialog); returns an error text or nil on success.
    static func requestAccess() -> String? {
        switch databaseKey() {
        case .success: nil
        case .failure(let failure): failure.text
        }
    }

    private struct Failure: Error { let text: String }

    private static func databaseKey() -> Result<Data, Failure> {
        lock.lock(); defer { lock.unlock() }
        if let cachedKey { return .success(cachedKey) }
        guard let config = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
              let json = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
              let hex = json["encryptedKey"] as? String, let encrypted = Data(hex: hex),
              encrypted.starts(with: Data("v10".utf8)) else {
            return .failure(Failure(text: "Signal Desktop ist nicht eingerichtet."))
        }
        // The keychain password; macOS asks once whether Crohniq Dock may use it.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Signal Safe Storage",
            kSecAttrAccount as String: "Signal Key",
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let password = item as? Data else {
            return .failure(Failure(text: "Kein Zugriff auf den Signal-Schlüssel. Beim nächsten Versuch im Schlüsselbund-Dialog „Erlauben“ wählen."))
        }
        // Electron safeStorage: AES-128-CBC, key from PBKDF2-SHA1(password, "saltysalt", 1003), IV of 16 spaces.
        guard let aesKey = pbkdf2(password: password, salt: Data("saltysalt".utf8), rounds: 1003, length: 16),
              let plain = aes(decrypt: encrypted.dropFirst(3), key: aesKey, iv: Data(repeating: 0x20, count: 16), padding: true),
              let hexKey = String(data: plain, encoding: .utf8), let key = Data(hex: hexKey), key.count == 32 else {
            return .failure(Failure(text: "Der Signal-Schlüssel kann nicht entschlüsselt werden."))
        }
        cachedKey = key
        return .success(key)
    }

    // MARK: - SQLCipher 4 page decryption

    private static let pageSize = 4096
    /// Per page: 16-byte IV + 64-byte HMAC-SHA512 at the end.
    private static let reserve = 80

    private static func decryptedDatabase() -> Result<URL, Failure> {
        let database = folder.appendingPathComponent("sql/db.sqlite")
        guard let encrypted = try? Data(contentsOf: database, options: .mappedIfSafe) else {
            return .failure(Failure(text: "Keine Signal-Chats gefunden."))
        }
        let key: Data
        switch databaseKey() {
        case .success(let k): key = k
        case .failure(let f): return .failure(f)
        }
        guard encrypted.count >= pageSize, encrypted.count % pageSize == 0 else {
            return .failure(Failure(text: "Die Signal-Datenbank hat ein unbekanntes Format."))
        }
        var plain = Data(capacity: encrypted.count)
        let pages = encrypted.count / pageSize
        for index in 0..<pages {
            guard let page = decryptPage(encrypted.subdata(in: index * pageSize ..< (index + 1) * pageSize), number: index + 1, key: key) else {
                cachedKey = nil
                return .failure(Failure(text: "Die Signal-Datenbank kann nicht entschlüsselt werden."))
            }
            plain.append(page)
        }
        // Pages written since the last checkpoint live in the (also encrypted) write-ahead log.
        applyWAL(URL(fileURLWithPath: database.path + "-wal"), to: &plain, key: key)

        // Sanity check of the decrypted header: page size 4096 and the SQLCipher reserve.
        guard plain.count > 100, plain[16] == 0x10, plain[17] == 0x00, Int(plain[20]) == reserve else {
            lock.lock(); cachedKey = nil; lock.unlock()
            return .failure(Failure(text: "Der Signal-Schlüssel passt nicht zur Datenbank."))
        }
        // WAL mode off in the copy, so sqlite3 reads it as a plain file.
        plain[18] = 1; plain[19] = 1

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crohniq-signal-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = dir.appendingPathComponent("db.sqlite")
            guard FileManager.default.createFile(atPath: url.path, contents: plain, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return .success(url)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return .failure(Failure(text: "Signal-Chats können nicht gelesen werden."))
        }
    }

    private static func decryptPage(_ page: Data, number: Int, key: Data) -> Data? {
        let offset = number == 1 ? 16 : 0
        let end = pageSize - reserve
        let iv = page.subdata(in: end ..< end + 16)
        guard let body = aes(decrypt: page.subdata(in: offset ..< end), key: key, iv: iv, padding: false) else { return nil }
        var out = Data(capacity: pageSize)
        if number == 1 { out.append(Data("SQLite format 3\0".utf8)) }
        out.append(body)
        out.append(Data(repeating: 0, count: reserve))
        return out
    }

    private static func applyWAL(_ url: URL, to plain: inout Data, key: Data) {
        guard let wal = try? Data(contentsOf: url), wal.count > 32 else { return }
        let frameSize = 24 + pageSize
        var frames: [(page: Int, data: Data)] = []
        var committed: [(page: Int, data: Data)] = []
        var offset = 32
        while offset + frameSize <= wal.count {
            let header = wal.subdata(in: offset ..< offset + 24)
            let pageNumber = Int(header.prefix(4).reduce(0) { $0 << 8 | UInt32($1) })
            let commitSize = header.subdata(in: 4..<8).reduce(0) { $0 << 8 | UInt32($1) }
            if let page = decryptPage(wal.subdata(in: offset + 24 ..< offset + frameSize), number: pageNumber, key: key) {
                frames.append((pageNumber, page))
            }
            if commitSize > 0 {
                committed.append(contentsOf: frames)
                frames.removeAll()
            }
            offset += frameSize
        }
        for frame in committed where frame.page > 0 {
            let start = (frame.page - 1) * pageSize
            if start + pageSize <= plain.count {
                plain.replaceSubrange(start ..< start + pageSize, with: frame.data)
            } else if start == plain.count {
                plain.append(frame.data)
            }
        }
    }

    // MARK: - Crypto helpers

    private static func pbkdf2(password: Data, salt: Data, rounds: UInt32, length: Int) -> Data? {
        var out = Data(count: length)
        let status = out.withUnsafeMutableBytes { outPtr in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                                         s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), rounds,
                                         outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
                }
            }
        }
        return status == kCCSuccess ? out : nil
    }

    private static func aes(decrypt data: Data, key: Data, iv: Data, padding: Bool) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(padding ? kCCOptionPKCS7Padding : 0),
                                k.baseAddress, key.count, v.baseAddress,
                                d.baseAddress, data.count, o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
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
}

private extension Data {
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(bytes: chars[i..<i + 2], encoding: .ascii) ?? "", radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        self.init(bytes)
    }
}
