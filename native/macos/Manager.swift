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
        "CFBundleDisplayName": "Multi Claude", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": releaseVersion, "CFBundleVersion": "4",
        "CFBundleIconFile": "ProfileIcon.icns", "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": true, "MultiClaudeManager": true, "LSUIElement": true]
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
final class UsageBarView: NSView {
    var percent: Double? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.24).setFill(); track.fill()
        guard let percent else { return }
        let width = bounds.width * min(1, max(0, percent / 100))
        guard width > 0 else { return }
        let radius = min(bounds.height / 2, width / 2)
        let fill = NSBezierPath(roundedRect: NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height), xRadius: radius, yRadius: radius)
        (percent >= 100 ? NSColor.systemRed : NSColor.controlAccentColor).setFill(); fill.fill()
    }
}
final class UsageMeterRow: NSView {
    init(title: String, meter: UsageMeter?, message: String) {
        super.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = managerLabel(title, size: 12, weight: .medium)
        let detailText = meter.flatMap { usageResetDescription($0.resetsAt) } ?? message
        let detailLabel = managerLabel(detailText, size: 10, color: .secondaryLabelColor)
        let percentage = NSTextField(labelWithString: meter.map { String(format: "%.0f%% used", $0.percent) } ?? "—")
        percentage.font = .systemFont(ofSize: 12); percentage.alignment = .right
        percentage.textColor = (meter?.percent ?? 0) >= 100 ? .systemRed : (meter == nil ? .secondaryLabelColor : .labelColor)
        percentage.translatesAutoresizingMaskIntoConstraints = false
        let bar = UsageBarView(); bar.percent = meter?.percent; bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setAccessibilityLabel(title + ", " + (meter.map { String(format: "%.0f percent used", $0.percent) } ?? message))
        addSubview(titleLabel); addSubview(detailLabel); addSubview(bar); addSubview(percentage)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor), titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            titleLabel.widthAnchor.constraint(equalToConstant: 200),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            detailLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),
            percentage.trailingAnchor.constraint(equalTo: trailingAnchor), percentage.centerYAnchor.constraint(equalTo: centerYAnchor), percentage.widthAnchor.constraint(equalToConstant: 78),
            bar.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14), bar.trailingAnchor.constraint(equalTo: percentage.leadingAnchor, constant: -14),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor), bar.heightAnchor.constraint(equalToConstant: 8)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)" ) }
}
func usageResetDescription(_ value: String?) -> String? {
    guard let value else { return nil }
    let iso = ISO8601DateFormatter()
    let date = iso.date(from: value) ?? {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: value)
    }()
    guard let date else { return nil }
    let formatter = DateFormatter(); formatter.timeZone = .current; formatter.dateFormat = "EEE h:mm a"
    return "Resets \(formatter.string(from: date))"
}

