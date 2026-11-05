import AppKit
import SpriteKit
import ExpeditionCore

/// All props share the click-through scene. Only the explorer's body has an input panel.
@MainActor
final class ExpeditionProps: SKNode {
    private let discovery = SKNode()
    private let suspectedSock = SKShapeNode()
    private let banana = SKShapeNode()
    private let flag = SKNode()
    private let binoculars = SKNode()
    private let map = SKNode()
    private let speech = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let speechBacking = SKShapeNode(rectOf: CGSize(width: 106, height: 24), cornerRadius: 8)

    override init() {
        super.init()
        addChild(discovery)
        let sock = CGMutablePath()
        sock.move(to: .init(x: -4, y: 22)); sock.addLine(to: .init(x: 5, y: 22))
        sock.addLine(to: .init(x: 5, y: 9)); sock.addQuadCurve(to: .init(x: 14, y: 3), control: .init(x: 18, y: 9))
        sock.addLine(to: .init(x: 0, y: 0)); sock.addQuadCurve(to: .init(x: -4, y: 7), control: .init(x: -5, y: 0)); sock.closeSubpath()
        suspectedSock.path = sock
        suspectedSock.fillColor = .init(calibratedWhite: 0.24, alpha: 1)
        suspectedSock.strokeColor = .init(calibratedWhite: 0.12, alpha: 1)
        discovery.addChild(suspectedSock)
        let curve = CGMutablePath()
        curve.move(to: .init(x: -10, y: 15))
        curve.addCurve(to: .init(x: 13, y: 18), control1: .init(x: -5, y: -7), control2: .init(x: 16, y: -4))
        curve.addCurve(to: .init(x: -10, y: 15), control1: .init(x: 8, y: 6), control2: .init(x: -2, y: 3))
        curve.closeSubpath()
        banana.path = curve
        banana.fillColor = .init(calibratedRed: 0.98, green: 0.78, blue: 0.15, alpha: 1)
        banana.strokeColor = .init(calibratedRed: 0.40, green: 0.27, blue: 0.10, alpha: 1)
        banana.lineWidth = 1
        discovery.addChild(banana)
        let stem = SKShapeNode(rect: .init(x: 10, y: 15, width: 3, height: 6), cornerRadius: 1)
        stem.fillColor = .brown; stem.strokeColor = .clear
        banana.addChild(stem)
        let pole = SKShapeNode(rect: .init(x: 0, y: 0, width: 1.5, height: 35))
        pole.fillColor = .brown; pole.strokeColor = .clear; flag.addChild(pole)
        let pennant = CGMutablePath()
        pennant.move(to: .init(x: 1, y: 34)); pennant.addLine(to: .init(x: 17, y: 29)); pennant.addLine(to: .init(x: 1, y: 24)); pennant.closeSubpath()
        let fabric = SKShapeNode(path: pennant); fabric.fillColor = .systemRed; fabric.strokeColor = .brown; fabric.lineWidth = 0.5
        flag.addChild(fabric); discovery.addChild(flag); flag.position.x = -20
        for x: CGFloat in [-4, 4] {
            let tube = SKShapeNode(rect: .init(x: x - 3, y: -3, width: 6, height: 9), cornerRadius: 2)
            tube.fillColor = .init(calibratedWhite: 0.17, alpha: 1); tube.strokeColor = .black; tube.lineWidth = 0.7
            binoculars.addChild(tube)
        }
        addChild(binoculars)
        let paper = SKShapeNode(rectOf: .init(width: 22, height: 16), cornerRadius: 1)
        paper.fillColor = .init(calibratedRed: 0.94, green: 0.87, blue: 0.68, alpha: 1)
        paper.strokeColor = .brown; paper.lineWidth = 0.7
        map.addChild(paper)
        let trail = CGMutablePath(); trail.move(to: .init(x: -8, y: -4)); trail.addLine(to: .init(x: -3, y: 4)); trail.addLine(to: .init(x: 5, y: -2))
        let ink = SKShapeNode(path: trail); ink.strokeColor = .systemRed; ink.lineWidth = 1; map.addChild(ink)
        addChild(map)
        speech.fontSize = 10; speech.fontColor = .init(calibratedWhite: 0.15, alpha: 1)
        speech.verticalAlignmentMode = .center; speech.zPosition = 3
        speechBacking.fillColor = .init(calibratedRed: 1, green: 0.97, blue: 0.88, alpha: 0.97)
        speechBacking.strokeColor = .init(calibratedWhite: 0.3, alpha: 0.9); speechBacking.lineWidth = 0.7
        speechBacking.zPosition = -1; speech.addChild(speechBacking); addChild(speech)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func update(mission: BananaMission, explorer: WorldPoint, target: WorldPoint?, facing: Double, viewport: CGRect, held: Bool) {
        let stage = mission.stage
        discovery.isHidden = target == nil || held
        if let target { discovery.position = .init(x: target.x, y: target.y + 2) }
        let revealed = stage == .revealing || stage == .updatingMap || stage == .resting
        banana.isHidden = !revealed
        suspectedSock.isHidden = revealed
        banana.zRotation = revealed ? sin(min(mission.elapsed, 0.4) / 0.4 * .pi) * 0.2 : 0
        flag.isHidden = !revealed
        binoculars.isHidden = stage != .spotting || held
        binoculars.position = .init(x: explorer.x + 10 * facing, y: explorer.y + 59)
        map.isHidden = stage != .updatingMap || held
        map.position = .init(x: explorer.x + 8 * facing, y: explorer.y + 45)
        map.zRotation = -0.2 * facing
        let text: String?
        switch stage {
        case .spotting: text = "A sock! Surely."
        case .revealing: text = "…a banana."
        case .updatingMap: text = "Mark it on the map."
        default: text = nil
        }
        speech.isHidden = text == nil || held
        speech.text = text
        speech.position = .init(x: min(max(explorer.x, viewport.minX + 58), viewport.maxX - 58), y: min(explorer.y + 96, viewport.maxY - 16))
    }
}
