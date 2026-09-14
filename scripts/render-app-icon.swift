#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let ashtrayURL = root.appendingPathComponent("assets/ashtray.png")
let cigaretteURL = root.appendingPathComponent("assets/cigarette.png")
let outputURL = root.appendingPathComponent("Packaging/AppIcon-1024.png")

guard let ashtray = NSImage(contentsOf: ashtrayURL),
      let cigarette = NSImage(contentsOf: cigaretteURL) else {
    fatalError("Missing icon source assets")
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon bitmap context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
defer { NSGraphicsContext.restoreGraphicsState() }

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let tileRect = NSRect(x: 62, y: 62, width: 900, height: 900)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 202, yRadius: 202)

NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
tileShadow.shadowBlurRadius = 30
tileShadow.shadowOffset = NSSize(width: 0, height: -18)
tileShadow.set()
NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.36, alpha: 1).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

let background = NSGradient(
    colorsAndLocations:
        (NSColor(calibratedRed: 0.52, green: 0.61, blue: 0.71, alpha: 1), 0),
        (NSColor(calibratedRed: 0.29, green: 0.37, blue: 0.47, alpha: 1), 0.54),
        (NSColor(calibratedRed: 0.19, green: 0.25, blue: 0.33, alpha: 1), 1)
)!
background.draw(in: tilePath, angle: -90)

NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
let topGlow = NSBezierPath(ovalIn: NSRect(x: 106, y: 500, width: 812, height: 610))
NSColor.white.withAlphaComponent(0.075).setFill()
topGlow.fill()
NSGraphicsContext.restoreGraphicsState()

let innerBorder = NSBezierPath(roundedRect: tileRect.insetBy(dx: 2, dy: 2), xRadius: 200, yRadius: 200)
innerBorder.lineWidth = 4
NSColor.white.withAlphaComponent(0.13).setStroke()
innerBorder.stroke()

// A quiet ground shadow keeps the dark blue-gray object legible at Dock sizes.
let groundShadow = NSBezierPath(ovalIn: NSRect(x: 205, y: 190, width: 615, height: 170))
NSColor.black.withAlphaComponent(0.25).setFill()
groundShadow.fill()

ashtray.draw(
    in: NSRect(x: 74, y: 92, width: 876, height: 876),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

// The filter stays outside the rim while the ember points into the bowl,
// matching the desktop pet rather than becoming a generic smoking symbol.
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: 702, yBy: 632)
transform.rotate(byDegrees: 257)
transform.translateX(by: -702, yBy: -632)
transform.concat()
cigarette.draw(
    in: NSRect(x: 500, y: 472, width: 404, height: 318),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode app icon")
}
try png.write(to: outputURL, options: .atomic)
