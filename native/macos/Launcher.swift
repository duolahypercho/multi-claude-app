import AppKit

// These small, persistent apps keep each account's name and color in the Dock.
// Claude itself remains the original signed application, in its own process.
func runningLauncher(_ p: Profile) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first {
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
final class ProfileLauncherDelegate: NSObject, NSApplicationDelegate {
    let id: String
    var timer: Timer?
    var hasSeenClaude = false
    var launchDate = Date()
    init(_ id: String) { self.id = id }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Claude Account"
        let main = NSMenu(); let item = NSMenuItem(); let menu = NSMenu()
        menu.addItem(withTitle: "Open " + title, action: #selector(openClaude), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Manage Accounts…", action: #selector(manage), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Account Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu; main.addItem(item); NSApp.mainMenu = main
        openClaude()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkRunning() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openClaude(); return false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    @objc func openClaude() {
        do { let c = try configuration(); try launchOfficial(c, profile(c, id)) }
        catch { showError(error.localizedDescription); NSApp.terminate(nil) }
    }
    @objc func manage() {
        if let c = try? configuration(), let path = c.managerPath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
    func checkRunning() {
        guard let c = try? configuration(), (try? profile(c, id)) != nil else { NSApp.terminate(nil); return }
        if let app = runningInstances(c)[id] {
            hasSeenClaude = true
            // Launching is asynchronous: focus the intended instance when it appears.
            if Date().timeIntervalSince(launchDate) < 4 { app.activate(options: [.activateAllWindows]) }
        } else if hasSeenClaude || Date().timeIntervalSince(launchDate) > 30 { NSApp.terminate(nil) }
    }
}
var profileLauncherDelegate: ProfileLauncherDelegate?
func startProfileLauncher(_ id: String) {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    profileLauncherDelegate = ProfileLauncherDelegate(id); app.delegate = profileLauncherDelegate; app.run()
}
