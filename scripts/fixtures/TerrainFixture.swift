import AppKit

@MainActor
final class Fixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var support: NSWindow!
    private var cover: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { return }
        let base = screen.visibleFrame.minY
        support = makeWindow(title: "Expedition terrain — high window", frame: .init(x: 600, y: base + 260, width: 320, height: 240))
        let lower = makeWindow(title: "Expedition terrain — landing window", frame: .init(x: 240, y: base + 20, width: 320, height: 180))
        lower.orderFront(nil)
        if !ProcessInfo.processInfo.arguments.contains("--low-only") { support.orderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--exercise") {
            schedule(5) { self.move() }
            schedule(35) { self.narrow() }
            schedule(50) { self.coverHigh() }
            schedule(65) { self.closeHigh() }
        }
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
