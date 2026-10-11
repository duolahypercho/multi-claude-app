import AppKit
import CoreServices
import Darwin

let helperID = "local.multi-claude-app"
let claudeID = "com.anthropic.claudefordesktop"
let iconColors = ["orange", "blue", "purple", "teal", "yellow"]
let fm = FileManager.default
var rootURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MULTI_CLAUDE_ROOT"] ?? NSHomeDirectory() + "/Library/Application Support/Multi Claude", isDirectory: true).standardizedFileURL
func rootPath() -> String { rootURL.path }
func fail(_ message: String) -> NSError { NSError(domain: "MultiClaude", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

struct Profile: Codable {
    var id: String
    var name: String
    var userDataDir: String
    var codeConfigDir: String
    var iconColor: String
    var launcherPath: String
    var displayName: String { launcherName(name) }
    var dataPath: String { userDataDir.isEmpty ? NSHomeDirectory() + "/Library/Application Support/Claude" : userDataDir }
}
struct Configuration: Codable {
    var version = 1
    var appPath: String
    var cliPath: String
    var applicationsDir: String
    var schemes: [String]
    var previousHandlers: [String: String] = [:]
    var integrationEnabled = false
    // Older installs have no mode. Prefer Claude's native authentication flow.
    var loginRoutingMode: String?
    var managerPath: String?
    var profiles: [Profile] = []
    var removedProfiles: [Profile] = []
    var usesLoginChooser: Bool { loginRoutingMode == "chooser" }
}
func launcherName(_ name: String) -> String {
    let lower = name.lowercased()
    return lower.hasPrefix("claude ") || lower.hasPrefix("claude (") ? name : "Claude " + name
}
func validateNames(_ profiles: [Profile]) throws {
    var seen = Set<String>()
    for p in profiles {
        guard !p.name.isEmpty, p.name == p.name.trimmingCharacters(in: .whitespacesAndNewlines), p.name.count <= 80,
              !p.name.contains(where: { $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }),
              p.name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|")) == nil,
              !p.name.hasSuffix("."), p.name.lowercased() != "claude" else { throw fail("Use a name of 1–80 characters without path separators or reserved characters.") }
        let key = p.displayName.precomposedStringWithCanonicalMapping.lowercased()
        guard seen.insert(key).inserted else { throw fail("Another profile already uses \(p.displayName).") }
        guard iconColors.contains(p.iconColor) else { throw fail("Unknown icon color. Choose: \(iconColors.joined(separator: ", ")).") }
    }
}
func plist(_ path: String) -> [String: Any]? {
    guard let data = fm.contents(atPath: path) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}
func bundleInfo(_ path: String) -> [String: Any]? { plist(path + "/Contents/Info.plist") }
func checkApp(_ path: String) throws -> [String] {
    guard let info = bundleInfo(path), info["CFBundleIdentifier"] as? String == claudeID,
          let executable = info["CFBundleExecutable"] as? String,
          !executable.contains("/"), fm.isExecutableFile(atPath: path + "/Contents/MacOS/" + executable) else {
        throw fail("Install the official Claude desktop app, or pass --app /absolute/path/to/Claude.app.")
    }
    let entries = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
    let schemes = entries.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
    return Array(Set(schemes.filter { $0 == "claude" || $0.hasPrefix("msauth.") })).sorted()
}
func configuration() throws -> Configuration {
    let path = rootURL.appendingPathComponent("config.json")
    guard fm.fileExists(atPath: path.path) else { throw fail("No setup found. Run multi-claude-app setup first.") }
    let c = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: path))
    try validateConfig(c)
    return c
}
func validateConfig(_ c: Configuration) throws {
    guard c.version == 1, c.appPath.hasPrefix("/"), c.cliPath == rootPath() + "/bin/multi-claude-app", c.applicationsDir.hasPrefix("/"),
          c.profiles.count <= 100, c.schemes.contains("claude"),
          c.schemes.allSatisfy({ $0 == "claude" || $0 == "msauth." + claudeID }) else { throw fail("Unsupported or damaged configuration. Keep config.json and restore a backup.") }
    try validateNames(c.profiles)
    if let mode = c.loginRoutingMode, !["native", "chooser"].contains(mode) { throw fail("Invalid login routing mode.") }
    if let managerPath = c.managerPath, managerPath != c.applicationsDir + "/Multi Claude.app" { throw fail("Invalid manager app path.") }
    var ids = Set<String>(), dirs = [String]()
    for p in c.profiles + c.removedProfiles {
        guard let id = Int(p.id), id > 0, id <= 1_000_000, String(id) == p.id, ids.insert(p.id).inserted,
              p.launcherPath == c.applicationsDir + "/" + p.displayName + ".app", iconColors.contains(p.iconColor) else { throw fail("Invalid profile configuration.") }
        if p.id == "1" {
            guard p.userDataDir.isEmpty, p.codeConfigDir.isEmpty else { throw fail("Primary must use Claude's original data folder.") }
        } else {
            let base = rootURL.appendingPathComponent("profiles/" + p.id).path
            guard p.userDataDir == base + "/desktop", p.codeConfigDir == base + "/claude-code" else { throw fail("Extra profiles must use their own managed folders.") }
            for path in [rootPath() + "/profiles", base, p.userDataDir, p.codeConfigDir] {
                if let attributes = try? fm.attributesOfItem(atPath: path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw fail("Refusing a redirected profile directory.") }
            }
        }
        dirs.append(URL(fileURLWithPath: p.dataPath).resolvingSymlinksInPath().path)
    }
    for i in dirs.indices { for j in dirs.indices where j > i {
        guard dirs[i] != dirs[j], !dirs[i].hasPrefix(dirs[j] + "/"), !dirs[j].hasPrefix(dirs[i] + "/") else { throw fail("Profile data folders overlap. Refusing to mix accounts.") }
    } }
}
func makeDirectory(_ path: String, mode: Int = 0o700) throws {
    if let attributes = try? fm.attributesOfItem(atPath: path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw fail("Refusing a symbolic link at \(path).") }
    try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: mode])
}
func makeProfileDirectories(_ p: Profile) throws {
    guard !p.userDataDir.isEmpty else { return }
    try makeDirectory(rootPath() + "/profiles")
    try makeDirectory(rootPath() + "/profiles/" + p.id)
    try makeDirectory(p.userDataDir); try makeDirectory(p.codeConfigDir)
}
func save(_ c: Configuration) throws {
    try validateConfig(c)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let path = rootURL.appendingPathComponent("config.json")
    try encoder.encode(c).write(to: path, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
}
func writePlist(_ value: [String: Any], _ path: String) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}
func profile(_ c: Configuration, _ id: String) throws -> Profile {
    guard let p = c.profiles.first(where: { $0.id == id }) else { throw fail("Profile \(id) is not active. Use list --removed to find removed profiles.") }
    return p
}
func newProfile(_ c: Configuration, name: String? = nil, color: String? = nil) throws -> Profile {
    guard c.profiles.count < 100 else { throw fail("At most 100 active profiles are supported.") }
    let id = (c.profiles + c.removedProfiles).compactMap { Int($0.id) }.max().map { $0 + 1 } ?? 1
    let defaultName = id == 1 ? "Primary" : id == 2 ? "Secondary" : "Account \(id)"
    let base = rootPath() + "/profiles/\(id)"
    let p = Profile(id: String(id), name: name ?? defaultName, userDataDir: id == 1 ? "" : base + "/desktop",
                    codeConfigDir: id == 1 ? "" : base + "/claude-code", iconColor: color ?? iconColors[(id - 1) % iconColors.count],
                    launcherPath: c.applicationsDir + "/" + launcherName(name ?? defaultName) + ".app")
    try validateNames(c.profiles + [p]); return p
}
func handler(_ scheme: String) -> String { LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String? ?? "" }
func setHandler(_ scheme: String, _ id: String) throws {
    guard LSSetDefaultHandlerForURLScheme(scheme as CFString, id as CFString) == noErr else { throw fail("macOS could not change the \(scheme) link handler.") }
}
func commandLine(_ pid: pid_t) -> String? {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-ww", "-p", String(pid), "-o", "command="]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
func runningInstances(_ c: Configuration) -> [String: NSRunningApplication] {
    let profiles = c.profiles + c.removedProfiles
    let apps = NSWorkspace.shared.runningApplications.filter { app in
        guard !app.isTerminated, let path = app.bundleURL?.standardizedFileURL.path else { return false }
        if path == c.appPath { return true }
        return profiles.contains { $0.launcherPath == path && isNativeProfileApp(path) }
    }
    let commands = apps.compactMap { app -> (NSRunningApplication, String)? in
        guard let cmd = commandLine(app.processIdentifier) else { return nil }; return (app, cmd)
    }
    var result = [String: NSRunningApplication]()
    for p in profiles {
        let matches = commands.filter { app, cmd in
            let native = app.bundleURL?.standardizedFileURL.path == p.launcherPath
            if native {
                guard let executable = nativeExecutable(p.launcherPath), cmd.hasPrefix(executable + " ") else { return false }
            }
            if !native && p.userDataDir.isEmpty { return !cmd.contains("--user-data-dir") && !cmd.contains("--user-data-path") }
            guard let range = cmd.range(of: "--user-data-dir=" + p.dataPath) else { return false }
            let rest = cmd[range.upperBound...]; return rest.isEmpty || rest.hasPrefix(" --")
        }
        if matches.count == 1 { result[p.id] = matches[0].0 }
    }
    return result
}
func validURI(_ raw: String, schemes: [String]) -> Bool {
    guard !raw.isEmpty, raw.utf8.count <= 65536, !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
          let u = URLComponents(string: raw), let scheme = u.scheme?.lowercased(), schemes.contains(scheme),
          !(u.host ?? "").isEmpty, u.user == nil, u.password == nil, u.port == nil, u.url != nil else { return false }
    return true
}
func deliver(_ raw: String, to app: NSRunningApplication) throws {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(0x4755524c), eventID: AEEventID(0x4755524c), targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier), returnID: AEReturnID(-1), transactionID: AETransactionID(0))
    event.setParam(NSAppleEventDescriptor(string: raw), forKeyword: AEKeyword(0x2d2d2d2d))
    _ = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 5)
}
@discardableResult func run(_ executable: String, _ arguments: [String], quiet: Bool = true, environment: [String: String]? = nil) throws -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    if let environment { p.environment = environment }
    if quiet { p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice }
    try p.run(); p.waitUntilExit(); return p.terminationStatus
}
@discardableResult func launchOfficial(_ c: Configuration, _ p: Profile) throws -> NSRunningApplication? {
    _ = try checkApp(c.appPath)
    if let app = runningInstances(c)[p.id] {
        if c.integrationEnabled && !c.usesLoginChooser {
            let owner = app.bundleURL?.standardizedFileURL.path == c.appPath ? claudeID : helperID + ".profile" + p.id
            for scheme in c.schemes { try setHandler(scheme, owner) }
        }
        app.activate(options: [.activateAllWindows]); return app
    }
    try makeProfileDirectories(p)
    let native = isNativeProfileApp(p.launcherPath) && ownsBundle(p.launcherPath, profileID: p.id)
    if native && c.integrationEnabled && !c.usesLoginChooser { for scheme in c.schemes { try setHandler(scheme, helperID + ".profile" + p.id) } }
    var args = ["-n", native ? p.launcherPath : c.appPath]
    var env = ProcessInfo.processInfo.environment
    for key in ["CLAUDE_USER_DATA_DIR", "CLAUDE_CDP_AUTH", "CLAUDE_CONFIG_DIR", "ELECTRON_RUN_AS_NODE"] { env.removeValue(forKey: key) }
    if !native {
        if !p.codeConfigDir.isEmpty { args += ["--env", "CLAUDE_CONFIG_DIR=" + p.codeConfigDir] }
        if !p.userDataDir.isEmpty { args += ["--args", "--user-data-dir=" + p.userDataDir] }
    }
    guard try run("/usr/bin/open", args, environment: env) == 0 else { throw fail("Could not open \(p.displayName).") }
    // Claude re-registers its schemes at startup. The menu helper reclaims them too.
    if c.integrationEnabled && c.usesLoginChooser { for scheme in c.schemes { try? setHandler(scheme, helperID) } }
    return nil
}
func launch(_ c: Configuration, _ p: Profile) throws {
    // Launch directly. A second visible wrapper app adds an unwanted Dock icon.
    try launchOfficial(c, p)
}
func showError(_ text: String) {
    let a = NSAlert(); a.messageText = "Multi Claude"; a.informativeText = text; a.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true); a.runModal()
}
