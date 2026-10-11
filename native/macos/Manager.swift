import AppKit
import UniformTypeIdentifiers

let managerID = helperID + ".manager"

func ownsManager(_ path: String) -> Bool {
    guard let info = bundleInfo(path) else { return false }
    return info["CFBundleIdentifier"] as? String == managerID && info["MultiClaudeRoot"] as? String == rootPath()
}
func packageManager(source: String, destination: String, root: String?) throws {
    if fm.fileExists(atPath: destination) {
        guard let info = bundleInfo(destination), info["CFBundleIdentifier"] as? String == managerID,
              info["MultiClaudeManager"] as? Bool == true,
              (root == nil || info["MultiClaudeRoot"] as? String == root) else { throw fail("Refusing to replace an unrelated app at \(destination).") }
        try fm.removeItem(atPath: destination)
    }
    try makeDirectory(destination + "/Contents/MacOS", mode: 0o755)
    try makeDirectory(destination + "/Contents/Resources", mode: 0o755)
    try fm.copyItem(atPath: source, toPath: destination + "/Contents/MacOS/MultiClaude")
    var info: [String: Any] = ["CFBundleIdentifier": managerID, "CFBundleExecutable": "MultiClaude", "CFBundleName": "Multi Claude",
        "CFBundleDisplayName": "Multi Claude", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2",
        "CFBundleIconFile": "ProfileIcon.icns", "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": true, "MultiClaudeManager": true]
    if let root { info["MultiClaudeRoot"] = root }
    try writePlist(info, destination + "/Contents/Info.plist")
    try renderProfileIcon("teal", destination + "/Contents/Resources/ProfileIcon.icns", tag: "M")
    guard try run("/usr/bin/codesign", ["--force", "--sign", "-", destination]) == 0 else { throw fail("Could not sign the manager app.") }
}
func installManager(_ c: inout Configuration) throws {
    let path = c.applicationsDir + "/Multi Claude.app"
    let stage = c.applicationsDir + "/.multi-claude-manager-" + UUID().uuidString
    try makeDirectory(stage); defer { try? fm.removeItem(atPath: stage) }
    let staged = stage + "/Multi Claude.app"
    try packageManager(source: c.cliPath, destination: staged, root: rootPath())
    if fm.fileExists(atPath: path) {
        guard ownsManager(path) else { throw fail("Refusing to replace an unrelated manager app.") }
        for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL.path == path { app.terminate() }
        try fm.removeItem(atPath: path)
    }
    try fm.moveItem(atPath: staged, toPath: path); c.managerPath = path
    if c.integrationEnabled { _ = try run(lsregister, ["-f", path]) }
}

func managerLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
    label.lineBreakMode = .byTruncatingMiddle; label.translatesAutoresizingMaskIntoConstraints = false; return label
}
func managerButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action); button.bezelStyle = .rounded
    button.translatesAutoresizingMaskIntoConstraints = false; return button
}
final class AccountDocumentView: NSView { override var isFlipped: Bool { true } }
final class AccountCard: NSView {
    let profile: Profile
    init(_ p: Profile, running: Bool, target: ManagerDelegate) {
        profile = p; super.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.cornerRadius = 14
        layer?.borderWidth = 1; layer?.borderColor = (palette[p.iconColor] ?? .separatorColor).withAlphaComponent(0.35).cgColor
        let accent = NSView(); accent.wantsLayer = true; accent.layer?.backgroundColor = (palette[p.iconColor] ?? .controlAccentColor).cgColor
        accent.layer?.cornerRadius = 3; accent.translatesAutoresizingMaskIntoConstraints = false; addSubview(accent)
        let image = NSImageView(); image.image = profileImage(p, size: 48); image.translatesAutoresizingMaskIntoConstraints = false; addSubview(image)
        let title = managerLabel(p.name, size: 18, weight: .semibold); addSubview(title)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = managerLabel(running ? "Running · click Open to switch" : "Closed · opens a separate Claude profile", size: 12, color: .secondaryLabelColor); addSubview(detail)
        let state = managerLabel(running ? "● Running" : "○ Closed", size: 11, weight: .medium, color: running ? .systemGreen : .secondaryLabelColor); addSubview(state)
        let openButton = managerButton("Open Claude", target: target, action: #selector(ManagerDelegate.openAccount(_:)))
        openButton.identifier = NSUserInterfaceItemIdentifier(p.id); addSubview(openButton)
        openButton.setAccessibilityLabel("Open Claude for " + p.name)
        let more = NSPopUpButton(frame: .zero, pullsDown: true); more.translatesAutoresizingMaskIntoConstraints = false; more.bezelStyle = .rounded
        let menu = NSMenu(); menu.addItem(withTitle: "Manage", action: nil, keyEquivalent: "")
        let rename = menu.addItem(withTitle: "Rename / Set Email Label…", action: #selector(ManagerDelegate.renameAccount(_:)), keyEquivalent: ""); rename.target = target; rename.representedObject = p.id
        let signIn = menu.addItem(withTitle: "Retry Native Sign-in…", action: #selector(ManagerDelegate.retrySignIn(_:)), keyEquivalent: ""); signIn.target = target; signIn.representedObject = p.id
        let colors = NSMenu(); for color in iconColors {
            let item = colors.addItem(withTitle: color.capitalized, action: #selector(ManagerDelegate.changeColor(_:)), keyEquivalent: "")
            item.target = target; item.representedObject = [p.id, color]; item.state = color == p.iconColor ? .on : .off
            item.image = iconImage(color, size: 32); item.image?.size = NSSize(width: 16, height: 16)
        }
        let colorItem = menu.addItem(withTitle: "Icon Color", action: nil, keyEquivalent: ""); colorItem.submenu = colors
        menu.addItem(.separator())
        let remove = menu.addItem(withTitle: "Remove Profile…", action: #selector(ManagerDelegate.removeAccount(_:)), keyEquivalent: ""); remove.target = target; remove.representedObject = p.id
        more.menu = menu; more.setAccessibilityLabel("Manage " + p.name); addSubview(more)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 112), accent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), accent.centerYAnchor.constraint(equalTo: centerYAnchor), accent.widthAnchor.constraint(equalToConstant: 4), accent.heightAnchor.constraint(equalToConstant: 72),
            image.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 14), image.centerYAnchor.constraint(equalTo: centerYAnchor), image.widthAnchor.constraint(equalToConstant: 48), image.heightAnchor.constraint(equalToConstant: 48),
            title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 16), title.topAnchor.constraint(equalTo: topAnchor, constant: 22), title.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -18),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5), detail.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -16),
            state.leadingAnchor.constraint(equalTo: title.leadingAnchor), state.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 7),
            more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), more.centerYAnchor.constraint(equalTo: centerYAnchor), more.widthAnchor.constraint(equalToConstant: 92),
            openButton.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -8), openButton.centerYAnchor.constraint(equalTo: centerYAnchor), openButton.widthAnchor.constraint(equalToConstant: 112)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
}

