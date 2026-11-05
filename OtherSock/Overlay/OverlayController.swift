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
        }
        inputView.onBegin = { [weak self] point in
            guard let self else { return }
            self.scene.beginDrag(at: self.scenePoint(point))
        }
        inputView.onDrag = { [weak self] point in
            guard let self else { return }
            self.scene.drag(to: self.scenePoint(point))
        }
        inputView.onEnd = { [weak self] in self?.scene.endDrag() }
        updateDisplay()
    }

    private func scenePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayOrigin.x, y: point.y - displayOrigin.y)
    }

    func show() {
        panel.orderFrontRegardless()
        inputPanel.order(.above, relativeTo: panel.windowNumber)
    }

    func updateDisplay() {
        // The first screen owns the menu bar. Do not follow whichever screen has keyboard focus.
        guard let screen = NSScreen.screens.first else {
            inputView.cancelDrag()
            panel.orderOut(nil)
            inputPanel.orderOut(nil)
            return
        }
        inputView.cancelDrag()
        displayOrigin = screen.frame.origin
        panel.setFrame(screen.frame, display: true)
        scene.size = screen.frame.size
        let usable = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        scene.layout(in: usable)
        show()
    }

    func setPaused(_ paused: Bool) {
        scene.setExpeditionPaused(paused)
        // Keep rendering user-driven placement even while autonomous animation is paused.
    }

    func setDebugVisible(_ visible: Bool) { scene.setDebugVisible(visible) }

    func close() {
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
}
