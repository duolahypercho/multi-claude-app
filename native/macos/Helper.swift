import AppKit
import CoreServices
import Darwin

// ProfileButton and Chooser adapted from am-will/multi-codex-app (MIT).
// Cards use ordinary AppKit controls, retaining keyboard and VoiceOver support.
final class ProfileButton: NSButton {
    let profile: Profile
    let available: Bool
    var selected = false { didSet { needsDisplay = true; setAccessibilityValue(selected ? "Selected" : "Not selected") } }
    init(_ profile: Profile, available: Bool) {
        self.profile = profile; self.available = available
        super.init(frame: .zero)
        title = ""; isBordered = false; setButtonType(.momentaryChange); isEnabled = available
        setAccessibilityLabel(profile.name + (available ? ", running" : ", closed"))
        translatesAutoresizingMaskIntoConstraints = false; heightAnchor.constraint(equalToConstant: 64).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1); let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.controlBackgroundColor).setFill(); path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.6)).setStroke(); path.lineWidth = selected ? 1.6 : 1; path.stroke()
        let iconRect = NSRect(x: 16, y: 16, width: 32, height: 32)
        profileImage(profile, size: 32)?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: available ? 1 : 0.45, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: profile.name, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: available ? NSColor.labelColor : NSColor.secondaryLabelColor, .paragraphStyle: paragraph]).draw(in: NSRect(x: 60, y: 16, width: max(0, bounds.width - 110), height: 20))
        NSAttributedString(string: available ? "Running on this Mac" : "Open this profile to continue", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 60, y: 36))
        let circle = NSRect(x: bounds.width - 34, y: 24, width: 16, height: 16)
        if selected {
            NSColor.controlAccentColor.setFill(); NSBezierPath(ovalIn: circle).fill()
            NSColor.white.setStroke(); let check = NSBezierPath(); check.move(to: NSPoint(x: circle.minX + 4, y: circle.midY)); check.line(to: NSPoint(x: circle.minX + 7, y: circle.minY + 11)); check.line(to: NSPoint(x: circle.maxX - 3, y: circle.minY + 5)); check.lineWidth = 1.7; check.stroke()
        } else { NSColor.tertiaryLabelColor.setStroke(); NSBezierPath(ovalIn: circle).stroke() }
        if NSApp.keyWindow?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10); focus.lineWidth = 2; focus.stroke() }
    }
}
final class Chooser: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var buttons: [ProfileButton] = []
    var selected: Profile?
    var completion: ((Profile?) -> Void)?
    var continueButton: NSButton!
    func show(_ c: Configuration, preview: Bool, completion: @escaping (Profile?) -> Void) {
        self.completion = completion
        let listHeight = min(CGFloat(c.profiles.count) * 74, 370)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 218 + listHeight), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Multi Claude"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.delegate = self
        let view = NSView(); window.contentView = view
        func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: text); f.font = font; f.textColor = color; f.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(f); return f
        }
        let title = label("Choose a Claude profile", font: .systemFont(ofSize: 23, weight: .bold), color: .labelColor)
        let subtitle = label("Send this sign-in or connection link to the profile where you started it.", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.drawsBackground = false; scroll.hasVerticalScroller = c.profiles.count > 5; view.addSubview(scroll)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = stack
        let running = runningInstances(c)
        for p in c.profiles {
            let b = ProfileButton(p, available: preview || running[p.id] != nil); b.target = self; b.action = #selector(selectProfile(_:)); stack.addArrangedSubview(b); b.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; buttons.append(b)
        }
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelChoice)); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"; cancel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(cancel)
        continueButton = NSButton(title: preview ? "Done" : "Continue", target: self, action: #selector(confirm)); continueButton.bezelStyle = .rounded; continueButton.keyEquivalent = "\r"; continueButton.isEnabled = false; continueButton.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(continueButton)
        let hint = label(preview ? "Preview — no connection is sent." : "Your other profiles stay open.", font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28), title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8), subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22), scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: title.trailingAnchor), scroll.heightAnchor.constraint(equalToConstant: listHeight),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor).withPriority(.defaultLow),
            continueButton.trailingAnchor.constraint(equalTo: title.trailingAnchor), continueButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 24), continueButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96), cancel.trailingAnchor.constraint(equalTo: continueButton.leadingAnchor, constant: -10), cancel.centerYAnchor.constraint(equalTo: continueButton.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor), hint.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12), hint.centerYAnchor.constraint(equalTo: continueButton.centerYAnchor)
        ])
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc func selectProfile(_ sender: ProfileButton) { selected = sender.profile; for b in buttons { b.selected = b === sender }; continueButton.isEnabled = true }
    @objc func confirm() { finish(selected) }
    @objc func cancelChoice() { finish(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(nil); return false }
    func finish(_ p: Profile?) { let callback = completion; completion = nil; window.orderOut(nil); callback?(p) }
}
extension NSLayoutConstraint { func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint { priority = p; return self } }