final class ManagerDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var stack: NSStackView!
    var status: NSTextField!
    var countLabel: NSTextField!
    var addButton: NSButton!
    var restoreButton: NSPopUpButton!
    var timer: Timer?
    var busy = false
    var lastState = ""
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu(); buildWindow(); reload()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in if self?.busy == false { self?.reload() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func buildMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); let app = NSMenu()
        app.addItem(withTitle: "About Multi Claude", action: #selector(about), keyEquivalent: "").target = self
        app.addItem(.separator()); app.addItem(withTitle: "Quit Multi Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app; main.addItem(appItem)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Add Account…", action: #selector(addAccount), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        fileMenu.addItem(withTitle: "Check Setup…", action: #selector(checkSetup), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Show App Launchers", action: #selector(showLaunchers), keyEquivalent: "").target = self
        let routing = NSMenu(); let routingItem = fileMenu.addItem(withTitle: "Login Links", action: nil, keyEquivalent: "")
        for (title, mode) in [("Claude Native Sign-in", "native"), ("Choose Profile for Browser Callbacks", "chooser")] {
            let item = routing.addItem(withTitle: title, action: #selector(changeLoginMode(_:)), keyEquivalent: ""); item.target = self; item.representedObject = mode
        }
        routingItem.submenu = routing
        file.submenu = fileMenu; main.addItem(file)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Multi Claude"; window.minSize = NSSize(width: 720, height: 420); window.isReleasedWhenClosed = false; window.delegate = self
        let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; window.contentView = view
        let title = managerLabel("Your Claude accounts", size: 28, weight: .bold); view.addSubview(title)
        let subtitle = managerLabel("Separate sign-ins. Your own names and Dock colors.", size: 14, color: .secondaryLabelColor); view.addSubview(subtitle)
        addButton = managerButton("+ Add Account", target: self, action: #selector(addAccount)); view.addSubview(addButton)
        countLabel = managerLabel("", size: 12, weight: .medium, color: .secondaryLabelColor); view.addSubview(countLabel)
        restoreButton = NSPopUpButton(frame: .zero, pullsDown: true); restoreButton.translatesAutoresizingMaskIntoConstraints = false; restoreButton.bezelStyle = .rounded; view.addSubview(restoreButton)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let document = AccountDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        status = managerLabel("", size: 12, color: .secondaryLabelColor); view.addSubview(status)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), title.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), addButton.centerYAnchor.constraint(equalTo: title.centerYAnchor), addButton.widthAnchor.constraint(equalToConstant: 132), title.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -20),
            countLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor), countLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            restoreButton.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), restoreButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 14), scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -18),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor), status.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
    func reload(force: Bool = false) {
        guard !busy else { return }
        guard fm.fileExists(atPath: rootPath() + "/config.json") else { showWelcome(); return }
        do {
            let c = try configuration(); let running = runningInstances(c)
            let state = c.profiles.map { "\($0.id):\($0.name):\($0.iconColor):\(running[$0.id]?.processIdentifier ?? 0)" }.joined(separator: "|") + c.removedProfiles.map(\.id).joined(separator: ",") + (c.loginRoutingMode ?? "native")
            guard force || state != lastState else { return }; lastState = state
            clearCards(); countLabel.stringValue = "\(c.profiles.count) accounts · \(running.filter { key, _ in c.profiles.contains(where: { $0.id == key }) }.count) running"
            for p in c.profiles { let card = AccountCard(p, running: running[p.id] != nil, target: self); stack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            addButton.title = "+ Add Account"; addButton.action = #selector(addAccount)
            let menu = NSMenu(); menu.addItem(withTitle: "Restore Profile", action: nil, keyEquivalent: "")
            for p in c.removedProfiles { let item = menu.addItem(withTitle: p.name, action: #selector(restoreAccount(_:)), keyEquivalent: ""); item.target = self; item.representedObject = p.id }
            restoreButton.menu = menu; restoreButton.isHidden = c.removedProfiles.isEmpty
            status.stringValue = c.usesLoginChooser ? "Login links: choose the account where you started sign-in. File → Login Links changes the mode." : "Native sign-in enabled. Sign-in trouble? Choose Manage → Retry Native Sign-in."
            if let routing = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "Login Links")?.submenu {
                for item in routing.items { item.state = (item.representedObject as? String == (c.usesLoginChooser ? "chooser" : "native")) ? .on : .off }
            }
        } catch { status.stringValue = "Setup needs attention. Use File → Check Setup for details." }
    }
    func clearCards() { for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() } }
    func showWelcome() {
        guard lastState != "welcome" else { return }; lastState = "welcome"; clearCards(); restoreButton.isHidden = true
        countLabel.stringValue = "Get started with two profiles"
        let text = NSTextField(wrappingLabelWithString: "Keep your existing Claude account as Primary, then add a fresh Secondary account. Give every account a name or email label and a different colored app icon.")
        text.font = .systemFont(ofSize: 18); text.textColor = .secondaryLabelColor; text.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(text); text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addButton.title = "Set Up Accounts"; addButton.action = #selector(setupAccounts); status.stringValue = "Uses the official Claude desktop app installed on this Mac."
    }
    func execute(_ args: [String], message: String, success: (() -> Void)? = nil) {
        guard !busy else { return }; busy = true; addButton.isEnabled = false; status.stringValue = message
        let executable = (try? configuration().cliPath) ?? sourceExecutable(); let arguments = ["--root", rootPath()] + args
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; let pipe = Pipe(); process.standardError = pipe
            var problem: String?
            do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if process.terminationStatus != 0 { problem = String(data: data, encoding: .utf8) ?? "The operation failed." }
            } catch { problem = "The operation could not start. Reinstall Multi Claude to repair it." }
            DispatchQueue.main.async {
                self.busy = false; self.addButton.isEnabled = true; self.reload(force: true)
                if let problem { showError(problem) } else { success?() }
            }
        }
    }
    @objc func setupAccounts() {
        var path = "/Applications/Claude.app"
        if (try? checkApp(path)) == nil {
            let panel = NSOpenPanel(); panel.title = "Choose the official Claude app"; panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let selected = panel.url else { return }; path = selected.path
        }
        execute(["setup", "--count", "2", "--app", path], message: "Setting up your account apps…")
    }
    @objc func addAccount() {
        if (try? configuration()) == nil { setupAccounts(); return }
        let alert = NSAlert(); alert.messageText = "Add a Claude account"; alert.informativeText = "Choose a name or email label and an icon color. Then sign in to that account in the Claude window."
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 74))
        let name = NSTextField(frame: NSRect(x: 0, y: 44, width: 350, height: 26)); name.placeholderString = "Account name or email"; accessory.addSubview(name)
        let color = NSPopUpButton(frame: NSRect(x: 0, y: 4, width: 180, height: 26)); color.addItems(withTitles: iconColors.map { $0.capitalized }); accessory.addSubview(color)
        if let c = try? configuration() { color.selectItem(at: c.profiles.count % iconColors.count) }
        alert.accessoryView = accessory; alert.addButton(withTitle: "Add & Open"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = Set((try? configuration().profiles.map(\.id)) ?? [])
        var args = ["add", "--color", iconColors[color.indexOfSelectedItem]]; if !label.isEmpty { args += ["--name", label] }
        execute(args, message: "Creating a separate account profile…") {
            if let c = try? configuration(), let p = c.profiles.first(where: { !previous.contains($0.id) }) { do { try launch(c, p) } catch { showError(error.localizedDescription) } }
        }
    }
    @objc func openAccount(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        do { let c = try configuration(); try launch(c, profile(c, id)); status.stringValue = "Opened \(try profile(c, id).name). Complete sign-in in its Claude window." }
        catch { showError(error.localizedDescription) }
    }
    @objc func renameAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let c = try? configuration(), let p = try? profile(c, id) else { return }
        let alert = NSAlert(); alert.messageText = "Name this account"; alert.informativeText = "Use an account name or email so you can recognize its app icon. This changes the label, not the sign-in."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 26)); field.stringValue = p.name; alert.accessoryView = field
        alert.addButton(withTitle: "Save Name"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        execute(["rename", id, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)], message: "Updating account name…")
    }
    @objc func changeColor(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        execute(["icon", pair[0], pair[1]], message: "Updating the app icon…")
    }
    @objc func changeLoginMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        execute(["login-routing", mode], message: "Updating sign-in handling…") {
            showError(mode == "native" ? "Claude handles authentication directly. Cancel any old sign-in attempt, then retry from the intended account window.\n\nIf a browser callback opens another account, use File → Login Links → Choose Profile for Browser Callbacks and retry." : "Browser callbacks will ask you to choose a running account. Pick the profile where you started sign-in.\n\nIf Claude's native sign-in sheet stalls, switch back to Claude Native Sign-in.")
        }
    }
    @objc func retrySignIn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        execute(["login-routing", "native"], message: "Preparing Claude's native sign-in…") {
            do { let c = try configuration(); let p = try profile(c, id)
                showError("Native sign-in is ready for \(p.name).\n\nCancel the previous attempt in Claude, then click its sign-in button again. Choose the intended account in the browser or authentication sheet.\n\nIf the callback opens Primary instead, enable the profile chooser from File → Login Links and retry.")
                try launch(c, p)
            } catch { showError(error.localizedDescription) }
        }
    }
    @objc func removeAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let c = try? configuration(), let p = try? profile(c, id) else { return }
        let alert = NSAlert(); alert.messageText = "Remove \(p.name)?"; alert.informativeText = "Its launcher is removed. All account data is kept, and you can restore this profile later. Its open Claude window stays open."
        alert.addButton(withTitle: "Remove Profile"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        execute(["remove", id], message: "Removing the launcher and keeping its data…")
    }
    @objc func restoreAccount(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { execute(["restore", id], message: "Restoring your account launcher…") } }
    @objc func refresh() { reload(force: true) }
    @objc func showLaunchers() { if let c = try? configuration() { NSWorkspace.shared.open(URL(fileURLWithPath: c.applicationsDir)) } }
    @objc func checkSetup() { execute(["doctor"], message: "Checking your installation…") { showError("Your profile folders, app launchers, and enabled login routing passed their checks.") } }
    @objc func about() { showError("Multi Claude 1.1\n\nSeparate Claude profiles with account labels and colored Dock launchers. The official Claude desktop app is unchanged.\n\nInspired by am-will/multi-codex-app (MIT).") }
}
var managerDelegate: ManagerDelegate?
func startManager() {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    managerDelegate = ManagerDelegate(); app.delegate = managerDelegate; app.run()
}
