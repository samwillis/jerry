import AppKit

/// A small hit area above the mouse-ignoring rendering layer. Never takes keyboard focus.
@MainActor
final class ExplorerInputPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ExplorerInputView: NSView {
    var onBegin: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    private var dragging = false

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Explorer — drag to move")
        toolTip = "Grab me and move me out of the way"
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ dirtyRect: NSRect) {
        // A near-transparent backing keeps the small panel hit-testable on macOS.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        dragging = true
        NSCursor.closedHand.push()
        onBegin?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(NSEvent.mouseLocation)
        cancelDrag()
    }

    func cancelDrag() {
        guard dragging else { return }
        dragging = false
        NSCursor.pop()
        onEnd?()
    }
}
