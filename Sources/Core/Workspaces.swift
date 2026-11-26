import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Model

/// Window rectangle as fractions of the screen's visible area, origin top-left.
struct FracRect: Codable, Equatable, Hashable {
    var x: Double, y: Double, w: Double, h: Double

    static let presets: [(String, FracRect?)] = [
        ("Unverändert", nil),
        ("Vollbild", .init(x: 0, y: 0, w: 1, h: 1)),
        ("Mitte", .init(x: 0.15, y: 0.1, w: 0.7, h: 0.8)),
        ("Links ½", .init(x: 0, y: 0, w: 0.5, h: 1)),
        ("Rechts ½", .init(x: 0.5, y: 0, w: 0.5, h: 1)),
        ("Oben ½", .init(x: 0, y: 0, w: 1, h: 0.5)),
        ("Unten ½", .init(x: 0, y: 0.5, w: 1, h: 0.5)),
        ("Links ⅓", .init(x: 0, y: 0, w: 1.0 / 3, h: 1)),
        ("Mitte ⅓", .init(x: 1.0 / 3, y: 0, w: 1.0 / 3, h: 1)),
        ("Rechts ⅓", .init(x: 2.0 / 3, y: 0, w: 1.0 / 3, h: 1)),
        ("Links ⅔", .init(x: 0, y: 0, w: 2.0 / 3, h: 1)),
        ("Rechts ⅔", .init(x: 1.0 / 3, y: 0, w: 2.0 / 3, h: 1)),
        ("Oben links ¼", .init(x: 0, y: 0, w: 0.5, h: 0.5)),
        ("Oben rechts ¼", .init(x: 0.5, y: 0, w: 0.5, h: 0.5)),
        ("Unten links ¼", .init(x: 0, y: 0.5, w: 0.5, h: 0.5)),
        ("Unten rechts ¼", .init(x: 0.5, y: 0.5, w: 0.5, h: 0.5)),
    ]

    var presetName: String {
        Self.presets.first { $0.1 == self }?.0 ?? "Eigene Position"
    }
}

/// One window exactly as it was on screen (AX coordinates: top-left origin of the main display).
struct SavedWindow: Codable, Equatable, Hashable {
    var title: String
    var x: Double, y: Double, w: Double, h: Double
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct WorkspaceApp: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var path: String
    var frame: FracRect?
    var screen: Int = 0
    var files: [String] = []
    /// Saved desktop: every window of the app with its exact position and size.
    var windows: [SavedWindow] = []

    init(path: String, frame: FracRect? = nil, screen: Int = 0, files: [String] = [], windows: [SavedWindow] = []) {
        self.path = path
        self.frame = frame
        self.screen = screen
        self.files = files
        self.windows = windows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        frame = try c.decodeIfPresent(FracRect.self, forKey: .frame)
        screen = try c.decodeIfPresent(Int.self, forKey: .screen) ?? 0
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        windows = try c.decodeIfPresent([SavedWindow].self, forKey: .windows) ?? []
    }

    var name: String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
    var bundleID: String? { Bundle(path: path)?.bundleIdentifier }
}

enum OthersPolicy: String, Codable, CaseIterable, Identifiable {
    case keep, hide, quit, forceQuit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .keep: "Offen lassen"
        case .hide: "Ausblenden"
        case .quit: "Beenden"
        case .forceQuit: "Sofort beenden (hart)"
        }
    }
}

struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String = "rectangle.3.group"
    var apps: [WorkspaceApp] = []
    var others: OthersPolicy = .hide
    var dockProfileID: UUID?
    /// Unroll the app list when hovering this workspace in the bar.
    var showOnHover: Bool?
}

// MARK: - Manager

