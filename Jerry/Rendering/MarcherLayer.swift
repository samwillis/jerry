import AppKit
import SpriteKit
import ExpeditionCore

/// Click-through artwork for Marchers mode: the hatch, the exit, every marcher, the tunnels and
/// bridges they leave on windows, and the skill tokens Jerry signals with.
@MainActor
final class MarcherLayer: SKNode {
    private let tunnels = SKShapeNode()
    private let bricks = SKShapeNode()
    private let hatch = SKNode()
    private let hatchLeft = SKShapeNode(rectOf: CGSize(width: 15, height: 2.4), cornerRadius: 0.6)
    private let hatchRight = SKShapeNode(rectOf: CGSize(width: 15, height: 2.4), cornerRadius: 0.6)
    private let exitDoor = SKNode()
    private let sprites = SKNode()
    private var marchers: [Int: MarcherSprite] = [:]
    private let signalPaths = SKShapeNode()
    private var tokens: [SKNode] = []
    private let planMarker = SKShapeNode(circleOfRadius: 8)
    private let planBadge = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let status = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let statusBacking = SKShapeNode()
    private var drawnRevision = -1
    private var drawnFrames: [WorldRect] = []
    private var drawnLevel = -1
    private var drawnStatus = ""

    private static let wood = NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.2, alpha: 1)
    private static let darkWood = NSColor(calibratedRed: 0.3, green: 0.19, blue: 0.1, alpha: 1)

    override init() {
        super.init()
        tunnels.fillColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.09, alpha: 0.72)
        tunnels.strokeColor = NSColor(calibratedRed: 0.4, green: 0.28, blue: 0.16, alpha: 0.8)
        tunnels.lineWidth = 0.6
        addChild(tunnels)
        bricks.fillColor = NSColor(calibratedRed: 0.82, green: 0.53, blue: 0.3, alpha: 1)
        bricks.strokeColor = NSColor(calibratedRed: 0.45, green: 0.26, blue: 0.13, alpha: 1)
        bricks.lineWidth = 0.5
        addChild(bricks)
        buildHatch()
        buildExit()
        addChild(sprites)
        signalPaths.strokeColor = NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.3, alpha: 0.8)
        signalPaths.lineWidth = 1
        signalPaths.zPosition = 4
        addChild(signalPaths)
        planMarker.strokeColor = NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.3, alpha: 0.75)
        planMarker.lineWidth = 1
        planMarker.zPosition = 3
        planBadge.fontSize = 8; planBadge.verticalAlignmentMode = .center
        planBadge.fontColor = planMarker.strokeColor
        planMarker.addChild(planBadge)
        addChild(planMarker)
        status.fontSize = 11; status.fontColor = NotebookTheme.ink
        status.horizontalAlignmentMode = .left; status.verticalAlignmentMode = .center
        status.zPosition = 6
        statusBacking.fillColor = NSColor(calibratedRed: 1, green: 0.97, blue: 0.88, alpha: 0.95)
        statusBacking.strokeColor = NSColor(calibratedWhite: 0.3, alpha: 0.9); statusBacking.lineWidth = 0.7
        statusBacking.zPosition = -1
        status.addChild(statusBacking)
        addChild(status)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func update(coach: MarcherCoach?) {
        guard let coach else {
            isHidden = true
            sprites.removeAllChildren(); marchers.removeAll()
            drawnRevision = -1; drawnLevel = -1
            return
        }
        isHidden = false
        let level = coach.level
        if drawnLevel != level.number {
            drawnLevel = level.number
            sprites.removeAllChildren(); marchers.removeAll()
            drawnRevision = -1
        }
        drawTerrainChanges(level.world)

        let hatchPoint = level.hatch
        hatch.position = CGPoint(x: hatchPoint.x, y: hatchPoint.y)
        let open: CGFloat = level.phase == .releasing ? 1.2 : 0
        hatchLeft.zRotation = -open; hatchRight.zRotation = open

        if let exit = level.exitPoint {
            exitDoor.isHidden = false
            exitDoor.position = CGPoint(x: exit.x, y: exit.y)
        } else {
            exitDoor.isHidden = true
        }

        var seen = Set<Int>()
        for marcher in level.marchers where marcher.state != .saved && marcher.state != .lost {
            seen.insert(marcher.id)
            let sprite: MarcherSprite
            if let existing = marchers[marcher.id] { sprite = existing } else {
                sprite = MarcherSprite(); marchers[marcher.id] = sprite; sprites.addChild(sprite)
            }
            sprite.show(marcher)
        }
        for (id, sprite) in marchers where !seen.contains(id) { sprite.removeFromParent(); marchers[id] = nil }

        drawSignals(coach.signals)
        if let next = coach.plans.values.min(by: { $0.delay < $1.delay }), let marcher = level.marcher(next.marcherID), marcher.isActive {
            planMarker.isHidden = false
            planMarker.position = CGPoint(x: next.position.x + 0.5, y: next.position.y + 7)
            planBadge.text = next.skill.badge
        } else {
            planMarker.isHidden = true
        }

        let text = coach.status
        if text != drawnStatus {
            drawnStatus = text
            status.text = text
            let width = status.frame.width + 16
            statusBacking.path = CGPath(roundedRect: CGRect(x: -8, y: -10, width: width, height: 20), cornerWidth: 7, cornerHeight: 7, transform: nil)
        }
        status.position = CGPoint(x: hatchPoint.x + 34, y: hatchPoint.y - 12)
    }

    private func drawTerrainChanges(_ world: MarcherWorld) {
        let frames = world.blocks.map(\.frame)
        guard world.revision != drawnRevision || frames != drawnFrames else { return }
        drawnRevision = world.revision; drawnFrames = frames
        let holes = CGMutablePath()
        for (_, carve) in world.worldCarves() {
            switch carve {
            case .rect(let rect): holes.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
            case .circle(let x, let y, let radius): holes.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        tunnels.path = holes
        let steps = CGMutablePath()
        for rect in world.brickRects { steps.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)) }
        bricks.path = steps
    }

    private func drawSignals(_ signals: [MarcherSignal]) {
        let path = CGMutablePath()
        while tokens.count < signals.count {
            let token = SKShapeNode(circleOfRadius: 5)
            token.fillColor = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.36, alpha: 1)
            token.strokeColor = Self.darkWood; token.lineWidth = 0.8; token.zPosition = 5
            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.name = "badge"; label.fontSize = 7; label.fontColor = Self.darkWood
            label.verticalAlignmentMode = .center
            token.addChild(label)
            addChild(token); tokens.append(token)
        }
        for (index, token) in tokens.enumerated() {
            guard index < signals.count else { token.isHidden = true; continue }
            let signal = signals[index]
            let flight = MarcherSignal.duration * 0.6
            let progress = CGFloat(min(1, signal.age / flight))
            let from = CGPoint(x: signal.from.x, y: signal.from.y), to = CGPoint(x: signal.to.x, y: signal.to.y)
            let control = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 36)
            let a: CGFloat = (1 - progress) * (1 - progress), b: CGFloat = 2 * (1 - progress) * progress, c: CGFloat = progress * progress
            path.move(to: from); path.addQuadCurve(to: to, control: control)
            token.isHidden = false
            token.position = CGPoint(x: a * from.x + b * control.x + c * to.x, y: a * from.y + b * control.y + c * to.y)
            let fade = CGFloat(max(0, 1 - (signal.age - flight) / (MarcherSignal.duration - flight)))
            token.alpha = progress >= 1 ? fade : 1
            (token.childNode(withName: "badge") as? SKLabelNode)?.text = signal.skill.badge
        }
        signalPaths.path = path
        signalPaths.alpha = signals.isEmpty ? 0 : CGFloat(0.6)
    }

    private func buildHatch() {
        let frame = SKShapeNode(rectOf: CGSize(width: 38, height: 9), cornerRadius: 2)
        frame.fillColor = Self.wood; frame.strokeColor = Self.darkWood; frame.lineWidth = 1
        let opening = SKShapeNode(rectOf: CGSize(width: 30, height: 4), cornerRadius: 1)
        opening.fillColor = NSColor(calibratedWhite: 0.08, alpha: 1); opening.strokeColor = .clear
        opening.position = CGPoint(x: 0, y: -1)
        frame.addChild(opening)
        hatch.addChild(frame)
        for (flap, x) in [(hatchLeft, -15.0), (hatchRight, 15.0)] {
            flap.fillColor = Self.wood; flap.strokeColor = Self.darkWood; flap.lineWidth = 0.6
            // Each flap hinges at its outer end.
            flap.path = CGPath(roundedRect: CGRect(x: x < 0 ? 0 : -15, y: -1.2, width: 15, height: 2.4), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil)
            flap.position = CGPoint(x: x, y: -4)
            hatch.addChild(flap)
        }
        addChild(hatch)
    }

    private func buildExit() {
        let arch = CGMutablePath()
        arch.move(to: CGPoint(x: -8, y: 0)); arch.addLine(to: CGPoint(x: -8, y: 13))
        arch.addArc(center: CGPoint(x: 0, y: 13), radius: 8, startAngle: .pi, endAngle: 0, clockwise: true)
        arch.addLine(to: CGPoint(x: 8, y: 0)); arch.closeSubpath()
        let door = SKShapeNode(path: arch)
        door.fillColor = NSColor(calibratedRed: 0.13, green: 0.09, blue: 0.07, alpha: 1)
        door.strokeColor = Self.wood; door.lineWidth = 2.2
        exitDoor.addChild(door)
        let glow = SKShapeNode(circleOfRadius: 3)
        glow.fillColor = NSColor(calibratedRed: 1, green: 0.82, blue: 0.4, alpha: 0.9); glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: 9)
        exitDoor.addChild(glow)
        let pole = CGMutablePath(); pole.move(to: CGPoint(x: 9, y: 0)); pole.addLine(to: CGPoint(x: 9, y: 32))
        let poleNode = SKShapeNode(path: pole); poleNode.strokeColor = Self.darkWood; poleNode.lineWidth = 1.2
        exitDoor.addChild(poleNode)
        let pennant = CGMutablePath()
        pennant.move(to: CGPoint(x: 9, y: 32)); pennant.addLine(to: CGPoint(x: 21, y: 28.5)); pennant.addLine(to: CGPoint(x: 9, y: 25)); pennant.closeSubpath()
        let flag = SKShapeNode(path: pennant)
        flag.fillColor = NotebookTheme.rust; flag.strokeColor = Self.darkWood; flag.lineWidth = 0.6
        exitDoor.addChild(flag)
        exitDoor.zPosition = -0.5
        addChild(exitDoor)
    }
}

