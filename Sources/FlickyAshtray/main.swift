import AppKit

MainActor.assumeIsolated {
    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
    NSApplication.shared.run()
    withExtendedLifetime(appDelegate) {}
}
