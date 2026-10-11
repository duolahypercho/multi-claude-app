import AppKit

// Retained for migration: stop only our old persistent launchers, never Claude.
func runningLauncher(_ p: Profile) -> NSRunningApplication? {
    guard !isNativeProfileApp(p.launcherPath) else { return nil }
    return NSWorkspace.shared.runningApplications.first {
        $0.bundleIdentifier == helperID + ".profile" + p.id && $0.bundleURL?.standardizedFileURL.path == p.launcherPath
    }
}
@discardableResult func stopLauncher(_ p: Profile) -> Bool {
    guard let app = runningLauncher(p) else { return false }
    app.terminate()
    // Wait for the wrapper only, never terminate its Claude process.
    for _ in 0..<30 where !app.isTerminated { Thread.sleep(forTimeInterval: 0.05) }
    return true
}
func startProfileLauncher(_ id: String) {
    // Finder shortcuts launch Claude once and exit without creating a Dock tile.
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    do { let c = try configuration(); try launch(c, profile(c, id)) }
    catch { showError(error.localizedDescription); exit(1) }
}
