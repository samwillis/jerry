import AppKit
import SpriteKit
import ExpeditionCore

/// All props share the click-through scene. Only the explorer's body has an input panel.
@MainActor
final class ExpeditionProps: SKNode {
    private let discovery = SKNode()
    private let sock = SKNode()
    private var sockStyle = -1
    private let binoculars = SKNode()
    private let map = SKNode()
    private let speech = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let speechBacking = SKShapeNode(rectOf: CGSize(width: 106, height: 24), cornerRadius: 8)

    override init() {
        super.init()
        addChild(discovery)
        discovery.addChild(sock)
        styleSock(0)
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

    /// Four designs rotate between discoveries; every mark is clipped to the knit.
    private func styleSock(_ style: Int) {
        guard sockStyle != style else { return }
        sockStyle = style; sock.removeAllChildren()
        let bases: [NSColor] = [.init(calibratedRed: 0.72, green: 0.22, blue: 0.23, alpha: 1),
                                .init(calibratedRed: 0.17, green: 0.33, blue: 0.53, alpha: 1),
                                .init(calibratedRed: 0.17, green: 0.50, blue: 0.44, alpha: 1),
                                .init(calibratedRed: 0.49, green: 0.30, blue: 0.59, alpha: 1)]
        let cream = NSColor(calibratedRed: 1, green: 0.91, blue: 0.68, alpha: 1)
        let ink = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1)
        let shape = CGMutablePath()
        shape.move(to: .init(x: -5, y: 24)); shape.addLine(to: .init(x: 6, y: 24))
        shape.addLine(to: .init(x: 6, y: 10))
        shape.addQuadCurve(to: .init(x: 15, y: 8), control: .init(x: 18, y: 11))
        shape.addQuadCurve(to: .init(x: 14, y: 2), control: .init(x: 19, y: 4))
        shape.addLine(to: .init(x: 0, y: 0))
        shape.addQuadCurve(to: .init(x: -5, y: 7), control: .init(x: -6, y: 0)); shape.closeSubpath()
        let body = SKShapeNode(path: shape); body.fillColor = bases[style]; body.strokeColor = .clear; sock.addChild(body)
        let crop = SKCropNode()
        let mask = SKShapeNode(path: shape); mask.fillColor = .white; mask.strokeColor = .clear; crop.maskNode = mask; sock.addChild(crop)
        func mark(_ path: CGPath, fill: NSColor = .clear, stroke: NSColor = .clear, width: CGFloat = 1) {
            let node = SKShapeNode(path: path); node.fillColor = fill; node.strokeColor = stroke; node.lineWidth = width; crop.addChild(node)
        }
        switch style {
        case 0: // Cream sailor stripes.
            for y in stride(from: CGFloat(4), through: 20, by: 5) { mark(CGPath(rect: .init(x: -6, y: y, width: 26, height: 2), transform: nil), fill: cream) }
        case 1: // Big enough to read as spots at desktop scale.
            for y in stride(from: CGFloat(5), through: 20, by: 5) {
                for x in stride(from: CGFloat(-3), through: 13, by: 5) {
                    mark(CGPath(ellipseIn: .init(x: x, y: y, width: 2.2, height: 2.2), transform: nil), fill: cream)
                }
            }
        case 2: // Tiny argyle diamonds.
            for y in stride(from: CGFloat(5), through: 20, by: 6) {
                let diamond = CGMutablePath(); diamond.move(to: .init(x: 0.5, y: y + 3)); diamond.addLine(to: .init(x: 4, y: y)); diamond.addLine(to: .init(x: 0.5, y: y - 3)); diamond.addLine(to: .init(x: -3, y: y)); diamond.closeSubpath()
                mark(diamond, fill: cream)
            }
        default: // Zigzag knit.
            for y in stride(from: CGFloat(5), through: 20, by: 5) {
                let zigzag = CGMutablePath(); zigzag.move(to: .init(x: -6, y: y))
                for x in stride(from: -3, through: 18, by: 3) { zigzag.addLine(to: .init(x: CGFloat(x), y: y + (x % 2 == 0 ? 0 : 2))) }
                mark(zigzag, stroke: cream, width: 1.5)
            }
        }
        mark(CGPath(rect: .init(x: -5, y: 20, width: 11, height: 4), transform: nil), fill: cream)
        mark(CGPath(ellipseIn: .init(x: 11, y: 0, width: 9, height: 9), transform: nil), fill: cream)
        mark(CGPath(ellipseIn: .init(x: -8, y: 0, width: 9, height: 8), transform: nil), fill: cream)
        for x in stride(from: CGFloat(-3), through: 4, by: 2) { mark(CGPath(rect: .init(x: x, y: 21, width: 0.5, height: 2), transform: nil), fill: bases[style].withAlphaComponent(0.5)) }
        let outline = SKShapeNode(path: shape); outline.fillColor = .clear; outline.strokeColor = ink; outline.lineWidth = 0.9; sock.addChild(outline)
    }

    func update(mission: SockMission, explorer: WorldPoint, target: WorldPoint?, facing: Double, viewport: CGRect, held: Bool) {
        let stage = mission.stage
        discovery.isHidden = target == nil || held
        if let target { discovery.position = .init(x: target.x, y: target.y + 2) }
        let revealed = stage == .revealing || stage == .updatingMap || stage == .resting
        styleSock(mission.pattern.rawValue)
        sock.zRotation = revealed ? sin(min(mission.elapsed, 0.4) / 0.4 * .pi) * 0.12 : 0
        binoculars.isHidden = stage != .spotting || held
        binoculars.position = .init(x: explorer.x + 10 * facing, y: explorer.y + 59)
        map.isHidden = stage != .updatingMap || held
        map.position = .init(x: explorer.x + 8 * facing, y: explorer.y + 45)
        map.zRotation = -0.2 * facing
        let text: String?
        switch stage {
        case .spotting: text = "A sock!"
        case .revealing: text = ["Stripes! Nice.", "Spots! Excellent.", "Argyle. Classy.", "Zigzags!"][sockStyle]
        case .updatingMap: text = "Mark it on the map."
        default: text = nil
        }
        speech.isHidden = text == nil || held
        speech.text = text
        speech.position = .init(x: min(max(explorer.x, viewport.minX + 58), viewport.maxX - 58), y: min(explorer.y + 96, viewport.maxY - 16))
    }
}