final class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var workspaces: [Workspace] { didSet { save() } }
    @Published var activeID: UUID?
    @Published var status: String?

    private let key = "workspaces.v1"
    /// Never quit these when switching.
    private let protected: Set<String> = ["com.apple.finder", "ch.crohniq.dock", "crohniq.dock.ch", "com.apple.systempreferences"]

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let w = try? JSONDecoder().decode([Workspace].self, from: d) {
            workspaces = w
        } else {
            workspaces = [
                Workspace(name: "Büro", symbol: "briefcase.fill", apps: [
                    WorkspaceApp(path: "/System/Applications/Mail.app", frame: FracRect.presets[3].1),
                    WorkspaceApp(path: "/System/Applications/Calendar.app", frame: FracRect.presets[4].1),
                ]),
                Workspace(name: "Entwicklung", symbol: "hammer.fill", apps: [
                    WorkspaceApp(path: "/Applications/Xcode.app", frame: FracRect.presets[10].1),
                    WorkspaceApp(path: "/Applications/Safari.app", frame: FracRect.presets[9].1),
                ]),
            ]
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: Accessibility

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: Apply

    func apply(_ ws: Workspace) {
        activeID = ws.id
        status = "„\(ws.name)“ wird vorbereitet …"
        if let p = ws.dockProfileID, DockStore.shared.profiles.contains(where: { $0.id == p }) {
            DockStore.shared.switchProfile(p)
        }

        let wanted = Set(ws.apps.compactMap(\.bundleID))
        if ws.others != .keep {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                guard let bid = app.bundleIdentifier, !wanted.contains(bid), !protected.contains(bid),
                      !bid.hasPrefix("ch.crohniq.fileiq") || ws.others == .hide else { continue }
                switch ws.others {
                case .quit: app.terminate()
                case .forceQuit: app.forceTerminate()
                default: app.hide()
                }
            }
        }

        let group = DispatchGroup()
        for item in ws.apps {
            group.enter()
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            let docs = item.files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            let handler: (NSRunningApplication?, Error?) -> Void = { app, _ in
                DispatchQueue.main.async {
                    app?.unhide()
                    if let app, !item.windows.isEmpty {
                        self.restore(app: app, windows: item.windows, attempts: 25) { group.leave() }
                    } else if let app, let frame = item.frame {
                        self.place(app: app, frame: frame, screen: item.screen, attempts: 30) { group.leave() }
                    } else {
                        group.leave()
                    }
                }
            }
            if docs.isEmpty {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.path), configuration: cfg, completionHandler: handler)
            } else {
                NSWorkspace.shared.open(docs, withApplicationAt: URL(fileURLWithPath: item.path), configuration: cfg, completionHandler: handler)
            }
        }
        group.notify(queue: .main) {
            // Bring the workspace apps to front in the listed order, the first one last so it ends up on top.
            for item in ws.apps.reversed() {
                if let bid = item.bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
                    app.activate()
                }
            }
            self.status = nil
        }
        if ws.apps.contains(where: { $0.frame != nil || !$0.windows.isEmpty }) && !Self.hasAccessibility {
            status = "Für Fensterpositionen braucht Crohniq Dock die Bedienungshilfen-Freigabe."
            Self.requestAccessibility()
        }
    }

    private func place(app: NSRunningApplication, frame: FracRect, screen: Int, attempts: Int, done: @escaping () -> Void) {
        guard Self.hasAccessibility else { done(); return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        let windows = (value as? [AXUIElement]) ?? []
        guard let win = windows.first else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.place(app: app, frame: frame, screen: screen, attempts: attempts - 1, done: done)
                }
            } else { done() }
            return
        }
        let rect = Self.axRect(for: frame, screen: screen)
        // Size, position, size again: some apps clamp the size until the window has moved.
        Self.set(win, size: rect.size)
        Self.set(win, position: rect.origin)
        Self.set(win, size: rect.size)
        done()
    }

    private static func axWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        return ((value as? [AXUIElement]) ?? []).filter { win in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &role)
            return (role as? String) == kAXStandardWindowSubrole as String
        }
    }

    private static func title(of win: AXUIElement) -> String {
        var t: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &t)
        return t as? String ?? ""
    }

    private static func frame(of win: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
        guard let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private static func isMinimized(_ win: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &v)
        return (v as? Bool) ?? false
    }

    /// Puts every saved window back where it was. Windows are matched by title first, then by order.
    private func restore(app: NSRunningApplication, windows saved: [SavedWindow], attempts: Int, done: @escaping () -> Void) {
        guard Self.hasAccessibility else { done(); return }
        let wins = Self.axWindows(of: app)
        if wins.count < saved.count && attempts > 0 {
            // The app is still opening its windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.restore(app: app, windows: saved, attempts: attempts - 1, done: done)
            }
            return
        }
        var unused = wins
        var pairs: [(AXUIElement, SavedWindow)] = []
        var rest: [SavedWindow] = []
        for sw in saved {
            if !sw.title.isEmpty, let i = unused.firstIndex(where: { Self.title(of: $0) == sw.title }) {
                pairs.append((unused.remove(at: i), sw))
            } else {
                rest.append(sw)
            }
        }
        for sw in rest where !unused.isEmpty { pairs.append((unused.removeFirst(), sw)) }
        for (win, sw) in pairs {
            if Self.isMinimized(win) { AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            Self.set(win, size: sw.rect.size)
            Self.set(win, position: sw.rect.origin)
            Self.set(win, size: sw.rect.size)
        }
        done()
    }

    /// Front-to-back order of apps on screen (works without screen-recording permission).
    private static func zOrderedPIDs() -> [pid_t] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var seen = Set<pid_t>(), result: [pid_t] = []
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = w[kCGWindowOwnerPID as String] as? pid_t, seen.insert(pid).inserted { result.append(pid) }
        }
        return result
    }

    /// Snapshot of the desktop: every visible app with all its windows, front-most app first.
    func snapshotDesktop(keepingFilesFrom old: [WorkspaceApp] = []) -> [WorkspaceApp]? {
        guard Self.hasAccessibility else { Self.requestAccessibility(); return nil }
        let own = Bundle.main.bundleIdentifier
        let order = Self.zOrderedPIDs()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.bundleIdentifier != own && $0.bundleURL != nil }
            .sorted { (order.firstIndex(of: $0.processIdentifier) ?? .max) < (order.firstIndex(of: $1.processIdentifier) ?? .max) }
        return apps.compactMap { app in
            let windows: [SavedWindow] = Self.axWindows(of: app).filter { !Self.isMinimized($0) }.compactMap { win in
                guard let r = Self.frame(of: win), r.width > 50, r.height > 50 else { return nil }
                return SavedWindow(title: Self.title(of: win), x: r.minX, y: r.minY, w: r.width, h: r.height)
            }
            // Finder only counts when it has real windows open.
            if app.bundleIdentifier == "com.apple.finder" && windows.isEmpty { return nil }
            guard !windows.isEmpty else { return nil }
            let path = app.bundleURL!.path
            let files = old.first { $0.path == path }?.files ?? []
            return WorkspaceApp(path: path, files: files, windows: windows)
        }
    }

    /// Replaces the workspace's apps and windows with what is on screen right now.
    @discardableResult
    func saveDesktop(into id: UUID) -> Bool {
        guard let i = workspaces.firstIndex(where: { $0.id == id }),
              let snap = snapshotDesktop(keepingFilesFrom: workspaces[i].apps) else { return false }
        workspaces[i].apps = snap
        activeID = id
        status = "Desktop in „\(workspaces[i].name)“ gespeichert"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.status = nil }
        return true
    }

    func saveDesktopAsNew() -> Workspace? {
        guard let snap = snapshotDesktop() else { return nil }
        let ws = Workspace(name: "Desktop \(workspaces.count + 1)", symbol: "macwindow.on.rectangle", apps: snap)
        workspaces.append(ws)
        activeID = ws.id
        return ws
    }

    private static func screenFor(_ index: Int) -> NSScreen {
        let screens = NSScreen.screens
        return screens.indices.contains(index) ? screens[index] : (NSScreen.main ?? screens[0])
    }

    /// Converts a fractional frame into AX (top-left origin, main-screen based) coordinates.
    static func axRect(for f: FracRect, screen: Int) -> CGRect {
        let vis = screenFor(screen).visibleFrame
        let primaryHeight = NSScreen.screens[0].frame.height
        let w = vis.width * f.w, h = vis.height * f.h
        let x = vis.minX + vis.width * f.x
        let topCocoa = vis.maxY - vis.height * f.y
        return CGRect(x: x, y: primaryHeight - topCocoa, width: w, height: h)
    }

    static func fracRect(fromAX r: CGRect) -> (FracRect, Int) {
        let primaryHeight = NSScreen.screens[0].frame.height
        let cocoa = CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        let idx = NSScreen.screens.firstIndex { $0.frame.intersects(cocoa) && $0.frame.contains(CGPoint(x: cocoa.midX, y: cocoa.midY)) } ?? 0
        let vis = NSScreen.screens[idx].visibleFrame
        func clamp(_ v: Double) -> Double { (max(0, min(1, v)) * 1000).rounded() / 1000 }
        let f = FracRect(x: clamp((cocoa.minX - vis.minX) / vis.width),
                         y: clamp((vis.maxY - cocoa.maxY) / vis.height),
                         w: clamp(cocoa.width / vis.width),
                         h: clamp(cocoa.height / vis.height))
        return (f, idx)
    }

    private static func set(_ win: AXUIElement, position: CGPoint) {
        var p = position
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
    }

    private static func set(_ win: AXUIElement, size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
    }

    static func frontWindowFrame(of app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &value)
        if value == nil {
            var list: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &list)
            value = (list as? [AXUIElement])?.first
        }
        guard let v = value else { return nil }
        let win = v as! AXUIElement
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero, size = CGSize.zero
        guard let posRef, let sizeRef else { return nil }
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    /// Builds a workspace from all visible apps and their current window positions.
    func captureCurrent() -> [WorkspaceApp] {
        guard Self.hasAccessibility else { Self.requestAccessibility(); return [] }
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.bundleIdentifier != own && $0.bundleIdentifier != "com.apple.finder" }
            .compactMap { app in
                guard let url = app.bundleURL else { return nil }
                var item = WorkspaceApp(path: url.path)
                if let r = Self.frontWindowFrame(of: app) {
                    let (f, idx) = Self.fracRect(fromAX: r)
                    item.frame = f
                    item.screen = idx
                }
                return item
            }
    }

    /// Updates the frames of the listed apps from their current windows.
    func capturePositions(for apps: [WorkspaceApp]) -> [WorkspaceApp] {
        guard Self.hasAccessibility else { Self.requestAccessibility(); return apps }
        return apps.map { item in
            var item = item
            if let bid = item.bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
               let r = Self.frontWindowFrame(of: app) {
                let (f, idx) = Self.fracRect(fromAX: r)
                item.frame = f
                item.screen = idx
            }
            return item
        }
    }
}

