import AppKit

@MainActor
final class FixtureClickCanvas: NSView {
    var count = 0
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { count += 1; onClick?(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        ("Custom clicks: \(count)" as NSString).draw(at: .init(x: 16, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.labelColor])
    }
}

@MainActor
final class InternalTerrainCanvas: NSView {
    private var scrollOffset = 0.0
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        scrollOffset = min(100, max(-100, scrollOffset - event.scrollingDeltaY))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); bounds.fill()
        NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.45, alpha: 1).setFill()
        CGRect(x: 35, y: 170 + scrollOffset, width: bounds.width - 70, height: 85).fill()
        NSColor.black.setFill()
        CGRect(x: 35, y: 340 + scrollOffset, width: bounds.width - 70, height: 2).fill()
        CGRect(x: 330, y: 40 + scrollOffset, width: 2, height: 300).fill()
        ("Scroll here to move the ledges and cracks" as NSString).draw(at: .init(x: 24, y: bounds.height - 35), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor])
    }
}

@MainActor
final class Fixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var support: NSWindow!
    private var cover: NSWindow?
    private var clickCount = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { return }
        let base = screen.visibleFrame.minY
        if ProcessInfo.processInfo.arguments.contains("--internal-terrain") {
            let target = NSWindow(contentRect: .init(x: 280, y: base + 80, width: 720, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            target.title = "Climbing landscape — scroll inside"; target.isReleasedWhenClosed = false
            target.contentView = InternalTerrainCanvas(frame: target.contentView!.bounds)
            windows.append(target); target.orderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--click-target") {
            let rope = ProcessInfo.processInfo.arguments.contains("--rope-click-target")
            let target = NSWindow(contentRect: .init(x: rope ? 700 : 830, y: base, width: rope ? 350 : 220, height: rope ? 500 : 70), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            target.title = "Explorer click target"; target.isReleasedWhenClosed = false
            if ProcessInfo.processInfo.arguments.contains("--custom-click-target") {
                let canvas = FixtureClickCanvas(frame: target.contentView!.bounds)
                canvas.setAccessibilityElement(true); canvas.setAccessibilityRole(.group)
                canvas.setAccessibilityLabel("Custom click test canvas")
                canvas.onClick = { [weak self] in
                    self?.clickCount += 1; print("FIXTURE custom clicks: \(self?.clickCount ?? 0)"); fflush(stdout)
                }
                target.contentView = canvas
            } else {
                let button = NSButton(title: "Clicks: 0", target: self, action: #selector(countClick(_:)))
                button.frame = target.contentView!.bounds
                target.contentView?.addSubview(button)
            }
            windows.append(target); target.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let frontOnly = ProcessInfo.processInfo.arguments.contains("--front-only")
        support = makeWindow(title: "Expedition terrain — high window", frame: .init(x: 600, y: base + 260, width: 320, height: frontOnly ? 420 : 240))
        let lower = makeWindow(title: "Expedition terrain — landing window", frame: .init(x: 240, y: base + 20, width: 320, height: 180))
        if !frontOnly { lower.orderFront(nil) }
        if !ProcessInfo.processInfo.arguments.contains("--low-only") { support.orderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--exercise") {
            schedule(5) { self.move() }
            schedule(35) { self.narrow() }
            schedule(50) { self.coverHigh() }
            schedule(65) { self.closeHigh() }
        }
    }
    @objc private func countClick(_ sender: NSButton) {
        clickCount += 1; sender.title = "Clicks: \(clickCount)"
        print("FIXTURE clicks: \(clickCount)"); fflush(stdout)
    }
    private func schedule(_ seconds: Double, action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { action() }
    }
    private func makeWindow(title: String, frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "Disposable windows for native expedition checks.")
        stack.addArrangedSubview(label)
        let field = NSTextField(string: "Type here while the explorer travels")
        field.setAccessibilityIdentifier("fixtureTyping"); stack.addArrangedSubview(field)
        for (title, action) in [("Move high window", #selector(move)), ("Narrow high window", #selector(narrow)), ("Cover high window", #selector(coverHigh)), ("Close high window", #selector(closeHigh))] {
            stack.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 12), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 12), stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -12)])
        windows.append(window); return window
    }
    @objc private func move() { support.setFrameOrigin(.init(x: support.frame.minX + 40, y: support.frame.minY + 20)) }
    @objc private func narrow() { support.setFrame(.init(x: support.frame.minX, y: support.frame.minY, width: 150, height: support.frame.height), display: true) }
    @objc private func coverHigh() {
        cover = makeWindow(title: "Expedition terrain — occluder", frame: .init(x: support.frame.minX - 50, y: support.frame.maxY - 50, width: support.frame.width + 100, height: 180))
        cover?.orderFront(nil)
    }
    @objc private func closeHigh() { support.close() }
}
let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.setActivationPolicy(.regular)
withExtendedLifetime(delegate) { app.run() }
