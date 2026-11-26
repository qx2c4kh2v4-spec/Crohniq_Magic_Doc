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

// MARK: - Entitlements (trial / base / premium)

/// What the user is entitled to. Higher raw value includes the lower one.
enum LicenseTier: Int, Comparable {
    case none = 0, base = 1, premium = 2
    static func < (a: LicenseTier, b: LicenseTier) -> Bool { a.rawValue < b.rawValue }
}

@MainActor
final class Entitlements: ObservableObject {
    static let shared = Entitlements()

    /// Free, full-feature trial length.
    static let trialDays = 14

    private let tierKey = "license.tier"
    private let codeKey = "license.code"
    private let trialStartKey = "trial.start"
    private let seenKey = "addon.seenFeatures"

    @Published private(set) var tier: LicenseTier

    private init() {
        tier = LicenseTier(rawValue: UserDefaults.standard.integer(forKey: tierKey)) ?? .none
        if UserDefaults.standard.object(forKey: trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: trialStartKey)
        }
    }

    // MARK: Trial

    var trialStart: Date { UserDefaults.standard.object(forKey: trialStartKey) as? Date ?? Date() }
    var trialDaysLeft: Int {
        let used = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return max(0, Self.trialDays - used)
    }
    var inTrial: Bool { trialDaysLeft > 0 }

    // MARK: Entitlement state

    /// Developer builds behave as premium unless the lock is simulated for testing.
    private var devOverride: Bool {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "addon.simulateLock")
        #else
        return false
        #endif
    }

    var premiumUnlocked: Bool { devOverride || tier == .premium }
    var baseUnlocked: Bool { premiumUnlocked || tier == .base }
    /// Kept for existing call sites: true when premium is fully unlocked.
    var unlocked: Bool { premiumUnlocked }
    /// Trial over and no license: the app shows only the start view with a buy link.
    var expired: Bool { !devOverride && !inTrial && tier == .none }

    /// Whether a widget is locked right now. Everything is free during the trial.
    func isLocked(_ kind: WidgetKind) -> Bool {
        if devOverride || inTrial { return false }
        switch tier {
        case .premium: return false
        case .base: return kind.isPremium
        case .none: return true
        }
    }

    // MARK: Activation

    /// Applies a license code; upgrades the tier (never downgrades). Returns the unlocked tier, or nil.
    @discardableResult
    func activate(_ code: String) -> LicenseTier? {
        guard let bought = Activation.tier(of: code), bought != .none else { return nil }
        let newTier = max(tier, bought)
        UserDefaults.standard.set(newTier.rawValue, forKey: tierKey)
        UserDefaults.standard.set(code.trimmingCharacters(in: .whitespaces).uppercased(), forKey: codeKey)
        tier = newTier
        if premiumUnlocked { markAllPremiumSeen(); PromoBubble.shared.stop() }
        return newTier
    }

    #if DEBUG
    var simulatingLock: Bool { UserDefaults.standard.bool(forKey: "addon.simulateLock") }
    func toggleSimulateLock() {
        UserDefaults.standard.set(!simulatingLock, forKey: "addon.simulateLock")
        objectWillChange.send()
        if premiumUnlocked { PromoBubble.shared.stop() } else { PromoBubble.shared.start() }
    }
    /// Testing: move the trial start into the past so the expired state can be checked.
    func debugExpireTrial() {
        UserDefaults.standard.set(Calendar.current.date(byAdding: .day, value: -(Self.trialDays + 1), to: Date()), forKey: trialStartKey)
        objectWillChange.send()
    }
    func reset() {
        [tierKey, codeKey, trialStartKey, "addon.simulateLock"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.set(Date(), forKey: trialStartKey)
        tier = .none
        objectWillChange.send()
    }
    #endif

    // Premium features the user has already been told about (for "Neu" bubbles after updates).
    var seenPremium: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }

    private func markAllPremiumSeen() {
        seenPremium = Set(WidgetKind.allCases.filter(\.isPremium).map(\.rawValue))
    }
}

// MARK: - Activation codes (offline, tier-aware)

/// Short, offline-verifiable license codes. A code is 1 byte tier + 2 bytes serial + 4 bytes HMAC tag,
/// Crockford-base32 encoded and grouped. Generate with `--make-codes base|premium <n>`.
enum Activation {
    /// Shared secret – also used by the code generator built into this app.
    private static let secret = SymmetricKey(data: Data("CrohniqDock.Addon.v1.$7hK29pLmQ".utf8))
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ") // Crockford base32

    /// A master premium code for support/development (not sold).
    static let master = "CROHNIQ_DOCK_PREM"

    static func make(tier: LicenseTier, serial: UInt16) -> String {
        var payload = Data([UInt8(tier.rawValue), UInt8(serial >> 8), UInt8(serial & 0xFF)])
        payload.append(tag(for: payload))
        return group(encode(payload))
    }

    /// The tier a code grants, or nil if it is not a valid code.
    static func tier(of raw: String) -> LicenseTier? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == master { return .premium }
        guard let data = decode(normalized), data.count == 7 else { return nil }
        let head = data.prefix(3)
        guard tag(for: head) == data.suffix(4) else { return nil }
        return LicenseTier(rawValue: Int(data[data.startIndex]))
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

    /// Prints `count` fresh codes of a tier (used by the `--make-codes` developer command).
    static func batch(tier: LicenseTier, count: Int, startingAt first: UInt16 = UInt16.random(in: 1000...9000)) -> [String] {
        (0..<count).map { make(tier: tier, serial: first &+ UInt16($0)) }
    }
}
