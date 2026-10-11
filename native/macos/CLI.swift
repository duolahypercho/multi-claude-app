import AppKit
import Darwin

let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
var managementFD: Int32 = -1
func lockManagement() throws {
    try makeDirectory(rootPath())
    managementFD = open(rootPath() + "/management.lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
    guard managementFD >= 0, flock(managementFD, LOCK_EX | LOCK_NB) == 0 else { throw fail("Another profile-management command is running. Try again when it finishes.") }
}
func ownsBundle(_ path: String, profileID: String? = nil) -> Bool {
    if let attributes = try? fm.attributesOfItem(atPath: path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { return false }
    guard let info = bundleInfo(path), info["MultiClaudeRoot"] as? String == rootPath() else { return false }
    if let profileID { return info["CFBundleIdentifier"] as? String == helperID + ".profile" + profileID && info["MultiClaudeProfileID"] as? String == profileID }
    return info["CFBundleIdentifier"] as? String == helperID
}
func preflight(_ c: Configuration) throws {
    try validateConfig(c)
    let resolvedRoot = rootURL.resolvingSymlinksInPath().path
    for protected in [c.appPath, NSHomeDirectory() + "/Library/Application Support/Claude"] {
        let path = URL(fileURLWithPath: protected).resolvingSymlinksInPath().path
        guard resolvedRoot != path, !resolvedRoot.hasPrefix(path + "/") else { throw fail("The Multi Claude root must be outside the official app and its existing account data.") }
        let applications = URL(fileURLWithPath: c.applicationsDir).resolvingSymlinksInPath().path
        guard applications != path, !applications.hasPrefix(path + "/") else { throw fail("The account apps folder must be outside the official app and its existing account data.") }
    }
    for p in c.profiles {
        if fm.fileExists(atPath: p.launcherPath) && !ownsBundle(p.launcherPath, profileID: p.id) { throw fail("\(p.launcherPath) belongs to another app. Choose a different profile name.") }
    }
    let helper = rootPath() + "/Multi Claude Helper.app"
    if fm.fileExists(atPath: helper) && !ownsBundle(helper) { throw fail("An unrelated app exists at \(helper).") }
    let manager = c.applicationsDir + "/Multi Claude.app"
    if fm.fileExists(atPath: manager) && !ownsManager(manager) { throw fail("An unrelated app exists at \(manager).") }
    let cli = rootPath() + "/bin/multi-claude-app"
    if fm.fileExists(atPath: cli) && !fm.fileExists(atPath: rootPath() + "/config.json") { throw fail("The CLI destination already exists without a managed configuration.") }
}
func sourceExecutable() -> String { Bundle.main.executableURL?.path ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path }
func installCLI(_ c: Configuration) throws {
    try makeDirectory(rootPath() + "/bin")
    let source = sourceExecutable()
    if URL(fileURLWithPath: source).resolvingSymlinksInPath().path != URL(fileURLWithPath: c.cliPath).resolvingSymlinksInPath().path {
        // Atomic replacement also works while the installed executable is running.
        let temp = c.cliPath + "." + UUID().uuidString
        try fm.copyItem(atPath: source, toPath: temp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp)
        guard rename(temp, c.cliPath) == 0 else { try? fm.removeItem(atPath: temp); throw fail("Could not install the CLI.") }
    }
}
func installBundle(_ c: Configuration, _ p: Profile?, in stage: String) throws -> String {
    let path = stage + "/" + (p?.displayName ?? "Multi Claude Helper") + ".app"
    try makeDirectory(path + "/Contents/MacOS", mode: 0o755); try makeDirectory(path + "/Contents/Resources", mode: 0o755)
    try fm.copyItem(atPath: c.cliPath, toPath: path + "/Contents/MacOS/MultiClaude")
    var info: [String: Any] = ["CFBundleIdentifier": helperID + (p.map { ".profile" + $0.id } ?? ""), "CFBundleExecutable": "MultiClaude",
        "CFBundleName": p?.displayName ?? "Multi Claude Helper", "CFBundleDisplayName": p?.displayName ?? "Multi Claude Helper",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": releaseVersion, "CFBundleVersion": "4", "LSMinimumSystemVersion": "13.0",
        "LSUIElement": true, "CFBundleIconFile": "ProfileIcon.icns", "MultiClaudeRoot": rootPath(),
        "NSAppleEventsUsageDescription": "Send a Claude sign-in link to the running profile you choose."]
    if let p { info["MultiClaudeProfileID"] = p.id }
    else { info["CFBundleURLTypes"] = c.schemes.map { ["CFBundleURLName": "Claude profile routing", "CFBundleURLSchemes": [$0]] } }
    try writePlist(info, path + "/Contents/Info.plist")
    try renderProfileIcon(p?.iconColor ?? "orange", path + "/Contents/Resources/ProfileIcon.icns", tag: p.map(accountTag))
    guard try run("/usr/bin/codesign", ["--force", "--sign", "-", path]) == 0 else { throw fail("Could not sign the local launcher.") }
    return path
}
func installLaunchers(_ c: Configuration, ids: Set<String>? = nil) throws {
    try makeDirectory(c.applicationsDir, mode: 0o755)
    let stage = c.applicationsDir + "/.multi-claude-stage-" + UUID().uuidString
    try makeDirectory(stage); defer { try? fm.removeItem(atPath: stage) }
    let selected = c.profiles.filter { (ids == nil || ids!.contains($0.id)) && !nativeAppIsCurrent(c, $0) }
    for p in selected { try requireNativeAppClosed(p) }
    if c.integrationEnabled && !selected.isEmpty {
        guard try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", c.appPath]) == 0 else {
            throw fail("The official Claude signature failed verification. Reinstall Claude from its official source before creating account apps.")
        }
    }
    var staged = [String: String]()
    for p in selected { staged[p.id] = try installNativeProfile(c, p, in: stage) }
    for p in selected {
        stopLauncher(p)
        if fm.fileExists(atPath: p.launcherPath) {
            guard ownsBundle(p.launcherPath, profileID: p.id) else { throw fail("Refusing to replace an unrelated launcher.") }
            try fm.removeItem(atPath: p.launcherPath)
        }
        try fm.moveItem(atPath: staged[p.id]!, toPath: p.launcherPath)
        if c.integrationEnabled { _ = try run(lsregister, ["-f", p.launcherPath]) }
    }
}
func agentPath() -> String { NSHomeDirectory() + "/Library/LaunchAgents/" + helperID + ".plist" }
func stopHelper() {
    _ = try? run("/bin/launchctl", ["bootout", "gui/\(getuid())/" + helperID])
    for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL.path == rootPath() + "/Multi Claude Helper.app" { app.terminate() }
}
func installIntegration(_ c: inout Configuration) throws {
    guard c.integrationEnabled else { return }
    for scheme in c.schemes where c.previousHandlers[scheme] == nil {
        let existing = handler(scheme)
        c.previousHandlers[scheme] = existing.isEmpty || existing == helperID ? claudeID : existing
    }
    try save(c) // Record the original handlers before changing any of them.
    stopHelper()
    let stage = rootPath() + "/.helper-stage-" + UUID().uuidString
    try makeDirectory(stage); defer { try? fm.removeItem(atPath: stage) }
    let bundle = rootPath() + "/Multi Claude Helper.app"
    let staged = try installBundle(c, nil, in: stage)
    if fm.fileExists(atPath: bundle) { guard ownsBundle(bundle) else { throw fail("Refusing to replace an unrelated helper.") }; try fm.removeItem(atPath: bundle) }
    try fm.moveItem(atPath: staged, toPath: bundle)
    guard try run(lsregister, ["-f", bundle]) == 0 else { throw fail("macOS could not register the helper.") }
    for scheme in c.schemes { try setHandler(scheme, c.usesLoginChooser ? helperID : claudeID) }
    try makeDirectory(NSHomeDirectory() + "/Library/LaunchAgents", mode: 0o755)
    let agent = agentPath()
    if fm.fileExists(atPath: agent), let existingRoot = plist(agent)?["MultiClaudeRoot"] as? String, existingRoot != rootPath() { throw fail("A helper is installed for a different Multi Claude root. Uninstall it before enabling this root.") }
    if fm.fileExists(atPath: agent), plist(agent)?["MultiClaudeRoot"] == nil { throw fail("The LaunchAgent destination belongs to another app.") }
    try writePlist(["Label": helperID, "ProgramArguments": [bundle + "/Contents/MacOS/MultiClaude", "helper"], "RunAtLoad": true,
                    "KeepAlive": true, "ProcessType": "Interactive", "MultiClaudeRoot": rootPath()], agent)
    guard try run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agent]) == 0 else { throw fail("The helper was installed but could not start. Run multi-claude-app setup to repair it.") }
}
func ensureCLIShortcut(_ c: Configuration) throws {
    let directory = NSHomeDirectory() + "/.local/bin"; try makeDirectory(directory, mode: 0o755)
    let path = directory + "/multi-claude-app"
    if let destination = try? fm.destinationOfSymbolicLink(atPath: path) {
        guard destination == c.cliPath else { throw fail("~/.local/bin/multi-claude-app already points elsewhere.") }; return
    }
    guard !fm.fileExists(atPath: path) else { throw fail("~/.local/bin/multi-claude-app belongs to another file.") }
    try fm.createSymbolicLink(atPath: path, withDestinationPath: c.cliPath)
}
func setup(_ args: [String]) throws {
    let options = try Options(args, allowed: ["--app", "--count", "--applications"], flags: ["--no-integration"])
    guard options.rest.isEmpty else { throw fail("Unexpected setup argument.") }
    let count = try number(options.values["--count"] ?? "2", max: 100)
    let configExists = fm.fileExists(atPath: rootPath() + "/config.json")
    var c = configExists ? try configuration() : Configuration(appPath: "/Applications/Claude.app", cliPath: rootPath() + "/bin/multi-claude-app", applicationsDir: NSHomeDirectory() + "/Applications", schemes: ["claude"])
    if c.integrationEnabled && options.flags.contains("--no-integration") { throw fail("Run uninstall before switching an integrated installation to --no-integration.") }
    if let path = options.values["--app"] { guard path.hasPrefix("/") else { throw fail("--app needs an absolute path.") }; c.appPath = URL(fileURLWithPath: path).standardizedFileURL.path }
    if let path = options.values["--applications"] {
        guard path.hasPrefix("/"), c.profiles.isEmpty && c.removedProfiles.isEmpty else { throw fail("--applications needs an absolute path and can only be chosen on first setup.") }
        c.applicationsDir = URL(fileURLWithPath: path).standardizedFileURL.path
    }
    c.schemes = try checkApp(c.appPath)
    c.integrationEnabled = !options.flags.contains("--no-integration")
    if c.loginRoutingMode == nil { c.loginRoutingMode = "native" }
    while c.profiles.count < count { c.profiles.append(try newProfile(c)) }
    try preflight(c)
    if configExists {
        let newBootstrap = try fileDigest(sourceExecutable())
        let oldBootstrap = try? fileDigest(c.cliPath)
        for p in c.profiles where newBootstrap != oldBootstrap || !nativeAppIsCurrent(c, p) { try requireNativeAppClosed(p) }
    }
    // Check destinations before replacing launchers or registering protocols.
    if c.integrationEnabled, fm.fileExists(atPath: agentPath()), plist(agentPath())?["MultiClaudeRoot"] as? String != rootPath() { throw fail("Another Multi Claude installation owns the menu helper.") }
    let reopen = c.profiles.filter { runningLauncher($0) != nil }.map(\.id)
    let reopenManager = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == c.applicationsDir + "/Multi Claude.app" }
    try installCLI(c); try save(c)
    for p in c.profiles { try makeProfileDirectories(p) }
    try installLaunchers(c); try installManager(&c); try installIntegration(&c); try save(c)
    if c.integrationEnabled { try ensureCLIShortcut(c) }
    for id in reopen { try launch(c, profile(c, id)) }
    if reopenManager, let path = c.managerPath { _ = try run("/usr/bin/open", [path]) }
    print("Installed \(c.profiles.count) native Claude account apps in \(c.applicationsDir).")
    print("Primary keeps your existing account. Open each extra profile and sign in separately.")
    if runningInstances(c).values.contains(where: { $0.bundleURL?.standardizedFileURL.path == c.appPath }) {
        print("Existing Claude windows were kept open. Quit and reopen each account when ready to apply its tagged Dock icon.")
    }
}
struct Options {
    var values = [String: String](), flags = Set<String>(), rest = [String]()
    init(_ args: [String], allowed: Set<String> = [], flags allowedFlags: Set<String> = []) throws {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if allowed.contains(arg) {
                guard i + 1 < args.count, !args[i + 1].hasPrefix("--"), values[arg] == nil else { throw fail("\(arg) needs one value.") }
                values[arg] = args[i + 1]; i += 2
            } else if allowedFlags.contains(arg) { flags.insert(arg); i += 1 }
            else if arg.hasPrefix("--") { throw fail("Unknown option \(arg).") }
            else { rest.append(arg); i += 1 }
        }
    }
}
func number(_ value: String, max: Int) throws -> Int {
    guard let n = Int(value), n > 0, n <= max else { throw fail("Use a number from 1 to \(max).") }; return n
}
func add(_ args: [String]) throws {
    let options = try Options(args, allowed: ["--name", "--color", "--count"])
    guard options.rest.isEmpty else { throw fail("Use add --name Work --color teal.") }
    let count = try number(options.values["--count"] ?? "1", max: 100)
    guard count == 1 || options.values["--name"] == nil else { throw fail("Use --name when adding one profile.") }
    var c = try configuration(); var ids = Set<String>()
    for _ in 0..<count { let p = try newProfile(c, name: options.values["--name"], color: options.values["--color"]); c.profiles.append(p); ids.insert(p.id) }
    try preflight(c)
    try installLaunchers(c, ids: ids)
    for p in c.profiles where ids.contains(p.id) { try makeProfileDirectories(p) }
    try save(c)
    for p in c.profiles where ids.contains(p.id) { print("Added \(p.id): \(p.displayName)") }
}
func editProfile(_ id: String, name: String? = nil, color: String? = nil) throws {
    var c = try configuration(); let old = try profile(c, id)
    try requireNativeAppClosed(old)
    guard let index = c.profiles.firstIndex(where: { $0.id == id }) else { return }
    if let name { c.profiles[index].name = name; c.profiles[index].launcherPath = c.applicationsDir + "/" + launcherName(name) + ".app" }
    if let color { c.profiles[index].iconColor = color }
    try preflight(c)
    let reopen = stopLauncher(old)
    do { try installLaunchers(c, ids: [id]); try save(c) }
    catch { if reopen { try? launch(try configuration(), old) }; throw error }
    if old.launcherPath != c.profiles[index].launcherPath, ownsBundle(old.launcherPath, profileID: id) {
        if c.integrationEnabled { _ = try? run(lsregister, ["-u", old.launcherPath]) }
        try fm.removeItem(atPath: old.launcherPath)
    }
    if reopen { try launch(c, c.profiles[index]) }
    print("Updated \(id): \(c.profiles[index].displayName) (\(c.profiles[index].iconColor)).")
}
func removeProfile(_ id: String) throws {
    var c = try configuration(); let p = try profile(c, id)
    try requireNativeAppClosed(p)
    if fm.fileExists(atPath: p.launcherPath) { guard ownsBundle(p.launcherPath, profileID: id) else { throw fail("Refusing to remove an unrelated app.") } }
    c.profiles.removeAll { $0.id == id }; c.removedProfiles.append(p); try save(c)
    stopLauncher(p)
    if ownsBundle(p.launcherPath, profileID: id) {
        if c.integrationEnabled { _ = try? run(lsregister, ["-u", p.launcherPath]) }
        try fm.removeItem(atPath: p.launcherPath)
    }
    print("Removed \(p.displayName)'s app. Its data is preserved; restore with: multi-claude-app restore \(id).")
}
func restoreProfile(_ id: String) throws {
    var c = try configuration()
    guard let p = c.removedProfiles.first(where: { $0.id == id }) else { throw fail("No removed profile \(id).") }
    c.removedProfiles.removeAll { $0.id == id }; c.profiles.append(p); c.profiles.sort { Int($0.id)! < Int($1.id)! }
    try preflight(c); try installLaunchers(c, ids: [id]); try save(c); print("Restored \(p.displayName) with its original data.")
}
func list(_ args: [String]) throws {
    let options = try Options(args, flags: ["--removed", "--json"])
    guard options.rest.isEmpty else { throw fail("Unexpected list argument.") }
    let c = try configuration(); let rows = options.flags.contains("--removed") ? c.removedProfiles : c.profiles
    if options.flags.contains("--json") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(rows), encoding: .utf8)!); return
    }
    let running = runningInstances(c)
    for p in rows { print("\(p.id)  \(p.displayName)  [\(p.iconColor)]  \(running[p.id].map { "running (PID \($0.processIdentifier))" } ?? "closed")") }
    if rows.isEmpty { print("No \(options.flags.contains("--removed") ? "removed" : "active") profiles.") }
}
func doctor() throws {
    let c = try configuration(); _ = try checkApp(c.appPath); var problems = [String]()
    print("Claude: \(bundleInfo(c.appPath)?["CFBundleShortVersionString"] as? String ?? "unknown") at \(c.appPath)")
    if try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", c.appPath]) != 0 { problems.append("Official Claude signature verification failed.") }
    let running = runningInstances(c)
    for p in c.profiles {
        if !ownsBundle(p.launcherPath, profileID: p.id) { problems.append("Missing or unrelated launcher for \(p.displayName).") }
        else if isNativeProfileApp(p.launcherPath) {
            if try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", p.launcherPath]) != 0 { problems.append("Local signature verification failed for \(p.displayName).") }
            if !nativeAppIsCurrent(c, p) { problems.append("\(p.displayName) needs rebuilding from the current Claude app. Quit that account and run setup.") }
        }
        if !p.userDataDir.isEmpty && !fm.fileExists(atPath: p.userDataDir) { problems.append("Missing data folder for \(p.displayName).") }
        print("\(p.id) \(p.displayName): \(running[p.id].map { "running (PID \($0.processIdentifier))" } ?? "closed"); data: \(p.dataPath)")
    }
    if c.integrationEnabled {
        let helper = rootPath() + "/Multi Claude Helper.app"
        if !ownsBundle(helper) { problems.append("Menu helper is missing.") }
        let runningHelper = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == helper }
        if !runningHelper { problems.append("Menu helper is not running.") }
        for scheme in c.schemes {
            let owner = handler(scheme); print("\(scheme):// handler: \(owner)")
            let nativeOwners = Set([claudeID] + c.profiles.filter { ownsBundle($0.launcherPath, profileID: $0.id) && isNativeProfileApp($0.launcherPath) }.map { helperID + ".profile" + $0.id })
            if c.usesLoginChooser ? owner != helperID : !nativeOwners.contains(owner) { problems.append("\(scheme) login routing does not match the selected mode.") }
        }
        print("Login mode: \(c.usesLoginChooser ? "Choose profile for browser callbacks" : "Claude native sign-in")")
    } else { print("Login routing and automatic startup are disabled (--no-integration).") }
    if let managerPath = c.managerPath, !ownsManager(managerPath) { problems.append("The Multi Claude manager app is missing.") }
    if !problems.isEmpty { throw fail(problems.joined(separator: "\n") + "\nRun multi-claude-app setup to repair the integration.") }
    print("Profile folders, launchers, and enabled integration checks passed.")
    print("Native copies use local signatures. Second-account sign-in, enterprise SSO, passkeys, and Code/Cowork compatibility require verification.")
}
func uninstall() throws {
    var c = try configuration()
    for p in c.profiles + c.removedProfiles { try requireNativeAppClosed(p) }
    if c.integrationEnabled {
        stopHelper()
        let managedOwners = Set([helperID] + (c.profiles + c.removedProfiles).map { helperID + ".profile" + $0.id })
        for scheme in c.schemes where managedOwners.contains(handler(scheme)) { try setHandler(scheme, c.previousHandlers[scheme] ?? claudeID) }
        if plist(agentPath())?["MultiClaudeRoot"] as? String == rootPath() { try fm.removeItem(atPath: agentPath()) }
    }
    for p in c.profiles + c.removedProfiles where ownsBundle(p.launcherPath, profileID: p.id) {
        stopLauncher(p)
        _ = try? run(lsregister, ["-u", p.launcherPath]); try fm.removeItem(atPath: p.launcherPath)
    }
    let helper = rootPath() + "/Multi Claude Helper.app"
    if ownsBundle(helper) { _ = try? run(lsregister, ["-u", helper]); try fm.removeItem(atPath: helper) }
    if let manager = c.managerPath, ownsManager(manager) {
        for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL.path == manager { app.terminate() }
        _ = try? run(lsregister, ["-u", manager]); try fm.removeItem(atPath: manager)
    }
    c.integrationEnabled = false; try save(c)
    print("Removed launchers and login routing. All profile data and the CLI are preserved. Run setup to reinstall.")
}
func loginRouting(_ mode: String) throws {
    guard ["native", "chooser"].contains(mode) else { throw fail("Use login-routing native or login-routing chooser.") }
    var c = try configuration(); c.loginRoutingMode = mode; try save(c)
    if c.integrationEnabled { for scheme in c.schemes { try setHandler(scheme, c.usesLoginChooser ? helperID : claudeID) } }
    print(mode == "native" ? "Claude now handles its native sign-in. Retry sign-in from the intended account window." : "Browser callbacks now ask you to choose a running profile. Restart sign-in from the intended account window.")
}
func prompt(_ text: String, default fallback: String) -> String {
    print("\(text) [\(fallback)]: ", terminator: ""); fflush(stdout)
    let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return answer.isEmpty ? fallback : answer
}
func wizard() throws {
    guard isatty(STDIN_FILENO) != 0 else { throw fail("Wizard needs a terminal. Use setup --count 2 instead.") }
    if !fm.fileExists(atPath: rootPath() + "/config.json") { try setup(["--count", prompt("Total accounts", default: "2")]); return }
    try list([])
    print("\n1 Setup / repair  2 Add  3 Rename  4 Color  5 Remove  6 Restore  7 Quit")
    switch prompt("Action", default: "7") {
    case "1": try setup(["--count", prompt("Total active accounts", default: String(try configuration().profiles.count))])
    case "2": try add(["--name", prompt("Profile name", default: "Work"), "--color", prompt("Icon color (\(iconColors.joined(separator: ", ")))", default: "teal")])
    case "3": try editProfile(prompt("Profile number", default: "2"), name: prompt("New name", default: "Work"))
    case "4": try editProfile(prompt("Profile number", default: "2"), color: prompt("Color", default: "teal"))
    case "5": try removeProfile(prompt("Profile number", default: "2"))
    case "6": try list(["--removed"]); try restoreProfile(prompt("Profile number", default: "2"))
    default: break
    }
}
let help = """
Multi Claude App — independent Claude desktop profiles on macOS

  setup [--count N] [--app /path/to/Claude.app]   Install or repair (default: 2)
  wizard                                        Guided profile management
  list [--removed] [--json]                      Show profiles and status
  launch ID                                     Open or focus one profile
  add [--name Work] [--color teal] [--count N]    Add fresh profiles
  rename ID NAME                                Rename a launcher
  icon ID COLOR                                 Change its icon color
  icons                                         Show available colors
  remove ID / restore ID                        Preserve and restore profile data
  doctor                                        Check profiles and login routing
  gui                                           Open the account manager
  login-routing native|chooser                   Select native sign-in or callback chooser
  preview                                       Preview the login chooser
  uninstall                                     Remove integration, keep all data

Global: --root /absolute/path (also MULTI_CLAUDE_ROOT)
Development setup: --no-integration --applications /absolute/path
"""
func cli(_ command: String, _ args: [String]) throws {
    switch command {
    case "help", "--help", "-h": print(help)
    case "version", "--version": print("multi-claude-app " + releaseVersion)
    case "setup": try setup(args)
    case "wizard": guard args.isEmpty else { throw fail("wizard takes no arguments.") }; try wizard()
    case "add": try add(args)
    case "list": try list(args)
    case "icons": guard args.isEmpty else { throw fail("icons takes no arguments.") }; print(iconColors.joined(separator: ", "))
    case "rename", "icon": guard args.count == 2 else { throw fail("Use \(command) ID \(command == "rename" ? "NAME" : "COLOR").") }; try editProfile(args[0], name: command == "rename" ? args[1] : nil, color: command == "icon" ? args[1] : nil)
    case "remove", "restore": guard args.count == 1 else { throw fail("Use \(command) ID.") }; if command == "remove" { try removeProfile(args[0]) } else { try restoreProfile(args[0]) }
    case "launch": guard args.count == 1 else { throw fail("Use launch ID.") }; let c = try configuration(); try launch(c, profile(c, args[0]))
    case "doctor": guard args.isEmpty else { throw fail("doctor takes no arguments.") }; try doctor()
    case "gui": guard args.isEmpty else { throw fail("gui takes no arguments.") }; startManager()
    case "login-routing": guard args.count == 1 else { throw fail("Use login-routing native or login-routing chooser.") }; try loginRouting(args[0])
    case "package-manager": guard args.count == 1, args[0].hasPrefix("/") else { throw fail("package-manager needs an absolute output path.") }; try packageManager(source: sourceExecutable(), destination: args[0], root: nil)
    case "uninstall": guard args.isEmpty else { throw fail("uninstall takes no arguments.") }; try uninstall()
    case "preview":
        guard args.isEmpty else { throw fail("preview takes no arguments.") }
        let c = try configuration()
        if c.integrationEnabled { guard try run("/usr/bin/open", [rootPath() + "/Multi Claude Helper.app"]) == 0 else { throw fail("Could not open the chooser preview.") } }
        else { startHelper(preview: true) }
    case "deliver":
        guard args.count == 1 else { throw fail("Use deliver ID with the URL on standard input.") }
        let c = try configuration(); let p = try profile(c, args[0])
        let raw = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard validURI(raw, schemes: c.schemes) else { throw fail("Invalid Claude link.") }
        guard let app = runningInstances(c)[p.id] else { throw fail("Open the selected profile before delivering its link.") }
        do { try deliver(raw, to: app); app.activate(options: [.activateAllWindows]) } catch { throw fail("The link could not be delivered to that profile. It was not sent to another account.") }
    case "helper": guard args.isEmpty else { throw fail("helper takes no arguments.") }; startHelper(preview: false)
    default: throw fail("Unknown command \(command). Run multi-claude-app help.")
    }
}
