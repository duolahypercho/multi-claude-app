import AppKit
import CryptoKit
import Darwin
import Security

let releaseVersion = "1.3.0"
let nativeBootstrap = "MultiClaudeNative"

func signingInfo(_ path: String) -> [String: Any] {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return [:] }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return [:] }
    return info as? [String: Any] ?? [:]
}
func fileDigest(_ path: String) throws -> String {
    SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
}
func sourceStamp(_ c: Configuration) -> String {
    let info = bundleInfo(c.appPath) ?? [:]
    let hash = signingInfo(c.appPath)[kSecCodeInfoUnique as String] as? Data ?? Data()
    return "\(info["CFBundleShortVersionString"] ?? ""):\(info["CFBundleVersion"] ?? ""):" + hash.map { String(format: "%02x", $0) }.joined()
}
func isNativeProfileApp(_ path: String) -> Bool { bundleInfo(path)?["MultiClaudeNative"] as? Bool == true }
func nativeExecutable(_ path: String) -> String? {
    guard let name = bundleInfo(path)?["MultiClaudeNativeExecutable"] as? String, !name.isEmpty, !name.contains("/") else { return nil }
    return path + "/Contents/MacOS/" + name
}
func nativeAppIsCurrent(_ c: Configuration, _ p: Profile) -> Bool {
    guard ownsBundle(p.launcherPath, profileID: p.id), let info = bundleInfo(p.launcherPath), isNativeProfileApp(p.launcherPath) else { return false }
    return info["MultiClaudeSourceStamp"] as? String == sourceStamp(c)
        && info["MultiClaudeBootstrapDigest"] as? String == (try? fileDigest(c.cliPath))
        && info["MultiClaudeIconColor"] as? String == p.iconColor
        && info["CFBundleDisplayName"] as? String == p.displayName
        && info["MultiClaudeRelease"] as? String == releaseVersion
}
func runningNativeApp(_ path: String) -> NSRunningApplication? {
    guard let executable = nativeExecutable(path) else { return nil }
    return NSWorkspace.shared.runningApplications.first {
        guard !$0.isTerminated, $0.bundleURL?.standardizedFileURL.path == path, let cmd = commandLine($0.processIdentifier) else { return false }
        // Also protect the brief startup interval before the bootstrap execs.
        let bootstrap = path + "/Contents/MacOS/" + nativeBootstrap
        return cmd.hasPrefix(executable + " ") || cmd == bootstrap || cmd.hasPrefix(bootstrap + " ")
    }
}
func requireNativeAppClosed(_ p: Profile) throws {
    guard runningNativeApp(p.launcherPath) == nil else { throw fail("Quit \(p.displayName) with Command-Q before changing or removing its app. Its account data will be kept.") }
}

