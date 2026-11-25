import AppKit
import SwiftUI

// MARK: - Hover list panel

final class UnrollModel: ObservableObject {
    @Published var open = false
    /// Height the whole list may take between the dock edge and the screen edge.
    @Published var available: CGFloat = .infinity
    /// Height of everything in the list except its scrolling part (header, buttons, padding).
    @Published var chrome: CGFloat = 0
    var scrollHeight: CGFloat = 0 { didSet { updateChrome() } }
    var height: CGFloat = 0 { didSet { updateChrome() } }

    /// Everything but the scroll area keeps its height; the scroll area gets what is left.
    private func updateChrome() {
        guard height > 0 else { return }
        let value = height - scrollHeight
        if abs(value - chrome) > 0.5 { chrome = value }
    }

    /// The tallest the list's scrolling part may become so the list still fits beside the dock.
    var scrollCap: CGFloat { max(80, available - chrome) }
}

private struct HoverScrollCapKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

private struct HoverScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

extension EnvironmentValues {
    var hoverScrollCap: CGFloat {
        get { self[HoverScrollCapKey.self] }
        set { self[HoverScrollCapKey.self] = newValue }
    }
}

extension View {
    /// The scrolling part of a hover list: at most `maxHeight` tall, and shorter when the
    /// space between dock and screen edge is smaller, so the list never covers the dock.
    func hoverListScroll(maxHeight: CGFloat) -> some View {
        modifier(HoverListScroll(maxHeight: maxHeight))
    }
}

private struct HoverListScroll: ViewModifier {
    let maxHeight: CGFloat
    @Environment(\.hoverScrollCap) private var cap

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: min(maxHeight, cap))
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear.preference(key: HoverScrollHeightKey.self, value: g.size.height)
            })
    }
}

/// Floating panel that shows a list next to a hovered tile, in the dock's own look.
final class HoverPanel {
    static let shared = HoverPanel()

    private let panel: DockPanel
    private let model = UnrollModel()
    private var host: FirstMouseHostingView<AnyView>?
    private(set) var ownerID: String?
    private var anchor: NSRect = .zero
    private var pending: DispatchWorkItem?
    private var pendingOwnerID: String?
    private var watch: Timer?
    private var vertical = false
    private var fromBottom = false
    private var rightClickMonitor: Any?

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    private init() {
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Called when the pointer enters a tile that has hover content.
    func enter(owner: String, anchor: NSRect, width: CGFloat, content: @escaping () -> AnyView) {
        guard DockStore.shared.settings.hoverLists ?? true, widgetAllowsUnroll(owner: owner) else { return }
        pending?.cancel()
        if ownerID == owner && isVisible { return }
        pendingOwnerID = owner
        let work = DispatchWorkItem { [weak self] in
            self?.pendingOwnerID = nil
            self?.show(owner: owner, anchor: anchor, width: width, content: content())
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isVisible ? 0.05 : 0.35), execute: work)
    }

    func leave(owner: String) {
        if pendingOwnerID == owner {
            pending?.cancel()
            pendingOwnerID = nil
        }
    }

    func close(ownerPrefix: String) {
        if let pendingOwnerID, pendingOwnerID == ownerPrefix || pendingOwnerID.hasPrefix(ownerPrefix) {
            pending?.cancel()
            self.pendingOwnerID = nil
        }
        if let ownerID, ownerID == ownerPrefix || ownerID.hasPrefix(ownerPrefix) {
            closeImmediately()
        }
    }

    private func widgetAllowsUnroll(owner: String) -> Bool {
        guard owner.count >= 36,
              let widgetID = UUID(uuidString: String(owner.prefix(36))),
              let widget = DockStore.shared.instance(widgetID) else { return true }
        return widget.cfg("unrollEnabled", "1") != "0"
    }

