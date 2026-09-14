import AppKit

enum VisualAssets {
    static let ashtray = load("ashtray")
    static let sprinkle = load("ash-sprinkle")
    static let full = load("ash-full")
    static let overLimit = load("ash-over")
    static let filthy = load("ash-filthy")
    static let cigarette = load("cigarette")

    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }
}
