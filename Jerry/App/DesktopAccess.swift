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
        present(.screenRecording, openSettings: false)
    }
    func captureStarted() {
        guard screenCaptureRejected else { return }
        screenCaptureRejected = false; refresh()
    }
    func present(_ permission: Permission, openSettings: Bool = true) {
        refresh()
        if setup?.permission != permission { setup?.close(); setup = DesktopAccessController(permission: permission) }
        setup?.showWindow(nil); setup?.window?.makeKeyAndOrderFront(nil)
        if openSettings { open(permission) } else { NSApp.activate(ignoringOtherApps: true) }
    }
    func open(_ permission: Permission) {
        if permission == .accessibility { UserDefaults.standard.set(true, forKey: "desktopAccessibilityRequested") }
        if !snapshot.allows(permission), requested.insert(permission).inserted {
            if permission == .accessibility {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            } else { _ = CGRequestScreenCaptureAccess() }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + permission.pane) { NSWorkspace.shared.open(url) }
        setup?.positionBesideSettings()
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
private final class DesktopAccessController: NSWindowController {
    let permission: DesktopAccess.Permission
    private let status = NSTextField(wrappingLabelWithString: "")
    private let done = NSButton(title: "Not now", target: nil, action: nil)
    private var next: DesktopAccess.Permission?
    init(permission: DesktopAccess.Permission) {
        self.permission = permission
        let window = NotebookWindow(contentRect: .init(x: 0, y: 0, width: 380, height: 510), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Jerry — " + permission.title; window.isReleasedWhenClosed = false; window.level = .floating
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
        window.center(); refresh()
    }
    required init?(coder: NSCoder) { fatalError("Use init(permission:)") }
    func refresh() {
        let access = DesktopAccess.shared.snapshot
        let allowed = access.allows(permission)
        status.stringValue = allowed ? "✓ macOS allows this copy of Jerry." : "Waiting for macOS to allow access…"
        status.textColor = allowed ? NotebookTheme.ink : NotebookTheme.rust; status.font = .systemFont(ofSize: 12, weight: .medium)
        next = allowed ? DesktopAccess.needed(for: access).first : nil
        done.title = next.map { _ in "Next permission…" } ?? (allowed ? "Done" : "Not now"); NotebookTheme.style(done, primary: allowed)
        if window?.isVisible == true { positionBesideSettings() }
    }
    func positionBesideSettings() {
        guard let window, let screen = window.screen ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        if let entry = entries.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
           let dictionary = entry[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) {
            let x = rect.maxX + 12 + window.frame.width <= visible.maxX ? rect.maxX + 12 : max(visible.minX, rect.minX - window.frame.width - 12)
            let top = (NSScreen.screens.first?.frame.maxY ?? visible.maxY) - rect.minY
            window.setFrameOrigin(.init(x: x, y: max(visible.minY, min(visible.maxY - window.frame.height, top - window.frame.height))))
        }
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
