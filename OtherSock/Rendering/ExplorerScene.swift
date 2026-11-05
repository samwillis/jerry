import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class ExplorerScene: SKScene {
    private let explorer = ExplorerRig()
    private let debug = SKNode()
    private let rope = SKShapeNode()
    private let props = ExpeditionProps()
    private var startedOnWindow = false
    private var startedRopeDemo = false
    private var tracedState = ""
    private var frameSamples: [Double] = []
    private var lastInputFrame: CGRect?
    private var lastInputState = ""
    var playbackRate: Double = 1
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
        addChild(rope)
        rope.strokeColor = .init(calibratedRed: 0.72, green: 0.57, blue: 0.32, alpha: 1)
        rope.lineWidth = 1.2
        addChild(explorer)
        addChild(props)
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
        interaction?.autonomous = true
        interaction?.runsMission = true
        applyPlacement()
    }

    func resetExpedition() {
        interaction = nil
        previousUpdateTime = nil
        let previousTerrain = terrain
        layout(in: usableFrame)
        if let previousTerrain { updateTerrain(previousTerrain) }
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
        interaction?.beginDrag(at: .init(x: point.x, y: point.y), time: ProcessInfo.processInfo.systemUptime)
        applyPlacement()
    }

    func drag(to point: CGPoint) {
        interaction?.drag(to: .init(x: point.x, y: point.y), time: ProcessInfo.processInfo.systemUptime)
        applyPlacement()
    }

    func endDrag() {
        interaction?.endDrag(on: terrain)
        applyPlacement()
        if interaction?.state == .settling, interaction?.attachment != nil { explorer.land(strength: 0.5) }
    }

    func updateTerrain(_ snapshot: TerrainSnapshot?) {
        let unavailable = snapshot == nil
        // If window-server metadata fails, retain only the guaranteed rescue boundaries.
        let next = snapshot ?? TerrainSnapshot(windows: [], viewport: WorldRect(x: usableFrame.minX, y: usableFrame.minY + 2, width: usableFrame.width, height: max(0, usableFrame.height - 2)))
        guard terrain != next || geometryUnavailable != unavailable else { return }
        terrain = next
        geometryUnavailable = unavailable
        #if DEBUG
        if !startedOnWindow, ProcessInfo.processInfo.arguments.contains("--start-on-window") {
            let initialSurfaces = ProcessInfo.processInfo.arguments.contains("--start-low") ? next.surfaces.sorted { $0.start.y < $1.start.y } : next.surfaces
            for surface in initialSurfaces where surface.id.edge == .top {
                if let (_, point) = TerrainSupport.attach(at: .init(x: (surface.start.x + surface.end.x) / 2, y: surface.start.y), in: next) {
                    let safe = ExplorerInteraction.Bounds(minimum: .init(x: usableFrame.minX + 24, y: usableFrame.minY + 2), maximum: .init(x: usableFrame.maxX - 24, y: usableFrame.maxY - 76))
                    interaction = ExplorerInteraction(position: point, bounds: safe)
                    interaction?.autonomous = true
                    interaction?.runsMission = !ProcessInfo.processInfo.arguments.contains("--movement-only") && !ProcessInfo.processInfo.arguments.contains("--rope-demo")
                    startedOnWindow = true
                    break
                }
            }
        }
        #endif
        interaction?.updateTerrain(next)
        #if DEBUG
        if !startedRopeDemo, ProcessInfo.processInfo.arguments.contains("--rope-demo"), let anchor = interaction?.attachment {
            let steps = NavigationGraph(terrain: next).route(from: anchor, seed: 0, allowParachute: false)
            if steps.contains(where: { $0.kind == .abseiling }) { startedRopeDemo = interaction?.follow(steps) == true }
        }
        #endif
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
        let rawElapsed = previousUpdateTime.map { max(currentTime - $0, 0) } ?? 0
        let elapsed = min(rawElapsed, 0.25)
        previousUpdateTime = currentTime
        guard !expeditionPaused else { return }
        let previousState = interaction?.state
        interaction?.advance(by: elapsed * playbackRate)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--freeze-rope"), let interaction,
           interaction.state == .abseiling, let anchor = interaction.ropeAnchor,
           interaction.position.y < anchor.y - 90 {
            setExpeditionPaused(true)
        }
        #endif
        if previousState == .recovering, interaction?.state == .settling { explorer.land() }
        // Mission beats also change while the explorer is standing still.
        applyPlacement()
        explorer.render(delta: elapsed * playbackRate)
        #if DEBUG
        if rawElapsed > 0, ProcessInfo.processInfo.arguments.contains("--performance-report") {
            frameSamples.append(rawElapsed)
            if frameSamples.count == 300 {
                let sorted = frameSamples.sorted()
                func nodes(_ node: SKNode) -> Int { 1 + node.children.reduce(0) { $0 + nodes($1) } }
                print(String(format: "PERFORMANCE %.1f fps · p95 %.1f ms · max %.1f ms · %d nodes", 300 / frameSamples.reduce(0, +), sorted[284] * 1000, sorted.last! * 1000, nodes(self)))
                frameSamples.removeAll(keepingCapacity: true)
                fflush(stdout)
            }
        }
        let trace = "\(interaction?.state.rawValue ?? "none") · \(interaction?.mission.stage.rawValue ?? "none") · \(interaction?.mission.completedExpeditions ?? 0)"
        if tracedState != trace, ProcessInfo.processInfo.arguments.contains("--trace-movement") {
            tracedState = trace
            print("EXPEDITION \(trace) @ \(interaction?.position ?? .zero)")
            fflush(stdout)
        }
        #endif
    }

    private func applyPlacement() {
        guard let interaction else { return }
        explorer.position = CGPoint(x: interaction.position.x, y: interaction.position.y)
        var motion: ExplorerMotion
        switch interaction.state {
        case .held: motion = .held
        case .recovering: motion = .parachuting
        case .walking: motion = .walking
        case .climbing: motion = .climbing
        case .abseiling: motion = .abseiling
        default: motion = .idle
        }
        let stage = interaction.mission.stage
        let stationary = interaction.state == .idle || interaction.state == .settling
        if stationary, [.spotting, .investigating, .revealing, .updatingMap].contains(stage) { motion = .investigating }
        let target = interaction.mission.target.flatMap { anchor in terrain.flatMap { TerrainSupport.resolve(anchor, in: $0) } }
        var facing = interaction.facing
        if stationary, let target { facing = target.x >= interaction.position.x ? 1 : -1 }
        explorer.xScale = facing
        explorer.handTargets = nil
        explorer.footTargets = nil
        if motion == .climbing {
            let contacts = ClimbingContacts(heightAlongWall: interaction.heightAlongWall)
            explorer.handTargets = (contacts.leftHand, contacts.rightHand)
            explorer.footTargets = (contacts.leftFoot, contacts.rightFoot)
        }
        if stationary, stage == .spotting {
            explorer.handTargets = (.init(x: 6, y: 59), .init(x: 14, y: 59))
        } else if stationary, stage == .updatingMap {
            explorer.handTargets = (.init(x: -1, y: 43), .init(x: 16, y: 44))
        }
        props.update(mission: interaction.mission, explorer: interaction.position, target: target, facing: facing, viewport: usableFrame, held: interaction.state == .held)
        explorer.select(motion)
        rope.isHidden = interaction.ropeAnchor == nil
        if let anchor = interaction.ropeAnchor {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: anchor.x, y: anchor.y))
            path.addLine(to: CGPoint(x: interaction.position.x, y: interaction.position.y + 61))
            path.addLine(to: CGPoint(x: interaction.position.x, y: max(usableFrame.minY, interaction.position.y - 30)))
            rope.path = path
        }
        explorer.render(delta: 0)
        let hitFrame = CGRect(x: explorer.position.x - 24, y: explorer.position.y - 1, width: 48, height: 76)
        if hitFrame != lastInputFrame || interaction.state.rawValue != lastInputState {
            onPlacementChanged?(hitFrame, interaction.state.rawValue)
            lastInputFrame = hitFrame
            lastInputState = interaction.state.rawValue
        }
        if !debug.isHidden { rebuildDebug() }
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
        debugLabel.text = "PROTOTYPE · \(expeditionPaused ? "PAUSED" : "RUNNING") · \(interaction?.state.rawValue.uppercased() ?? "IDLE") · \(status)"
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
