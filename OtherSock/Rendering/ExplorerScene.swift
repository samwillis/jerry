import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class ExplorerScene: SKScene {
    private let explorer = SKNode()
    private let debug = SKNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo")
    private var usableFrame = CGRect.zero
    private var expeditionPaused = false
    private var interaction: ExplorerInteraction?
    private var previousUpdateTime: TimeInterval?
    var onPlacementChanged: ((CGRect, String) -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(explorer)
        addChild(debug)
        debug.isHidden = true
        buildExplorer()
        startIdle()
    }

    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    private func shape(_ rect: CGRect, color: NSColor, radius: CGFloat = 2, parent: SKNode? = nil) -> SKShapeNode {
        let node = SKShapeNode(rect: rect, cornerRadius: radius)
        node.fillColor = color
        node.strokeColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        node.lineWidth = 1.5
        (parent ?? explorer).addChild(node)
        return node
    }

    private func buildExplorer() {
        // Temporary vector shapes only; the articulated rig belongs to stage four.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 44, height: 7))
        shadow.position = CGPoint(x: 0, y: 1)
        shadow.fillColor = NSColor.black.withAlphaComponent(0.2)
        shadow.strokeColor = .clear
        explorer.addChild(shadow)
        _ = shape(CGRect(x: 7, y: 24, width: 16, height: 26), color: .systemBrown, radius: 5)
        _ = shape(CGRect(x: -11, y: 6, width: 9, height: 20), color: .darkGray)
        _ = shape(CGRect(x: 3, y: 6, width: 9, height: 20), color: .darkGray)
        _ = shape(CGRect(x: -15, y: 0, width: 14, height: 9), color: .brown)
        _ = shape(CGRect(x: 2, y: 0, width: 15, height: 9), color: .brown)
        _ = shape(CGRect(x: -13, y: 23, width: 27, height: 26), color: .systemOrange, radius: 5)
        _ = shape(CGRect(x: -21, y: 24, width: 8, height: 22), color: .systemOrange, radius: 3)
        _ = shape(CGRect(x: 14, y: 24, width: 8, height: 22), color: .systemOrange, radius: 3)
        _ = shape(CGRect(x: -11, y: 48, width: 23, height: 19), color: NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.54, alpha: 1), radius: 7)
        _ = shape(CGRect(x: -13, y: 61, width: 27, height: 10), color: .systemTeal, radius: 4)
        _ = shape(CGRect(x: -18, y: 59, width: 36, height: 4), color: .systemTeal)
        _ = shape(CGRect(x: -4, y: 53, width: 2, height: 3), color: .black, radius: 0)
        _ = shape(CGRect(x: 5, y: 53, width: 2, height: 3), color: .black, radius: 0)
        explorer.setScale(CGFloat(ExpeditionConfiguration.explorerHeight) / 72)
    }

    private func startIdle() {
        let breathe = SKAction.sequence([
            .scaleY(to: 1.025, duration: 1.2),
            .scaleY(to: 1, duration: 1.2)
        ])
        breathe.timingMode = .easeInEaseOut
        explorer.run(.repeatForever(breathe), withKey: "idle")
    }

    func layout(in usableFrame: CGRect) {
        self.usableFrame = usableFrame
        let safeOrigins = ExplorerInteraction.Bounds(
            minimum: .init(x: usableFrame.minX + 24, y: usableFrame.minY + 2),
            maximum: .init(x: usableFrame.maxX - 24, y: usableFrame.maxY - 76)
        )
        if interaction == nil {
            interaction = ExplorerInteraction(position: .init(x: usableFrame.midX, y: usableFrame.minY + 12), bounds: safeOrigins)
        } else {
            interaction?.updateBounds(safeOrigins)
        }
        applyPlacement()
    }

    func setExpeditionPaused(_ paused: Bool) {
        expeditionPaused = paused
        previousUpdateTime = nil
        applyPlacement()
    }

    func beginDrag(at point: CGPoint) {
        interaction?.beginDrag(at: .init(x: point.x, y: point.y))
        applyPlacement()
    }

    func drag(to point: CGPoint) {
        interaction?.drag(to: .init(x: point.x, y: point.y))
        applyPlacement()
    }

    func endDrag() {
        interaction?.endDrag()
        applyPlacement()
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = previousUpdateTime.map { min(max(currentTime - $0, 0), 0.1) } ?? 0
        previousUpdateTime = currentTime
        guard !expeditionPaused else { return }
        let previousState = interaction?.state
        interaction?.advance(by: elapsed)
        if previousState != interaction?.state { applyPlacement() }
    }

    private func applyPlacement() {
        guard let interaction else { return }
        explorer.position = CGPoint(x: interaction.position.x, y: interaction.position.y)
        explorer.isPaused = expeditionPaused || interaction.state != .idle
        let hitFrame = CGRect(x: explorer.position.x - 24, y: explorer.position.y - 1, width: 48, height: 76)
        onPlacementChanged?(hitFrame, interaction.state.rawValue)
        rebuildDebug()
    }

    func setDebugVisible(_ visible: Bool) {
        debug.isHidden = !visible
        rebuildDebug()
    }

    private func rebuildDebug() {
        debug.removeAllChildren()
        let outline = SKShapeNode(rect: usableFrame.insetBy(dx: 3, dy: 3))
        outline.strokeColor = .systemTeal
        outline.lineWidth = 1
        debug.addChild(outline)
        let bounds = SKShapeNode(rect: CGRect(x: explorer.position.x - 24, y: explorer.position.y - 1, width: 48, height: 76))
        bounds.strokeColor = .systemYellow
        bounds.lineWidth = 1
        debug.addChild(bounds)
        debugLabel.text = "PHASE 2 · \(expeditionPaused ? "PAUSED" : "RUNNING") · \(interaction?.state.rawValue.uppercased() ?? "IDLE") · DRAG EXPLORER · terrain not connected"
        debugLabel.fontSize = 11
        debugLabel.fontColor = .white
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .center
        debugLabel.position = CGPoint(x: usableFrame.minX + 20, y: usableFrame.maxY - 24)
        let backing = SKShapeNode(rect: CGRect(x: usableFrame.minX + 12, y: usableFrame.maxY - 40, width: min(650, usableFrame.width - 24), height: 32), cornerRadius: 6)
        backing.fillColor = NSColor.black.withAlphaComponent(0.8)
        backing.strokeColor = .clear
        debug.addChild(backing)
        debug.addChild(debugLabel)
    }
}
