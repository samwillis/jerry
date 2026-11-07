import AppKit
import ExpeditionCore
@preconcurrency import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let applicationArtwork = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    private var overlay: OverlayController?
    private var welcome: WelcomeController?
    private var taskController: AgentTaskController?
    private var needsWelcome: Bool { UserDefaults.standard.integer(forKey: "welcomeVersion") < 1 }
    private var idleItem: NSMenuItem!
    private var keyboardItem: NSMenuItem!
    private var askItem: NSMenuItem!
    private var stopTaskItem: NSMenuItem?
    private var runWhenExploring = UserDefaults.standard.bool(forKey: "runWhenExploring")
    private var fasterRopeWork = UserDefaults.standard.bool(forKey: "fasterRopeWork")
    private var debugItem: NSMenuItem?
    private var exploreInsideWindows = UserDefaults.standard.bool(forKey: "exploreInsideWindows")
    private var developerMenu: NSMenu!
    private let hotKey = ExplorerControlHotKey()
    private let askHotKey = ExplorerControlHotKey(keyCode: 36, id: 2)
    private var isPaused = ProcessInfo.processInfo.arguments.contains("--paused")
    private var idleExploration = UserDefaults.standard.object(forKey: "idleExploration") as? Bool ?? !UserDefaults.standard.bool(forKey: "expeditionPaused")
    private var gentlePace = UserDefaults.standard.bool(forKey: "gentlePace")
    private var showsDebug = ProcessInfo.processInfo.arguments.contains("--debug-terrain") || UserDefaults.standard.bool(forKey: "debugGuides")
    #if DEBUG
    private var playground: AnimationPlaygroundController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let applicationArtwork { NSApp.applicationIconImage = applicationArtwork }
        installMenu()
        overlay = OverlayController()
        overlay?.onKeyboardControlChanged = { [weak self] enabled in
            if enabled { self?.taskController?.manualTakeover() }
            self?.updateMenu()
        }
        overlay?.onPromptRequested = { [weak self] in self?.openTasks() }
        overlay?.onTaskInterrupted = { [weak self] in self?.taskController?.stop() }
        overlay?.setIdleExploration(idleExploration)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--inside-windows") { exploreInsideWindows = true }
        #endif
        overlay?.setExploreInsideWindows(exploreInsideWindows)
        overlay?.setDebugVisible(showsDebug)
        overlay?.setGentlePace(gentlePace)
        overlay?.setRunWhenExploring(runWhenExploring)
        overlay?.setFasterRopeWork(fasterRopeWork)
        overlay?.setPaused(isPaused)
        overlay?.show()
        hotKey.onTrigger = { [weak self] in self?.toggleKeyboard() }
        hotKey.register()
        askHotKey.onTrigger = { [weak self] in self?.openTasks() }
        askHotKey.register()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trace-movement") { print("CONTROL global shortcut registered: \(hotKey.isRegistered)"); fflush(stdout) }
        #endif
        updateMenu()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(frontAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if ProcessInfo.processInfo.arguments.contains("--tasks") { openTasks() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-menu") {
            DispatchQueue.main.async { [weak self] in self?.statusItem?.button?.performClick(nil) }
        }
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
        if NSApp.mainMenu == nil {
            let bar = NSMenu()
            let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu
            appMenu.addItem(withTitle: "About Jerry", action: #selector(showAbout), keyEquivalent: "").target = self
            appMenu.addItem(.separator())
            let ask = appMenu.addItem(withTitle: "Ask Jerry…", action: #selector(openTasks), keyEquivalent: "\r")
            ask.target = self; ask.keyEquivalentModifierMask = [.control, .option]
            appMenu.addItem(withTitle: "Expedition Journal…", action: #selector(showAgentActivity), keyEquivalent: "").target = self
            appMenu.addItem(.separator())
            appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            appMenu.addItem(withTitle: "Quit Jerry", action: #selector(quit), keyEquivalent: "q").target = self
            bar.addItem(appItem)
            let edit = NSMenu(title: "Edit"); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; bar.addItem(editItem)
            for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
                edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
            }
            NSApp.mainMenu = bar
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = ExplorerRig.menuBarArtwork()
        let menu = NSMenu()
        menu.autoenablesItems = false; menu.delegate = self
        let heading = NSMenuItem(title: "Jerry", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading); menu.addItem(.separator())
        askItem = add("Ask Jerry…", action: #selector(openTasks), to: menu)
        askItem.keyEquivalent = "\r"; askItem.keyEquivalentModifierMask = [.control, .option]
        _ = add("Expedition Journal…", action: #selector(showAgentActivity), to: menu)
        menu.addItem(.separator())
        keyboardItem = add("Take Control", action: #selector(toggleKeyboard), to: menu)
        keyboardItem.keyEquivalent = " "; keyboardItem.keyEquivalentModifierMask = [.control, .option]
        idleItem = add("Enable Idle Exploration", action: #selector(toggleIdle), to: menu)
        stopTaskItem = add("Stop Task", action: #selector(stopTask), to: menu)
        menu.addItem(.separator())

        _ = add("Settings…", action: #selector(openSettings), to: menu)
        _ = add("Controls & Tips…", action: #selector(showTips), to: menu)
        _ = add("About Jerry", action: #selector(showAbout), to: menu)

        developerMenu = NSMenu(title: "Developer Tools"); developerMenu.autoenablesItems = false; developerMenu.delegate = self
        let developmentItem = NSMenuItem(title: "Developer Tools", action: nil, keyEquivalent: ""); developmentItem.submenu = developerMenu; menu.addItem(developmentItem)
        menuNeedsUpdate(developerMenu)
        menu.addItem(.separator())
        _ = add("Quit Jerry", action: #selector(quit), to: menu)
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
        case .sockSearch: return "Look for the Sock"
        case .automatic: return "Enable Idle Exploration"
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
        guard menu === developerMenu else { return }
        menu.removeAllItems()
        debugItem = add("Show Terrain Guides", action: #selector(toggleDebug), to: menu)
        #if DEBUG
        _ = add("Animation Playground…", action: #selector(openPlayground), to: menu)
        #endif
        menu.addItem(.separator())
        let heading = NSMenuItem(title: "Test an Activity", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        let state = overlay?.keyboardControlEnabled == true ? "You're in control" : (idleExploration ? "Exploring when idle" : "Idle exploration is off")
        let status = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status); menu.addItem(.separator())
        let available = overlay?.availableActivities ?? []
        for (index, activity) in ExplorerActivity.allCases.enumerated() where activity != .automatic {
            let unavailable = activity == .releaseRope ? " (Attach a rope first)" : " (No suitable route nearby)"
            let item = add(actionTitle(activity) + (available.contains(activity) ? "" : unavailable), action: #selector(triggerActivity(_:)), to: menu)
            item.tag = index; item.isEnabled = available.contains(activity)
        }
        updateMenu()
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
    private func setPaused(_ paused: Bool) { isPaused = paused; overlay?.setPaused(paused); updateMenu() }
    @objc private func resetExpedition() { overlay?.resetExpedition() }
    @objc private func toggleDebug() {
        showsDebug.toggle(); UserDefaults.standard.set(showsDebug, forKey: "debugGuides")
        overlay?.setDebugVisible(showsDebug); updateMenu()
    }
    private func prepareTasks() {
        if taskController == nil {
            let controller = AgentTaskController()
            controller.onPreferencesChanged = { [weak self] in self?.applySettings() }
            controller.onResetExplorer = { [weak self] in self?.resetExpedition() }
            controller.onWelcomeRequested = { [weak self] in self?.showWelcome(markSeen: true) }
            controller.onTakeControlRequested = { [weak self] in self?.toggleKeyboard() }
            controller.onTaskStateChanged = { [weak self] in self?.updateMenu() }
            controller.shortcutStatusProvider = { [weak self] in
                guard let self else { return "" }
                if self.askHotKey.isRegistered && self.hotKey.isRegistered { return "Global shortcuts work from any app." }
                return "A shortcut is unavailable. Use Ask Jerry or Take Control in the menu."
            }
            controller.onStop = { [weak self] in
                guard let self else { return }
                self.overlay?.stopAgent(); self.overlay?.setIdleExploration(self.idleExploration)
            }
            controller.computer.reach = { [weak self] point in guard let self else { throw CancellationError() }; try await self.overlay?.reachForAgent(point) }
            controller.computer.reading = { [weak self] in self?.overlay?.setAgentReading($0) }
            overlay?.onAgentHandMoved = { [weak controller] in controller?.computer.moveHand($0) }
            controller.onBeforeInput = { [weak self] in self?.overlay?.agentInputVisible(false) }
            controller.onAfterInput = { [weak self] in self?.overlay?.agentInputVisible(true) }
            controller.onPromptCancelled = { [weak self] in self?.overlay?.setKeyboardControl(true) }
            controller.onPromptOpened = { [weak self] in self?.overlay?.setIdleExploration(false) }
            controller.onPromptDismissed = { [weak self] in guard let self else { return }; self.overlay?.setIdleExploration(self.idleExploration) }
            controller.onSubmitted = { [weak self] in
                guard let self else { return }
                self.overlay?.beginAgent(); self.overlay?.restoreExternalFocus()
            }
            controller.explorerFrame = { [weak self] in self?.overlay?.explorerScreenFrame ?? .zero }
            overlay?.onExplorerMoved = { [weak controller] in controller?.updatePromptPosition() }
            taskController = controller
        }
    }
    @objc private func openTasks() {
        let resume = overlay?.keyboardControlEnabled == true
        overlay?.setKeyboardControl(false)
        prepareTasks(); taskController?.openPrompt(resumeControl: resume)
    }
    @objc private func showAgentActivity() { prepareTasks(); taskController?.showActivity() }
    @objc private func openAISettings() {
        overlay?.setKeyboardControl(false)
        prepareTasks(); taskController?.openSettings(section: "AI")
    }
    @objc private func openSettings() { overlay?.setKeyboardControl(false); prepareTasks(); taskController?.openSettings() }
    @objc private func showTips() { overlay?.setKeyboardControl(false); prepareTasks(); taskController?.openSettings(section: "Controls") }
    @objc private func stopTask() { taskController?.stop() }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "Jerry", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", .credits: NSAttributedString(string: "Jerry. One small adventurer. One missing sock.")]
        // Avoid the placeholder held by Launch Services for an earlier local build.
        if let applicationArtwork { options[.applicationIcon] = applicationArtwork }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    private func applySettings() {
        let defaults = UserDefaults.standard
        idleExploration = defaults.object(forKey: "idleExploration") as? Bool ?? idleExploration
        runWhenExploring = defaults.bool(forKey: "runWhenExploring"); fasterRopeWork = defaults.bool(forKey: "fasterRopeWork")
        gentlePace = defaults.bool(forKey: "gentlePace"); exploreInsideWindows = defaults.bool(forKey: "exploreInsideWindows"); showsDebug = defaults.bool(forKey: "debugGuides")
        overlay?.setIdleExploration(idleExploration); overlay?.setRunWhenExploring(runWhenExploring); overlay?.setFasterRopeWork(fasterRopeWork)
        overlay?.setGentlePace(gentlePace); overlay?.setExploreInsideWindows(exploreInsideWindows); overlay?.setDebugVisible(showsDebug)
        updateMenu()
    }
    private func showWelcome(markSeen: Bool) {
        overlay?.setKeyboardControl(false)
        if welcome == nil {
            let guide = WelcomeController()
            guide.onIdleChanged = { [weak self] enabled in
                guard let self, enabled != self.idleExploration else { return }; self.toggleIdle()
            }
            guide.onSetupAI = { [weak self] in self?.openAISettings() }
            guide.onTakeControl = { [weak self] in
                self?.setPaused(false); self?.overlay?.setKeyboardControl(true); self?.updateMenu()
            }
            welcome = guide
        }
        welcome?.onClose = { [weak self] in
            if markSeen { UserDefaults.standard.set(1, forKey: "welcomeVersion") }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.overlay?.keyboardControlEnabled != true, self.taskController?.window?.isVisible != true else { return }
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
        stopTaskItem?.isHidden = taskController?.isTaskRunning != true
        statusItem?.menu?.items.first { $0.title == "Developer Tools" }?.isHidden = !UserDefaults.standard.bool(forKey: "developerToolsEnabled")
        idleItem?.state = idleExploration ? .on : .off
        debugItem?.state = showsDebug ? .on : .off
        keyboardItem?.state = overlay?.keyboardControlEnabled == true ? .on : .off
        keyboardItem?.title = overlay?.keyboardControlEnabled == true ? "Release Control" : "Take Control"
        askItem?.toolTip = askHotKey.isRegistered ? "Control–Option–Return opens a prompt from any app." : "The shortcut is unavailable; use this menu item."
        keyboardItem?.toolTip = hotKey.isRegistered ? "Control–Option–Space works from any app." : "The shortcut is unavailable; use this menu item."
        statusItem?.button?.toolTip = "Jerry — \(overlay?.keyboardControlEnabled == true ? "you're in control" : (idleExploration ? "exploring" : "resting"))"
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
        menuNeedsUpdate(developerMenu)
        var passed = true
        func check(_ result: Bool, _ name: String) { print("NATIVE \(result ? "PASS" : "FAIL") \(name)"); passed = passed && result }
        check(statusItem?.button?.image?.isTemplate == true && statusItem?.button?.image?.size == NSSize(width: 22, height: 22), "menu bar uses Jerry's actual head as a monochrome template")
        let developer = statusItem?.menu?.items.first { $0.title == "Developer Tools" }?.submenu
        check(developer?.items.contains { $0.title == "Show Terrain Guides" && $0.action == #selector(toggleDebug) } == true && statusItem?.menu?.items.contains { $0.action == #selector(toggleDebug) } == false, "terrain guides are available inside Developer Tools")
        check(developerMenu === developer && developer?.items.contains { $0.action == #selector(triggerActivity(_:)) } == true, "activity tests are directly inside Developer Tools")
        check(statusItem?.menu?.items.allSatisfy { $0.submenu?.items.allSatisfy { $0.submenu == nil } ?? true } == true, "status menu has at most two levels")
        check(statusItem?.menu?.items.first { $0.title == "Developer Tools" }?.isHidden == !UserDefaults.standard.bool(forKey: "developerToolsEnabled"), "developer menu follows the Advanced opt-in")
        check(stopTaskItem?.isHidden == true, "Stop Task is hidden when no task is running")
        check(askItem.keyEquivalent == "\r" && askItem.keyEquivalentModifierMask == [.control, .option], "Ask Explorer advertises Control Option Return")
        check(statusItem?.menu?.items.contains { $0.title == "Settings…" && $0.submenu == nil && $0.action == #selector(openSettings) } == true, "Settings opens a unified window without nested preferences")
        let commands = developerMenu.items.filter { $0.action == #selector(triggerActivity(_:)) }
        check(commands.count == ExplorerActivity.allCases.count - 1, "Actions contains explicit activities without duplicate automatic mode")
        let rope = commands.first { $0.tag == ExplorerActivity.allCases.firstIndex(of: .abseil) }
        check(rope?.isEnabled == overlay?.availableActivities.contains(.abseil), "Actions reflects reachable abseil routes")
        if let walk = commands.first(where: { $0.tag == ExplorerActivity.allCases.firstIndex(of: .walk) }) {
            developerMenu.performActionForItem(at: developerMenu.index(of: walk))
            check(overlay?.activityStatus.hasPrefix("Walk:") == true, "Walk action reaches desktop simulation")
        } else { check(false, "Walk action reaches desktop simulation") }
        idleExploration = true; toggleIdle()
        check(overlay?.idleExplorationEnabled == false && idleItem.state == .off, "idle checkbox stops exploration without freezing physics")
        toggleIdle()
        check(overlay?.idleExplorationEnabled == true && idleItem.state == .on, "idle checkbox restores exploration")
        check(statusItem?.menu?.items.contains { $0.title == "Expedition" || $0.title.contains("Prototype") } == false, "main menu uses plain product labels")
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
        let askShortcut = ExplorerControlHotKey(keyCode: 36, id: 2)
        var asks = 0; askShortcut.onTrigger = { asks += 1 }; askShortcut.register()
        check(askShortcut.isRegistered, "global Control Option Return shortcut registers")
        check(askShortcut.dispatchNativeCheck() == noErr && asks == 1 && presses == 1, "Ask shortcut routes only to its own callback")
        check(shortcut.dispatchNativeCheck() == noErr && presses == 2 && asks == 1, "control shortcut stays independent of Ask shortcut")
        askShortcut.close()
        shortcut.close()
        check(!shortcut.isRegistered && !askShortcut.isRegistered, "global shortcut unregisters on cleanup")
        return passed
    }
    @objc private func openPlayground() {
        if playground == nil { playground = AnimationPlaygroundController() }; playground?.open()
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.close(); askHotKey.close()
        taskController?.closeAll(); taskController = nil
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
    private let keyCode: UInt32
    private let id: UInt32
    init(keyCode: UInt32 = 49, id: UInt32 = 1) { self.keyCode = keyCode; self.id = id }
    var onTrigger: (() -> Void)?
    var isRegistered: Bool { reference != nil }
    func register() {
        guard reference == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ExplorerControlHotKey>.fromOpaque(pointer).takeUnretainedValue()
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                      identifier.signature == 0x536f636b, identifier.id == owner.id else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed = false }
                else if !owner.pressed { owner.pressed = true; owner.onTrigger?() }
                return noErr
            }
        }, 2, &specs, pointer, &handler)
        guard installed == noErr else { return }
        let result = RegisterEventHotKey(keyCode, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x536f636b, id: id), GetApplicationEventTarget(), 0, &reference)
        if result != noErr { close() }
    }
    #if DEBUG
    func dispatchNativeCheck() -> OSStatus {
        var event: EventRef?
        let result = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event)
        guard result == noErr, let event else { return result }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x536f636b, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
        let first = SendEventToEventTarget(event, GetApplicationEventTarget())
        _ = SendEventToEventTarget(event, GetApplicationEventTarget()) // Holding must not toggle twice.
        var released: EventRef?
        if CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyReleased), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &released) == noErr, let released {
            SetEventParameter(released, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
            SendEventToEventTarget(released, GetApplicationEventTarget()); ReleaseEvent(released)
        }
        return first
    }
    #endif
    func close() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        pressed = false
    }
}