func installNativeProfile(_ c: Configuration, _ p: Profile, in stage: String) throws -> String {
    let path = stage + "/" + p.displayName + ".app"
    // APFS clones share unchanged file blocks. Fall back on other filesystems.
    if try run("/bin/cp", ["-cR", c.appPath, path]) != 0 {
        if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
        guard try run("/usr/bin/ditto", [c.appPath, path]) == 0 else { throw fail("Could not copy the installed Claude app.") }
    }
    var info = bundleInfo(path) ?? [:]
    guard let executable = info["CFBundleExecutable"] as? String, !executable.contains("/"), executable != nativeBootstrap else { throw fail("Unsupported Claude executable name.") }
    // Keep CFBundleName: Electron uses it to locate Claude Helper.app.
    info["CFBundleIdentifier"] = helperID + ".profile" + p.id
    info["CFBundleDisplayName"] = p.displayName
    info["CFBundleExecutable"] = nativeBootstrap
    info["CFBundleIconFile"] = "ProfileIcon.icns"
    info.removeValue(forKey: "CFBundleIconName")
    info["LSUIElement"] = false
    // Keep native authentication schemes. Chooser mode overrides their owner centrally.
    info["MultiClaudeRoot"] = rootPath(); info["MultiClaudeProfileID"] = p.id
    info["MultiClaudeNative"] = true; info["MultiClaudeNativeExecutable"] = executable
    info["MultiClaudeIconColor"] = p.iconColor; info["MultiClaudeRelease"] = releaseVersion
    info["MultiClaudeSourceStamp"] = sourceStamp(c)
    info["MultiClaudeBootstrapDigest"] = try fileDigest(c.cliPath)
    try writePlist(info, path + "/Contents/Info.plist")
    let resources = path + "/Contents/Resources"
    try makeDirectory(resources, mode: 0o755)
    // The vendor asset catalog overrides .icns icons on recent macOS versions.
    let catalog = resources + "/Assets.car"
    if fm.fileExists(atPath: catalog) { try fm.removeItem(atPath: catalog) }
    try renderProfileIcon(p.iconColor, resources + "/ProfileIcon.icns", tag: accountTag(p))
    if let oldIcon = bundleInfo(c.appPath)?["CFBundleIconFile"] as? String, !oldIcon.contains("/"), oldIcon != "ProfileIcon.icns" {
        let destination = resources + "/" + oldIcon
        if fm.fileExists(atPath: destination) { try fm.removeItem(atPath: destination) }
        try fm.copyItem(atPath: resources + "/ProfileIcon.icns", toPath: destination)
    }
    // Vendor updates would remove the bootstrap and its profile selection. Keep
    // the copied Squirrel installer from running, including manual update checks.
    let shipIt = path + "/Contents/Frameworks/Squirrel.framework/Resources/ShipIt"
    if fm.fileExists(atPath: shipIt) { try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shipIt) }
    try fm.copyItem(atPath: c.cliPath, toPath: path + "/Contents/MacOS/" + nativeBootstrap)

    // A local signer cannot claim Anthropic's team or restricted Keychain groups.
    let original = signingInfo(c.appPath)[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    var entitlements = original.filter { $0.key.hasPrefix("com.apple.security.") && $0.key != "com.apple.security.application-groups" }
    entitlements["com.apple.security.cs.allow-jit"] = true
    entitlements["com.apple.security.cs.disable-library-validation"] = true
    let entitlementsPath = stage + "/entitlements-" + p.id + ".plist"
    try writePlist(entitlements, entitlementsPath)
    // Sign the real native executable, then the bootstrap bundle. Frameworks stay untouched.
    guard try run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlementsPath, path + "/Contents/MacOS/" + executable]) == 0,
          try run("/usr/bin/codesign", ["--force", "--sign", "-", path]) == 0,
          try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", path]) == 0 else { throw fail("Could not sign and verify the local Claude copy. The official app is unchanged.") }
    return path
}

func execNativeProfile(_ id: String) throws {
    let c = try configuration(); let p = try profile(c, id)
    let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
    guard bundlePath == p.launcherPath, ownsBundle(bundlePath, profileID: id), let executable = nativeExecutable(bundlePath) else { throw fail("This account app does not match its configuration. Run setup to repair it.") }
    // Claude's own single-instance lock handles a repeated Finder launch.
    try makeProfileDirectories(p)
    for key in ["CLAUDE_USER_DATA_DIR", "CLAUDE_CDP_AUTH", "CLAUDE_CONFIG_DIR", "ELECTRON_RUN_AS_NODE"] { unsetenv(key) }
    if !p.codeConfigDir.isEmpty { setenv("CLAUDE_CONFIG_DIR", p.codeConfigDir, 1) }
    setenv("DISABLE_AUTOUPDATER", "1", 1)
    // Explicit even for Primary: a custom app name must never select new storage.
    let values = [executable, "--user-data-dir=" + p.dataPath]
    var argv = values.map { strdup($0) } + [nil]
    defer { for value in argv { free(value) } }
    // Complete the macOS launch handshake before replacing the process image.
    // Otherwise LaunchServices can keep tracking the startup executable.
    NSApplication.shared.finishLaunching()
    // Replace this process. There is no resident launcher or second Dock tile.
    _ = argv.withUnsafeMutableBufferPointer { execv(executable, $0.baseAddress!) }
    throw fail("Could not start the native Claude process. Run doctor to check this account app.")
}