    private func show(owner: String, anchor: NSRect, width: CGFloat, content: AnyView) {
        self.anchor = anchor
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let vertical = DockStore.shared.vertical
        // Unroll away from the screen edge the bar sits on.
        let fromBottom = !vertical && anchor.midY < vis.midY
        if ownerID != owner || !isVisible { model.open = false }
        ownerID = owner

        self.vertical = vertical
        self.fromBottom = fromBottom
        model.available = availableHeight(vis: vis)
        // A fresh identity per owner, so each list loads its own entries instead of keeping the last one's state.
        let root = AnyView(UnrollView(model: model, fromBottom: fromBottom, width: width, content: AnyView(content.id(owner)))
            .environment(\.colorScheme, Theme.palette.dark ? .dark : .light))
        if let host { host.rootView = root } else {
            let h = FirstMouseHostingView(rootView: root)
            host = h
            panel.contentView = h
        }
        place(size: host!.fittingSize)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { self.model.open = true }
        }
        startWatching()
    }

    /// The dock's outer edge above (or below) the hovered tile: the header tab's edge where the tile
    /// lies under the tab, otherwise the lower edge of the band beside it.
    private func dockEdge(_ dock: NSRect, top: Bool) -> CGFloat {
        let store = DockStore.shared
        let edge = top ? dock.maxY : dock.minY
        guard store.showsHeader, !store.vertical else { return edge }
        let tabHalf = store.headerTabWidth / 2
        let underTab = abs(anchor.midX - dock.midX) <= tabHalf
        let inset = store.profileStripHeight + store.headerGap
        return underTab ? edge : (top ? edge - inset : edge + inset)
    }

    /// Room for the list between the dock's outer edge and the far screen edge.
    private func availableHeight(vis: NSRect) -> CGFloat {
        let dock = AppDelegate.shared.dock.windowFrame ?? anchor
        if vertical { return vis.height }
        return fromBottom ? vis.maxY - dockEdge(dock, top: true) : dockEdge(dock, top: false) - vis.minY
    }

    /// The list grew or shrank (entries finished loading): fit the panel to it.
    func contentSizeChanged() {
        guard isVisible, let host else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            let size = host.fittingSize
            if abs(size.width - self.panel.frame.width) > 0.5 || abs(size.height - self.panel.frame.height) > 0.5 {
                self.place(size: size)
            }
        }
    }

    private func place(size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        var origin: NSPoint
        // The list sits on the dock's outer edge (its own edge on that side has no margin),
        // so its line meets the dock's line and the dock stays uncovered.
        let dock = AppDelegate.shared.dock.windowFrame ?? anchor
        if vertical {
            let right = anchor.midX < vis.midX
            origin = NSPoint(x: right ? dock.maxX : dock.minX - size.width, y: anchor.maxY - size.height + 10)
        } else if fromBottom {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: dockEdge(dock, top: true))
        } else {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: dockEdge(dock, top: false) - size.height)
        }
        origin.x = max(vis.minX, min(origin.x, vis.maxX - size.width))
        if vertical {
            origin.y = max(vis.minY, min(origin.y, vis.maxY - size.height))
        }
        // Horizontal bar: the list always grows out of the dock's edge and is never pushed back over the dock.
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func startWatching() {
        watch?.invalidate()
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.closeImmediately()
            return event
        }
        var outsideSince: Date?
        watch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = NSEvent.mouseLocation
            let inside = self.anchor.insetBy(dx: -4, dy: -4).contains(m) || self.panel.frame.insetBy(dx: -6, dy: -6).contains(m)
                || self.bridge.contains(m)
            if inside { outsideSince = nil; return }
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.35 { self.close() }
        }
    }

    /// Gap between tile and panel, so moving the pointer across it does not close the list.
    private var bridge: NSRect { anchor.union(panel.frame).intersection(anchor.union(panel.frame)) }

    func close() {
        watch?.invalidate()
        watch = nil
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
        pending?.cancel()
        pendingOwnerID = nil
        withAnimation(.easeIn(duration: 0.15)) { model.open = false }
        let owner = ownerID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.ownerID == owner, !self.model.open else { return }
            self.panel.orderOut(nil)
            self.ownerID = nil
        }
    }

    private func closeImmediately() {
        watch?.invalidate()
        watch = nil
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
        pending?.cancel()
        pendingOwnerID = nil
        model.open = false
        panel.orderOut(nil)
        ownerID = nil
    }
}

/// The hover list, drawn like the dock itself: same glass, tint, corner radius and white edge.
/// It slides out of the dock and fades in.
struct UnrollView: View {
    @ObservedObject var model: UnrollModel
    let fromBottom: Bool
    let width: CGFloat
    let content: AnyView

    private var edgesAwayFromDock: Edge.Set {
        if DockStore.shared.vertical { return [.top, .bottom, .leading, .trailing] }
        return fromBottom ? [.top, .leading, .trailing] : [.bottom, .leading, .trailing]
    }

    var body: some View {
        let store = DockStore.shared
        let shape = RoundedRectangle(cornerRadius: store.corner + store.barPadding, style: .continuous)
        content
            .frame(width: width)
            .padding(.vertical, 12)
            .modifier(DockSheetSurface(shape: shape))
            .foregroundStyle(Theme.fg)
            .opacity(model.open ? 1 : 0)
            .scaleEffect(model.open ? 1 : 0.96, anchor: fromBottom ? .bottom : .top)
            .offset(y: model.open ? 0 : (fromBottom ? 10 : -10))
            // Margin for the slide-in, except on the side that touches the dock.
            .padding(edgesAwayFromDock, 10)
            .fixedSize()
            .environment(\.hoverScrollCap, model.scrollCap)
            .onPreferenceChange(HoverScrollHeightKey.self) { h in
                model.scrollHeight = h
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                model.height = size.height
                HoverPanel.shared.contentSizeChanged()
            }
    }
}

/// Exactly the dock bar's surface: same glass, tint and edge.
private struct DockSheetSurface: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        let settings = DockStore.shared.settings
        if Theme.glass {
            content
                .glassEffect(.clear.tint(Theme.bar.opacity(settings.glassTint ?? 0.18)), in: shape)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .allowsHitTesting(false))
        } else {
            content.background {
                shape.fill(Theme.bar.opacity(settings.barOpacity))
                    .overlay(shape.strokeBorder(Theme.fg.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            }
        }
    }
}

// MARK: - Tile hook

extension View {
    /// Shows `content` in an unrolling list while the pointer rests on this tile.
    func hoverUnroll(id: UUID, width: CGFloat, enabled: Bool = true, content: @escaping () -> AnyView) -> some View {
        modifier(HoverUnrollModifier(id: id.uuidString, width: width, enabled: enabled, content: content))
    }

    func hoverUnroll(key: String, width: CGFloat, enabled: Bool = true, content: @escaping () -> AnyView) -> some View {
        modifier(HoverUnrollModifier(id: key, width: width, enabled: enabled, content: content))
    }
}

private struct HoverUnrollModifier: ViewModifier {
    let id: String
    let width: CGFloat
    let enabled: Bool
    let content: () -> AnyView
    @State private var frame: CGRect = .zero

    func body(content view: Content) -> some View {
        view
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onHover { inside in
                guard enabled else { return }
                if inside, let win = AppDelegate.shared.dock.windowFrame {
                    let screenRect = NSRect(x: win.minX + frame.minX, y: win.maxY - frame.maxY, width: frame.width, height: frame.height)
                    HoverPanel.shared.enter(owner: id, anchor: screenRect, width: width, content: content)
                } else {
                    HoverPanel.shared.leave(owner: id)
                }
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled { HoverPanel.shared.close(ownerPrefix: id) }
            }
    }
}