/// A 14-point marcher drawn from simple strokes. Feet are at the node's origin.
@MainActor
private final class MarcherSprite: SKNode {
    private let figure = SKNode()
    private let leftLeg = MarcherSprite.limb(length: 5, width: 1.7, color: NSColor(calibratedRed: 0.32, green: 0.22, blue: 0.14, alpha: 1))
    private let rightLeg = MarcherSprite.limb(length: 5, width: 1.7, color: NSColor(calibratedRed: 0.38, green: 0.27, blue: 0.17, alpha: 1))
    private let leftArm = MarcherSprite.limb(length: 4.4, width: 1.4, color: NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.36, alpha: 1))
    private let rightArm = MarcherSprite.limb(length: 4.4, width: 1.4, color: NSColor(calibratedRed: 0.68, green: 0.62, blue: 0.42, alpha: 1))
    private let body = SKShapeNode(rectOf: CGSize(width: 5.2, height: 6.2), cornerRadius: 1.8)
    private let head = SKShapeNode(circleOfRadius: 2.3)
    private let hat = SKShapeNode()
    private let badge = SKShapeNode(circleOfRadius: 1.1)
    private let umbrella = SKShapeNode()
    private let tool = SKShapeNode()
    private let fuse = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let burst = SKShapeNode(circleOfRadius: 10)

    override init() {
        super.init()
        addChild(figure)
        leftLeg.position = CGPoint(x: -0.8, y: 5); rightLeg.position = CGPoint(x: 0.8, y: 5)
        leftArm.position = CGPoint(x: -0.4, y: 10.2); rightArm.position = CGPoint(x: 0.6, y: 10.2)
        body.position = CGPoint(x: 0, y: 8)
        body.fillColor = NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.45, alpha: 1)
        body.strokeColor = NSColor(calibratedRed: 0.36, green: 0.3, blue: 0.18, alpha: 1); body.lineWidth = 0.6
        head.position = CGPoint(x: 0.4, y: 12.5)
        head.fillColor = NSColor(calibratedRed: 0.95, green: 0.76, blue: 0.6, alpha: 1)
        head.strokeColor = NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.27, alpha: 1); head.lineWidth = 0.5
        let crown = CGMutablePath()
        crown.move(to: CGPoint(x: -3.6, y: 0)); crown.addLine(to: CGPoint(x: 4.2, y: 0))
        crown.move(to: CGPoint(x: -2, y: 0)); crown.addLine(to: CGPoint(x: -1.6, y: 2)); crown.addLine(to: CGPoint(x: 2.2, y: 2)); crown.addLine(to: CGPoint(x: 2.6, y: 0))
        hat.path = crown
        hat.position = CGPoint(x: 0.3, y: 13.6)
        hat.strokeColor = NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.13, alpha: 1); hat.lineWidth = 1.3
        hat.fillColor = NSColor(calibratedRed: 0.55, green: 0.37, blue: 0.2, alpha: 1)
        badge.position = CGPoint(x: 0.2, y: 15.4); badge.strokeColor = .clear
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -8, y: 0)); canopy.addQuadCurve(to: CGPoint(x: 8, y: 0), control: CGPoint(x: 0, y: 10))
        canopy.addQuadCurve(to: CGPoint(x: -8, y: 0), control: CGPoint(x: 0, y: 3))
        canopy.move(to: CGPoint(x: 0, y: 6)); canopy.addLine(to: CGPoint(x: 0, y: -7))
        umbrella.path = canopy
        umbrella.position = CGPoint(x: 0, y: 19)
        umbrella.fillColor = NSColor(calibratedRed: 0.24, green: 0.45, blue: 0.62, alpha: 1)
        umbrella.strokeColor = NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.32, alpha: 1); umbrella.lineWidth = 0.7
        tool.strokeColor = NSColor(calibratedWhite: 0.25, alpha: 1); tool.lineWidth = 1.1
        for node in [leftLeg, leftArm, body, rightLeg, head, hat, badge, rightArm, umbrella, tool] as [SKNode] { figure.addChild(node) }
        fuse.fontSize = 9; fuse.fontColor = NotebookTheme.rust; fuse.position = CGPoint(x: 0, y: 20)
        addChild(fuse)
        burst.fillColor = NSColor(calibratedRed: 1, green: 0.7, blue: 0.25, alpha: 0.85)
        burst.strokeColor = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.1, alpha: 1); burst.lineWidth = 1.5
        burst.position = CGPoint(x: 0, y: 5)
        addChild(burst)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    private static func limb(length: CGFloat, width: CGFloat, color: NSColor) -> SKShapeNode {
        let path = CGMutablePath(); path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: -length))
        let node = SKShapeNode(path: path)
        node.strokeColor = color; node.lineWidth = width; node.lineCap = .round
        return node
    }

    func show(_ m: Marcher) {
        position = CGPoint(x: Double(m.x) + 0.5, y: Double(m.y))
        figure.xScale = CGFloat(m.direction)
        figure.yScale = 1; figure.alpha = 1; figure.isHidden = false; figure.position = .zero; figure.zRotation = 0
        umbrella.isHidden = !m.umbrellaOpen
        burst.isHidden = true
        tool.isHidden = true
        badge.isHidden = !(m.isClimber || m.isFloater)
        badge.fillColor = m.isClimber && m.isFloater ? .systemPurple : (m.isClimber ? .systemGreen : .systemBlue)
        if let remaining = m.fuse, m.isActive {
            fuse.isHidden = false; fuse.text = "\(max(1, Int(remaining.rounded(.up))))"
        } else { fuse.isHidden = true }

        let t = m.stateTime
        let swing = CGFloat(sin(m.stride * 0.55)) * 0.6
        var legs: (CGFloat, CGFloat) = (swing, -swing)
        var arms: (CGFloat, CGFloat) = (-swing * 0.8, swing * 0.8)
        switch m.state {
        case .walking:
            figure.position.y = abs(CGFloat(sin(m.stride * 0.55))) * 0.5
        case .falling:
            legs = (0.25, -0.25)
            let flail = CGFloat(sin(t * 18)) * 0.3
            arms = m.umbrellaOpen ? (2.9, 2.9) : (2.5 + flail, -2.5 - flail)
        case .climbing:
            let phase = CGFloat(sin(t * 9))
            legs = (0.9 + phase * 0.4, 0.9 - phase * 0.4)
            arms = (2.4 + phase * 0.4, 2.4 - phase * 0.4)
            figure.position.x = -0.5
        case .blocking:
            legs = (0.35, -0.35)
            arms = (1.57, -1.57)
        case .building:
            let lay = CGFloat(max(0, sin(t / MarcherTuning.buildInterval * .pi * 2)))
            legs = (0.15, -0.15)
            arms = (0.6 + lay * 0.9, 0.4 + lay * 0.9)
        case .bashing:
            let punch = CGFloat(sin(t * 14))
            legs = (0.3, -0.3)
            arms = (1.6 + punch * 0.5, 1.3 - punch * 0.5)
        case .mining:
            let stroke = CGFloat(sin(t * 7))
            legs = (0.4, -0.2)
            arms = (2.2 + stroke * 1.1, 2.2 + stroke * 1.1)
            drawTool(pick: true, angle: 2.2 + stroke * 1.1)
        case .digging:
            let scoop = CGFloat(sin(t * 10))
            figure.position.y = -1 + scoop * 0.6
            legs = (0.5, -0.5)
            arms = (0.5 + scoop * 0.5, 0.5 + scoop * 0.5)
            drawTool(pick: false, angle: 0.5 + scoop * 0.5)
        case .exiting:
            let progress = CGFloat(min(1, t / MarcherTuning.exitDuration))
            figure.alpha = 1 - progress
            figure.yScale = 1 - progress * 0.4
            arms = (2.6, -2.6)
        case .splatting:
            let progress = CGFloat(min(1, t / MarcherTuning.splatDuration))
            figure.yScale = 0.3
            figure.alpha = 1 - progress
            legs = (1.4, -1.4); arms = (1.5, -1.5)
        case .exploding:
            figure.isHidden = true
            let progress = CGFloat(min(1, t / MarcherTuning.explosionDuration))
            burst.isHidden = false
            burst.setScale(0.4 + progress * 1.4)
            burst.alpha = 1 - progress
        case .saved, .lost:
            figure.isHidden = true
        }
        leftLeg.zRotation = legs.0; rightLeg.zRotation = legs.1
        leftArm.zRotation = arms.0; rightArm.zRotation = arms.1
    }

    /// A pick or shovel held at the end of the front arm.
    private func drawTool(pick: Bool, angle: CGFloat) {
        let hand = CGPoint(x: rightArm.position.x + sin(angle) * 4.4, y: rightArm.position.y - cos(angle) * 4.4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: hand.x - 1, y: hand.y + 1)); path.addLine(to: CGPoint(x: hand.x + 3, y: hand.y - 3))
        if pick {
            path.move(to: CGPoint(x: hand.x + 1, y: hand.y - 4)); path.addLine(to: CGPoint(x: hand.x + 5, y: hand.y - 1))
        } else {
            path.addRect(CGRect(x: hand.x + 2.2, y: hand.y - 4.6, width: 2.2, height: 2.2))
        }
        tool.path = path
        tool.isHidden = false
    }
}
