import AppKit
import ExpeditionCore
@preconcurrency import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private var welcome: WelcomeController?
    private var needsWelcome: Bool { UserDefaults.standard.integer(forKey: "welcomeVersion") < 1 }
    private var idleItem: NSMenuItem!
    private var keyboardItem: NSMenuItem!
    private var paceItem: NSMenuItem!
    private var debugItem: NSMenuItem?
    private var activitiesMenu: NSMenu!
    private let hotKey = ExplorerControlHotKey()
    private var isPaused = ProcessInfo.processInfo.arguments.contains("--paused")
    private var idleExploration = UserDefaults.standard.object(forKey: "idleExploration") as? Bool ?? !UserDefaults.standard.bool(forKey: "expeditionPaused")
    private var gentlePace = UserDefaults.standard.bool(forKey: "gentlePace")
    #if DEBUG
    private var showsDebug = ProcessInfo.processInfo.arguments.contains("--debug-terrain") || UserDefaults.standard.bool(forKey: "debugGuides")
    private var playground: AnimationPlaygroundController?
    #else
    private var showsDebug = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        overlay = OverlayController()
        overlay?.onKeyboardControlChanged = { [weak self] _ in self?.updateMenu() }
        overlay?.setIdleExploration(idleExploration)
        overlay?.setDebugVisible(showsDebug)
        overlay?.setGentlePace(gentlePace)
        overlay?.setPaused(isPaused)
        overlay?.show()
        hotKey.onTrigger = { [weak self] in self?.toggleKeyboard() }
        hotKey.register()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trace-movement") { print("CONTROL global shortcut registered: \(hotKey.isRegistered)"); fflush(stdout) }
        #endif
        updateMenu()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(frontAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--playground") { openPlayground() }
        if ProcessInfo.processInfo.arguments.contains("--keyboard-control") { setPaused(false); overlay?.setKeyboardControl(true) }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let previewWelcome = ProcessInfo.processInfo.arguments.contains("--welcome")
        if previewWelcome || needsWelcome {
            DispatchQueue.main.async { [weak self] in self?.showWelcome(markSeen: !previewWelcome) }
        }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "figure.hiking", accessibilityDescription: "The Other Sock") {
            image.isTemplate = true; item.button?.image = image
        } else { item.button?.title = "Sock" }
        let menu = NSMenu()
        menu.autoenablesItems = false; menu.delegate = self
        let heading = NSMenuItem(title: "The Other Sock", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading); menu.addItem(.separator())
        idleItem = add("Enable Idle Exploration", action: #selector(toggleIdle), to: menu)
        keyboardItem = add("Take Control", action: #selector(toggleKeyboard), to: menu)
        keyboardItem.keyEquivalent = " "; keyboardItem.keyEquivalentModifierMask = [.control, .option]
        activitiesMenu = NSMenu(title: "Actions")
        activitiesMenu.autoenablesItems = false; activitiesMenu.delegate = self
        let actions = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        actions.submenu = activitiesMenu; menu.addItem(actions)
        menu.addItem(.separator())
        let settings = NSMenu(title: "Settings"); settings.autoenablesItems = false
        paceItem = add("Slow Movement", action: #selector(togglePace), to: settings)
        _ = add("Allow Clicks in Other Apps…", action: #selector(allowClicks), to: settings)
        settings.addItem(.separator())
        _ = add("Bring Explorer Back to Desktop", action: #selector(resetExpedition), to: settings)
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings; menu.addItem(settingsItem)
        _ = add("Controls & Tips…", action: #selector(showTips), to: menu)
        #if DEBUG
        let development = NSMenu(title: "Developer Tools"); development.autoenablesItems = false
        debugItem = add("Show Window Guides", action: #selector(toggleDebug), to: development)
        _ = add("Animation Playground…", action: #selector(openPlayground), to: development)
        let developmentItem = NSMenuItem(title: "Developer Tools", action: nil, keyEquivalent: "")
        developmentItem.submenu = development; menu.addItem(developmentItem)
        #endif
        menu.addItem(.separator())
        _ = add("Quit The Other Sock", action: #selector(quit), to: menu)
        item.menu = menu; statusItem = item
        updateMenu()
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item); return item
    }
    private func actionTitle(_ activity: ExplorerActivity) -> String {
        switch activity {
        case .walk: return "Walk Along This Edge"
        case .climb: return "Climb Up a Window"
        case .abseil: return "Abseil Down"
        case .grapple: return "Use the Grappling Hook"
        case .ropeClimb: return "Climb the Rope"
        case .swing: return "Swing on the Rope"
        case .releaseRope: return "Let Go of the Rope"
        case .parachute: return "Jump and Parachute"
        case .bananaAdventure: return "Look for the Sock"
        case .automatic: return "Enable Idle Exploration"
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
        guard menu === activitiesMenu else { return }
        menu.removeAllItems()
        let state = overlay?.keyboardControlEnabled == true ? "You're in control" : (idleExploration ? "Exploring when idle" : "Idle exploration is off")
        let status = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status); menu.addItem(.separator())
        let available = overlay?.availableActivities ?? []
        for (index, activity) in ExplorerActivity.allCases.enumerated() where activity != .automatic {
            let unavailable = activity == .releaseRope ? " (Attach a rope first)" : " (No suitable route nearby)"
            let item = add(actionTitle(activity) + (available.contains(activity) ? "" : unavailable), action: #selector(triggerActivity(_:)), to: menu)
            item.tag = index; item.isEnabled = available.contains(activity)
        }
    }
    @objc private func triggerActivity(_ sender: NSMenuItem) {
        guard ExplorerActivity.allCases.indices.contains(sender.tag) else { return }
        setPaused(false); overlay?.requestActivity(ExplorerActivity.allCases[sender.tag])
    }
    @objc private func toggleIdle() {
        idleExploration.toggle()
        UserDefaults.standard.set(idleExploration, forKey: "idleExploration")
        setPaused(false)
        overlay?.setIdleExploration(idleExploration)
        updateMenu()
    }
    @objc private func toggleKeyboard() {
        guard let overlay else { return }
        let enabled = !overlay.keyboardControlEnabled
        if enabled { setPaused(false) }
        overlay.setKeyboardControl(enabled, restoreFocus: !enabled)
        updateMenu()
    }
    @objc private func allowClicks() { overlay?.requestClickAccess() }
    private func setPaused(_ paused: Bool) { isPaused = paused; overlay?.setPaused(paused); updateMenu() }
    @objc private func resetExpedition() { overlay?.resetExpedition() }
    @objc private func toggleDebug() {
        showsDebug.toggle(); UserDefaults.standard.set(showsDebug, forKey: "debugGuides")
        overlay?.setDebugVisible(showsDebug); updateMenu()
    }
    @objc private func togglePace() {
        gentlePace.toggle(); UserDefaults.standard.set(gentlePace, forKey: "gentlePace")
        overlay?.setGentlePace(gentlePace); updateMenu()
    }
    @objc private func showTips() { showWelcome(markSeen: true) }
    private func showWelcome(markSeen: Bool) {
        overlay?.setKeyboardControl(false)
        if welcome == nil {
            let guide = WelcomeController()
            guide.onIdleChanged = { [weak self] enabled in
                guard let self, enabled != self.idleExploration else { return }; self.toggleIdle()
            }
            guide.onAllowClicks = { [weak self] in self?.overlay?.requestClickAccess() }
            guide.onTakeControl = { [weak self] in
                self?.setPaused(false); self?.overlay?.setKeyboardControl(true); self?.updateMenu()
            }
            welcome = guide
        }
        welcome?.onClose = { [weak self] in
            if markSeen { UserDefaults.standard.set(1, forKey: "welcomeVersion") }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.overlay?.keyboardControlEnabled != true else { return }
                self.overlay?.restoreExternalFocus()
            }
        }
        welcome?.open(idleExploration: idleExploration)
    }
    @objc private func willSleep() { overlay?.setSleeping(true) }
    @objc private func didWake() { overlay?.setSleeping(false) }
    @objc private func frontAppChanged() { overlay?.recordFrontApp(); overlay?.checkDesktop() }
    @objc private func spaceChanged() { overlay?.desktopChanged() }
    private func updateMenu() {
        idleItem?.state = idleExploration ? .on : .off
        debugItem?.state = showsDebug ? .on : .off
        paceItem?.state = gentlePace ? .on : .off
        keyboardItem?.state = overlay?.keyboardControlEnabled == true ? .on : .off
        keyboardItem?.title = overlay?.keyboardControlEnabled == true ? "Release Control" : "Take Control"
        keyboardItem?.toolTip = hotKey.isRegistered ? "Control–Option–Space works from any app." : "The shortcut is unavailable; use this menu item."
        statusItem?.button?.toolTip = "The Other Sock — \(overlay?.keyboardControlEnabled == true ? "you're in control" : (idleExploration ? "exploring" : "resting"))"
    }
    @objc private func displaysChanged() { overlay?.updateDisplay() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    #if DEBUG
    func runActivityMenuChecks() -> Bool {
        let previousIdle = UserDefaults.standard.object(forKey: "idleExploration")
        let previousWelcome = UserDefaults.standard.object(forKey: "welcomeVersion")
        installMenu(); overlay = OverlayController()
        defer {
            welcome?.onClose = nil; welcome?.close(); welcome = nil
            if let previousWelcome { UserDefaults.standard.set(previousWelcome, forKey: "welcomeVersion") }
            else { UserDefaults.standard.removeObject(forKey: "welcomeVersion") }
            overlay?.close(); overlay = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }; statusItem = nil
            if let previousIdle { UserDefaults.standard.set(previousIdle, forKey: "idleExploration") }
            else { UserDefaults.standard.removeObject(forKey: "idleExploration") }
        }
        menuNeedsUpdate(activitiesMenu)
        var passed = true
        func check(_ result: Bool, _ name: String) { print("NATIVE \(result ? "PASS" : "FAIL") \(name)"); passed = passed && result }
        let commands = activitiesMenu.items.filter { $0.action != nil }
        check(commands.count == ExplorerActivity.allCases.count - 1, "Actions contains explicit activities without duplicate automatic mode")
        let rope = commands.first { $0.tag == ExplorerActivity.allCases.firstIndex(of: .abseil) }
        check(rope?.isEnabled == overlay?.availableActivities.contains(.abseil), "Actions reflects reachable abseil routes")
        if let walk = commands.first(where: { $0.tag == ExplorerActivity.allCases.firstIndex(of: .walk) }) {
            activitiesMenu.performActionForItem(at: activitiesMenu.index(of: walk))
            check(overlay?.activityStatus.hasPrefix("Walk:") == true, "Walk action reaches desktop simulation")
        } else { check(false, "Walk action reaches desktop simulation") }
        idleExploration = true; toggleIdle()
        check(overlay?.idleExplorationEnabled == false && idleItem.state == .off, "idle checkbox stops exploration without freezing physics")
        toggleIdle()
        check(overlay?.idleExplorationEnabled == true && idleItem.state == .on, "idle checkbox restores exploration")
        check(statusItem?.menu?.items.contains { $0.title.contains("Expedition") || $0.title.contains("Prototype") } == false, "main menu uses plain product labels")
        UserDefaults.standard.removeObject(forKey: "welcomeVersion")
        check(needsWelcome, "first launch schedules the welcome guide")
        showWelcome(markSeen: true)
        check(welcome?.window?.isVisible == true, "welcome opens as a reusable non-modal guide")
        welcome?.close()
        check(!needsWelcome, "dismissing the guide records first-run completion")
        let shortcut = ExplorerControlHotKey()
        var presses = 0; shortcut.onTrigger = { presses += 1 }; shortcut.register()
        check(shortcut.isRegistered, "global Control Option Space shortcut registers")
        check(shortcut.dispatchNativeCheck() == noErr && presses == 1, "registered hotkey event reaches the control callback")
        shortcut.close()
        check(!shortcut.isRegistered, "global shortcut unregisters on cleanup")
        return passed
    }
    @objc private func openPlayground() {
        if playground == nil { playground = AnimationPlaygroundController() }; playground?.open()
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.close()
        welcome?.close(); welcome = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        overlay?.close(); overlay = nil
        #if DEBUG
        playground?.close(); playground = nil
        #endif
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }; statusItem = nil
    }
}

/// A registered system hotkey, rather than a global keyboard event monitor.
@MainActor
final class ExplorerControlHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    var onTrigger: (() -> Void)?
    var isRegistered: Bool { reference != nil }
    func register() {
        guard reference == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ExplorerControlHotKey>.fromOpaque(pointer).takeUnretainedValue()
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed = false }
                else if !owner.pressed { owner.pressed = true; owner.onTrigger?() }
            }
            return noErr
        }, 2, &specs, pointer, &handler)
        guard installed == noErr else { return }
        let result = RegisterEventHotKey(49, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x536f636b, id: 1), GetApplicationEventTarget(), 0, &reference)
        if result != noErr { close() }
    }
    #if DEBUG
    func dispatchNativeCheck() -> OSStatus {
        var event: EventRef?
        let result = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event)
        guard result == noErr, let event else { return result }
        defer { ReleaseEvent(event) }
        let first = SendEventToEventTarget(event, GetApplicationEventTarget())
        _ = SendEventToEventTarget(event, GetApplicationEventTarget()) // Holding must not toggle twice.
        return first
    }
    #endif
    func close() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        pressed = false
    }
}
