import AppKit
import Darwin

if let bundleRoot = Bundle.main.object(forInfoDictionaryKey: "MultiClaudeRoot") as? String {
    rootURL = URL(fileURLWithPath: bundleRoot, isDirectory: true).standardizedFileURL
}
var args = Array(CommandLine.arguments.dropFirst())
do {
    if args.first == "--root" {
        guard args.count >= 2, args[1].hasPrefix("/") else { throw fail("--root needs an absolute path.") }
        rootURL = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL; args.removeFirst(2)
    }
    if let id = Bundle.main.object(forInfoDictionaryKey: "MultiClaudeProfileID") as? String {
        if Bundle.main.object(forInfoDictionaryKey: "MultiClaudeNative") as? Bool == true {
            do { try execNativeProfile(id) } catch { showError(error.localizedDescription); exit(1) }
        } else { startProfileLauncher(id) }
    } else if Bundle.main.object(forInfoDictionaryKey: "MultiClaudeManager") as? Bool == true && args.isEmpty {
        startManager()
    } else {
        let command = args.first ?? (Bundle.main.bundleIdentifier == helperID ? "helper" : "help")
        if ["setup", "wizard", "add", "rename", "icon", "remove", "restore", "uninstall", "login-routing"].contains(command) { try lockManagement() }
        defer { if managementFD >= 0 { flock(managementFD, LOCK_UN); close(managementFD) } }
        try cli(command, Array(args.dropFirst()))
    }
} catch {
    // Do not print underlying event errors: they may contain credentials.
    let description = (error as NSError).domain == "MultiClaude" ? error.localizedDescription : "The operation failed. Check file permissions and config.json, then run doctor."
    FileHandle.standardError.write(Data(("multi-claude-app: " + description + "\n").utf8)); exit(1)
}
