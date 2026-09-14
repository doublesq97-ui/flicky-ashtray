import AppKit
import SwiftUI

@MainActor
final class ControlPanelWindowController: NSWindowController {
    init(model: AppModel, onDone: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: ControlPanelView(model: model, onDone: onDone))
        window.title = "Flicky Ashtray 控制面板"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.minSize = NSSize(width: 460, height: 520)
        window.setContentSize(frame.size)
        // Center only the unsaved default frame. setFrameAutosaveName restores
        // the user's own position afterwards, so subsequent openings never
        // snap back to the middle of the screen.
        window.center()
        window.setFrameAutosaveName("FlickyAshtray.ControlPanel")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { window?.orderOut(nil) }
}
