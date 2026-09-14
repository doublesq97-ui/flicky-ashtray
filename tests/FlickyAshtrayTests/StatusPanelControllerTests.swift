import AppKit
import XCTest
@testable import FlickyAshtray

@MainActor
final class StatusPanelControllerTests: XCTestCase {
    func testSecondPinToggleRetractsPanelImmediately() {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        let model = AppModel(repository: repository)
        let controller = StatusPanelController(model: model)
        let petFrame = NSRect(x: 200, y: 200, width: 220, height: 180)

        controller.togglePinned(relativeTo: petFrame)
        XCTAssertEqual(controller.window?.isVisible, true)

        controller.togglePinned(relativeTo: petFrame)
        XCTAssertEqual(controller.window?.isVisible, false)
    }

    func testStatusPanelSamplesBehindItsTransparentWindow() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(
            repository: StoreRepository(fileURL: directory.appendingPathComponent("store.json"))
        )
        let controller = StatusPanelController(model: model)
        let material = controller.window?.contentView as? NSVisualEffectView

        XCTAssertEqual(material?.blendingMode, .behindWindow)
        XCTAssertEqual(material?.material, .popover)
    }
}
