import AppKit
import ExpeditionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private var pauseItem: NSMenuItem!
    private var resumeItem: NSMenuItem!
    private var debugItem: NSMenuItem!
    private var activitiesMenu: NSMenu!
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
        activitiesMenu = NSMenu(title: "Activities")
        activitiesMenu.autoenablesItems = false
        activitiesMenu.delegate = self
        let activitiesItem = NSMenuItem(title: "Activities", action: nil, keyEquivalent: "")
        activitiesItem.submenu = activitiesMenu
        menu.insertItem(activitiesItem, at: 5)
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === activitiesMenu else { return }
        menu.removeAllItems()
        let status = NSMenuItem(title: overlay?.activityStatus ?? "Preparing terrain…", action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status); menu.addItem(.separator())
        let available = overlay?.availableActivities ?? []
        for (index, activity) in ExplorerActivity.allCases.enumerated() {
            if activity == .automatic { menu.addItem(.separator()) }
            let unavailable = activity == .releaseRope ? " — no rope attached" : " — no reachable route"
            let item = add(activity.title + (available.contains(activity) ? "" : unavailable), action: #selector(triggerActivity(_:)), to: menu)
            item.tag = index; item.isEnabled = available.contains(activity)
        }
    }

    @objc private func triggerActivity(_ sender: NSMenuItem) {
        guard ExplorerActivity.allCases.indices.contains(sender.tag) else { return }
        setPaused(false)
        overlay?.requestActivity(ExplorerActivity.allCases[sender.tag])
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
    func runActivityMenuChecks() -> Bool {
        let previousPause = UserDefaults.standard.object(forKey: "expeditionPaused")
        installMenu()
        overlay = OverlayController()
        defer {
            overlay?.close(); overlay = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            if let previousPause { UserDefaults.standard.set(previousPause, forKey: "expeditionPaused") }
            else { UserDefaults.standard.removeObject(forKey: "expeditionPaused") }
        }
        menuNeedsUpdate(activitiesMenu)
        var passed = true
        func check(_ result: Bool, _ name: String) { print("NATIVE \(result ? "PASS" : "FAIL") \(name)"); passed = passed && result }
        let commands = activitiesMenu.items.filter { $0.action != nil }
        check(commands.count == ExplorerActivity.allCases.count, "all activity commands appear in submenu")
        let rope = commands.first { $0.tag == ExplorerActivity.allCases.firstIndex(of: .abseil) }
        check(rope?.isEnabled == overlay?.availableActivities.contains(.abseil), "activity menu reflects reachable abseil routes")
        if let walk = commands.first(where: { $0.tag == ExplorerActivity.allCases.firstIndex(of: .walk) }) {
            activitiesMenu.performActionForItem(at: activitiesMenu.index(of: walk))
            check(overlay?.activityStatus.hasPrefix("Walk:") == true, "Walk menu action reaches desktop simulation")
        } else { check(false, "Walk menu action reaches desktop simulation") }
        if let automatic = commands.first(where: { $0.tag == ExplorerActivity.allCases.firstIndex(of: .automatic) }) {
            activitiesMenu.performActionForItem(at: activitiesMenu.index(of: automatic))
            check(overlay?.activityStatus == "Automatic adventures", "automatic menu action restores mission control")
        } else { check(false, "automatic menu action restores mission control") }
        return passed
    }

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
