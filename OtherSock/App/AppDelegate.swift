import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private var pauseItem: NSMenuItem!
    private var resumeItem: NSMenuItem!
    private var debugItem: NSMenuItem!
    private var isPaused = false
    private var showsDebug = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        overlay = OverlayController()
        overlay?.show()
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "figure.hiking", accessibilityDescription: "The Other Sock") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "Sock"
        }
        item.button?.toolTip = "The Other Sock — expedition running"
        let menu = NSMenu()
        let heading = NSMenuItem(title: "The Other Sock · Prototype", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        pauseItem = add("Pause Expedition", action: #selector(pause), to: menu)
        resumeItem = add("Resume Expedition", action: #selector(resume), to: menu)
        debugItem = add("Show Debug Guides", action: #selector(toggleDebug), to: menu)
        menu.addItem(.separator())
        _ = add("Quit The Other Sock", action: #selector(quit), to: menu)
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateMenu()
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func pause() { setPaused(true) }
    @objc private func resume() { setPaused(false) }
    private func setPaused(_ paused: Bool) {
        isPaused = paused
        overlay?.setPaused(paused)
        updateMenu()
    }

    @objc private func toggleDebug() {
        showsDebug.toggle()
        overlay?.setDebugVisible(showsDebug)
        updateMenu()
    }

    private func updateMenu() {
        pauseItem.isEnabled = !isPaused
        resumeItem.isEnabled = isPaused
        debugItem.state = showsDebug ? .on : .off
        statusItem?.button?.toolTip = "The Other Sock — expedition \(isPaused ? "paused" : "running")"
    }

    @objc private func displaysChanged() {
        overlay?.updateDisplay()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        overlay?.close()
        overlay = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
