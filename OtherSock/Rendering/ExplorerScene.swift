import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class ExplorerScene: SKScene {
    private let explorer = ExplorerRig()
    private let debug = SKNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo")
    private let terrainGuides = SKNode()
    private var terrain: TerrainSnapshot?
    private var geometryUnavailable = true
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
    }

    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    func layout(in usableFrame: CGRect) {
        self.usableFrame = usableFrame
        terrain = nil
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
        if let position = interaction?.position {
            explorer.grabPoint = CGPoint(x: point.x - position.x, y: point.y - position.y)
        }
        interaction?.beginDrag(at: .init(x: point.x, y: point.y))
        applyPlacement()
    }

    func drag(to point: CGPoint) {
        interaction?.drag(to: .init(x: point.x, y: point.y))
        applyPlacement()
    }

    func endDrag() {
        interaction?.endDrag(on: terrain)
        applyPlacement()
    }

    func updateTerrain(_ snapshot: TerrainSnapshot?) {
        let unavailable = snapshot == nil
        // If window-server metadata fails, retain only the guaranteed rescue boundaries.
        let next = snapshot ?? TerrainSnapshot(windows: [], viewport: WorldRect(x: usableFrame.minX, y: usableFrame.minY + 2, width: usableFrame.width, height: max(0, usableFrame.height - 2)))
        guard terrain != next || geometryUnavailable != unavailable else { return }
        terrain = next
        geometryUnavailable = unavailable
        interaction?.updateTerrain(next)
        rebuildTerrainGuides()
        applyPlacement()
    }

    private func rebuildTerrainGuides() {
        terrainGuides.removeAllChildren()
        guard let terrain else { return }
        for surface in terrain.surfaces {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: surface.start.x, y: surface.start.y))
            path.addLine(to: CGPoint(x: surface.end.x, y: surface.end.y))
            let line = SKShapeNode(path: path)
            line.strokeColor = surface.id.owner == .screen ? .systemTeal : (surface.id.edge == .top ? .systemGreen : .systemPink)
            line.lineWidth = 2
            terrainGuides.addChild(line)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = previousUpdateTime.map { min(max(currentTime - $0, 0), 0.1) } ?? 0
        previousUpdateTime = currentTime
        guard !expeditionPaused else { explorer.render(delta: 0); return }
        let previousState = interaction?.state
        let previousPosition = interaction?.position
        interaction?.advance(by: elapsed)
        if previousState != interaction?.state || previousPosition != interaction?.position { applyPlacement() }
        explorer.render(delta: interaction?.state == .settling ? 0 : elapsed)
    }

    private func applyPlacement() {
        guard let interaction else { return }
        explorer.position = CGPoint(x: interaction.position.x, y: interaction.position.y)
        let motion: ExplorerMotion = interaction.state == .held ? .held : (interaction.state == .recovering ? .parachuting : .idle)
        explorer.select(motion)
        explorer.render(delta: 0)
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
        debug.addChild(terrainGuides)
        let outline = SKShapeNode(rect: usableFrame.insetBy(dx: 3, dy: 3))
        outline.strokeColor = .systemTeal
        outline.lineWidth = 1
        debug.addChild(outline)
        let bounds = SKShapeNode(rect: CGRect(x: explorer.position.x - 24, y: explorer.position.y - 1, width: 48, height: 76))
        bounds.strokeColor = .systemYellow
        bounds.lineWidth = 1
        debug.addChild(bounds)
        let count = terrain?.windows.filter(\.canClimb).count ?? 0
        let status = geometryUnavailable ? "GEOMETRY UNAVAILABLE" : "\(count) WINDOWS · \(terrain?.surfaces.count ?? 0) EDGES"
        debugLabel.text = "PHASE 3 · \(expeditionPaused ? "PAUSED" : "RUNNING") · \(interaction?.state.rawValue.uppercased() ?? "IDLE") · \(status)"
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
