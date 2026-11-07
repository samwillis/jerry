import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices

extension Notification.Name {
    static let desktopAccessChanged = Notification.Name("JerryDesktopAccessChanged")
}

/// Reads macOS grants rather than assuming a saved preference is permission.
/// Reading status never prompts or changes a grant.
@MainActor
final class DesktopAccess {
    enum Permission: String, CaseIterable {
        case accessibility, screenRecording
        var title: String {
            if self == .screenRecording { return "Screen Recording" }
            if #available(macOS 27.0, *) { return "Device Control and Data Access" }
            return "Accessibility"
        }
        var pane: String { self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture" }
    }
    struct Snapshot: Equatable {
        var accessibility: Bool
        var screenRecording: Bool
        func allows(_ permission: Permission) -> Bool { permission == .accessibility ? accessibility : screenRecording }
    }
    static let shared = DesktopAccess()
    private(set) var snapshot = Snapshot(accessibility: false, screenRecording: false)
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var setup: DesktopAccessController?
    private var requested: Set<Permission> = []
    private var screenCaptureRejected = false

    static func needed(for snapshot: Snapshot, defaults: UserDefaults = .standard) -> [Permission] {
        let clicksUsed = defaults.bool(forKey: "desktopAccessibilityRequested") || defaults.bool(forKey: "desktopAccessibilityGranted")
            || !(defaults.string(forKey: "agentModelID") ?? "").isEmpty
        let imagesUsed = defaults.bool(forKey: "exploreInsideWindows") || defaults.bool(forKey: "agentShareImages")
        return Permission.allCases.filter {
            !snapshot.allows($0) && ($0 == .accessibility ? clicksUsed : imagesUsed)
        }
    }
    func start() {
        refresh()
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.setup?.window?.isVisible == true || NSApp.isActive else { return }
                self.refresh()
            }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        setup?.close(); setup = nil
    }
    func refresh() {
        let next = Snapshot(accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess() && !screenCaptureRejected)
        if next.accessibility, !UserDefaults.standard.bool(forKey: "desktopAccessibilityGranted") { UserDefaults.standard.set(true, forKey: "desktopAccessibilityGranted") }
        let changed = next != snapshot
        snapshot = next
        setup?.refresh()
        if changed { NotificationCenter.default.post(name: .desktopAccessChanged, object: self) }
    }
    func captureRejected() {
        guard !screenCaptureRejected else { return }
        screenCaptureRejected = true; refresh()
        if setup?.window?.isVisible != true { present(.screenRecording, openSettings: false) }
    }
    func captureStarted() {
        guard screenCaptureRejected else { return }
        screenCaptureRejected = false; refresh()
    }
    func present(_ permission: Permission, openSettings: Bool = true) {
        refresh()
        if setup?.permission != permission {
            let previousFrame = setup?.window?.isVisible == true ? setup?.window?.frame : nil
            setup?.close(); setup = DesktopAccessController(permission: permission)
            if let previousFrame { setup?.preservePosition(from: previousFrame) }
        }
        setup?.positionBesideSettings()
        setup?.window?.orderFront(nil)
        if openSettings { open(permission) }
        else if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.systempreferences" {
            NSApp.activate(ignoringOtherApps: true); setup?.window?.makeKeyAndOrderFront(nil)
        }
    }
    func open(_ permission: Permission) {
        if permission == .accessibility { UserDefaults.standard.set(true, forKey: "desktopAccessibilityRequested") }
        if !snapshot.allows(permission), requested.insert(permission).inserted {
            if permission == .accessibility {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            } else { _ = CGRequestScreenCaptureAccess() }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + permission.pane) { NSWorkspace.shared.open(url) }
        // Let Settings finish opening before one placement attempt. Permission
        // polling must never move windows or compete with a user dragging them.
        let guide = setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak guide] in guide?.positionBesideSettings() }
    }

    static func setupFrame(size: CGSize, beside settings: CGRect, in visible: CGRect) -> CGRect? {
        guard size.width <= visible.width, size.height <= visible.height else { return nil }
        let y = max(visible.minY, min(visible.maxY - size.height, settings.maxY - size.height))
        let candidates = [
            CGRect(x: settings.maxX + 12, y: y, width: size.width, height: size.height),
            CGRect(x: settings.minX - size.width - 12, y: y, width: size.width, height: size.height)
        ]
        // If neither side has room, leave the normal-level window where it is.
        // Never clamp it into the permission list merely to fit it on screen.
        return candidates.first { visible.contains($0) && !$0.intersects(settings) }
    }
}

/// A real file URL drag: the currently running bundle, never a stale app name.
@MainActor
final class JerryApplicationDragView: NSView, NSDraggingSource {
    let applicationURL: URL
    private let icon = NSImageView()
    private var dragStart: NSEvent?
    init(applicationURL: URL = Bundle.main.bundleURL) {
        self.applicationURL = applicationURL
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 10; layer?.backgroundColor = NotebookTheme.leather.withAlphaComponent(0.09).cgColor
        icon.image = NSWorkspace.shared.icon(forFile: applicationURL.path); icon.imageScaling = .scaleProportionallyUpOrDown
        icon.frame = .init(x: 12, y: 12, width: 64, height: 64); addSubview(icon)
        let name = NSTextField(labelWithString: "Jerry.app"); name.font = NotebookTheme.font(16, weight: .semibold); name.textColor = NotebookTheme.ink
        name.frame = .init(x: 90, y: 46, width: 205, height: 24); addSubview(name)
        let hint = NSTextField(labelWithString: "Drag into the permission list"); hint.font = .systemFont(ofSize: 11); hint.textColor = NotebookTheme.faded
        hint.frame = .init(x: 90, y: 23, width: 215, height: 20); addSubview(hint)
        toolTip = applicationURL.path
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Jerry application — drag into System Settings")
        heightAnchor.constraint(equalToConstant: 88).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(applicationURL:)") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { dragStart = event }
    override func mouseUp(with event: NSEvent) { dragStart = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) >= 3 else { return }
        dragStart = nil
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(icon.frame, contents: icon.image)
        beginDraggingSession(with: [item], event: start, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .link, .generic] }
}

