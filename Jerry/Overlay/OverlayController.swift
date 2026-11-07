import AppKit
import SpriteKit
import ExpeditionCore

/// The full-screen rendering layer never accepts input.
@MainActor
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let panel: OverlayPanel
    private let view: SKView
    private let scene: ExplorerScene
    private let inputPanel: ExplorerInputPanel
    private let inputView: ExplorerInputView
    private var displayOrigin = CGPoint.zero
    private let windowProvider = WindowProvider()
    var onPromptRequested: (() -> Void)?
    var onExplorerMoved: (() -> Void)?
    var onAgentHandMoved: ((CGPoint) -> Void)?
    private var agentInputSuppressed = false
    private var parkedAgentPointer: CGPoint?
    var onTaskInterrupted: (() -> Void)?
    private var terrainTimer: Timer?
    private var featureTimer: Timer?
    private let featureCapture = WindowFeatureCapture()
    private let supplementaryCapture = WindowFeatureCapture()
    private var geometry: TerrainSnapshot?
    private var lastGeometryTime: TimeInterval?
    private var geometrySampleElapsed = 0.1
    private var policy = RuntimePolicy()
    private var desktopCheck: DispatchWorkItem?
    private var terrainRefreshCount = 0
    private var characterHeld = false
    private let keyboard = ExplorerKeyboardController()
    private var clickPending = false
    var onKeyboardControlChanged: ((Bool) -> Void)?
    private var renderPauseWork: DispatchWorkItem?

    init() {
        let frame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Jerry Overlay"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.animationBehavior = .none

        scene = ExplorerScene(size: frame.size)
        inputPanel = ExplorerInputPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        inputPanel.title = "Explorer — drag to move"
        inputPanel.isFloatingPanel = true
        inputPanel.hidesOnDeactivate = false
        inputPanel.becomesKeyOnlyIfNeeded = true
        inputPanel.isMovable = false
        inputPanel.isOpaque = false
        inputPanel.backgroundColor = .clear
        inputPanel.hasShadow = false
        inputPanel.level = panel.level
        inputPanel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        inputPanel.isReleasedWhenClosed = false
        inputPanel.isRestorable = false
        inputPanel.animationBehavior = .none
        inputView = ExplorerInputView(frame: .zero)
        inputView.autoresizingMask = [.width, .height]
        inputPanel.contentView = inputView
        // Keep the hit area above the renderer even if another app or accessibility tool raises it.
        panel.addChildWindow(inputPanel, ordered: .above)
        view = SKView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.allowsTransparency = true
        view.preferredFramesPerSecond = ExpeditionConfiguration.framesPerSecond
        panel.contentView = view
        view.presentScene(scene)
        scene.onFrame = { [weak self] in self?.updateAgentHitAreas() }
        scene.onPlacementChanged = { [weak self] frame, state in
            guard let self else { return }
            self.inputPanel.setFrame(frame.offsetBy(dx: self.displayOrigin.x, dy: self.displayOrigin.y), display: true)
            self.onExplorerMoved?()
            if self.scene.agentMode, let point = self.scene.agentHandPoint, let primary = NSScreen.screens.first {
                self.onAgentHandMoved?(.init(x: point.x + self.displayOrigin.x, y: primary.frame.maxY - point.y - self.displayOrigin.y))
            }
            self.inputView.setAccessibilityValue("\(state) at \(Int(frame.midX)), \(Int(frame.minY))")
            let wasHeld = self.characterHeld
            self.characterHeld = state == "held"
            self.updateRenderingPause(allowFinalFrame: wasHeld && !self.characterHeld)
        }
        inputView.onBegin = { [weak self] point in
            guard let self else { return }
            self.onTaskInterrupted?()
            self.setKeyboardControl(false)
            self.scene.beginDrag(at: self.scenePoint(point))
        }
        inputView.onDrag = { [weak self] point in
            guard let self else { return }
            self.scene.drag(to: self.scenePoint(point))
        }
        inputView.onEnd = { [weak self] in
            self?.refreshTerrain()
            self?.scene.endDrag()
        }
        keyboard.onPrompt = { [weak self] in self?.onPromptRequested?() }
        keyboard.onDirection = { [weak self] x, y in self?.scene.setControlDirection(x, y) }
        keyboard.onLowPointer = { [weak self] in self?.scene.setControlPointerLowered($0) }
        keyboard.onCrouch = { [weak self] held in self?.scene.setControlCrouch(held) }
        keyboard.onFastPace = { [weak self] fast in self?.scene.setControlFastPace(fast) }
        keyboard.onJump = { [weak self] in self?.scene.controlJump() }
        keyboard.onAimDirection = { [weak self] x, y in self?.scene.setAimDirection(x, y) }
        keyboard.onAimChanged = { [weak self] active in
            self?.scene.setGrappleAiming(active)
            if active { self?.keyboard.showMessage("Hold G and use the arrows to aim at a window's top rim. Release G to fire. Release G to use arrows for movement again.") }
        }
        keyboard.onGrapple = { [weak self] in
            guard let self else { return }
            self.keyboard.showMessage(self.scene.fireAimedGrapple() ? "Hook fired. Up climbs, Down descends; left/right pumps the swing." : "No reachable top rim there. Hold G and use the arrows to aim at a window's top edge.")
        }
        keyboard.onInteract = { [weak self] in self?.clickAtExplorer() }
        keyboard.onStop = { [weak self] in
            self?.scene.setKeyboardControl(false)
            self?.onKeyboardControlChanged?(false)
        }
        updateDisplay()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.policy.shouldPollTerrain else { return }
                self.refreshTerrain()
            }
        }
        featureCapture.onFeatures = { [weak self] _ in self?.publishTerrain() }
        supplementaryCapture.onFeatures = { [weak self] _ in self?.publishTerrain() }
        let featureTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.policy.shouldPollTerrain, self.featureCapture.enabled else { return }
                self.publishTerrain()
            }
        }
        self.featureTimer = featureTimer
        RunLoop.main.add(featureTimer, forMode: .common)
        terrainTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scenePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayOrigin.x, y: point.y - displayOrigin.y)
    }

    func show() {
        guard policy.shouldShow, !clickPending else { return }
        panel.orderFrontRegardless()
        if !scene.agentMode { inputPanel.order(.above, relativeTo: panel.windowNumber) }
        else { updateAgentHitAreas() }
    }

    func updateDisplay() {
        setKeyboardControl(false)
        // The first screen owns the menu bar. Do not follow whichever screen has keyboard focus.
        guard let screen = NSScreen.screens.first else {
            policy.desktopSupported = false
            applyPolicy()
            return
        }
        inputView.cancelDrag()
        displayOrigin = screen.frame.origin
        panel.setFrame(screen.frame, display: true)
        scene.size = screen.frame.size
        let usable = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        scene.layout(in: usable)
        refreshTerrain()
        checkDesktop()
        show()
    }

    private func refreshTerrain() {
        terrainRefreshCount += 1
        guard let screen = NSScreen.screens.first else { return }
        let now = ProcessInfo.processInfo.systemUptime
        geometrySampleElapsed = lastGeometryTime.map { max(1.0 / 120, now - $0) } ?? 0.1
        lastGeometryTime = now
        geometry = windowProvider.snapshot(on: screen)
        if let geometry {
            let host = geometry.windows.first { $0.id == scene.attachedWindowID && $0.canClimb }?.id
            let primary = host ?? windowProvider.frontWindowID ?? windowProvider.keyboardWindowID
            featureCapture.update(terrain: geometry, preferredWindow: primary, running: policy.shouldRun)
            // Keep the visible keyboard and working window available together, with
            // no duplicate stream when the explorer transfers onto the keyboard.
            let secondary = [windowProvider.keyboardWindowID, windowProvider.frontWindowID].compactMap { $0 }.first { $0 != primary }
            let extra = TerrainSnapshot(windows: geometry.windows.filter { $0.id == secondary }, viewport: geometry.viewport)
            supplementaryCapture.update(terrain: extra, preferredWindow: secondary, running: policy.shouldRun)
        }
        publishTerrain()
    }

    private func publishTerrain() {
        guard let geometry else { scene.updateTerrain(nil); return }
        scene.updateTerrain(TerrainSnapshot(windows: geometry.windows, viewport: geometry.viewport, features: featureCapture.currentFeatures() + supplementaryCapture.currentFeatures()), geometrySampleElapsed: geometrySampleElapsed)
    }
    func setExploreInsideWindows(_ enabled: Bool) {
        featureCapture.enabled = enabled; supplementaryCapture.enabled = enabled
        if !enabled { featureCapture.stop(); supplementaryCapture.stop() }
        refreshTerrain()
    }
    var windowExplorationStatus: String { featureCapture.status + (supplementaryCapture.currentFeatures().isEmpty ? "" : " · Keyboard/second window: " + supplementaryCapture.status) }

    func beginAgent() { setKeyboardControl(false); scene.setAgentMode(true); setAgentLayer(true); setPaused(false); checkDesktop() }
    func stopAgent() { parkedAgentPointer = nil; agentInputSuppressed = false; setAgentLayer(false); scene.setAgentMode(false); checkDesktop() }
    private func setAgentLayer(_ active: Bool) {
        panel.level = .init(rawValue: active ? NSWindow.Level.popUpMenu.rawValue + 1 : NSWindow.Level.statusBar.rawValue + 1)
        inputPanel.level = panel.level
    }
    func setAgentReading(_ reading: Bool) { scene.agentReading = reading }
    func agentInputVisible(_ visible: Bool) {
        agentInputSuppressed = !visible
        if visible && scene.agentMode { parkedAgentPointer = NSEvent.mouseLocation }
        updateAgentHitAreas()
    }
    private func updateAgentHitAreas() {
        let mouse = NSEvent.mouseLocation
        if let parked = parkedAgentPointer, hypot(parked.x - mouse.x, parked.y - mouse.y) > 2 { parkedAgentPointer = nil }
        func update(_ hit: NSPanel) {
            let parkedUnderCharacter = scene.agentMode && parkedAgentPointer != nil && hit.frame.contains(mouse)
            let visible = policy.shouldShow && !agentInputSuppressed && !parkedUnderCharacter
            if visible { if !hit.isVisible { hit.order(.above, relativeTo: panel.windowNumber) } }
            else if hit.isVisible { hit.orderOut(nil) }
        }
        update(inputPanel)
    }
    func reachForAgent(_ quartz: CGPoint) async throws {
        guard let primary = NSScreen.screens.first, scene.agentMode else { throw CancellationError() }
        let point = CGPoint(x: quartz.x - displayOrigin.x, y: primary.frame.maxY - quartz.y - displayOrigin.y)
        scene.agentTarget = point
        let deadline = ProcessInfo.processInfo.systemUptime + 100
        var stable = 0
        var lastTrace = 0.0
        while stable < 4 {
            try Task.checkCancellation(); guard scene.agentMode else { throw CancellationError() }
            if ProcessInfo.processInfo.systemUptime > deadline { throw AgentConnectionError(message: "The explorer could not reach that control in time. Choose a nearer route or move its window.") }
            #if DEBUG
            let now = ProcessInfo.processInfo.systemUptime
            if ProcessInfo.processInfo.arguments.contains("--trace-agent"), now - lastTrace > 1 {
                print("AGENT REACH", scene.agentDiagnostic, "target", point, "paused", view.isPaused); fflush(stdout); lastTrace = now
            }
            #endif
            stable = scene.agentAtTarget ? stable + 1 : 0
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    func setPaused(_ paused: Bool) {
        if paused { setKeyboardControl(false) }
        policy.manuallyPaused = paused
        if paused { applyPolicy() } else { checkDesktop() }
    }
    func recordFrontApp() { keyboard.recordFrontApp() }
    func restoreExternalFocus() { keyboard.restoreExternalFocus() }
    var explorerScreenFrame: CGRect { inputPanel.frame }
    var keyboardControlEnabled: Bool { keyboard.isControlling }
    func setKeyboardControl(_ enabled: Bool, restoreFocus: Bool = false) {
        if enabled {
            guard policy.shouldShow else { return }
            setPaused(false)
            scene.setKeyboardControl(true)
            keyboard.start()
            onKeyboardControlChanged?(true)
        } else { keyboard.stop(restoreFocus: restoreFocus) }
    }
    func requestClickAccess() {
        ExplorerDesktopClick.requestAccess()
        keyboard.showMessage("Enable Jerry in Privacy & Security → Accessibility, then return to keyboard control.")
    }
    private func clickAtExplorer() {
        guard keyboard.isControlling, !clickPending, let local = scene.keyboardClickPoint,
              let screen = NSScreen.screens.first else { return }
        guard ExplorerDesktopClick.hasAccess else { requestClickAccess(); return }
        let cocoa = CGPoint(x: local.x + displayOrigin.x, y: local.y + displayOrigin.y)
        guard !keyboard.panel.frame.contains(cocoa) else {
            keyboard.showMessage("Move the marker away from the keyboard-control window."); return
        }
        let point = ExplorerDesktopClick.quartzPoint(cocoa, primaryTop: screen.frame.maxY)
        clickPending = true
        keyboard.beginClick()
        panel.orderOut(nil); inputPanel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            if self.keyboard.isControlling && self.policy.shouldRun {
                self.keyboard.showMessage(ExplorerDesktopClick.press(at: point))
            }
            self.clickPending = false
            self.keyboard.finishClick()
            if self.policy.shouldShow { self.show() }
        }
    }

    func setIdleExploration(_ enabled: Bool) { scene.setIdleExploration(enabled) }
    var idleExplorationEnabled: Bool { scene.idleExplorationEnabled }
    var activityStatus: String { scene.activityStatus }
    var availableActivities: Set<ExplorerActivity> { scene.availableActivities }
    func requestActivity(_ activity: ExplorerActivity) { setKeyboardControl(false); refreshTerrain(); scene.requestActivity(activity) }

    func setRunWhenExploring(_ enabled: Bool) { scene.setRunWhenExploring(enabled) }
    func setFasterRopeWork(_ enabled: Bool) { scene.setFasterRopeWork(enabled) }
    func setGentlePace(_ gentle: Bool) { scene.playbackRate = gentle ? 0.65 : 1 }

    func setSleeping(_ sleeping: Bool) {
        policy.sleeping = sleeping
        if !sleeping { updateDisplay(); checkDesktop() }
        applyPolicy()
    }

    func desktopChanged() {
        // Hide during the transition, then read the new Space rather than retaining old anchors.
        desktopCheck?.cancel()
        policy.desktopSupported = false
        applyPolicy()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkDesktop() }
        }
        desktopCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func checkDesktop() {
        guard !policy.manuallyPaused, !policy.sleeping else { applyPolicy(); return }
        guard let screen = NSScreen.screens.first else { return }
        policy.desktopSupported = scene.agentMode || windowProvider.isSupportedDesktop(on: screen)
        applyPolicy()
    }

    private func applyPolicy() {
        if !policy.shouldRun { setKeyboardControl(false); featureCapture.stop(); supplementaryCapture.stop() }
        if policy.shouldRun { refreshTerrain() }
        scene.setExpeditionPaused(!policy.shouldRun)
        if policy.shouldShow { show() }
        else {
            inputView.cancelDrag()
            panel.orderOut(nil)
            inputPanel.orderOut(nil)
        }
        updateRenderingPause()
    }

    private func updateRenderingPause(allowFinalFrame: Bool = false) {
        renderPauseWork?.cancel()
        if policy.shouldRun || (policy.shouldShow && characterHeld) { view.isPaused = false }
        else if allowFinalFrame && policy.shouldShow {
            // A paused drag still needs rendering, including its final release position.
            view.isPaused = false
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.policy.shouldRun, !self.characterHeld else { return }
                    self.view.isPaused = true
                }
            }
            renderPauseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        } else { view.isPaused = true }
    }

    func resetExpedition() { setKeyboardControl(false); refreshTerrain(); scene.resetExpedition() }

    func setDebugVisible(_ visible: Bool) { scene.setDebugVisible(visible) }

    func close() {
        keyboard.close()
        desktopCheck?.cancel()
        renderPauseWork?.cancel()
        featureCapture.stop(); supplementaryCapture.stop(); featureTimer?.invalidate(); featureTimer = nil
        terrainTimer?.invalidate()
        terrainTimer = nil
        inputView.cancelDrag()
        scene.onPlacementChanged = nil
        inputPanel.orderOut(nil)
        panel.removeChildWindow(inputPanel)
        inputPanel.close()
        view.isPaused = true
        view.presentScene(nil)
        panel.orderOut(nil)
        panel.close()
    }
    #if DEBUG
    /// Tests our real AppKit panel/lifecycle integration without synthesising user input,
    /// sleeping the machine, or changing Spaces on the user's desktop.
    func runNativeChecks() -> Bool {
        var passed = true
        func check(_ condition: Bool, _ name: String) {
            print("NATIVE \(condition ? "PASS" : "FAIL") \(name)")
            passed = passed && condition
        }
        check(WindowProvider.isScreenRecorder(bundle: "com.apple.screencaptureui", owner: "Screenshot"), "Screenshot selection windows and toolbar are excluded from terrain")
        check(WindowProvider.isScreenRecorder(bundle: nil, owner: "screencapture"), "the unbundled recording backdrop is excluded from terrain")
        check(!WindowProvider.isScreenRecorder(bundle: "com.apple.QuickTimePlayerX", owner: "QuickTime Player"), "normal QuickTime playback windows retain their edges")
        check(!WindowProvider.isScreenRecorder(bundle: nil, owner: "another helper"), "unrelated unbundled windows are not excluded")
        let display = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        check(WindowProvider.isKeyboardBackdrop(bundle: "com.apple.inputmethod.AssistiveControl", layer: 2997, frame: display, display: display), "transparent accessibility keyboard backdrops do not occlude terrain")
        check(!WindowProvider.isKeyboardBackdrop(bundle: "com.apple.inputmethod.AssistiveControl", layer: 101, frame: CGRect(x: 1000, y: 690, width: 600, height: 323), display: display), "the actual floating keyboard still occludes terrain")
        check(!WindowProvider.isKeyboardBackdrop(bundle: "com.apple.inputmethod.AssistiveControl", layer: 2997, frame: CGRect(x: 0, y: 0, width: 500, height: 100), display: display), "small accessibility panels are not mistaken for full-screen backdrops")
        check(!WindowProvider.isKeyboardBackdrop(bundle: "another.app", layer: 2997, frame: display, display: display), "other apps retain their real full-screen occluders")
        let keyboardFrame = CGRect(x: 1048, y: 692, width: 598, height: 323)
        check(WindowProvider.canClimbWindow(bundle: "com.apple.inputmethod.AssistiveControl", layer: 101, frame: keyboardFrame), "the Accessibility Keyboard has climbable edges and can supply internal holds")
        check(WindowProvider.canClimbWindow(bundle: "com.apple.KeyboardViewer", layer: 101, frame: keyboardFrame), "Keyboard Viewer floating panels have climbable edges")
        check(!WindowProvider.canClimbWindow(bundle: "com.apple.inputmethod.AssistiveControl", layer: 2997, frame: display), "keyboard backdrops cannot become climbing or capture targets")
        check(!WindowProvider.canClimbWindow(bundle: "another.app", layer: 101, frame: keyboardFrame), "unrelated floating overlays remain occluders only")
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let hatPart = PaintedPart(rect: .init(x: -12, y: 7, width: 24, height: 8), radius: 2, color: ExplorerPalette.hat, material: .felt)
        check(panel.level.rawValue > Int(CGWindowLevelForKey(.dockWindow)), "explorer is layered above the system Dock")
        check(hatPart.silhouettePath.boundingBoxOfPath == .init(x: -12, y: -4, width: 24, height: 8), "shadow silhouettes use sprite-local coordinates")
        let shadowRig = ExplorerRig(), shadowSpace = SKNode()
        shadowSpace.addChild(shadowRig); shadowRig.position = .init(x: 200, y: 200)
        shadowRig.setShadowOcclusion(windows: [.init(x: 180, y: 0, width: 200, height: 200)], from: shadowSpace)
        check(shadowRig.shadowIsVisible(at: .init(x: 0, y: 20)) && !shadowRig.shadowIsVisible(at: .init(x: 0, y: -1)), "supporting window hides shadow beneath its lip")
        shadowRig.xScale = -1
        shadowRig.setShadowOcclusion(windows: [.init(x: 180, y: 0, width: 200, height: 200)], from: shadowSpace)
        check(!shadowRig.shadowIsVisible(at: .init(x: -50, y: -1)) && shadowRig.shadowIsVisible(at: .init(x: 50, y: -1)), "ledge shadow clipping survives mirrored facing")
        shadowRig.position.y = 180
        shadowRig.setShadowOcclusion(windows: [.init(x: 180, y: 0, width: 200, height: 200)], from: shadowSpace)
        check(shadowRig.shadowIsVisible(at: .init(x: 0, y: -1)), "hanging in front of a window keeps its cast shadow")
        var crackClamps = 0
        for horizontal in [true, false] {
            for step in 0..<120 {
                shadowRig.crackPose = CrackAnimation.pose(horizontal: horizontal, time: Double(step) / 60, offset: Double(step))
                shadowRig.select(.climbing); shadowRig.render(delta: 0.1)
                crackClamps += shadowRig.clampedContacts
            }
        }
        check(crackClamps == 0, "crack traverse and vertical climbing stay inside limb reach")
        shadowRig.crackPose = nil
        var crouchClamps = 0
        for step in 0..<120 {
            shadowRig.crouchAmount = Double(step % 30) / 29
            shadowRig.select(.walking); shadowRig.synchronizedTime = Double(step) / 60
            shadowRig.render(delta: 1.0 / 60)
            crouchClamps += shadowRig.clampedContacts
        }
        check(crouchClamps == 0, "crouched walking keeps knees and reaching arms inside limb reach")
        shadowRig.crouchAmount = 0
        show()
        check(panel.isVisible && inputPanel.isVisible, "both panels visible")
        check(panel.ignoresMouseEvents && !inputPanel.ignoresMouseEvents, "input confined to body panel")
        check(!panel.canBecomeKey && !inputPanel.canBecomeKey, "panels cannot take keyboard focus")
        check(inputPanel.frame.width == 48 && inputPanel.frame.height == 76, "body-only hit area")
        setPaused(true)
        check(!policy.shouldPollTerrain && view.isPaused, "explicit pause suspends polling and scene")
        let pausedPolls = terrainRefreshCount
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        check(terrainRefreshCount == pausedPolls, "paused timer performs no geometry reads")
        let original = inputPanel.frame
        let grab = CGPoint(x: original.midX, y: original.midY)
        inputView.onBegin?(grab)
        inputView.onDrag?(CGPoint(x: grab.x + 60, y: grab.y + 30))
        check(abs(inputPanel.frame.midX - original.midX - 60) < 0.1, "paused drag callback moves body panel")
        check(!view.isPaused && !policy.shouldRun, "paused drag renders without advancing simulation")
        inputView.onEnd?()
        // First-use mask/blur pipeline compilation can delay the final frame.
        let finalFrameDeadline = Date(timeIntervalSinceNow: 0.75)
        while !view.isPaused && Date() < finalFrameDeadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        check(view.isPaused, "paused release renders final frame then stops")
        setSleeping(true)
        check(!panel.isVisible && !inputPanel.isVisible, "sleep hides all panels")
        setSleeping(false)
        check(policy.manuallyPaused && !policy.shouldRun, "wake preserves explicit pause")
        policy.desktopSupported = false
        applyPolicy()
        check(!panel.isVisible && !inputPanel.isVisible && !policy.shouldPollTerrain, "unsupported desktop is hidden and suspended")
        policy.desktopSupported = true
        setPaused(false)
        check(policy.shouldRun && panel.isVisible && inputPanel.isVisible, "return refreshes and resumes")
        resetExpedition()
        check(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus, "launch/reset/lifecycle preserve frontmost app")
        let previousApp = NSWorkspace.shared.frontmostApplication
        var direction = CGPoint.zero, aimDirection = CGPoint.zero, jumps = 0, clicks = 0, shots = 0, aiming = false, fastPace = false
        let tester = ExplorerKeyboardController()
        tester.onDirection = { x, y in direction = .init(x: x, y: y) }
        tester.onJump = { jumps += 1 }
        tester.onFastPace = { fastPace = $0 }
        tester.onInteract = { clicks += 1 }
        tester.onAimChanged = { aiming = $0 }
        tester.onAimDirection = { x, y in aimDirection = .init(x: x, y: y) }
        var crouching = false
        tester.onCrouch = { crouching = $0 }
        tester.onGrapple = { shots += 1 }
        tester.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        check(tester.isControlling && tester.panel.canBecomeKey && !panel.canBecomeKey, "manual mode has a dedicated keyboard input target")
        check(tester.panel.frame.size == .init(width: 1, height: 1) && !tester.panel.isOpaque && tester.panel.ignoresMouseEvents && tester.panel.styleMask == .borderless, "manual input has no visible controls window or mouse hit area")
        func key(_ code: UInt16, down: Bool = true, repeatKey: Bool = false, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: tester.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
        }
        check(tester.routeKey(key(124)) == nil && direction.x == 1, "arrow key is consumed and starts player movement")
        _ = tester.routeKey(key(0))
        check(direction.x == 0, "opposite movement keys cancel")
        _ = tester.routeKey(key(0, down: false)); _ = tester.routeKey(key(124, down: false))
        check(direction == .zero, "key release clears movement")
        _ = tester.routeKey(key(124, flags: .shift))
        check(fastPace && direction.x == 1, "Shift movement enables fast pace without clearing directions")
        _ = tester.routeKey(key(124, down: false))
        check(!fastPace && direction == .zero, "releasing Shift restores normal pace")
        _ = tester.routeKey(key(8))
        check(crouching && direction == .zero, "holding C crouches without stepping off the ledge")
        _ = tester.routeKey(key(14))
        check(crouching && clicks == 1 && tester.isControlling, "E retains crouch and manual control")
        _ = tester.routeKey(key(8, down: false))
        check(!crouching, "releasing C restores standing posture")
        _ = tester.routeKey(key(49)); _ = tester.routeKey(key(49, repeatKey: true))
        _ = tester.routeKey(key(14)); _ = tester.routeKey(key(14, repeatKey: true))
        check(jumps == 1 && clicks == 2, "jump and click fire once rather than on key repeat")
        check(tester.routeKey(key(14, flags: .command)) != nil && clicks == 2, "command shortcuts pass through without clicking")
        _ = tester.routeKey(key(5)); _ = tester.routeKey(key(5, repeatKey: true))
        check(aiming && shots == 0, "holding G aims without firing or repeating")
        _ = tester.routeKey(key(124))
        check(aimDirection.x == 1 && direction == .zero, "G plus Right adjusts aim without moving or pumping the explorer")
        _ = tester.routeKey(key(126))
        check(aimDirection == .init(x: 1, y: 1) && direction == .zero, "G plus arrows supports diagonal aim")
        _ = tester.routeKey(key(5, down: false))
        check(!aiming && shots == 1, "releasing G fires one aimed shot")
        check(aimDirection == .zero && direction == .init(x: 1, y: 1), "releasing G restores held arrows to movement")
        _ = tester.routeKey(key(124, down: false)); _ = tester.routeKey(key(126, down: false))
        var prompts = 0
        tester.onPrompt = { prompts += 1 }
        _ = tester.routeKey(key(124, flags: .shift))
        _ = tester.routeKey(key(36)); _ = tester.routeKey(key(36, repeatKey: true)); _ = tester.routeKey(key(36, down: false))
        check(prompts == 1 && direction == .zero && !fastPace, "Return opens one prompt and clears held movement and pace")
        check(tester.routeKey(key(36, flags: .command)) != nil && prompts == 1, "modified Return passes through without opening a prompt")
        tester.beginClick()
        tester.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: tester.panel))
        check(tester.isControlling && tester.isPerformingClick, "click-induced focus loss preserves keyboard session")
        _ = tester.routeKey(key(53))
        check(!tester.isControlling && !tester.panel.isVisible && direction == .zero, "Escape ends capture and clears held directions")
        tester.close()
        check(ExplorerDesktopClick.quartzPoint(.init(x: 120, y: 240), primaryTop: 900) == .init(x: 120, y: 660), "click marker converts to Quartz coordinates")
        if !ExplorerDesktopClick.hasAccess {
            check(ExplorerDesktopClick.press(at: .zero).hasPrefix("Allow"), "desktop click is gated without Accessibility permission")
        }
        print("NATIVE INFO Accessibility permission: \(ExplorerDesktopClick.hasAccess)")
        previousApp?.activate(options: [])
        close()
        check(!panel.isVisible && !inputPanel.isVisible && terrainTimer == nil, "close removes panels and timer")
        return passed
    }
    #endif

}
