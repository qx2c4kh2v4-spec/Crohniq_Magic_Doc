import AppKit
import SwiftUI

// MARK: - Unrolling hover panel ("scroll" animation)

final class UnrollModel: ObservableObject {
    @Published var open = false
}

/// Floating panel that unrolls a list next to a hovered tile, like a scroll between two rods.
final class HoverPanel {
    static let shared = HoverPanel()

    private let panel: DockPanel
    private let model = UnrollModel()
    private var host: FirstMouseHostingView<AnyView>?
    private(set) var ownerID: UUID?
    private var anchor: NSRect = .zero
    private var pending: DispatchWorkItem?
    private var watch: Timer?

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
    func enter(owner: UUID, anchor: NSRect, width: CGFloat, content: @escaping () -> AnyView) {
        guard DockStore.shared.settings.hoverLists ?? true else { return }
        pending?.cancel()
        if ownerID == owner && isVisible { return }
        let work = DispatchWorkItem { [weak self] in self?.show(owner: owner, anchor: anchor, width: width, content: content()) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isVisible ? 0.05 : 0.35), execute: work)
    }

    func leave(owner: UUID) {
        if ownerID != owner { pending?.cancel() }
    }

    private func show(owner: UUID, anchor: NSRect, width: CGFloat, content: AnyView) {
        self.anchor = anchor
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let vertical = DockStore.shared.vertical
        // Unroll away from the screen edge the bar sits on.
        let fromBottom = !vertical && anchor.midY < vis.midY
        if ownerID != owner || !isVisible { model.open = false }
        ownerID = owner

        let root = AnyView(UnrollView(model: model, fromBottom: fromBottom, width: width, content: content)
            .environment(\.colorScheme, Theme.palette.dark ? .dark : .light))
        if let host { host.rootView = root } else {
            let h = FirstMouseHostingView(rootView: root)
            host = h
            panel.contentView = h
        }
        let size = host!.fittingSize
        var origin: NSPoint
        if vertical {
            let right = anchor.midX < vis.midX
            origin = NSPoint(x: right ? anchor.maxX + 8 : anchor.minX - 8 - size.width, y: anchor.maxY - size.height + 6)
        } else if fromBottom {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 4)
        } else {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - 4 - size.height)
        }
        origin.x = max(vis.minX + 4, min(origin.x, vis.maxX - size.width - 4))
        origin.y = max(vis.minY + 4, min(origin.y, vis.maxY - size.height - 4))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { self.model.open = true }
        }
        startWatching()
    }

    private func startWatching() {
        watch?.invalidate()
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
        pending?.cancel()
        withAnimation(.easeIn(duration: 0.22)) { model.open = false }
        let owner = ownerID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.ownerID == owner, !self.model.open else { return }
            self.panel.orderOut(nil)
            self.ownerID = nil
        }
    }
}

struct UnrollView: View {
    @ObservedObject var model: UnrollModel
    let fromBottom: Bool
    let width: CGFloat
    let content: AnyView

    private let rod: CGFloat = 12

    var body: some View {
        let p: CGFloat = model.open ? 1 : 0
        VStack(spacing: 0) {
            content
                .frame(width: width)
                .padding(.vertical, 10)
                .modifier(SheetSurface())
                .foregroundStyle(Theme.fg)
                .opacity(model.open ? 1 : 0.2)
                .mask {
                    GeometryReader { g in
                        Rectangle()
                            .frame(height: max(0, g.size.height * p))
                            .frame(maxHeight: .infinity, alignment: fromBottom ? .bottom : .top)
                    }
                }
                .overlay(alignment: fromBottom ? .bottom : .top) { Rod(width: width + 16) .offset(y: fromBottom ? rod / 2 : -rod / 2) }
                .overlay {
                    GeometryReader { g in
                        Rod(width: width + 16)
                            .position(x: g.size.width / 2,
                                      y: fromBottom ? g.size.height * (1 - p) - rod / 2 + 0 : g.size.height * p + rod / 2)
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, rod + 4)
    }
}

/// The unrolled sheet: frosted glass (content stays on top) or a solid tile colour.
private struct SheetSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if Theme.glass {
            content
                .glassEffect(.regular.tint(Theme.tile.opacity(0.25 + (DockStore.shared.settings.glassTint ?? 0.18) * 0.6)), in: shape)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1), .white.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .allowsHitTesting(false))
        } else {
            content.background(
                shape.fill(Theme.tile.opacity(0.97))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            )
        }
    }
}

/// One rod of the scroll: a rounded bar with knobs at both ends.
struct Rod: View {
    let width: CGFloat

    var body: some View {
        if Theme.glass { glassRod } else { solidRod }
    }

    private var glassRod: some View {
        let tint = Theme.tileHi.opacity(0.35)
        return HStack(spacing: 0) {
            Color.clear.frame(width: 10, height: 18).glassEffect(.regular.tint(tint), in: Capsule())
            Color.clear.frame(height: 12).glassEffect(.regular.tint(tint), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.75))
            Color.clear.frame(width: 10, height: 18).glassEffect(.regular.tint(tint), in: Capsule())
        }
        .frame(width: width, height: 18)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private var solidRod: some View {
        let shade = LinearGradient(colors: [Theme.tileHi.mix(with: .white, by: 0.25), Theme.tileHi, Theme.tile.mix(with: .black, by: 0.4)],
                                   startPoint: .top, endPoint: .bottom)
        return HStack(spacing: 0) {
            Capsule().fill(shade).frame(width: 9, height: 16)
            Capsule().fill(shade).frame(height: 11)
            Capsule().fill(shade).frame(width: 9, height: 16)
        }
        .frame(width: width, height: 16)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

// MARK: - Tile hook

extension View {
    /// Shows `content` in an unrolling list while the pointer rests on this tile.
    func hoverUnroll(id: UUID, width: CGFloat, enabled: Bool = true, content: @escaping () -> AnyView) -> some View {
        modifier(HoverUnrollModifier(id: id, width: width, enabled: enabled, content: content))
    }
}

private struct HoverUnrollModifier: ViewModifier {
    let id: UUID
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
    }
}
