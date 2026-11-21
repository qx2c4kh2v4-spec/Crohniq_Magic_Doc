import AppKit
import Combine
import SwiftUI

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockPanelController: NSObject, NSWindowDelegate {
    private var panel: DockPanel!
    private var bag = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var lastInside = Date()
    private(set) var isVisible = false
    private var revealed = true
    private var isRepositioning = false
    private var dragging = false

    private var store: DockStore { .shared }

    override init() {
        super.init()
        panel = DockPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        let host = FirstMouseHostingView(rootView: DockView())
        host.sizingOptions = []
        panel.contentView = host

        store.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.layout(animated: true) }
            .store(in: &bag)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() { layout(animated: false) }

    func show() {
        isVisible = true
        revealed = true
        layout(animated: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startHoverTimer()
    }

    func hide() {
        isVisible = false
        panel.orderOut(nil)
        hoverTimer?.invalidate()
    }

    func toggle() { isVisible ? hide() : show() }

    var windowFrame: NSRect? { panel.isVisible ? panel.frame : nil }

    private var screen: NSScreen {
        if let i = store.settings.screenIndex, NSScreen.screens.indices.contains(i) { return NSScreen.screens[i] }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func targetFrame() -> NSRect {
        let s = store.settings
        let vis = screen.visibleFrame
        let margin = CGFloat(s.margin)
        var size = store.contentSize
        size.width = min(size.width, max(1, vis.width - margin * 2))
        size.height = min(size.height, max(1, vis.height - margin * 2))
        let cx = s.along.map { vis.minX + vis.width * $0 } ?? vis.midX
        let cy = s.along.map { vis.minY + vis.height * $0 } ?? vis.midY
        var origin: NSPoint
        switch s.position {
        case .bottom:
            origin = NSPoint(x: cx - size.width / 2, y: vis.minY + margin)
        case .top:
            origin = NSPoint(x: cx - size.width / 2, y: vis.maxY - size.height - margin)
        case .left:
            origin = NSPoint(x: vis.minX + margin, y: cy - size.height / 2)
        case .right:
            origin = NSPoint(x: vis.maxX - size.width - margin, y: cy - size.height / 2)
        case .free:
            if let x = s.freeX, let y = s.freeY {
                origin = NSPoint(x: x, y: y)
                let savedFrame = NSRect(origin: origin, size: size)
                let visibleFrame = vis.insetBy(dx: margin, dy: margin)
                if !visibleFrame.intersects(savedFrame) {
                    origin = NSPoint(x: vis.midX - size.width / 2, y: vis.minY + margin)
                }
            } else {
                origin = NSPoint(x: vis.midX - size.width / 2, y: vis.minY + margin)
            }
        }
        // The margin is a minimum distance to every screen edge, also for a freely placed bar.
        let area = vis.insetBy(dx: min(margin, max(0, (vis.width - size.width) / 2)),
                               dy: min(margin, max(0, (vis.height - size.height) / 2)))
        origin.x = max(area.minX, min(origin.x, area.maxX - size.width))
        origin.y = max(area.minY, min(origin.y, area.maxY - size.height))
        return NSRect(origin: origin, size: size)
    }

    // MARK: Drag & snap

    func beginDrag() {
        dragging = true
        if !revealed { reveal(true) }
    }

    /// The bar stays exactly where it is dropped. Dropped near the left/right edge (mid-height) it turns vertical.
    func endDrag() {
        dragging = false
        let f = panel.frame
        let pointer = NSEvent.mouseLocation
        let idx = NSScreen.screens.firstIndex { $0.frame.contains(pointer) } ?? NSScreen.screens.firstIndex(of: screen) ?? 0
        let scr = NSScreen.screens[idx]
        let vis = scr.visibleFrame
        let rx = (pointer.x - vis.minX) / vis.width
        let ry = (pointer.y - vis.minY) / vis.height
        let wantVertical = (rx < 0.15 || rx > 0.85) && ry > 0.12 && ry < 0.88

        var s = store.settings
        let wasVertical = store.vertical
        s.position = .free
        s.freeVertical = wantVertical
        s.screenIndex = scr == (NSScreen.main ?? NSScreen.screens[0]) ? nil : idx
        s.along = nil
        var origin = f.origin
        if wasVertical != wantVertical {
            // Orientation flips: keep the grip under the pointer.
            store.settings.freeVertical = wantVertical
            store.settings.position = .free
            let size = store.contentSize
            let half = store.unit / 2 + store.barPadding
            if wantVertical {
                origin = NSPoint(x: pointer.x - half, y: pointer.y + store.grip / 2 + store.barPadding - size.height)
            } else {
                origin = NSPoint(x: pointer.x - store.grip / 2 - store.barPadding, y: pointer.y - size.height / 2)
            }
            origin.x = max(vis.minX, min(origin.x, vis.maxX - size.width))
            origin.y = max(vis.minY, min(origin.y, vis.maxY - size.height))
        }
        s.freeX = Double(origin.x)
        s.freeY = Double(origin.y)
        store.settings = s
        layout(animated: true)
    }

    func layout(animated: Bool) {
        let s = store.settings
        panel.level = s.floatAbove ? .floating : .normal
        panel.isMovableByWindowBackground = s.position == .free
        let frame = targetFrame()
        isRepositioning = true
        guard !dragging else { isRepositioning = false; return }
        if animated && panel.isVisible && panel.frame != frame {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in self?.isRepositioning = false }
        } else {
            panel.setFrame(frame, display: true)
            isRepositioning = false
        }
        if !s.autoHide && isVisible && !revealed { reveal(true) }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning, !dragging, store.settings.position == .free else { return }
        let o = panel.frame.origin
        if store.settings.freeX != Double(o.x) || store.settings.freeY != Double(o.y) {
            store.settings.freeX = Double(o.x)
            store.settings.freeY = Double(o.y)
        }
    }

    // MARK: Auto-hide

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
    }

    private func checkHover() {
        guard isVisible, store.settings.autoHide, !dragging else { return }
        let mouse = NSEvent.mouseLocation
        let frame = targetFrame()
        let s = store.settings
        var inside = frame.insetBy(dx: -12, dy: -12).contains(mouse)
        if !revealed {
            let vis = screen.visibleFrame
            let full = screen.frame
            let inX = mouse.x >= frame.minX - 40 && mouse.x <= frame.maxX + 40
            let inY = mouse.y >= frame.minY - 40 && mouse.y <= frame.maxY + 40
            switch s.position {
            case .bottom: inside = inX && mouse.y <= vis.minY + 3 && mouse.y >= full.minY
            case .top: inside = inX && mouse.y >= vis.maxY - 3
            case .left: inside = inY && mouse.x <= vis.minX + 3 && mouse.x >= full.minX
            case .right: inside = inY && mouse.x >= vis.maxX - 3 && mouse.x <= full.maxX
            case .free: inside = frame.contains(mouse)
            }
        }
        // Keep visible while a popover, an unrolled list or a text field is in use.
        if HoverPanel.shared.isVisible && HoverPanel.shared.frame.insetBy(dx: -8, dy: -8).contains(mouse) { inside = true }
        if panel.isKeyWindow || NSApp.windows.contains(where: { $0.isVisible && $0.className.contains("Popover") }) {
            inside = true
        }
        if inside {
            lastInside = Date()
            if !revealed { reveal(true) }
        } else if revealed, Date().timeIntervalSince(lastInside) > 0.7 {
            reveal(false)
        }
    }

    private func reveal(_ show: Bool) {
        revealed = show
        panel.ignoresMouseEvents = !show
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = show ? 1 : 0
        }
    }
}