// MARK: - Widget

struct WorkspacesWidget: View {
    let w: WidgetInstance
    @ObservedObject private var mgr = WorkspaceManager.shared
    @Environment(\.dockScale) private var s

    var body: some View {
        Group {
            if w.size == 1 {
                Menu {
                    ForEach(mgr.workspaces) { ws in Button(ws.name) { mgr.apply(ws) } }
                    Divider()
                    if let a = active { Button("Aktuellen Desktop in „\(a.name)“ speichern") { mgr.saveDesktop(into: a.id) } }
                    Button("Aktuellen Desktop als neuen Bereich speichern") { _ = mgr.saveDesktopAsNew() }
                    Button("Arbeitsbereiche bearbeiten …") { AppDelegate.shared.openSettings(page: .workspaces) }
                } label: {
                    VStack(spacing: 3 * s) {
                        Image(systemName: active?.symbol ?? "rectangle.3.group").font(.system(size: 20 * s))
                        Text(active?.name ?? "Bereiche").font(.system(size: 9 * s)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            } else {
                HStack(spacing: 6 * s) {
                    ForEach(Array(mgr.workspaces.prefix(w.size + 1).enumerated()), id: \.element.id) { i, ws in
                        Button { mgr.apply(ws) } label: {
                            VStack(spacing: 3 * s) {
                                Image(systemName: ws.symbol).font(.system(size: 17 * s, weight: .semibold))
                                Text(ws.name).font(.system(size: 9 * s, weight: .medium)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10 * s)
                                .fill(mgr.activeID == ws.id ? Color.accentColor.opacity(0.35) : Theme.tileHi))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help((ws.showOnHover ?? true) ? "" : "\(ws.name) – \(ws.apps.map(\.name).joined(separator: ", "))\(i < 9 ? "  (⌃⌥\(i + 1))" : "")")
                        .hoverUnroll(id: ws.id, width: 320, enabled: ws.showOnHover ?? true) {
                            AnyView(WorkspaceHoverList(id: ws.id, shortcut: i < 9 ? "⌃⌥\(i + 1)" : nil))
                        }
                        .contextMenu {
                            Button("Aktuellen Desktop in „\(ws.name)“ speichern") { mgr.saveDesktop(into: ws.id) }
                            Button("Aktuellen Desktop als neuen Bereich speichern") { _ = mgr.saveDesktopAsNew() }
                            Divider()
                            Button("Arbeitsbereiche bearbeiten …") { AppDelegate.shared.openSettings(page: .workspaces) }
                        }
                    }
                }
                .padding(7 * s)
            }
        }
        .overlay(alignment: .bottom) {
            if let st = mgr.status {
                Text(st).font(.system(size: 9 * s)).lineLimit(1).padding(.horizontal, 6 * s)
                    .background(Capsule().fill(.black.opacity(0.7))).padding(.bottom, 2 * s)
            }
        }
    }

    private var active: Workspace? { mgr.workspaces.first { $0.id == mgr.activeID } }
}
