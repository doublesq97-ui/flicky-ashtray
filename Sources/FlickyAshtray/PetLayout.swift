import AppKit

struct RecordActionDebouncer: Equatable, Sendable {
    private(set) var lastAttemptUptime: TimeInterval?

    mutating func accept(nowUptime: TimeInterval, doubleClickInterval: TimeInterval) -> Bool {
        let previousAttempt = lastAttemptUptime
        // Rejected clicks also extend the sequence. A rapid triple-click must
        // remain one gesture instead of leaking another record after the first
        // accepted click's interval happens to expire.
        lastAttemptUptime = nowUptime
        if let previousAttempt,
           nowUptime - previousAttempt <= max(0, doubleClickInterval) {
            return false
        }
        return true
    }
}

enum PetLayout {
    // Keep enough room for the cigarette and hover hand-off without letting a
    // large transparent floating panel intercept unrelated desktop clicks.
    static let ashtraySurfaceSize = NSSize(width: 220, height: 180)
    static let surfaceSize = ashtraySurfaceSize
    static let ashtraySize = NSSize(width: 250, height: 202)

    // The note is deliberately a little shorter than the ashtray. Its native
    // window follows this geometry so transparent pixels never keep stealing
    // desktop clicks after the user switches styles.
    static let noteSurfaceSize = NSSize(width: 218, height: 148)
    static let noteCardRect = NSRect(x: 6, y: 8, width: 206, height: 132)
    static let noteActionButtonSize = NSSize(width: 44, height: 44)
    static let noteActionOffset = NSSize(width: 72, height: 40)
    static let noteActionCenter = NSPoint(
        x: noteSurfaceSize.width / 2 + noteActionOffset.width,
        y: noteSurfaceSize.height / 2 - noteActionOffset.height
    )

    static let minimumScale: CGFloat = 0.6
    static let maximumScale: CGFloat = 1
    static let resizeEdgeTolerance: CGFloat = 24
    static let dragIntentThreshold: CGFloat = 6

    static let cigaretteButtonSize = NSSize(width: 86, height: 70)
    static let cigaretteAngle = 122.0
    static let cigaretteOffset = NSSize(width: 42, height: -34)

    static let ashtrayHitRect = NSRect(x: 34, y: 27, width: 152, height: 120)

    static func normalizedScale(_ proposedScale: CGFloat) -> CGFloat {
        min(max(proposedScale, minimumScale), maximumScale)
    }

    static func noteCaptionFontSize(for proposedScale: CGFloat) -> CGFloat {
        max(12, 10.5 / normalizedScale(proposedScale))
    }

    static func noteSecondaryFontSize(for proposedScale: CGFloat) -> CGFloat {
        max(11, 9.5 / normalizedScale(proposedScale))
    }

    static func noteCountFontSize(for proposedScale: CGFloat) -> CGFloat {
        max(24, 16 / normalizedScale(proposedScale))
    }

    static func showsNoteSecondaryLine(for proposedScale: CGFloat) -> Bool {
        normalizedScale(proposedScale) >= 0.75
    }

    static func isDragIntent(from start: NSPoint, to end: NSPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= dragIntentThreshold
    }

    static func surfaceSize(for style: PetStyle) -> NSSize {
        switch style {
        case .ashtray: return ashtraySurfaceSize
        case .note: return noteSurfaceSize
        }
    }

    static func scaledSurfaceSize(
        for proposedScale: CGFloat,
        style: PetStyle = .ashtray
    ) -> NSSize {
        let scale = normalizedScale(proposedScale)
        let baseSize = surfaceSize(for: style)
        return NSSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
    }

    /// Converts a physical point in the resized panel back into the single base
    /// coordinate space used by the artwork and all interaction geometry.
    static func basePoint(fromScaledPoint point: NSPoint, scale proposedScale: CGFloat) -> NSPoint {
        let scale = normalizedScale(proposedScale)
        return NSPoint(x: point.x / scale, y: point.y / scale)
    }

    /// Keeps a pet that is parked at the menu-bar corner parked there. Away from
    /// that corner, resizing preserves the visual center instead of making the pet
    /// jump toward an arbitrary window edge.
    static func originAfterResize(
        from oldFrame: NSRect,
        to newSize: NSSize,
        in visibleFrame: NSRect,
        edgeTolerance: CGFloat = resizeEdgeTolerance
    ) -> NSPoint {
        let keepsRightEdge = abs(oldFrame.maxX - visibleFrame.maxX) <= edgeTolerance
        let keepsTopEdge = abs(oldFrame.maxY - visibleFrame.maxY) <= edgeTolerance

        let proposed = NSPoint(
            x: keepsRightEdge ? visibleFrame.maxX - newSize.width : oldFrame.midX - newSize.width / 2,
            y: keepsTopEdge ? visibleFrame.maxY - newSize.height : oldFrame.midY - newSize.height / 2
        )
        return clampedOrigin(proposed, windowSize: newSize, in: visibleFrame)
    }

    static func clampedOrigin(
        _ proposed: NSPoint,
        windowSize: NSSize,
        in visibleFrame: NSRect
    ) -> NSPoint {
        guard !visibleFrame.isEmpty else { return proposed }
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        return NSPoint(
            x: min(max(proposed.x, visibleFrame.minX), maximumX),
            y: min(max(proposed.y, visibleFrame.minY), maximumY)
        )
    }

    static func containsCigarette(_ point: NSPoint, padding: CGFloat = 4) -> Bool {
        let center = NSPoint(
            x: surfaceSize.width / 2 + cigaretteOffset.width,
            y: surfaceSize.height / 2 - cigaretteOffset.height
        )
        // SwiftUI's screen-space rotation becomes the opposite angle in AppKit's y-up space.
        let radians = -cigaretteAngle * .pi / 180
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        let localX = deltaX * cos(radians) + deltaY * sin(radians)
        let localY = -deltaX * sin(radians) + deltaY * cos(radians)
        return abs(localX) <= cigaretteButtonSize.width / 2 + padding
            && abs(localY) <= cigaretteButtonSize.height / 2 + padding
    }

    static func dragHitRect(for style: PetStyle) -> NSRect {
        switch style {
        case .ashtray: return ashtrayHitRect
        case .note: return noteCardRect
        }
    }

    static func containsPrimaryAction(
        _ point: NSPoint,
        style: PetStyle,
        padding: CGFloat = 4
    ) -> Bool {
        switch style {
        case .ashtray:
            return containsCigarette(point, padding: padding)
        case .note:
            let halfWidth = noteActionButtonSize.width / 2 + padding
            let halfHeight = noteActionButtonSize.height / 2 + padding
            return abs(point.x - noteActionCenter.x) <= halfWidth
                && abs(point.y - noteActionCenter.y) <= halfHeight
        }
    }
}