final class AccountCard: NSView {
    let profile: Profile
    init(_ p: Profile, running: Bool, needsReopen: Bool, usage: ProfileUsageSnapshot?, target: ManagerDelegate) {
        profile = p; super.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.cornerRadius = 14
        layer?.borderWidth = 1; layer?.borderColor = (palette[p.iconColor] ?? .separatorColor).withAlphaComponent(0.35).cgColor
        let header = NSView(); header.translatesAutoresizingMaskIntoConstraints = false; addSubview(header)
        let accent = NSView(); accent.wantsLayer = true; accent.layer?.backgroundColor = (palette[p.iconColor] ?? .controlAccentColor).cgColor
        accent.layer?.cornerRadius = 3; accent.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(accent)
        let image = NSImageView(); image.image = profileImage(p, size: 40); image.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(image)
        let title = managerLabel(p.name, size: 16, weight: .semibold); header.addSubview(title)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = managerLabel(needsReopen ? "Quit and reopen this account to apply its Dock tag" : running ? "Running · click Open to switch" : "Closed · opens a separate Claude profile", size: 12, color: .secondaryLabelColor); header.addSubview(detail)
        let openButton = managerButton("Open Claude", target: target, action: #selector(ManagerDelegate.openAccount(_:)))
        openButton.identifier = NSUserInterfaceItemIdentifier(p.id); header.addSubview(openButton)
        openButton.setAccessibilityLabel("Open Claude for " + p.name)
        let usageButton = managerButton("Usage page", target: target, action: #selector(ManagerDelegate.openUsage(_:)))
        usageButton.identifier = NSUserInterfaceItemIdentifier(p.id); header.addSubview(usageButton)
        usageButton.setAccessibilityLabel("Open the official Claude Usage page for " + p.name)
        let more = NSPopUpButton(frame: .zero, pullsDown: true); more.translatesAutoresizingMaskIntoConstraints = false; more.bezelStyle = .rounded
        let menu = NSMenu(); menu.addItem(withTitle: "Manage", action: nil, keyEquivalent: "")
        let rename = menu.addItem(withTitle: "Rename / Set Email Label…", action: #selector(ManagerDelegate.renameAccount(_:)), keyEquivalent: ""); rename.target = target; rename.representedObject = p.id
        let signIn = menu.addItem(withTitle: "Retry Native Sign-in…", action: #selector(ManagerDelegate.retrySignIn(_:)), keyEquivalent: ""); signIn.target = target; signIn.representedObject = p.id
        let colors = NSMenu(); for color in iconColors {
            let item = colors.addItem(withTitle: color.capitalized, action: #selector(ManagerDelegate.changeColor(_:)), keyEquivalent: "")
            item.target = target; item.representedObject = [p.id, color]; item.state = color == p.iconColor ? .on : .off
            item.image = iconImage(color, size: 32, tag: ""); item.image?.size = NSSize(width: 16, height: 16)
        }
        let colorItem = menu.addItem(withTitle: "Tag Color", action: nil, keyEquivalent: ""); colorItem.submenu = colors
        menu.addItem(.separator())
        let remove = menu.addItem(withTitle: "Remove Profile…", action: #selector(ManagerDelegate.removeAccount(_:)), keyEquivalent: ""); remove.target = target; remove.representedObject = p.id
        more.menu = menu; more.setAccessibilityLabel("Manage " + p.name); header.addSubview(more)
        var rows: [(String, UsageMeter?)] = [("Current session", usage?.fiveHour), ("This week", usage?.weekly)]
        rows += (usage?.scopedWeekly ?? []).map { ($0.title, $0) }
        let rowStack = NSStackView(); rowStack.orientation = .vertical; rowStack.alignment = .leading; rowStack.spacing = 3
        rowStack.translatesAutoresizingMaskIntoConstraints = false; addSubview(rowStack)
        let placeholder = usage?.message ?? "Usage is loading…"
        for (name, meter) in rows {
            let row = UsageMeterRow(title: name, meter: meter, message: meter == nil ? placeholder : "")
            rowStack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        }
        let cardHeight = 10 + 52 + 8 + CGFloat(rows.count) * 36 + CGFloat(max(0, rows.count - 1)) * 2 + 10
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: cardHeight),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10), header.heightAnchor.constraint(equalToConstant: 52),
            accent.leadingAnchor.constraint(equalTo: header.leadingAnchor), accent.centerYAnchor.constraint(equalTo: header.centerYAnchor), accent.widthAnchor.constraint(equalToConstant: 4), accent.heightAnchor.constraint(equalToConstant: 42),
            image.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 10), image.centerYAnchor.constraint(equalTo: header.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 38), image.heightAnchor.constraint(equalToConstant: 38),
            title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10), title.topAnchor.constraint(equalTo: header.topAnchor, constant: 6), title.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -10),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2), detail.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -10),
            more.trailingAnchor.constraint(equalTo: header.trailingAnchor), more.centerYAnchor.constraint(equalTo: header.centerYAnchor), more.widthAnchor.constraint(equalToConstant: 82),
            usageButton.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -6), usageButton.centerYAnchor.constraint(equalTo: header.centerYAnchor), usageButton.widthAnchor.constraint(equalToConstant: 88),
            openButton.trailingAnchor.constraint(equalTo: usageButton.leadingAnchor, constant: -6), openButton.centerYAnchor.constraint(equalTo: header.centerYAnchor), openButton.widthAnchor.constraint(equalToConstant: 102),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28), rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rowStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
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
    var modeControl: NSSegmentedControl!
    var operationIndicator: NSProgressIndicator!
    var chooserPreviewMode = false
    var chooserPreviewButtons: [ProfileButton] = []
    var chooserPreviewDoneButton: NSButton?
    var chooserPreviewSelection: String?
    var timer: Timer?
    var busy = false
    var lastState = ""
    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(helperProfilesDidChange(_:)), name: helperProfilesDidChangeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(usageDidRefresh(_:)), name: usageDidRefreshNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showChooserPreviewFromHelper(_:)), name: helperRequestsChooserPreviewNotification, object: nil)
        buildMenu(); buildWindow(); reload()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in if self?.busy == false { self?.reload() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    @objc func helperProfilesDidChange(_ note: Notification) { reload(force: true) }
    @objc func usageDidRefresh(_ note: Notification) { reload(force: true) }
    func buildMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); let app = NSMenu()
        app.addItem(withTitle: "About Multi Claude", action: #selector(about), keyEquivalent: "").target = self
        app.addItem(.separator()); app.addItem(withTitle: "Quit Multi Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app; main.addItem(appItem)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Add Account…", action: #selector(addAccount), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        fileMenu.addItem(withTitle: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Check Setup…", action: #selector(checkSetup), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Show Account Apps", action: #selector(showLaunchers), keyEquivalent: "").target = self
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
        let subtitle = managerLabel("Separate sign-ins. Account names and colored tags.", size: 14, color: .secondaryLabelColor); view.addSubview(subtitle)
        addButton = managerButton("+ Add Account", target: self, action: #selector(addAccount)); view.addSubview(addButton)
        modeControl = NSSegmentedControl(labels: ["Accounts", "Chooser Preview"], trackingMode: .selectOne, target: self, action: #selector(changeMode(_:)))
        modeControl.translatesAutoresizingMaskIntoConstraints = false; modeControl.selectedSegment = 0; view.addSubview(modeControl)
        modeControl.setAccessibilityLabel("Project manager view")
        countLabel = managerLabel("", size: 12, weight: .medium, color: .secondaryLabelColor); view.addSubview(countLabel)
        restoreButton = NSPopUpButton(frame: .zero, pullsDown: true); restoreButton.translatesAutoresizingMaskIntoConstraints = false; restoreButton.bezelStyle = .rounded; view.addSubview(restoreButton)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let document = AccountDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        status = managerLabel("", size: 12, color: .secondaryLabelColor); view.addSubview(status)
        operationIndicator = NSProgressIndicator(); operationIndicator.style = .spinning; operationIndicator.controlSize = .small
        operationIndicator.isDisplayedWhenStopped = false; operationIndicator.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(operationIndicator)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), title.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), addButton.centerYAnchor.constraint(equalTo: title.centerYAnchor), addButton.widthAnchor.constraint(equalToConstant: 132), title.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -20),
            modeControl.leadingAnchor.constraint(equalTo: title.leadingAnchor), modeControl.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18), modeControl.widthAnchor.constraint(equalToConstant: 230),
            countLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor), countLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 10),
            restoreButton.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), restoreButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 14), scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -18),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor), status.trailingAnchor.constraint(lessThanOrEqualTo: operationIndicator.leadingAnchor, constant: -8), status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            operationIndicator.trailingAnchor.constraint(equalTo: addButton.trailingAnchor), operationIndicator.centerYAnchor.constraint(equalTo: status.centerYAnchor), operationIndicator.widthAnchor.constraint(equalToConstant: 16), operationIndicator.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    func reload(force: Bool = false) {
        guard !busy else { return }
        guard fm.fileExists(atPath: rootPath() + "/config.json") else { showWelcome(); return }
        do {
            let c = try configuration(); let running = runningInstances(c)
            let state = c.profiles.map { "\($0.id):\($0.name):\($0.iconColor):\(running[$0.id]?.processIdentifier ?? 0)" }.joined(separator: "|") + c.removedProfiles.map(\.id).joined(separator: ",") + (c.loginRoutingMode ?? "native") + (chooserPreviewMode ? ":preview" : ":accounts")
            guard force || state != lastState else { return }; lastState = state
            clearCards(); countLabel.stringValue = "\(c.profiles.count) accounts · \(running.filter { key, _ in c.profiles.contains(where: { $0.id == key }) }.count) running"
            modeControl.selectedSegment = chooserPreviewMode ? 1 : 0
            countLabel.isHidden = chooserPreviewMode
            restoreButton.isHidden = chooserPreviewMode || c.removedProfiles.isEmpty
            if chooserPreviewMode {
                renderChooserPreview(c)
                status.stringValue = "Preview only · choosing Done sends no sign-in link."
                updateLoginModeMenu(c)
                return
            }
            let usage = UsageCacheFile.load().profiles
            for p in c.profiles {
                let legacy = running[p.id]?.bundleURL?.standardizedFileURL.path == c.appPath
                let card = AccountCard(p, running: running[p.id] != nil, needsReopen: legacy,
                                       usage: usage[p.id], target: self)
                stack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            addButton.title = "+ Add Account"; addButton.action = #selector(addAccount)
            let menu = NSMenu(); menu.addItem(withTitle: "Restore Profile", action: nil, keyEquivalent: "")
            for p in c.removedProfiles { let item = menu.addItem(withTitle: p.name, action: #selector(restoreAccount(_:)), keyEquivalent: ""); item.target = self; item.representedObject = p.id }
            restoreButton.menu = menu; restoreButton.isHidden = c.removedProfiles.isEmpty
            status.stringValue = c.usesLoginChooser ? "Login links: choose the account where you started sign-in. File → Login Links changes the mode." : "Native sign-in enabled. Sign-in trouble? Choose Manage → Retry Native Sign-in."
            updateLoginModeMenu(c)
        } catch { status.stringValue = "Setup needs attention. Use File → Check Setup for details." }
    }
    func updateLoginModeMenu(_ c: Configuration) {
        if let routing = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "Login Links")?.submenu {
            for item in routing.items { item.state = (item.representedObject as? String == (c.usesLoginChooser ? "chooser" : "native")) ? .on : .off }
        }
    }
    func renderChooserPreview(_ c: Configuration) {
        chooserPreviewButtons.removeAll(); chooserPreviewSelection = nil; chooserPreviewDoneButton = nil
        let title = managerLabel("Choose a Claude profile", size: 22, weight: .bold); stack.addArrangedSubview(title); title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let subtitle = NSTextField(wrappingLabelWithString: "This is how the sign-in chooser appears. Select an account to see the selected state; this preview never sends a link.")
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = .secondaryLabelColor; subtitle.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(subtitle); subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if c.profiles.isEmpty {
            let empty = managerLabel("Add an account to preview the chooser.", size: 14, color: .secondaryLabelColor)
            stack.addArrangedSubview(empty); empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for p in c.profiles {
            let button = ProfileButton(p, available: true, subtitle: "Preview only · no link will be sent")
            button.target = self; button.action = #selector(selectChooserPreviewProfile(_:)); stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; chooserPreviewButtons.append(button)
        }
        let done = managerButton("Done", target: self, action: #selector(finishChooserPreview)); done.isEnabled = false; chooserPreviewDoneButton = done
        let cancel = managerButton("Cancel", target: self, action: #selector(finishChooserPreview))
        let actions = NSView(); actions.translatesAutoresizingMaskIntoConstraints = false; actions.addSubview(cancel); actions.addSubview(done); stack.addArrangedSubview(actions)
        NSLayoutConstraint.activate([
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor), actions.heightAnchor.constraint(equalToConstant: 34),
            done.trailingAnchor.constraint(equalTo: actions.trailingAnchor), done.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8), cancel.centerYAnchor.constraint(equalTo: actions.centerYAnchor)
        ])
    }
    @objc func selectChooserPreviewProfile(_ sender: ProfileButton) {
        chooserPreviewSelection = sender.profile.id
        for button in chooserPreviewButtons { button.selected = button === sender }
        chooserPreviewDoneButton?.isEnabled = true
    }
    @objc func finishChooserPreview() {
        chooserPreviewMode = false; chooserPreviewSelection = nil; modeControl.selectedSegment = 0; reload(force: true)
    }
    @objc func changeMode(_ sender: NSSegmentedControl) {
        chooserPreviewMode = sender.selectedSegment == 1; reload(force: true)
    }
    @objc func showChooserPreviewFromHelper(_ note: Notification) {
        if !chooserPreviewMode { chooserPreviewMode = true; modeControl.selectedSegment = 1; reload(force: true) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        DistributedNotificationCenter.default().post(name: managerOpenedChooserPreviewNotification, object: nil)
    }
    func clearCards() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        chooserPreviewButtons.removeAll(); chooserPreviewDoneButton = nil
    }
    func showWelcome() {
        guard lastState != "welcome" else { return }; lastState = "welcome"; clearCards(); restoreButton.isHidden = true
        countLabel.stringValue = "Get started with two profiles"
        let text = NSTextField(wrappingLabelWithString: "Keep your existing Claude account as Primary, then add a fresh Secondary account. Each account gets a native Claude copy with its own name and tagged Dock icon. These copies use local signatures; enterprise sign-in, passkeys, and Code/Cowork may need the official app.")
        text.font = .systemFont(ofSize: 18); text.textColor = .secondaryLabelColor; text.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(text); text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addButton.title = "Set Up Accounts"; addButton.action = #selector(setupAccounts); status.stringValue = "Uses the official Claude desktop app installed on this Mac."
    }
    func execute(_ args: [String], message: String, success: (() -> Void)? = nil) {
        guard !busy else { return }; busy = true; addButton.isEnabled = false; status.stringValue = message; operationIndicator.startAnimation(nil)
        let executable = (try? configuration().cliPath) ?? sourceExecutable(); let arguments = ["--root", rootPath()] + args
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; let pipe = Pipe(); process.standardError = pipe
            var problem: String?
            do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if process.terminationStatus != 0 { problem = String(data: data, encoding: .utf8) ?? "The operation failed." }
            } catch { problem = "The operation could not start. Reinstall Multi Claude to repair it." }
            DispatchQueue.main.async {
                self.busy = false; self.addButton.isEnabled = true; self.operationIndicator.stopAnimation(nil); self.reload(force: true)
                if let problem { showError(problem) }
                else {
                    DistributedNotificationCenter.default().post(name: managerProfilesDidChangeNotification, object: nil)
                    success?()
                }
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
            if let c = try? configuration(), let p = c.profiles.first(where: { !previous.contains($0.id) }) {
                self.beginOpening(c, p)
            }
        }
    }
    @objc func openAccount(_ sender: NSButton) {
        guard !busy, let id = sender.identifier?.rawValue else { return }
        do { let c = try configuration(); try beginOpening(c, profile(c, id)) }
        catch { busy = false; addButton.isEnabled = true; operationIndicator.stopAnimation(nil); showError(error.localizedDescription) }
    }
    @objc func openUsage(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let c = try? configuration(), let p = try? profile(c, id) else { return }
        openUsagePage(p) { [weak self] problem in
            guard let problem else { return }
            DispatchQueue.main.async {
                self?.status.stringValue = "Could not open Usage for \(p.name)."
                showError(problem + "\n\nOpen this account, then choose Settings → Usage in Claude.")
            }
        }
    }
    func beginOpening(_ c: Configuration, _ p: Profile) {
        guard !busy else { return }
        busy = true; addButton.isEnabled = false; status.stringValue = "Opening \(p.name)…"; operationIndicator.startAnimation(nil)
        launchOfficial(c, p) { [weak self] problem in self?.finishOpening(p, problem) }
    }
    func finishOpening(_ p: Profile, _ problem: String?) {
        busy = false; addButton.isEnabled = true; operationIndicator.stopAnimation(nil); reload(force: true)
        if let problem { status.stringValue = "Could not open \(p.name)."; showError(problem) }
        else {
            DistributedNotificationCenter.default().post(name: managerProfilesDidChangeNotification, object: nil)
            status.stringValue = "Opened \(p.name). Complete sign-in in its Claude window."
        }
    }
    @objc func renameAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let c = try? configuration(), let p = try? profile(c, id) else { return }
        let alert = NSAlert(); alert.messageText = "Name this account"; alert.informativeText = "Use an account name or email so you can recognize it in the account list. This changes the label, not the sign-in."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 26)); field.stringValue = p.name; alert.accessoryView = field
        alert.addButton(withTitle: "Save Name"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        execute(["rename", id, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)], message: "Updating account name…")
    }
    @objc func changeColor(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        execute(["icon", pair[0], pair[1]], message: "Updating the account tag…")
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
                self.beginOpening(c, p)
            } catch { showError(error.localizedDescription) }
        }
    }
    @objc func removeAccount(_ sender: NSMenuItem) {
        guard !busy, let id = sender.representedObject as? String, let c = try? configuration(), let p = try? profile(c, id) else { return }
        if let app = runningInstances(c)[id] {
            let alert = NSAlert(); alert.messageText = "Claude is still open for \(p.name)"
            alert.informativeText = "Force quitting will close only this Claude account app. Unsaved work in its window may be lost. The account data on disk will be kept, and you can restore the profile later."
            alert.addButton(withTitle: "Force Quit & Remove"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            forceQuitAndRemove(p, app)
            return
        }
        let alert = NSAlert(); alert.messageText = "Remove \(p.name)?"; alert.informativeText = "This removes its Claude app from the active account list. All account data is kept, and you can restore the profile later."
        alert.addButton(withTitle: "Remove Profile"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        removeClosedProfile(p)
    }
    func forceQuitAndRemove(_ p: Profile, _ app: NSRunningApplication) {
        guard !busy else { return }
        busy = true; addButton.isEnabled = false; status.stringValue = "Closing Claude for \(p.name)…"; operationIndicator.startAnimation(nil)
        _ = app.forceTerminate()
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(8)
            var hasExited = false
            repeat {
                hasExited = runningNativeApp(p.launcherPath) == nil
                if hasExited { break }
                Thread.sleep(forTimeInterval: 0.2)
            } while Date() < deadline
            let exited = hasExited
            DispatchQueue.main.async {
                self.busy = false; self.addButton.isEnabled = true; self.operationIndicator.stopAnimation(nil)
                guard exited else {
                    self.reload(force: true); self.status.stringValue = "Claude for \(p.name) is still open; the profile was not removed."
                    showError("Claude could not be closed, so Multi Claude left the profile and its account data unchanged. Quit it manually and try again.")
                    return
                }
                self.removeClosedProfile(p)
            }
        }
    }
    func removeClosedProfile(_ p: Profile) {
        execute(["remove", p.id], message: "Removing the Claude app and keeping its data…") {
            self.reload(force: true)
            self.status.stringValue = "Removed \(p.name). Its account data is saved and can be restored."
        }
    }
    @objc func restoreAccount(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { execute(["restore", id], message: "Restoring your account launcher…") } }
    @objc func refresh() { reload(force: true) }
    @objc func refreshUsage() {
        DistributedNotificationCenter.default().post(name: managerRequestsUsageRefreshNotification, object: nil)
        status.stringValue = "Refreshing 5-hour and weekly usage…"
    }
    @objc func showLaunchers() { if let c = try? configuration() { NSWorkspace.shared.open(URL(fileURLWithPath: c.applicationsDir)) } }
    @objc func checkSetup() { execute(["doctor"], message: "Checking your installation…") { showError("Your profile folders, app launchers, and enabled login routing passed their checks.") } }
    @objc func about() { showError("Multi Claude 1.3\n\nOne native Claude app and tagged Dock icon per account. The startup bootstrap becomes the Claude process. The manager and menu helper have no Dock icons.\n\nAccount copies are locally signed. Enterprise sign-in, passkeys, and Code/Cowork compatibility remain unverified.\n\nInspired by am-will/multi-codex-app (MIT).") }
}
var managerDelegate: ManagerDelegate?
func startManager() {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    managerDelegate = ManagerDelegate(); app.delegate = managerDelegate; app.run()
}
