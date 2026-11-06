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

/// Only this explicitly opened window receives game keys. No global keyboard monitor.
@MainActor
final class ExplorerControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ExplorerKeyboardController: NSObject, NSWindowDelegate {
    let panel: ExplorerControlPanel
    private let message = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var held: Set<UInt16> = []
    private var previousApp: NSRunningApplication?
    var onDirection: ((Double, Double) -> Void)?
    var onJump: (() -> Void)?
    var onGrapple: (() -> Void)?
    var onInteract: (() -> Void)?
    var onStop: (() -> Void)?
    private(set) var isControlling = false

    override init() {
        panel = ExplorerControlPanel(contentRect: .init(x: 0, y: 0, width: 640, height: 76), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = "Control the explorer — Esc to return to your computer"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let instructions = NSTextField(labelWithString: "← → / A D move · ↑ ↓ / W S climb/descend · Space jump · G hook · E click")
        instructions.font = .systemFont(ofSize: 12)
        instructions.frame = .init(x: 12, y: 48, width: 620, height: 18)
        panel.contentView?.addSubview(instructions)
        message.frame = .init(x: 12, y: 8, width: 615, height: 34)
        message.font = .systemFont(ofSize: 11)
        message.maximumNumberOfLines = 2
        message.lineBreakMode = .byWordWrapping
        panel.contentView?.addSubview(message)
    }

    func start() {
        guard !isControlling else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
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

    func showMessage(_ text: String) { message.stringValue = text }

    /// Local key routing is shared with native checks; repeated actions never click twice.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isControlling, NSApp.keyWindow === panel else { return event }
        return routeKey(event)
    }
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard isControlling else { return event }
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
        guard [UInt16(49), 5, 14].contains(event.keyCode) else { return event }
        if event.type == .keyDown, !event.isARepeat {
            switch event.keyCode { case 49: onJump?(); case 5: onGrapple?(); default: onInteract?() }
        }
        return nil
    }

    private func updateDirection() {
        let x = (held.isDisjoint(with: [2, 124]) ? 0.0 : 1) - (held.isDisjoint(with: [0, 123]) ? 0.0 : 1)
        let y = (held.isDisjoint(with: [13, 126]) ? 0.0 : 1) - (held.isDisjoint(with: [1, 125]) ? 0.0 : 1)
        onDirection?(x, y)
    }
    func clearDirections() { held.removeAll(); onDirection?(0, 0) }
    func stop(restoreFocus: Bool = false) {
        guard isControlling else { return }
        isControlling = false
        clearDirections()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        panel.orderOut(nil)
        onStop?()
        if restoreFocus, previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        previousApp = nil
    }
    func windowDidResignKey(_ notification: Notification) { stop() }
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
        // left click at the same marker, allowing the target app to take focus.
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return "Could not create the click." }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "Clicked at the hand marker. If the app takes focus, keyboard control ends."
    }
}
