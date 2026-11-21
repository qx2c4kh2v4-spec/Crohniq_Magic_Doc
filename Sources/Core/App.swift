import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct CrohniqDockApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) var shared: AppDelegate!

    let dock = DockPanelController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Developer check: render the gallery offscreen to a PNG and quit (no screen capture involved).
        if let i = CommandLine.arguments.firstIndex(of: "--render-gallery"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let view = WidgetGalleryView(scrolls: false).frame(width: 1000).background(Color(nsColor: .windowBackgroundColor))
                let r = ImageRenderer(content: view)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
            return
        }
        _ = LocationService.shared
        ShortcutsScheduler.shared.start()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Crohniq Dock")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        dock.show()
        updateHotKey()
        DockStore.shared.$settings.map(\.hotkey).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateHotKey() }
        }.store(in: &bag)
    }

    private func updateHotKey() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        guard DockStore.shared.settings.hotkey else { return }
        center.register(id: 1, keyCode: kVK_ANSI_D, modifiers: cmdKey | optionKey) { [weak self] in self?.dock.toggle() }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, key) in digits.enumerated() {
            center.register(id: UInt32(10 + i), keyCode: key, modifiers: controlKey | optionKey) {
                let list = WorkspaceManager.shared.workspaces
                if list.indices.contains(i) { WorkspaceManager.shared.apply(list[i]) }
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = DockStore.shared

        let toggle = NSMenuItem(title: dock.isVisible ? "Dock ausblenden" : "Dock einblenden",
                                action: #selector(toggleDock), keyEquivalent: "d")
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for p in store.profiles {
            let item = NSMenuItem(title: p.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.representedObject = p.id
            item.state = p.id == store.activeProfileID ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let wsHeader = NSMenuItem(title: "Arbeitsbereiche", action: nil, keyEquivalent: "")
        wsHeader.isEnabled = false
        menu.addItem(wsHeader)
        for (i, ws) in WorkspaceManager.shared.workspaces.enumerated() {
            let item = NSMenuItem(title: ws.name, action: #selector(applyWorkspace(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.keyEquivalentModifierMask = [.control, .option]
            item.representedObject = ws.id
            item.image = NSImage(systemSymbolName: ws.symbol, accessibilityDescription: nil)
            item.state = ws.id == WorkspaceManager.shared.activeID ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        let saveItem = NSMenuItem(title: "Aktuellen Desktop speichern in", action: nil, keyEquivalent: "")
        let saveMenu = NSMenu()
        for ws in WorkspaceManager.shared.workspaces {
            let item = NSMenuItem(title: ws.name, action: #selector(saveDesktopInto(_:)), keyEquivalent: "")
            item.representedObject = ws.id
            item.image = NSImage(systemSymbolName: ws.symbol, accessibilityDescription: nil)
            item.target = self
            saveMenu.addItem(item)
        }
        saveMenu.addItem(.separator())
        let newItem = NSMenuItem(title: "Neuer Bereich", action: #selector(saveDesktopNew), keyEquivalent: "")
        newItem.target = self
        saveMenu.addItem(newItem)
        saveItem.submenu = saveMenu
        menu.addItem(saveItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let login = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Crohniq Dock beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleDock() { dock.toggle() }

    @objc private func saveDesktopInto(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let ws = WorkspaceManager.shared.workspaces.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "„\(ws.name)“ mit dem aktuellen Desktop neu festlegen?"
        alert.informativeText = "Die gespeicherten Apps und Fensterpositionen werden ersetzt. Angehängte Dateien bleiben erhalten."
        alert.addButton(withTitle: "Übernehmen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn { WorkspaceManager.shared.saveDesktop(into: id) }
    }

    @objc private func saveDesktopNew() {
        if WorkspaceManager.shared.saveDesktopAsNew() != nil { openSettings(page: .workspaces) }
    }

    @objc private func applyWorkspace(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let ws = WorkspaceManager.shared.workspaces.first(where: { $0.id == id }) {
            WorkspaceManager.shared.apply(ws)
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { DockStore.shared.switchProfile(id) }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc func openSettingsAction() { openSettings() }

    func openSettings(page: SettingsPage? = nil, selecting id: UUID? = nil) {
        if let id { DockStore.shared.editingWidgetID = id; SettingsNav.shared.page = .widgets }
        if let page { SettingsNav.shared.page = page }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Crohniq Dock"
            w.isOpaque = false
            w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.setFrameAutosaveName("SettingsWindow")
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Global hotkeys (Carbon)

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        install()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x43444B31), id: id)
        if RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hk, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs[id] = ref
            actions[id] = action
        }
    }

    func unregister(id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        actions[id] = nil
    }

    func unregisterAll() { refs.keys.forEach(unregister) }

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
