import AppKit
import SwiftUI

/// Internal advertising: every couple of hours a small bubble floats above the dock promoting one
/// still-locked add-on function, until the add-on is unlocked. After unlocking, a bubble appears only
/// once for functions that were newly added in an update.
@MainActor
final class PromoBubble {
    static let shared = PromoBubble()

    /// Time between bubbles while locked.
    private let interval: TimeInterval = 2 * 60 * 60
    /// Delay before the first bubble after launch.
    private let firstDelay: TimeInterval = ProcessInfo.processInfo.environment["CROHNIQ_PROMO_DELAY"].flatMap(Double.init) ?? 45

    private var timer: Timer?
    private var panel: NSPanel?
    private var queue: [WidgetKind] = []

    func start() {
        if Entitlements.shared.unlocked {
            announceNewFeaturesIfAny()
            return
        }
        schedule(after: firstDelay)
    }

    /// Call after a successful unlock to stop the promos.
    func stop() {
        timer?.invalidate(); timer = nil
        dismiss()
    }

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
    }

    private func fire() {
        guard !Entitlements.shared.unlocked else { stop(); return }
        if queue.isEmpty { queue = WidgetKind.allCases.filter(\.isPremium).shuffled() }
        guard let kind = queue.popLast() else { return }
        present(kind)
        schedule(after: interval)
    }

    /// After unlocking: show one bubble if an update added premium functions the user hasn't seen.
    private func announceNewFeaturesIfAny() {
        let all = Set(WidgetKind.allCases.filter(\.isPremium).map(\.rawValue))
        let unseen = all.subtracting(Entitlements.shared.seenPremium)
        Entitlements.shared.seenPremium = all
        guard let raw = unseen.first, let kind = WidgetKind(rawValue: raw) else { return }
        schedule(after: firstDelay) // reuse timer slot to show it shortly
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: firstDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.present(kind, isNew: true) }
        }
    }

    // MARK: - Panel

    private func present(_ kind: WidgetKind, isNew: Bool = false) {
        dismiss()
        let size = NSSize(width: 320, height: 92)
        let origin = anchor(for: size)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PromoBubbleView(kind: kind, isNew: isNew,
            unlock: { [weak self] in self?.dismiss(); AddonUnlock.show(highlight: kind) },
            dismiss: { [weak self] in self?.dismiss() }))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; panel.animator().alphaValue = 1 }
        self.panel = panel
        // Auto-dismiss after a while.
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self, weak panel] in
            if self?.panel === panel { self?.dismiss() }
        }
    }

    private func anchor(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        if let dock = AppDelegate.shared.dock.windowFrame {
            let x = min(dock.maxX - size.width, screen.maxX - size.width - 16)
            return NSPoint(x: max(screen.minX + 16, x), y: dock.maxY + 12)
        }
        return NSPoint(x: screen.maxX - size.width - 16, y: screen.minY + 120)
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }
}

private struct PromoBubbleView: View {
    let kind: WidgetKind
    let isNew: Bool
    let unlock: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: kind.symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isNew {
                        Text("NEU").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.orange))
                    }
                    Text(kind.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.primary).lineLimit(1)
                }
                Text(kind.promoPitch).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button(action: unlock) {
                    Text(isNew ? "Ansehen" : "Freischalten").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320, height: 92)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}
