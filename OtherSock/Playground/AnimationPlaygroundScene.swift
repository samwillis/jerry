#if DEBUG
import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class AnimationPlaygroundScene: SKScene {
    let rig = ExplorerRig()
    private let actualSizeRig = ExplorerRig()
    private let terrain = SKNode()
    private let handles = SKNode()
    private let rope = SKShapeNode()
    private let status = SKLabelNode(fontNamed: "Menlo")
    private let scaleCaption = SKLabelNode(fontNamed: "Menlo")
    private var selected: ExplorerMotion = .idle
    private var previousTime: Double?
    private var activeHandle: String?
    private var rigDragOffset = CGPoint.zero
    private var handholds = [CGPoint(x: 20, y: 55), CGPoint(x: 20, y: 65)]
    private var ropeAnchor = CGPoint(x: 5, y: 125)
    private var grabPoint = CGPoint(x: 0, y: 64)
    private var hasCustomOrigin = false
    private var stageOrigin = CGPoint.zero
    var playbackPaused = false
    var playbackRate: Double = 1
    var zoom: CGFloat = 3 { didSet { updateScale(); layoutStage() } }
    var facing: CGFloat = 1 { didSet { updateScale(); rebuildStage() } }
    var showJoints = false {
        didSet { rig.showsJoints = showJoints; actualSizeRig.showsJoints = showJoints }
    }
    var tuning = AnimationTuning() {
        didSet { rig.tuning = tuning; actualSizeRig.tuning = tuning }
    }
    var darkBackground = true {
        didSet { backgroundColor = darkBackground ? NSColor(calibratedWhite: 0.09, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1); rebuildStage() }
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        addChild(terrain)
        addChild(rope)
        addChild(rig)
        addChild(actualSizeRig)
        addChild(handles)
        status.fontSize = 12
        status.horizontalAlignmentMode = .left
        status.verticalAlignmentMode = .top
        addChild(status)
        scaleCaption.fontSize = 11
        scaleCaption.horizontalAlignmentMode = .left
        addChild(scaleCaption)
        updateScale()
        layoutStage()
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    override func didChangeSize(_ oldSize: CGSize) { layoutStage() }

    private func updateScale() {
        rig.xScale = zoom * facing; rig.yScale = zoom
        actualSizeRig.xScale = facing; actualSizeRig.yScale = 1
    }

    private func layoutStage() {
        let tall = selected == .parachuting || selected == .abseiling
        let y = tall ? max(25, min(size.height * 0.25, size.height - 140 * zoom - 55)) : max(105, size.height * 0.25)
        stageOrigin = CGPoint(x: size.width * 0.53, y: y)
        if !hasCustomOrigin { rig.position = stageOrigin }
        actualSizeRig.position = CGPoint(x: 90, y: 80)
        scaleCaption.position = CGPoint(x: 25, y: 45)
        status.position = CGPoint(x: 22, y: size.height - 20)
        rebuildStage()
    }

    func select(_ motion: ExplorerMotion, restart: Bool = false) {
        activeHandle = nil
        selected = motion
        hasCustomOrigin = false
        rig.select(motion, restart: restart)
        actualSizeRig.select(motion, restart: restart)
        if restart {
            handholds = [CGPoint(x: 20, y: 55), CGPoint(x: 20, y: 65)]
            ropeAnchor = CGPoint(x: 5, y: 125)
            grabPoint = CGPoint(x: 0, y: 64)
            hasCustomOrigin = false
            layoutStage()
        }
        previousTime = nil
        layoutStage()
    }

    func restart() { select(selected, restart: true) }

    private func handle(_ name: String, at local: CGPoint, color: NSColor) {
        let point = rig.convert(local, to: self)
        let node = SKShapeNode(circleOfRadius: 7)
        node.name = name
        node.position = point
        node.strokeColor = color
        node.fillColor = color.withAlphaComponent(0.3)
        node.lineWidth = 2
        handles.addChild(node)
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = name
        label.fontSize = 10
        label.fontColor = darkBackground ? .white : .black
        label.position = CGPoint(x: point.x + 12 * facing, y: point.y + 10)
        label.horizontalAlignmentMode = facing > 0 ? .left : .right
        handles.addChild(label)
    }

    private func rebuildStage() {
        terrain.removeAllChildren()
        handles.removeAllChildren()
        let textColor: NSColor = darkBackground ? .white : .black
        status.fontColor = textColor
        scaleCaption.fontColor = textColor
        scaleCaption.text = "ACTUAL DESKTOP SIZE · 74 pt"
        let platformY = stageOrigin.y - (selected == .held ? 30 * zoom : 0)
        let vertical = selected == .climbing || selected == .abseiling
        let wallX = stageOrigin.x + (selected == .climbing ? 20 : 22) * zoom * facing
        var frame = vertical
            ? CGRect(x: facing > 0 ? wallX : wallX - 200, y: platformY - 100, width: 200, height: 100 + 90 * zoom)
            : CGRect(x: stageOrigin.x - 200, y: platformY - 120, width: 400, height: 120)
        if selected == .comic {
            frame = CGRect(x: stageOrigin.x + (facing > 0 ? -200 : -20), y: platformY - 120, width: 220, height: 120)
        }
        let window = SKShapeNode(rect: frame, cornerRadius: 8)
        window.fillColor = darkBackground ? NSColor(calibratedWhite: 0.17, alpha: 1) : .white
        window.strokeColor = .systemTeal
        window.lineWidth = 2
        terrain.addChild(window)
        let edgeLabel = SKLabelNode(fontNamed: "Menlo")
        edgeLabel.text = "FAKE WINDOW — animation only"
        edgeLabel.fontSize = 11
        edgeLabel.fontColor = textColor.withAlphaComponent(0.6)
        edgeLabel.position = CGPoint(x: frame.midX, y: frame.minY + 22)
        terrain.addChild(edgeLabel)
        if selected == .climbing {
            for (index, point) in handholds.enumerated() { handle(index == 0 ? "left handhold" : "right handhold", at: point, color: .systemGreen) }
        }
        if selected == .abseiling { handle("rope anchor", at: ropeAnchor, color: .systemYellow) }
        if selected == .held || selected == .comic { handle("grab point", at: grabPoint, color: .systemPink) }
        rebuildRope()
    }

    private func rebuildRope() {
        rope.isHidden = selected != .abseiling
        guard selected == .abseiling else { return }
        let path = CGMutablePath()
        path.move(to: rig.convert(ropeAnchor, to: self))
        let gripX = min(max(ropeAnchor.x, -10), 10)
        path.addLine(to: rig.convert(CGPoint(x: gripX, y: 61.5), to: self))
        path.addLine(to: rig.convert(CGPoint(x: gripX, y: -30), to: self))
        rope.path = path
        rope.strokeColor = .systemYellow
        rope.lineWidth = 2
    }

    override func update(_ currentTime: TimeInterval) {
        let realDelta = previousTime.map { min(max(currentTime - $0, 0), 0.1) } ?? 0
        previousTime = currentTime
        let delta = playbackPaused ? 0 : realDelta * playbackRate
        let liveMotion: ExplorerMotion = activeHandle == "body" ? .held : selected
        rig.select(liveMotion)
        actualSizeRig.select(liveMotion)
        var targets: (WorldPoint, WorldPoint)?
        if liveMotion == .climbing {
            targets = (.init(x: handholds[0].x, y: handholds[0].y), .init(x: handholds[1].x, y: handholds[1].y))
        } else if liveMotion == .abseiling {
            let x = min(max(ropeAnchor.x, -10), 10)
            targets = (.init(x: x - 4, y: 61), .init(x: x + 4, y: 62))
        }
        for character in [rig, actualSizeRig] {
            character.handTargets = targets
            character.grabPoint = grabPoint
            character.render(delta: delta)
        }
        var beat = "Drag the body to interrupt any pose"
        if selected == .comic {
            let t = rig.animationTime.truncatingRemainder(dividingBy: 9)
            beat = t < 2 ? "Approach the edge" : (t < 3.5 ? "Look down. Reconsider." : (t < 5 ? "Back away with dignity" : "Picked up by the mysterious giant"))
        }
        status.text = "\(liveMotion.rawValue.uppercased()) \(facing > 0 ? "→" : "←") · \(String(format: "%.2f", playbackRate))× · \(rig.clampedContacts) clamped contacts · \(beat)"
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        if let target = handles.children.first(where: { $0.name != nil && $0.contains(point) })?.name {
            activeHandle = target
            return
        }
        let local = rig.convert(point, from: self)
        if rig.calculateAccumulatedFrame().contains(point) {
            activeHandle = "body"
            rigDragOffset = CGPoint(x: point.x - rig.position.x, y: point.y - rig.position.y)
            grabPoint = local
            rig.select(.held)
            actualSizeRig.select(.held)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeHandle else { return }
        let point = event.location(in: self)
        let local = rig.convert(point, from: self)
        switch activeHandle {
        case "left handhold": handholds[0] = local
        case "right handhold": handholds[1] = local
        case "rope anchor": ropeAnchor = local
        case "grab point": grabPoint = local
        case "body":
            let fixedHolds = handholds.map { rig.convert($0, to: self) }
            let fixedAnchor = rig.convert(ropeAnchor, to: self)
            rig.position = CGPoint(x: min(max(point.x - rigDragOffset.x, 100), size.width - 100), y: min(max(point.y - rigDragOffset.y, 40), size.height - 100))
            handholds = fixedHolds.map { rig.convert($0, from: self) }
            ropeAnchor = rig.convert(fixedAnchor, from: self)
            hasCustomOrigin = true
        default: break
        }
        rebuildStage()
    }

    override func mouseUp(with event: NSEvent) {
        guard activeHandle != nil else { return }
        activeHandle = nil
        rig.select(selected)
        actualSizeRig.select(selected)
        rebuildStage()
    }
}
#endif
