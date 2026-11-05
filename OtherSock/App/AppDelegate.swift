import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private var pauseItem: NSMenuItem!
    private var resumeItem: NSMenuItem!
    private var debugItem: NSMenuItem!
    private var isPaused = ProcessInfo.processInfo.arguments.contains("--paused") || UserDefaults.standard.bool(forKey: "expeditionPaused")
    private var gentlePace = UserDefaults.standard.bool(forKey: "gentlePace")
    private var paceItem: NSMenuItem!
    private var showsDebug = ProcessInfo.processInfo.arguments.contains("--debug-terrain") || UserDefaults.standard.bool(forKey: "debugGuides")
    #if DEBUG
    private var playground: AnimationPlaygroundController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        overlay = OverlayController()
        overlay?.setDebugVisible(showsDebug)
        overlay?.setGentlePace(gentlePace)
        overlay?.setPaused(isPaused)
        overlay?.show()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(frontAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--playground") { openPlayground() }
        #endif
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
        _ = add("Reset Expedition", action: #selector(resetExpedition), to: menu)
        paceItem = add("Gentle Pace", action: #selector(togglePace), to: menu)
        debugItem = add("Show Debug Guides", action: #selector(toggleDebug), to: menu)
        #if DEBUG
        _ = add("Animation Playground…", action: #selector(openPlayground), to: menu)
        #endif
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
        UserDefaults.standard.set(paused, forKey: "expeditionPaused")
        overlay?.setPaused(paused)
        updateMenu()
    }

    @objc private func resetExpedition() { overlay?.resetExpedition() }

    @objc private func toggleDebug() {
        showsDebug.toggle()
        UserDefaults.standard.set(showsDebug, forKey: "debugGuides")
        overlay?.setDebugVisible(showsDebug)
        updateMenu()
    }

    @objc private func togglePace() {
        gentlePace.toggle()
        UserDefaults.standard.set(gentlePace, forKey: "gentlePace")
        overlay?.setGentlePace(gentlePace)
        updateMenu()
    }

    @objc private func willSleep() { overlay?.setSleeping(true) }
    @objc private func didWake() { overlay?.setSleeping(false) }
    @objc private func frontAppChanged() { overlay?.checkDesktop() }
    @objc private func spaceChanged() { overlay?.desktopChanged() }

    private func updateMenu() {
        pauseItem.isEnabled = !isPaused
        resumeItem.isEnabled = isPaused
        debugItem.state = showsDebug ? .on : .off
        paceItem.state = gentlePace ? .on : .off
        statusItem?.button?.toolTip = "The Other Sock — expedition \(isPaused ? "paused" : "running")"
    }

    @objc private func displaysChanged() {
        overlay?.updateDisplay()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    #if DEBUG
    @objc private func openPlayground() {
        if playground == nil { playground = AnimationPlaygroundController() }
        playground?.open()
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        overlay?.close()
        overlay = nil
        #if DEBUG
        playground?.close()
        playground = nil
        #endif
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
