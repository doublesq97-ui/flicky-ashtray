import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    var onDragBegan: (() -> Void)? {
        didSet { petPanel?.onDragBegan = onDragBegan }
    }
    var onDragEnded: (() -> Void)?
    var onShowControlPanel: (() -> Void)? {
        didSet { petPanel?.onShowControlPanel = onShowControlPanel }
    }
    var onHide: (() -> Void)? {
        didSet { petPanel?.onHide = onHide }
    }

    private var petPanel: PetPanel? { window as? PetPanel }
    private let hostingView: NSHostingView<PetSurfaceView>

    init(model: AppModel, rootView: PetSurfaceView) {
        let initialScale = PetLayout.normalizedScale(CGFloat(model.store.settings.petScale))
        let initialStyle = model.store.settings.petStyle
        var scaledRootView = rootView
        scaledRootView.scale = initialScale
        let hostingView = NSHostingView(rootView: scaledRootView)
        self.hostingView = hostingView
        let frame = NSRect(
            origin: .zero,
            size: PetLayout.scaledSurfaceSize(for: initialScale, style: initialStyle)
        )
        let window = PetPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.interactionScale = initialScale
        window.petStyle = initialStyle
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.setFrameAutosaveName("FlickyAshtray.PetWindow")
        super.init(window: window)
        // Frame autosave is useful for position, but its persisted size may belong
        // to a previous scale. Reconcile it immediately so visual and hit geometry
        // can never start a launch out of sync.
        let expectedSize = PetLayout.scaledSurfaceSize(for: initialScale, style: initialStyle)
        if abs(window.frame.width - expectedSize.width) > 0.5
            || abs(window.frame.height - expectedSize.height) > 0.5 {
            let restoredFrame = window.frame
            let visibleFrame = screen(for: restoredFrame)?.visibleFrame ?? restoredFrame
            let origin = PetLayout.originAfterResize(
                from: restoredFrame,
                to: expectedSize,
                in: visibleFrame
            )
            window.setFrame(NSRect(origin: origin, size: expectedSize), display: false)
        }
        window.onDragEnded = { [weak self] in
            guard let self else { return }
            self.finishNativeDrag()
            self.onDragEnded?()
        }
    }

    required init?(coder: NSCoder) { nil }

    var frame: NSRect { window?.frame ?? .zero }

    func show() {
        guard let window else { return }
        clampToVisibleScreen(window)
        window.orderFrontRegardless()
    }

    func hide() { window?.orderOut(nil) }

    /// Resizes the native panel, SwiftUI artwork and interaction coordinate system
    /// as one unit. App settings use `Double`, so this is intentionally the public
    /// boundary type; AppKit geometry remains `CGFloat` internally.
    func updateScale(_ proposedScale: Double) {
        applyConfiguration(
            scale: CGFloat(proposedScale),
            style: petPanel?.petStyle ?? .ashtray
        )
    }

    func updateStyle(_ style: PetStyle) {
        applyConfiguration(
            scale: petPanel?.interactionScale ?? 1,
            style: style
        )
    }

    func updateConfiguration(scale proposedScale: Double, style: PetStyle) {
        applyConfiguration(scale: CGFloat(proposedScale), style: style)
    }

    private func applyConfiguration(scale proposedScale: CGFloat, style: PetStyle) {
        guard let window, let panel = petPanel else { return }
        let scale = PetLayout.normalizedScale(proposedScale)
        let newSize = PetLayout.scaledSurfaceSize(for: scale, style: style)
        let scaleChanged = abs(scale - panel.interactionScale) > 0.0001
        let styleChanged = style != panel.petStyle
        let sizeChanged = abs(window.frame.width - newSize.width) > 0.5
            || abs(window.frame.height - newSize.height) > 0.5
        guard scaleChanged || styleChanged || sizeChanged else { return }

        let oldFrame = window.frame
        let targetScreen = screen(for: oldFrame)
        let visibleFrame = targetScreen?.visibleFrame ?? oldFrame
        let newOrigin = PetLayout.originAfterResize(
            from: oldFrame,
            to: newSize,
            in: visibleFrame
        )

        panel.interactionScale = scale
        panel.petStyle = style
        var rootView = hostingView.rootView
        rootView.scale = scale
        hostingView.rootView = rootView
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        clampToVisibleScreen(window)
    }

    func finishNativeDrag() {
        guard let window else { return }
        clampToVisibleScreen(window)
    }

    private func clampToVisibleScreen(_ window: NSWindow) {
        window.setFrameOrigin(clampedOrigin(window.frame.origin, for: window))
    }

    private func clampedOrigin(_ proposed: NSPoint, for window: NSWindow) -> NSPoint {
        let proposedFrame = NSRect(origin: proposed, size: window.frame.size)
        let targetScreen = screen(for: proposedFrame)
        let visible = targetScreen?.visibleFrame ?? .zero
        return PetLayout.clampedOrigin(proposed, windowSize: window.frame.size, in: visible)
    }

    private func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            let left = lhs.visibleFrame.intersection(frame)
            let right = rhs.visibleFrame.intersection(frame)
            return left.width * left.height < right.width * right.height
        } ?? NSScreen.main
    }
}

@MainActor
private final class PetPanel: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onShowControlPanel: (() -> Void)?
    var onHide: (() -> Void)?
    var interactionScale: CGFloat = 1
    var petStyle: PetStyle = .ashtray
    private var isPerformingNativeDrag = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let pointerScreen = isPerformingNativeDrag
            ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            : nil
        let targetScreen = pointerScreen ?? bestScreen(for: frameRect) ?? screen ?? self.screen ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame, !visibleFrame.isEmpty else {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        let origin = PetLayout.clampedOrigin(
            frameRect.origin,
            windowSize: frameRect.size,
            in: visibleFrame
        )
        return NSRect(origin: origin, size: frameRect.size)
    }

    override func sendEvent(_ event: NSEvent) {
        let point = PetLayout.basePoint(
            fromScaledPoint: event.locationInWindow,
            scale: interactionScale
        )
        let dragHitRect = PetLayout.dragHitRect(for: petStyle)
        let isOverPrimaryAction = PetLayout.containsPrimaryAction(point, style: petStyle)
        if event.type == .leftMouseDown,
           dragHitRect.contains(point),
           !isOverPrimaryAction {
            let originBefore = frame.origin
            onDragBegan?()
            isPerformingNativeDrag = true
            performDrag(with: event)
            isPerformingNativeDrag = false
            let originAfter = frame.origin
            let didMove = PetLayout.isDragIntent(from: originBefore, to: originAfter)
            if didMove {
                onDragEnded?()
            } else {
                // Treat sub-threshold pointer jitter as a no-op. Pinning belongs
                // to the hover card, so a pet-body click cannot be confused with
                // the adjacent record action.
                setFrameOrigin(originBefore)
                onDragEnded?()
            }
            return
        }
        if event.type == .rightMouseDown,
           dragHitRect.contains(point) || isOverPrimaryAction {
            showContextMenu(for: event)
            return
        }
        super.sendEvent(event)
    }

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        let open = NSMenuItem(title: "查看记录与设置…", action: #selector(openControlPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏桌宠", action: #selector(hidePet), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        if let contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        }
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        var result: NSScreen?
        var largestArea: CGFloat = 0
        for candidate in NSScreen.screens {
            let intersection = candidate.visibleFrame.intersection(frame)
            let area = intersection.width * intersection.height
            if area > largestArea {
                largestArea = area
                result = candidate
            }
        }
        return result
    }

    @objc private func openControlPanel() { onShowControlPanel?() }
    @objc private func hidePet() { onHide?() }
}
