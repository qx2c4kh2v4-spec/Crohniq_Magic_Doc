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
    /// The list's natural size as SwiftUI laid it out.
    var size: CGSize = .zero

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
            // The panel is sized and placed by `place` only; AppKit would otherwise grow it downward
            // (keeping its top edge) when the list loads more entries, over the dock.
            h.sizingOptions = []
            host = h
            panel.contentView = h
        }
        place(size: idealSize)
        panel.orderFrontRegardless()
        host?.layoutSubtreeIfNeeded()
        contentSizeChanged()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { self.model.open = true }
        }
        startWatching()
    }

    /// The dock's outline on the side the list grows out of: the band, plus the raised header tab
    /// in the middle (the same geometry `DockOutline` draws).
    private struct Outline {
        var bandEdge: CGFloat
        var tabEdge: CGFloat
        /// Horizontal extent of the tab, nil when the bar is a plain rectangle on this side.
        var tab: ClosedRange<CGFloat>?
        var fillet: CGFloat = 0
    }

    private func outline(_ dock: NSRect, top: Bool) -> Outline {
        let store = DockStore.shared
        let edge = top ? dock.maxY : dock.minY
        let plain = Outline(bandEdge: edge, tabEdge: edge, tab: nil)
        // The header (and so the tab) sits on the side facing the screen; on the other side the edge is straight.
        let headerOnTop = store.settings.position != .top
        guard store.showsHeader, !store.vertical, headerOnTop == top else { return plain }
        let inset = store.profileStripHeight + store.headerGap
        let radius = store.corner + store.barPadding
        let fillet = max(0, min(radius, inset) * 0.45)
        let tabWidth = store.headerTabWidth
        guard inset > 1, tabWidth < dock.width - 2 * (radius + fillet) else { return plain }
        return Outline(bandEdge: top ? edge - inset : edge + inset, tabEdge: edge,
                       tab: (dock.midX - tabWidth / 2)...(dock.midX + tabWidth / 2), fillet: fillet)
    }

    /// The list's natural size, measured by SwiftUI (the hosting view does not size the panel itself).
    private var idealSize: NSSize {
        model.size
    }

    /// Room for the list between the dock's outer edge and the far screen edge.
    private func availableHeight(vis: NSRect) -> CGFloat {
        let dock = AppDelegate.shared.dock.windowFrame ?? anchor
        if vertical { return vis.height }
        return fromBottom ? vis.maxY - dock.maxY : dock.minY - vis.minY
    }

    /// The list grew or shrank (entries finished loading): fit the panel to it.
    func contentSizeChanged() {
        guard isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            // Always re-place: the bottom must stay on the dock even if the size already matches.
            self.place(size: self.idealSize)
        }
    }

    private func place(size: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let dock = AppDelegate.shared.dock.windowFrame ?? anchor
        if vertical {
            let right = anchor.midX < vis.midX
            var origin = NSPoint(x: right ? dock.maxX : dock.minX - size.width, y: anchor.maxY - size.height + 10)
            origin.y = max(vis.minY, min(origin.y, vis.maxY - size.height))
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            return
        }
        // The visible sheet is inset by the slide margin on its left and right.
        let margin: CGFloat = 10
        let sheet = size.width - margin * 2
        let shape = outline(dock, top: fromBottom)
        var x = anchor.midX - size.width / 2
        if let tab = shape.tab {
            if tab.contains(anchor.midX) {
                // Tile under the tab: keep the whole sheet on the tab.
                if sheet <= tab.upperBound - tab.lowerBound {
                    x = min(max(x, tab.lowerBound - margin), tab.upperBound - margin - sheet)
                }
            } else if anchor.midX < tab.lowerBound {
                // Left of the tab: keep the sheet clear of it, on the band.
                x = min(x, tab.lowerBound - shape.fillet - margin - sheet)
            } else {
                x = max(x, tab.upperBound + shape.fillet - margin)
            }
        }
        x = max(vis.minX, min(x, vis.maxX - size.width))
        // Sit on whatever part of the outline lies under the sheet: the tab if the sheet reaches over it.
        var edge = shape.bandEdge
        if let tab = shape.tab {
            let left = x + margin, right = x + margin + sheet
            if right > tab.lowerBound - shape.fillet && left < tab.upperBound + shape.fillet { edge = shape.tabEdge }
        }
        let y = fromBottom ? edge : edge - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
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
            // Unrolls out of the dock: revealed from the edge that touches the dock outward.
            .mask(alignment: fromBottom ? .bottom : .top) {
                GeometryReader { g in
                    Rectangle()
                        .frame(height: model.open ? g.size.height : 0)
                        .frame(maxHeight: .infinity, alignment: fromBottom ? .bottom : .top)
                }
            }
            .opacity(model.open ? 1 : 0.3)
            // Margin for the slide-in, except on the side that touches the dock.
            .padding(edgesAwayFromDock, 10)
            .fixedSize()
            .environment(\.hoverScrollCap, model.scrollCap)
            .onPreferenceChange(HoverScrollHeightKey.self) { h in
                model.scrollHeight = h
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                model.size = size
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
