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
    private var terrainTimer: Timer?
    private var policy = RuntimePolicy()
    private var desktopCheck: DispatchWorkItem?
    private var terrainRefreshCount = 0
    private var characterHeld = false
    private var renderPauseWork: DispatchWorkItem?

    init() {
        let frame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "The Other Sock Overlay"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
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
        inputPanel.level = .floating
        inputPanel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
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
        scene.onPlacementChanged = { [weak self] frame, state in
            guard let self else { return }
            self.inputPanel.setFrame(frame.offsetBy(dx: self.displayOrigin.x, dy: self.displayOrigin.y), display: true)
            self.inputView.setAccessibilityValue("\(state) at \(Int(frame.midX)), \(Int(frame.minY))")
            let wasHeld = self.characterHeld
            self.characterHeld = state == "held"
            self.updateRenderingPause(allowFinalFrame: wasHeld && !self.characterHeld)
        }
        inputView.onBegin = { [weak self] point in
            guard let self else { return }
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
        updateDisplay()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.policy.shouldPollTerrain else { return }
                self.refreshTerrain()
            }
        }
        terrainTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scenePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayOrigin.x, y: point.y - displayOrigin.y)
    }

    func show() {
        guard policy.shouldShow else { return }
        panel.orderFrontRegardless()
        inputPanel.order(.above, relativeTo: panel.windowNumber)
    }

    func updateDisplay() {
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
        scene.updateTerrain(windowProvider.snapshot(on: screen))
    }

    func setPaused(_ paused: Bool) {
        policy.manuallyPaused = paused
        if paused { applyPolicy() } else { checkDesktop() }
    }

    var activityStatus: String { scene.activityStatus }
    var availableActivities: Set<ExplorerActivity> { scene.availableActivities }
    func requestActivity(_ activity: ExplorerActivity) { refreshTerrain(); scene.requestActivity(activity) }

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
        policy.desktopSupported = windowProvider.isSupportedDesktop(on: screen)
        applyPolicy()
    }

    private func applyPolicy() {
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

    func resetExpedition() { refreshTerrain(); scene.resetExpedition() }

    func setDebugVisible(_ visible: Bool) { scene.setDebugVisible(visible) }

    func close() {
        desktopCheck?.cancel()
        renderPauseWork?.cancel()
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
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
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
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
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
        close()
        check(!panel.isVisible && !inputPanel.isVisible && terrainTimer == nil, "close removes panels and timer")
        return passed
    }
    #endif

}
