import AppKit
import XCTest
@testable import FlickyAshtray

final class PetLayoutTests: XCTestCase {
    func testCigaretteHitTestingUsesRotatedShapeInsteadOfBoundingBoxCorners() {
        let center = NSPoint(
            x: PetLayout.surfaceSize.width / 2 + PetLayout.cigaretteOffset.width,
            y: PetLayout.surfaceSize.height / 2 - PetLayout.cigaretteOffset.height
        )

        XCTAssertTrue(PetLayout.containsCigarette(center))
        XCTAssertFalse(PetLayout.containsCigarette(NSPoint(x: center.x + 50, y: center.y + 45)))
    }

    func testScaleIsClampedAndResizesTheEntireSurface() {
        XCTAssertEqual(PetLayout.normalizedScale(0.2), 0.6, accuracy: 0.0001)
        XCTAssertEqual(PetLayout.normalizedScale(1.4), 1, accuracy: 0.0001)
        XCTAssertEqual(PetLayout.scaledSurfaceSize(for: 0.6), NSSize(width: 132, height: 108))
    }

    func testNoteStyleHasDedicatedWindowGeometryAndIgniterHitTarget() {
        XCTAssertEqual(
            PetLayout.scaledSurfaceSize(for: 1, style: .note),
            PetLayout.noteSurfaceSize
        )
        XCTAssertEqual(
            PetLayout.scaledSurfaceSize(for: 0.6, style: .note),
            NSSize(
                width: PetLayout.noteSurfaceSize.width * 0.6,
                height: PetLayout.noteSurfaceSize.height * 0.6
            )
        )

        XCTAssertTrue(PetLayout.containsPrimaryAction(PetLayout.noteActionCenter, style: .note))
        XCTAssertFalse(
            PetLayout.containsPrimaryAction(
                NSPoint(x: PetLayout.noteSurfaceSize.width / 2, y: PetLayout.noteSurfaceSize.height / 2),
                style: .note
            )
        )
        XCTAssertTrue(
            PetLayout.dragHitRect(for: .note).contains(
                NSPoint(x: PetLayout.noteSurfaceSize.width / 2, y: PetLayout.noteSurfaceSize.height / 2)
            )
        )
    }

    func testCompactNoteKeepsReadableTypeAndDropsOnlyTheSecondaryLine() {
        let compactScale: CGFloat = 0.6

        XCTAssertGreaterThanOrEqual(
            PetLayout.noteCaptionFontSize(for: compactScale) * compactScale,
            10.5
        )
        XCTAssertGreaterThanOrEqual(
            PetLayout.noteCountFontSize(for: compactScale) * compactScale,
            16
        )
        XCTAssertFalse(PetLayout.showsNoteSecondaryLine(for: compactScale))
        XCTAssertTrue(PetLayout.showsNoteSecondaryLine(for: 0.75))
        XCTAssertEqual(PetLayout.noteCaptionFontSize(for: 1), 12)
        XCTAssertEqual(PetLayout.noteCountFontSize(for: 1), 24)
    }

    func testClickJitterDoesNotBecomeDragIntent() {
        XCTAssertFalse(
            PetLayout.isDragIntent(
                from: NSPoint(x: 100, y: 100),
                to: NSPoint(x: 104, y: 103)
            )
        )
        XCTAssertTrue(
            PetLayout.isDragIntent(
                from: NSPoint(x: 100, y: 100),
                to: NSPoint(x: 106, y: 100)
            )
        )
    }

    func testRecordDebounceUsesSystemDoubleClickWindowIndependentlyOfAnimation() {
        var debouncer = RecordActionDebouncer()

        XCTAssertTrue(debouncer.accept(nowUptime: 10, doubleClickInterval: 0.5))
        XCTAssertFalse(debouncer.accept(nowUptime: 10.26, doubleClickInterval: 0.5))
        XCTAssertFalse(debouncer.accept(nowUptime: 10.5, doubleClickInterval: 0.5))
        XCTAssertFalse(debouncer.accept(nowUptime: 10.8, doubleClickInterval: 0.5))
        XCTAssertTrue(debouncer.accept(nowUptime: 11.31, doubleClickInterval: 0.5))
    }

    func testScaledCigaretteHitUsesTheSameBaseGeometry() {
        let scale: CGFloat = 0.6
        let baseCenter = NSPoint(
            x: PetLayout.surfaceSize.width / 2 + PetLayout.cigaretteOffset.width,
            y: PetLayout.surfaceSize.height / 2 - PetLayout.cigaretteOffset.height
        )
        let physicalCenter = NSPoint(x: baseCenter.x * scale, y: baseCenter.y * scale)
        let mappedCenter = PetLayout.basePoint(fromScaledPoint: physicalCenter, scale: scale)
        XCTAssertEqual(mappedCenter.x, baseCenter.x, accuracy: 0.0001)
        XCTAssertEqual(mappedCenter.y, baseCenter.y, accuracy: 0.0001)
        XCTAssertTrue(PetLayout.containsCigarette(mappedCenter))

        let physicalDeadCorner = NSPoint(
            x: (baseCenter.x + 50) * scale,
            y: (baseCenter.y + 45) * scale
        )
        let mappedDeadCorner = PetLayout.basePoint(
            fromScaledPoint: physicalDeadCorner,
            scale: scale
        )
        XCTAssertFalse(PetLayout.containsCigarette(mappedDeadCorner))
    }

    func testResizePreservesCenterAwayFromEdges() {
        let visible = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let oldFrame = NSRect(x: 350, y: 250, width: 300, height: 250)
        let newSize = PetLayout.scaledSurfaceSize(for: 0.6)
        let origin = PetLayout.originAfterResize(from: oldFrame, to: newSize, in: visible)
        let newFrame = NSRect(origin: origin, size: newSize)

        XCTAssertEqual(newFrame.midX, oldFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(newFrame.midY, oldFrame.midY, accuracy: 0.0001)
    }

    func testResizePreservesTopRightParkingAndClampsToVisibleScreen() {
        let visible = NSRect(x: 100, y: 80, width: 1_000, height: 700)
        let oldFrame = NSRect(x: 800, y: 530, width: 300, height: 250)
        let newSize = PetLayout.scaledSurfaceSize(for: 0.6)
        let origin = PetLayout.originAfterResize(from: oldFrame, to: newSize, in: visible)
        let newFrame = NSRect(origin: origin, size: newSize)

        XCTAssertEqual(newFrame.maxX, visible.maxX, accuracy: 0.0001)
        XCTAssertEqual(newFrame.maxY, visible.maxY, accuracy: 0.0001)

        let clamped = PetLayout.clampedOrigin(
            NSPoint(x: -500, y: 2_000),
            windowSize: newSize,
            in: visible
        )
        XCTAssertEqual(clamped.x, visible.minX, accuracy: 0.0001)
        XCTAssertEqual(clamped.y, visible.maxY - newSize.height, accuracy: 0.0001)
    }
}
