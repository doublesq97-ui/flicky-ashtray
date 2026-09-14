import AppKit
import SwiftUI

@MainActor
final class StatusPanelController: NSWindowController {
    private static let panelSize = NSSize(width: 252, height: 118)

    private var pinned = false
    private var hideWorkItem: DispatchWorkItem?
    private let model: AppModel
    private var anchorPetFrame = NSRect.zero
    private var wasVisibleBeforeDrag = false

    init(model: AppModel) {
        self.model = model
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        refreshContent()
    }

    required init?(coder: NSCoder) { nil }

    func petHoverChanged(_ inside: Bool, relativeTo petFrame: NSRect) {
        cancelScheduledHide()
        if inside {
            show(relativeTo: petFrame)
        } else if !pinned {
            scheduleHide()
        }
    }

    func togglePinned(relativeTo petFrame: NSRect) {
        cancelScheduledHide()
        pinned.toggle()
        refreshContent()
        if pinned {
            show(relativeTo: petFrame)
        } else {
            // A second click means "put this away", even while the pointer is
            // still inside the freshly rebuilt card. Scheduling here lets the
            // replacement view's onHover cancel the hide and makes unpinning
            // look broken.
            window?.orderOut(nil)
        }
    }

    func hideForDrag() {
        cancelScheduledHide()
        wasVisibleBeforeDrag = window?.isVisible == true
        window?.orderOut(nil)
    }

    func dragEnded(relativeTo petFrame: NSRect) {
        if pinned || wasVisibleBeforeDrag { show(relativeTo: petFrame) }
        wasVisibleBeforeDrag = false
    }

    func hideImmediately() {
        let needsRefresh = pinned
        pinned = false
        wasVisibleBeforeDrag = false
        cancelScheduledHide()
        if needsRefresh { refreshContent() }
        window?.orderOut(nil)
    }

    private func panelHoverChanged(_ inside: Bool) {
        cancelScheduledHide()
        if !inside && !pinned { scheduleHide() }
    }

    private func scheduleHide() {
        cancelScheduledHide()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.pinned else { return }
            self.window?.orderOut(nil)
            self.hideWorkItem = nil
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func show(relativeTo petFrame: NSRect) {
        guard let window else { return }
        anchorPetFrame = petFrame
        cancelScheduledHide()
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? petFrame
        var origin = NSPoint(x: petFrame.maxX - window.frame.width, y: petFrame.maxY + 2)
        if origin.y + window.frame.height > visible.maxY {
            origin.y = petFrame.minY - window.frame.height - 2
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        if window.isVisible {
            window.alphaValue = 1
            return
        }
        window.alphaValue = 0
        window.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1
        }
    }

    private func refreshContent() {
        let card = StatusCardView(
            model: model,
            isPinned: pinned,
            onHover: { [weak self] in self?.panelHoverChanged($0) },
            onTogglePin: { [weak self] in
                guard let self else { return }
                self.togglePinned(relativeTo: self.anchorPetFrame)
            }
        )
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        material.material = .popover
        // This is a separate transparent panel, so sample the desktop behind
        // it rather than blending only with the panel's own empty content.
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: card)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        window?.contentView = material
    }
}
