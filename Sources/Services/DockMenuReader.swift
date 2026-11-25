import AppKit

/// One entry of an app's macOS Dock menu (open windows, recent chats, app actions …).
struct DockMenuEntry: Identifiable, Hashable {
    /// Titles from the top-level menu down to this entry; used to find it again when pressed.
    let path: [String]
    let title: String
    let enabled: Bool
    let checked: Bool
    let isSeparator: Bool
    var children: [DockMenuEntry]

    var id: String { path.joined(separator: "\u{1F}") + (isSeparator ? "|sep" : "") }
    /// Disabled entries with a title, like "Recent", are section headings.
    var isHeading: Bool { !isSeparator && !enabled && children.isEmpty }
}

/// Reads and presses the menu macOS shows when an app's Dock icon is right-clicked.
/// The app hands its own items (e.g. ChatGPT's recent chats) only to the Dock, so they are read
/// through Accessibility: the menu opens for a fraction of a second and is closed again at once.
enum DockMenuReader {
    private static let queue = DispatchQueue(label: "ch.crohniq.dock.dockmenu")
    private static var cache: [String: (date: Date, items: [DockMenuEntry])] = [:]
    private static let maxAge: TimeInterval = 90

    /// Items the system adds to every Dock menu; the hover list shows its own buttons for these.
    private static let standardTitles: Set<String> = [
        "Optionen", "Options", "Alle Fenster anzeigen", "Show All Windows", "Ausblenden", "Hide",
        "Andere ausblenden", "Hide Others", "Beenden", "Quit", "Sofort beenden", "Force Quit",
        "Öffnen", "Open", "Einblenden", "Show", "Im Finder zeigen", "Show in Finder",
    ]

    /// App-specific entries of the running app's Dock menu; nil without Accessibility access or Dock item.
    /// Blocks briefly, so call it off the main thread.
    static func items(for app: NSRunningApplication, refresh: Bool = false) -> [DockMenuEntry]? {
        queue.sync {
            let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "\(app.processIdentifier)"
            if !refresh, let hit = cache[key], Date().timeIntervalSince(hit.date) < maxAge { return hit.items }
            guard AXIsProcessTrusted(), let item = dockItem(for: app), let menu = openMenu(item) else { return nil }
            let all = entries(in: menu, parentPath: [])
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            let items = trimmed(all.filter { $0.isSeparator || !standardTitles.contains($0.title) })
            cache[key] = (Date(), items)
            return items
        }
    }

    /// Presses the entry at `path` in the app's Dock menu, like choosing it there.
    static func press(_ path: [String], in app: NSRunningApplication) {
        queue.async {
            defer { cache[app.bundleIdentifier ?? ""] = nil }
            guard AXIsProcessTrusted(), !path.isEmpty, let item = dockItem(for: app), let menu = openMenu(item) else { return }
            var level = menu
            for (index, title) in path.enumerated() {
                guard let element = children(of: level).first(where: { string($0, kAXTitleAttribute) == title }) else {
                    AXUIElementPerformAction(menu, kAXCancelAction as CFString)
                    return
                }
                if index == path.count - 1 {
                    AXUIElementPerformAction(element, kAXPressAction as CFString)
                    return
                }
                guard let submenu = children(of: element).first(where: { string($0, kAXRoleAttribute) == "AXMenu" }) else {
                    AXUIElementPerformAction(menu, kAXCancelAction as CFString)
                    return
                }
                level = submenu
            }
        }
    }

    /// App Exposé for this app: the Dock menu's "Alle Fenster anzeigen".
    static func showAllWindows(of app: NSRunningApplication) {
        queue.async {
            guard AXIsProcessTrusted(), let item = dockItem(for: app), let menu = openMenu(item) else { return }
            let titles: Set<String> = ["Alle Fenster anzeigen", "Show All Windows"]
            if let entry = children(of: menu).first(where: { titles.contains(string($0, kAXTitleAttribute) ?? "") }) {
                AXUIElementPerformAction(entry, kAXPressAction as CFString)
            } else {
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
        }
    }

    // MARK: Accessibility helpers

    private static func dockItem(for app: NSRunningApplication) -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        let appURL = app.bundleURL?.standardizedFileURL
        for list in children(of: root) {
            for item in children(of: list) where string(item, kAXSubroleAttribute) == "AXApplicationDockItem" {
                var value: AnyObject?
                AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value)
                if let url = (value as? URL) ?? (value as? NSURL as URL?), let appURL,
                   url.standardizedFileURL.path == appURL.path { return item }
                if let name = app.localizedName, string(item, kAXTitleAttribute) == name { return item }
            }
        }
        return nil
    }

    private static func openMenu(_ item: AXUIElement) -> AXUIElement? {
        guard AXUIElementPerformAction(item, "AXShowMenu" as CFString) == .success else { return nil }
        for _ in 0..<25 {
            if let menu = children(of: item).first(where: { string($0, kAXRoleAttribute) == "AXMenu" }) { return menu }
            usleep(15_000)
        }
        return nil
    }

    private static func entries(in menu: AXUIElement, parentPath: [String]) -> [DockMenuEntry] {
        children(of: menu).map { element in
            let title = string(element, kAXTitleAttribute) ?? ""
            var enabled: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
            let mark = string(element, "AXMenuItemMarkChar") ?? ""
            let path = parentPath + [title]
            let sub = children(of: element).first { string($0, kAXRoleAttribute) == "AXMenu" }
            return DockMenuEntry(
                path: path,
                title: title,
                enabled: (enabled as? Bool) ?? false,
                checked: !mark.isEmpty,
                isSeparator: title.isEmpty,
                children: sub.map { trimmed(entries(in: $0, parentPath: path)) } ?? []
            )
        }
    }

    /// Drops leading, trailing and doubled separators.
    private static func trimmed(_ list: [DockMenuEntry]) -> [DockMenuEntry] {
        var out: [DockMenuEntry] = []
        for entry in list {
            if entry.isSeparator && (out.isEmpty || out.last?.isSeparator == true) { continue }
            out.append(entry)
        }
        while out.last?.isSeparator == true { out.removeLast() }
        return out
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return (value as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }
}

/// Temporary diagnostics: appends a line to ~/Library/Logs/CrohniqDock-diag.log.
func diagLog(_ format: String, _ args: CVarArg...) {
    let line = String(format: format, arguments: args) + "\n"
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/CrohniqDock-diag.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