@MainActor
private final class DesktopAccessController: NSWindowController, NSWindowDelegate {
    let permission: DesktopAccess.Permission
    private let status = NSTextField(wrappingLabelWithString: "")
    private let done = NSButton(title: "Not now", target: nil, action: nil)
    private var next: DesktopAccess.Permission?
    private var placed = false
    private var positioning = false
    init(permission: DesktopAccess.Permission) {
        self.permission = permission
        let window = NotebookWindow(contentRect: .init(x: 0, y: 0, width: 380, height: 510), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Jerry — " + permission.title; window.isReleasedWhenClosed = false; window.level = .normal
        window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        let root = NotebookTheme.install(on: window, title: "Access")
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 14; body.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(body)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), body.topAnchor.constraint(equalTo: root.topAnchor, constant: 14)])
        func text(_ value: String, size: CGFloat = 12) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value); field.font = NotebookTheme.font(size); field.textColor = NotebookTheme.ink; field.preferredMaxLayoutWidth = 322; return field
        }
        func button(_ title: String, _ action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action); NotebookTheme.style(button); return button
        }
        body.addArrangedSubview(text(permission == .accessibility ? "Let Jerry use your controls" : "Let Jerry see window ledges", size: 20))
        body.addArrangedSubview(text(permission == .accessibility ? "Accessibility lets Jerry read controls and press buttons in other apps." : "Screen Recording lets Jerry find ledges inside windows. AI image sharing stays a separate choice."))
        body.addArrangedSubview(button("Open " + permission.title + "…", #selector(openSettings)))
        body.addArrangedSubview(text("Drag Jerry into the list, then turn on his switch. If there’s no drop target, use + to add this app."))
        body.addArrangedSubview(JerryApplicationDragView())
        body.addArrangedSubview(button("Show this app in Finder", #selector(showInFinder)))
        body.addArrangedSubview(status)
        body.addArrangedSubview(text("Already listed but still blocked? Remove the old entry from this permission list and add this copy of Jerry."))
        let actions = NSStackView(); actions.spacing = 8
        actions.addArrangedSubview(button("Check again", #selector(checkAgain)))
        actions.addArrangedSubview(button("Restart Jerry", #selector(restart)))
        done.target = self; done.action = #selector(finish); actions.addArrangedSubview(done); body.addArrangedSubview(actions)
        body.addArrangedSubview(text("If macOS asks you to quit and reopen, restart Jerry after enabling access."))
        for view in body.arrangedSubviews { view.widthAnchor.constraint(equalToConstant: 322).isActive = true }
        window.contentView?.layoutSubtreeIfNeeded()
        window.setContentSize(.init(width: 380, height: max(510, body.fittingSize.height + 76)))
        window.center(); window.delegate = self; shouldCascadeWindows = false; refresh()
    }
    required init?(coder: NSCoder) { fatalError("Use init(permission:)") }
    func refresh() {
        let access = DesktopAccess.shared.snapshot
        let allowed = access.allows(permission)
        status.stringValue = allowed ? "✓ macOS allows this copy of Jerry." : "Waiting for macOS to allow access…"
        status.textColor = allowed ? NotebookTheme.ink : NotebookTheme.rust; status.font = .systemFont(ofSize: 12, weight: .medium)
        next = allowed ? DesktopAccess.needed(for: access).first : nil
        done.title = next.map { _ in "Next permission…" } ?? (allowed ? "Done" : "Not now"); NotebookTheme.style(done, primary: allowed)
    }
    func preservePosition(from frame: CGRect) {
        positioning = true
        window?.setFrameTopLeftPoint(.init(x: frame.minX, y: frame.maxY))
        positioning = false; placed = true
    }
    func windowDidMove(_ notification: Notification) {
        if !positioning { placed = true } // Respect a manually positioned guide.
    }
    func positionBesideSettings() {
        guard !placed, let window,
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier else { return }
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let settingsFrames = entries.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  rect.width >= 400, rect.height >= 300 else { return nil }
            return CGRect(x: rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.maxY, width: rect.width, height: rect.height)
        }
        guard let settings = settingsFrames.max(by: { $0.width * $0.height < $1.width * $1.height }),
              let screen = NSScreen.screens.max(by: { lhs, rhs in
                  let a = lhs.frame.intersection(settings), b = rhs.frame.intersection(settings)
                  return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
              }) else { return }
        placed = true
        guard let frame = DesktopAccess.setupFrame(size: window.frame.size, beside: settings, in: screen.visibleFrame) else { return }
        positioning = true; window.setFrameOrigin(frame.origin); positioning = false
    }
    @objc private func openSettings() { DesktopAccess.shared.open(permission) }
    @objc private func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func checkAgain() { DesktopAccess.shared.refresh() }
    @objc private func finish() { if let next { DesktopAccess.shared.present(next) } else { close() } }
    @objc private func restart() {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "jerry-restart", Bundle.main.bundleURL.path]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        do { try task.run(); NSApp.terminate(nil) }
        catch { status.stringValue = "Couldn’t restart. Quit Jerry and open him again." }
    }
}
