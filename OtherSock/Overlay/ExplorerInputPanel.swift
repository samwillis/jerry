import AppKit
@preconcurrency import ApplicationServices

/// A small hit area above the mouse-ignoring rendering layer. Never takes keyboard focus.
@MainActor
final class ExplorerInputPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ExplorerInputView: NSView {
    var onBegin: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    private var dragging = false

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Explorer — drag to move")
        toolTip = "Grab me and move me out of the way"
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ dirtyRect: NSRect) {
        // A near-transparent backing keeps the small panel hit-testable on macOS.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        dragging = true
        NSCursor.closedHand.push()
        onBegin?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(NSEvent.mouseLocation)
        cancelDrag()
    }

    func cancelDrag() {
        guard dragging else { return }
        dragging = false
        NSCursor.pop()
        onEnd?()
    }
}

/// Invisible key target used only during manual control. No instruction window or global keyboard monitor.
@MainActor
final class ExplorerControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ExplorerKeyboardController: NSObject, NSWindowDelegate {
    let panel: ExplorerControlPanel
    private(set) var lastMessage = ""
    private var monitor: Any?
    private var held: Set<UInt16> = []
    private var previousApp: NSRunningApplication?
    private var lastExternalApp = NSWorkspace.shared.frontmostApplication
    private var clickRestore: DispatchWorkItem?
    private(set) var isPerformingClick = false
    private var aiming = false
    var onDirection: ((Double, Double) -> Void)?
    var onFastPace: ((Bool) -> Void)?
    var onJump: (() -> Void)?
    var onAimChanged: ((Bool) -> Void)?
    var onAimDirection: ((Double, Double) -> Void)?
    var onGrapple: (() -> Void)?
    var onInteract: (() -> Void)?
    var onStop: (() -> Void)?
    private(set) var isControlling = false

    override init() {
        panel = ExplorerControlPanel(contentRect: .init(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.title = "Explorer keyboard input"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.setAccessibilityElement(false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
    }

    func start() {
        guard !isControlling else { return }
        recordFrontApp()
        previousApp = lastExternalApp
        isControlling = true
        held.removeAll()
        showMessage("The crosshair beside his hand is the click point. Down + Space drops through a platform.")
        if let screen = NSScreen.screens.first {
            panel.setFrameTopLeftPoint(.init(x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.maxY - 12))
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == nil }
            return consumed ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

    }

    func recordFrontApp() {
        if let active = NSWorkspace.shared.frontmostApplication, active.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = active
        }
    }
    func restoreExternalFocus() {
        if lastExternalApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApp?.activate(options: []) }
    }
    func showMessage(_ text: String) { lastMessage = text }

    /// Local key routing is shared with native checks; repeated actions never click twice.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isControlling, NSApp.keyWindow === panel else { return event }
        return routeKey(event)
    }
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard isControlling else { return event }
        onFastPace?(event.modifierFlags.contains(.shift) && event.modifierFlags.intersection([.command, .option, .control]).isEmpty)
        if event.type == .flagsChanged {
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { clearDirections() }
            return event
        }
        if event.keyCode == 53, event.type == .keyDown { stop(restoreFocus: true); return nil }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
        let moves: Set<UInt16> = [0, 1, 2, 13, 123, 124, 125, 126]
        if moves.contains(event.keyCode) {
            if event.type == .keyDown { held.insert(event.keyCode) } else { held.remove(event.keyCode) }
            updateDirection()
            return nil
        }
        if event.keyCode == 5 {
            if event.type == .keyDown, !event.isARepeat { aiming = true; onAimChanged?(true); updateDirection() }
            if event.type == .keyUp, aiming { aiming = false; onGrapple?(); onAimChanged?(false); updateDirection() }
            return nil
        }
        guard [UInt16(49), 14].contains(event.keyCode) else { return event }
        if event.type == .keyDown, !event.isARepeat {
            switch event.keyCode { case 49: onJump?(); default: onInteract?() }
        }
        return nil
    }

    private func updateDirection() {
        let x = (held.isDisjoint(with: [2, 124]) ? 0.0 : 1) - (held.isDisjoint(with: [0, 123]) ? 0.0 : 1)
        let y = (held.isDisjoint(with: [13, 126]) ? 0.0 : 1) - (held.isDisjoint(with: [1, 125]) ? 0.0 : 1)
        onAimDirection?(aiming ? x : 0, aiming ? y : 0)
        onDirection?(aiming ? 0 : x, aiming ? 0 : y)
    }
    func clearDirections() { held.removeAll(); updateDirection() }
    func stop(restoreFocus: Bool = false) {
        guard isControlling else { return }
        isControlling = false
        clickRestore?.cancel(); clickRestore = nil; isPerformingClick = false
        aiming = false; onAimChanged?(false)
        clearDirections(); onFastPace?(false)
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        panel.orderOut(nil)
        onStop?()
        if restoreFocus, previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        previousApp = nil
    }
    func beginClick() { isPerformingClick = true }
    func finishClick() {
        guard isControlling, isPerformingClick else { return }
        // AX actions and ordinary clicks can activate the destination app. Keep
        // the play session alive and return its key window after event delivery.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isControlling, self.isPerformingClick else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
                self.held = Set([UInt16(0), 1, 2, 13, 123, 124, 125, 126].filter {
                    CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
                })
                self.updateDirection()
                self.onFastPace?(CGEventSource.keyState(.combinedSessionState, key: 56) || CGEventSource.keyState(.combinedSessionState, key: 60))
                if self.aiming && !CGEventSource.keyState(.combinedSessionState, key: 5) {
                    self.aiming = false; self.onAimChanged?(false)
                    self.updateDirection()
                }
                self.isPerformingClick = false
                self.clickRestore = nil
            }
        }
        clickRestore?.cancel(); clickRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func windowDidResignKey(_ notification: Notification) {
        if !isPerformingClick { stop() }
    }
    func close() { stop(); panel.delegate = nil; panel.close() }
}

/// User-triggered interaction only. E performs one press at the visible hand marker.
@MainActor
final class ExplorerDesktopClick {
    static var hasAccess: Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func quartzPoint(_ point: CGPoint, primaryTop: CGFloat) -> CGPoint {
        .init(x: point.x, y: primaryTop - point.y)
    }
    static func press(at point: CGPoint) -> String {
        guard hasAccess else { return "Allow The Other Sock in System Settings → Privacy & Security → Accessibility, then press E again." }
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success {
            for _ in 0..<6 {
                guard let current = element else { break }
                var pid: pid_t = 0
                AXUIElementGetPid(current, &pid)
                guard pid != ProcessInfo.processInfo.processIdentifier else { return "Move the marker away from the explorer's own controls." }
                var actions: CFArray?
                if AXUIElementCopyActionNames(current, &actions) == .success,
                   let names = actions as? [String], names.contains(kAXPressAction as String),
                   AXUIElementPerformAction(current, kAXPressAction as CFString) == .success { return "Pressed the control at the hand marker." }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                      let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                element = (parent as! AXUIElement)
            }
        }
        // Canvas/custom controls may not expose AXPress. Send exactly one ordinary
        // left click at the same marker. The controller restores its key window.
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return "Could not create the click." }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "Clicked at the hand marker. Explorer control stays active."
    }
}
