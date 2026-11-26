import AppKit
import Combine
import CryptoKit
import SwiftUI

// MARK: - Which widgets belong to the paid add-on

extension WidgetKind {
    /// Functions unlocked by the add-on ("zweite Stufe"). Everything else is free forever.
    var isPremium: Bool {
        switch self {
        case .appleIntelligence, .claudeAsk, .chatGPTAsk, .nexus, .developerUsage,
             .calendar, .reminders, .mail,
             .water, .focus, .progress,
             .panoramas, .photos,
             .screenshots, .clipboard:
            return true
        default:
            return false
        }
    }

    /// One short line used in the promo bubbles.
    var promoPitch: String {
        switch self {
        case .appleIntelligence: "Frag Apple Intelligence direkt an der Leiste."
        case .claudeAsk: "Schick deine Frage mit einem Tastendruck an Claude."
        case .chatGPTAsk: "Schick deine Frage mit einem Tastendruck an ChatGPT."
        case .nexus: "Durchsuche alles – mit KI-Antworten direkt an der Leiste."
        case .calendar: "Dein nächster Termin, immer im Blick."
        case .reminders: "Aufgaben sehen und direkt abhaken."
        case .mail: "Deine neuesten Mails auf einen Blick."
        case .water: "Trink-Erinnerung mit Tagesziel."
        case .focus: "Fokuszeit, die sich gut anfühlt."
        case .progress: "Verfolge deinen Fortschritt für den Tag."
        case .panoramas: "Wechselnde Panorama-Hintergründe für deinen Mac."
        case .photos: "Deine schönsten Fotos direkt an der Leiste."
        case .developerUsage: "Behalte deine KI- und Entwickler-Kontingente im Blick."
        case .screenshots: "Bildschirmfotos samt Verlauf, direkt griffbereit."
        case .clipboard: "Copy & Paste mit Verlauf für Text und Bilder."
        default: title
        }
    }
}

// MARK: - Entitlements (free vs unlocked)

@MainActor
final class Entitlements: ObservableObject {
    static let shared = Entitlements()

    private let unlockedKey = "addon.unlocked"
    private let codeKey = "addon.code"
    private let seenKey = "addon.seenFeatures"

    @Published private(set) var unlocked: Bool

    private init() {
        unlocked = Self.computeUnlocked()
    }

    /// Developer builds are unlocked by default – the developer is never locked out. Locks can be
    /// switched on for testing. Release builds depend only on a real activation code.
    private static func computeUnlocked() -> Bool {
        if UserDefaults.standard.bool(forKey: "addon.unlocked") { return true }
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "addon.simulateLock")
        #else
        return false
        #endif
    }

    #if DEBUG
    var simulatingLock: Bool { UserDefaults.standard.bool(forKey: "addon.simulateLock") }
    /// Lets the developer preview the locked (customer) experience without entering a code.
    func toggleSimulateLock() {
        UserDefaults.standard.set(!simulatingLock, forKey: "addon.simulateLock")
        unlocked = Self.computeUnlocked()
        if unlocked { PromoBubble.shared.stop() } else { PromoBubble.shared.start() }
    }
    #endif

    /// The add-on widgets are visible but locked until this is true.
    func isLocked(_ kind: WidgetKind) -> Bool { kind.isPremium && !unlocked }

    /// Tries an activation code; returns true and unlocks on success.
    @discardableResult
    func activate(_ code: String) -> Bool {
        guard Activation.isValid(code) else { return false }
        UserDefaults.standard.set(true, forKey: unlockedKey)
        UserDefaults.standard.set(code.trimmingCharacters(in: .whitespaces).uppercased(), forKey: codeKey)
        markAllPremiumSeen()
        unlocked = true
        PromoBubble.shared.stop()
        return true
    }

    /// Only for development/testing: clears the unlock.
    func reset() {
        UserDefaults.standard.removeObject(forKey: unlockedKey)
        UserDefaults.standard.removeObject(forKey: codeKey)
        unlocked = Self.computeUnlocked()
    }

    // Premium features the user has already been told about (for "Neu" bubbles after updates).
    var seenPremium: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }

    private func markAllPremiumSeen() {
        seenPremium = Set(WidgetKind.allCases.filter(\.isPremium).map(\.rawValue))
    }
}

// MARK: - Activation codes (offline)

/// Short, offline-verifiable activation codes. A code is 2 bytes serial + 4 bytes HMAC tag,
/// Crockford-base32 encoded and grouped as XXXXX-XXXXX. Generate with `--make-codes <n>`.
enum Activation {
    /// Shared secret – also used by the code generator built into this app.
    private static let secret = SymmetricKey(data: Data("CrohniqDock.Addon.v1.$7hK29pLmQ".utf8))
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ") // Crockford base32

    static func make(serial: UInt16) -> String {
        var payload = Data([UInt8(serial >> 8), UInt8(serial & 0xFF)])
        payload.append(tag(for: payload))
        return group(encode(payload))
    }

    /// The fixed code that unlocks the premium features.
    static let universal = "CROHNIQ_DOCK_PREM"

    static func isValid(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == universal { return true }
        guard let data = decode(normalized), data.count == 6 else { return false }
        let serial = data.prefix(2)
        return tag(for: serial) == data.suffix(4)
    }

    private static func tag(for serial: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: serial, using: secret)
        return Data(mac).prefix(4)
    }

    private static func encode(_ data: Data) -> String {
        var bits = 0, value = 0, out = ""
        for byte in data {
            value = (value << 8) | Int(byte); bits += 8
            while bits >= 5 { out.append(alphabet[(value >> (bits - 5)) & 0x1F]); bits -= 5 }
        }
        if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 0x1F]) }
        return out
    }

    private static func decode(_ raw: String) -> Data? {
        let clean = raw.uppercased().filter { alphabet.contains($0) }
        guard !clean.isEmpty else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        var bits = 0, value = 0, out = [UInt8]()
        for ch in clean {
            guard let idx = lookup[ch] else { return nil }
            value = (value << 5) | idx; bits += 5
            if bits >= 8 { out.append(UInt8((value >> (bits - 8)) & 0xFF)); bits -= 8 }
        }
        return Data(out)
    }

    private static func group(_ code: String) -> String {
        let chars = Array(code)
        return stride(from: 0, to: chars.count, by: 5).map { String(chars[$0..<min($0 + 5, chars.count)]) }
            .joined(separator: "-")
    }

    /// Prints `count` fresh codes (used by the `--make-codes` developer command).
    static func batch(count: Int, startingAt first: UInt16 = UInt16.random(in: 1000...9000)) -> [String] {
        (0..<count).map { make(serial: first &+ UInt16($0)) }
    }
}