final class Helper: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var chooser: Chooser?
    var pending: [String] = []
    var ready = false
    var timer: Timer?
    var operationInProgress = false
    var progressPanel: NSPanel?
    var progressIndicator: NSProgressIndicator?
    var progressLabel: NSTextField?
    let previewMode: Bool
    init(preview: Bool) { previewMode = preview }
    func applicationWillFinishLaunching(_ note: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receive(_:reply:)), forEventClass: AEEventClass(0x4755524c), andEventID: AEEventID(0x4755524c))
    }
    func applicationDidFinishLaunching(_ note: Notification) {
        if previewMode { ready = true; preview(); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Multi Claude profiles")
        rebuildMenu(); claim(); ready = true; processNext()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.claim(); self?.rebuildMenu() }
        if CommandLine.arguments.count == 1 { preview() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { preview(); return false }
    func claim() {
        guard let c = try? configuration(), c.integrationEnabled && c.usesLoginChooser else { return }
        for scheme in c.schemes where handler(scheme) != helperID { try? setHandler(scheme, helperID) }
    }
    func rebuildMenu() {
        let menu = NSMenu(); let heading = menu.addItem(withTitle: "Multi Claude", action: nil, keyEquivalent: ""); heading.isEnabled = false
        menu.addItem(.separator())
        if let c = try? configuration() {
            let running = runningInstances(c)
            for p in c.profiles {
                let item = menu.addItem(withTitle: p.displayName + (running[p.id] == nil ? "" : "  •"), action: #selector(launchProfile(_:)), keyEquivalent: "")
                item.representedObject = p.id; item.target = self; item.image = profileImage(p, size: 20)
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Add Profile…", action: #selector(addProfile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preview Login Chooser…", action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Profile Management…", action: #selector(manage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "About Multi Claude", action: #selector(about), keyEquivalent: "").target = self
        status.menu = menu
    }
    func showProgress(_ message: String) {
        if progressPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 96), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Multi Claude"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            let view = NSView(); panel.contentView = view
            let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .regular; spinner.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(spinner)
            let label = NSTextField(wrappingLabelWithString: message); label.font = .systemFont(ofSize: 13); label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
            NSLayoutConstraint.activate([
                spinner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor), spinner.widthAnchor.constraint(equalToConstant: 20), spinner.heightAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 14), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            progressPanel = panel; progressIndicator = spinner; progressLabel = label
        }
        progressLabel?.stringValue = message; progressIndicator?.startAnimation(nil)
        NSApp.activate(ignoringOtherApps: true); progressPanel?.center(); progressPanel?.makeKeyAndOrderFront(nil)
    }
    func finishOperation(_ problem: String?) {
        operationInProgress = false; progressIndicator?.stopAnimation(nil); progressPanel?.orderOut(nil)
        if let problem { showError(problem) } else { rebuildMenu() }
    }
    @objc func launchProfile(_ sender: NSMenuItem) {
        guard !operationInProgress, let id = sender.representedObject as? String else { return }
        do {
            let c = try configuration(), p = try profile(c, id)
            operationInProgress = true; showProgress("Opening \(p.name)…")
            launchOfficial(c, p) { [weak self] problem in self?.finishOperation(problem) }
        } catch { finishOperation(error.localizedDescription) }
    }
    @objc func addProfile() {
        let alert = NSAlert(); alert.messageText = "Add a Claude profile"; alert.informativeText = "Give this account a name. It starts with a fresh sign-in."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26)); input.placeholderString = "Work or Personal"; alert.accessoryView = input
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel"); NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showError("Enter an account name, then choose Add Profile again."); return }
        do {
            let c = try configuration(); operationInProgress = true; showProgress("Creating and signing the Claude account app…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let proc = Process(); proc.executableURL = URL(fileURLWithPath: c.cliPath)
                proc.arguments = ["--root", rootPath(), "add", "--name", name]
                proc.standardOutput = FileHandle.nullDevice; let pipe = Pipe(); proc.standardError = pipe
                var problem: String?
                do {
                    try proc.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); proc.waitUntilExit()
                    if proc.terminationStatus != 0 { problem = String(data: data, encoding: .utf8) ?? "Could not add this profile." }
                } catch { problem = error.localizedDescription }
                DispatchQueue.main.async { self?.finishOperation(problem) }
            }
        } catch { finishOperation(error.localizedDescription) }
    }
    @objc func manage() {
        guard let c = try? configuration() else { return }
        let path = c.managerPath ?? c.applicationsDir + "/Multi Claude.app"
        if fm.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        else { showError("Re-run setup to install the Multi Claude account manager.") }
    }
    @objc func about() {
        let a = NSAlert(); a.messageText = "Multi Claude App 1.3"
        a.informativeText = "Independent Claude desktop profiles, account labels, and colored tags.\n\nInspired by am-will/multi-codex-app (MIT).\nThe official Claude app is unchanged.\n\nUse Multi Claude to manage accounts and sign-in modes."
        a.runModal()
    }
    @objc func preview() {
        guard chooser == nil else { return }
        do {
            let c = try configuration(); let choice = Chooser(); chooser = choice
            choice.show(c, preview: true) { [weak self] _ in self?.chooser = nil; if self?.previewMode == true { NSApp.terminate(nil) } else { self?.processNext() } }
        } catch { showError(error.localizedDescription); if previewMode { NSApp.terminate(nil) } }
    }
    @objc func receive(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(0x2d2d2d2d))?.stringValue,
              let c = try? configuration(), validURI(raw, schemes: c.schemes), pending.count < 10 else { return }
        pending.append(raw); processNext()
    }
    func processNext() {
        guard ready, chooser == nil, !pending.isEmpty else { return }
        guard let c = try? configuration(), c.integrationEnabled && c.usesLoginChooser else { pending.removeAll(); return }
        let raw = pending.removeFirst(); let choice = Chooser(); chooser = choice
        // Every link needs an explicit destination; nothing falls back to Primary.
        choice.show(c, preview: false) { [weak self] selected in
            if let p = selected { self?.forward(raw, p.id) }
            self?.chooser = nil; self?.processNext()
        }
    }
    func forward(_ raw: String, _ id: String) {
        do {
            let current = try configuration(); let p = try profile(current, id)
            guard validURI(raw, schemes: current.schemes), let app = runningInstances(current)[id] else { throw fail("Open the selected profile, then restart sign-in or Connect from it.") }
            do { try deliver(raw, to: app); app.activate(options: [.activateAllWindows]) }
            catch { throw fail("macOS could not reach \(p.displayName). Restart sign-in from that profile. The link was not sent to another account.") }
        } catch { showError(error.localizedDescription) }
    }
}
var helperDelegate: Helper?
var helperLockFD: Int32 = -1
func startHelper(preview: Bool) {
    if !preview {
        helperLockFD = open(rootPath() + "/helper.lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard helperLockFD >= 0, flock(helperLockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    }
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    helperDelegate = Helper(preview: preview); app.delegate = helperDelegate; app.run()
}
