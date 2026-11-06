import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class ExplorerScene: SKScene {
    private let explorer = ExplorerRig()
    private let debug = SKNode()
    private let rope = SKShapeNode()
    private let shotRope = SKShapeNode()
    private let hook = SKShapeNode()
    private let props = ExpeditionProps()
    private let controlMarker = SKShapeNode()
    private let pointerExtension = SKShapeNode()
    private let aimGuide = SKShapeNode()
    private var grappleAiming = false
    private var aimPoint: CGPoint?
    private var aimDirection = CGPoint.zero
    private(set) var idleExplorationEnabled = true
    private var runWhenExploring = false
    private var fasterRopeWork = false
    private var startedOnWindow = false
    private var startedRopeDemo = false
    private var startedActivityDemo = false
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
    private var rawTerrain: TerrainSnapshot?
    private(set) var agentMode = false
    var agentReading = false
    var agentTarget: CGPoint?
    #if DEBUG
    var agentDiagnostic: String { "\(interaction?.position ?? .zero) \(interaction?.state.rawValue ?? "none") ceiling=\(interaction?.agentCeilingHanging ?? false)" }
    #endif
    var agentHandPoint: CGPoint? {
        guard let interaction else { return nil }
        if let target = agentTarget, agentAtTarget { return target }
        return .init(x: interaction.controlClickPoint.x, y: interaction.controlClickPoint.y)
    }
    var agentAtTarget: Bool {
        guard let interaction, let target = agentTarget else { return false }
        let localX = (target.x - interaction.position.x) * interaction.facing
        let localY = target.y - interaction.position.y + interaction.controlPointerDrop
        let shoulderY = explorer.shoulderHeight
        return localX >= -8 && localX <= 36 && hypot(localX - 10, localY - shoulderY) < 29
            && (interaction.ropeSession.map { hypot($0.body.velocity.x, $0.body.velocity.y) < 24 } ?? true)
    }
    func setAgentMode(_ enabled: Bool) {
        guard agentMode != enabled else { return }
        agentMode = enabled; agentTarget = nil; agentReading = false
        interaction?.setKeyboardControl(enabled)
        interaction?.setIdleExploration(false)
        if enabled { interaction?.updateBounds(.init(minimum: .init(x: 24, y: 0), maximum: .init(x: size.width - 24, y: size.height - 76))) }
        else { interaction?.updateBounds(.init(minimum: .init(x: usableFrame.minX + 24, y: usableFrame.minY + 2), maximum: .init(x: usableFrame.maxX - 24, y: usableFrame.maxY - 76))) }
        let snapshot = rawTerrain; terrain = nil; updateTerrain(snapshot)
    }
    private var previousUpdateTime: TimeInterval?
    private var lastTerrainReadTime: TimeInterval?
    var onFrame: (() -> Void)?
    var onPlacementChanged: ((CGRect, String) -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(rope); addChild(shotRope)
        shotRope.strokeColor = .init(calibratedRed: 0.72, green: 0.57, blue: 0.32, alpha: 1); shotRope.lineWidth = 1.2; shotRope.zPosition = 1
        rope.strokeColor = .init(calibratedRed: 0.72, green: 0.57, blue: 0.32, alpha: 1)
        rope.lineWidth = 1.2
        rope.zPosition = 1 // Over the jacket, beneath the foreground rope grips.
        addChild(explorer)
        let hookPath = CGMutablePath()
        hookPath.move(to: .init(x: -5, y: 0)); hookPath.addLine(to: .init(x: 4, y: 0))
        hookPath.move(to: .init(x: 0, y: 0)); hookPath.addQuadCurve(to: .init(x: 1, y: 5), control: .init(x: 7, y: 5))
        hookPath.move(to: .init(x: 0, y: 0)); hookPath.addQuadCurve(to: .init(x: 1, y: -5), control: .init(x: 7, y: -5))
        hook.path = hookPath; hook.strokeColor = NSColor(calibratedWhite: 0.13, alpha: 1); hook.lineWidth = 2.4; hook.isHidden = true
        let metal = SKShapeNode(path: hookPath)
        metal.strokeColor = NSColor(calibratedWhite: 0.78, alpha: 1); metal.lineWidth = 1.2
        hook.addChild(metal)
        addChild(hook)
        addChild(props)
        let crosshair = CGMutablePath()
        crosshair.addEllipse(in: .init(x: -5, y: -5, width: 10, height: 10))
        crosshair.move(to: .init(x: -9, y: 0)); crosshair.addLine(to: .init(x: 9, y: 0))
        crosshair.move(to: .init(x: 0, y: -9)); crosshair.addLine(to: .init(x: 0, y: 9))
        controlMarker.path = crosshair
        controlMarker.strokeColor = .systemPink; controlMarker.lineWidth = 1.5
        controlMarker.zPosition = 100; controlMarker.isHidden = true
        addChild(controlMarker)
        pointerExtension.strokeColor = .systemPink; pointerExtension.lineWidth = 1.2; pointerExtension.zPosition = 99; addChild(pointerExtension)
        aimGuide.lineWidth = 1; aimGuide.zPosition = 90; aimGuide.isHidden = true
        addChild(aimGuide)
        addChild(debug)
        debug.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    func layout(in usableFrame: CGRect) {
        self.usableFrame = usableFrame
        terrain = nil
        let safeOrigins = ExplorerInteraction.Bounds(
            minimum: .init(x: agentMode ? 24 : usableFrame.minX + 24, y: agentMode ? 0 : usableFrame.minY + 2),
            maximum: .init(x: agentMode ? size.width - 24 : usableFrame.maxX - 24, y: agentMode ? size.height - 76 : usableFrame.maxY - 76)
        )
        if interaction == nil {
            interaction = ExplorerInteraction(position: .init(x: usableFrame.midX, y: usableFrame.minY + 12), bounds: safeOrigins)
        } else {
            interaction?.updateBounds(safeOrigins)
        }
        interaction?.autonomous = true
        interaction?.runsMission = idleExplorationEnabled
        interaction?.setIdleExploration(idleExplorationEnabled)
        interaction?.setRunWhenExploring(runWhenExploring)
        interaction?.setFasterRopeWork(fasterRopeWork)
        applyPlacement()
    }

    func resetExpedition() {
        interaction = nil
        previousUpdateTime = nil
        let previousTerrain = terrain
        layout(in: usableFrame)
        if let previousTerrain { updateTerrain(previousTerrain) }
    }

    var keyboardClickPoint: CGPoint? {
        guard let interaction, interaction.keyboardControlEnabled else { return nil }
        let point = interaction.controlClickPoint
        return .init(x: point.x, y: point.y)
    }
    func setKeyboardControl(_ enabled: Bool) {
        interaction?.setKeyboardControl(enabled)
        if !enabled { setGrappleAiming(false) }
        applyPlacement()
    }
    func setIdleExploration(_ enabled: Bool) {
        idleExplorationEnabled = enabled; interaction?.setIdleExploration(enabled); applyPlacement()
    }
    func setGrappleAiming(_ enabled: Bool) {
        grappleAiming = enabled; aimGuide.isHidden = !enabled
        aimDirection = .zero
        if enabled, let interaction {
            let suggestion = interaction.suggestedGrappleAim()
            aimPoint = suggestion.map { .init(x: $0.x, y: $0.y) }
                ?? .init(x: interaction.position.x, y: min(usableFrame.maxY, interaction.position.y + 240))
        }
        applyPlacement()
    }
    func setAimDirection(_ x: Double, _ y: Double) { aimDirection = .init(x: x, y: y) }
    private func updateGrappleAim(by elapsed: Double = 0) {
        guard grappleAiming, let point = aimPoint else { return }
        let distance = max(1, hypot(aimDirection.x, aimDirection.y))
        let step = min(0.1, max(0, elapsed)) * 320 / distance
        aimPoint = .init(x: min(usableFrame.maxX - 24, max(usableFrame.minX + 24, point.x + aimDirection.x * step)),
                         y: min(usableFrame.maxY, max(usableFrame.minY, point.y + aimDirection.y * step)))
    }
    @discardableResult func fireAimedGrapple() -> Bool {
        updateGrappleAim()
        guard let aimPoint else { return false }
        let result = interaction?.fireGrapple(toward: .init(x: aimPoint.x, y: aimPoint.y)) ?? false
        applyPlacement(); return result
    }
    func setRunWhenExploring(_ enabled: Bool) { runWhenExploring = enabled; interaction?.setRunWhenExploring(enabled) }
    func setFasterRopeWork(_ enabled: Bool) { fasterRopeWork = enabled; interaction?.setFasterRopeWork(enabled) }
    func setControlPointerLowered(_ held: Bool) { interaction?.setControlPointerLowered(held) }
    func setControlCrouch(_ held: Bool) { interaction?.setControlCrouch(held) }
    func setControlFastPace(_ fast: Bool) { interaction?.setControlFastPace(fast) }
    func setControlDirection(_ x: Double, _ y: Double) { interaction?.setControlDirection(horizontal: x, vertical: y) }
    func controlJump() { interaction?.controlJump(); applyPlacement() }
    func controlGrapple() { interaction?.controlGrapple(); applyPlacement() }

    var attachedWindowID: UInt32? { interaction?.attachedWindowID }
    var activityStatus: String { interaction?.activityStatus ?? "Preparing terrain…" }
    var availableActivities: Set<ExplorerActivity> { interaction?.availableActivities ?? [] }
    func requestActivity(_ activity: ExplorerActivity) {
        interaction?.requestActivity(activity)
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

    func updateTerrain(_ snapshot: TerrainSnapshot?, geometrySampleElapsed: TimeInterval? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        let sampleElapsed = geometrySampleElapsed ?? (lastTerrainReadTime.map { max(1.0 / 120, now - $0) } ?? 0.1)
        lastTerrainReadTime = now
        let unavailable = snapshot == nil
        // If window-server metadata fails, retain only the guaranteed rescue boundaries.
        rawTerrain = snapshot
        var next = snapshot ?? TerrainSnapshot(windows: [], viewport: WorldRect(x: usableFrame.minX, y: usableFrame.minY + 2, width: usableFrame.width, height: max(0, usableFrame.height - 2)))
        if agentMode {
            // The physical display rim supplies a fallback line when no window is
            // above a menu/Dock control. It uses the same grappling/rope solver.
            let rim = DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: size.height - 1, width: size.width, height: 1))
            next = TerrainSnapshot(windows: [rim] + next.windows, viewport: .init(x: 0, y: 0, width: size.width, height: size.height), features: next.features)
        }
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
        interaction?.updateTerrain(next, sampleElapsed: sampleElapsed)
        #if DEBUG
        if !startedActivityDemo, let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--activity=") }),
           let activity = ExplorerActivity(rawValue: String(argument.dropFirst("--activity=".count))) {
            startedActivityDemo = interaction?.requestActivity(activity) == true
        }
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
            line.strokeColor = surface.id.edge.isInternal ? (surface.id.edge == .ledge ? .systemGreen : (surface.id.edge == .horizontalCrack ? .systemOrange : .systemPurple)) : surface.id.owner == .screen ? .systemTeal : (surface.id.edge == .top ? .systemGreen : .systemPink)
            line.lineWidth = 2
            terrainGuides.addChild(line)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        onFrame?()
        let rawElapsed = previousUpdateTime.map { max(currentTime - $0, 0) } ?? 0
        let elapsed = min(rawElapsed, 0.25)
        previousUpdateTime = currentTime
        guard !expeditionPaused else { return }
        if agentMode, let target = agentTarget { interaction?.steerAgent(towardHand: .init(x: target.x, y: target.y)) }
        updateGrappleAim(by: elapsed)
        let previousState = interaction?.state
        let previousLandingCount = interaction?.landingCount
        interaction?.advance(by: elapsed * playbackRate)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--freeze-grapple"), interaction?.state == .grappling, (interaction?.ropeSession?.age ?? 0) > 0.15 { setExpeditionPaused(true) }
        if ProcessInfo.processInfo.arguments.contains("--freeze-swing"), interaction?.state == .swinging, interaction?.ropeSession?.isTakingUp == false, (interaction?.ropeSession?.age ?? 0) > 0.5 { setExpeditionPaused(true) }
        if ProcessInfo.processInfo.arguments.contains("--freeze-rope"), let interaction,
           interaction.state == .abseiling, let anchor = interaction.ropeAnchor,
           interaction.position.y < anchor.y - 90 {
            setExpeditionPaused(true)
        }
        #endif
        if let interaction, interaction.landingCount != previousLandingCount {
            explorer.land(strength: min(1, max(0.4, interaction.lastLandingSpeed / JumpAnimation.launchSpeed)))
        } else if previousState == .recovering, interaction?.state == .settling { explorer.land() }
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
        controlMarker.isHidden = !interaction.keyboardControlEnabled
        if let point = keyboardClickPoint { controlMarker.position = point }
        explorer.position = CGPoint(x: interaction.position.x, y: interaction.position.y)
        var motion: ExplorerMotion
        switch interaction.state {
        case .transferringHold: motion = .climbing
        case .dropping: motion = .launching
        case .held: motion = .held
        case .recovering: motion = .parachuting
        case .preparingJump, .jumping: motion = .jumping
        case .walking: motion = .walking
        case .running: motion = .running
        case .climbing: motion = .climbing
        case .abseiling: motion = .abseiling
        case .grappling: motion = .grappling
        case .swinging: motion = .ropeSwinging
        case .ropeClimbing: motion = .ropeClimbing
        case .traversingEdge: motion = interaction.edgeMotion ?? .idle
        default: motion = .idle
        }
        let stage = interaction.mission.stage
        let stationary = interaction.state == .idle || interaction.state == .settling
        if stationary, let edge = interaction.attachment?.edge, edge == .left || edge == .right { motion = .climbing }
        if stationary, [.spotting, .investigating, .revealing, .updatingMap].contains(stage) { motion = .investigating }
        let target = interaction.mission.target.flatMap { anchor in terrain.flatMap { TerrainSupport.resolve(anchor, in: $0) } }
        var facing = interaction.facing
        if stationary, let target { facing = target.x >= interaction.position.x ? 1 : -1 }
        explorer.xScale = facing
        explorer.setShadowOcclusion(windows: terrain?.windows.map {
            .init(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
        } ?? [], from: self)
        explorer.tuning = interaction.walkingTuning
        explorer.synchronizedTime = interaction.edgeMotion.map { interaction.edgeProgress * EdgeTraversal.duration($0) }
            ?? (motion == .walking ? interaction.walkingTime : (motion == .climbing && !stationary ? interaction.climbingTime - floor(interaction.climbingTime / 2) * 2 : nil))
        if motion == .running { explorer.synchronizedTime = interaction.runningTime }
        explorer.usingBinoculars = agentReading
        explorer.crouchAmount = interaction.canCrouch ? interaction.crouchBlend : 0
        explorer.jumpPose = interaction.dropPose ?? interaction.keyboardJumpPose
        explorer.crackPose = interaction.internalClimbingPose
        explorer.handTargets = nil
        explorer.footTargets = nil
        explorer.ropePose = nil
        explorer.usesHarnessPivot = false
        let aimedTarget = grappleAiming ? aimPoint.map { interaction.aimedGrappleTarget(toward: .init(x: $0.x, y: $0.y)) } ?? nil : nil
        let gunTarget = interaction.grappleTarget ?? (grappleAiming ? (aimedTarget ?? aimPoint.map { WorldPoint(x: $0.x, y: $0.y) }) : nil)
        if grappleAiming, let aimPoint {
            let target = aimedTarget ?? .init(x: aimPoint.x, y: aimPoint.y)
            let path = CGMutablePath()
            path.move(to: .init(x: interaction.position.x, y: interaction.position.y + 46))
            path.addLine(to: .init(x: target.x, y: target.y))
            path.addEllipse(in: .init(x: target.x - 7, y: target.y - 7, width: 14, height: 14))
            aimGuide.path = path; aimGuide.strokeColor = aimedTarget == nil ? .systemOrange : .systemGreen
        }
        explorer.grappleAim = gunTarget.map { .init(x: ($0.x - interaction.position.x) * facing, y: $0.y - interaction.position.y) }
        if let session = interaction.ropeSession, let guide = interaction.ropeGuide, session.mode != .supported && session.mode != .firing {
            let path = guide.taut(toward: session.body.position)
            let dx = (path.sideTangent.x - session.body.position.x) * facing, dy = path.sideTangent.y - session.body.position.y
            let length = max(0.001, hypot(dx, dy))
            explorer.ropePose = RopeAnimation.pose(mode: session.mode, direction: .init(x: dx / length, y: dy / length), velocity: .init(x: session.body.velocity.x * facing, y: session.body.velocity.y), pullTime: session.pullTime)
            explorer.usesHarnessPivot = true
        }
        if motion == .climbing && !interaction.internalClimbing {
            let contacts = ClimbingContacts(heightAlongWall: interaction.heightAlongWall)
            explorer.handTargets = (contacts.leftHand, contacts.rightHand)
            explorer.footTargets = (contacts.leftFoot, contacts.rightFoot)
        }
        if stationary, stage == .spotting {
            explorer.handTargets = (.init(x: 6, y: 59), .init(x: 14, y: 59))
        } else if stationary, stage == .updatingMap {
            explorer.handTargets = (.init(x: -1, y: 43), .init(x: 16, y: 44))
        }
        let ropeGripHeight = interaction.ropeAnchor.map { min(61, max(0, $0.y - 16 - interaction.position.y)) } ?? 61
        if motion == .abseiling && interaction.ropeSession == nil {
            explorer.handTargets = (.init(x: 0, y: ropeGripHeight), .init(x: 8, y: ropeGripHeight + 1))
        }
        if interaction.agentCeilingHanging {
            var pose = CrackAnimation.pose(horizontal: true, time: interaction.climbingTime, offset: interaction.position.x * facing)
            pose.hips.y += 12; pose.leftHand.y += 18; pose.rightHand.y += 18
            explorer.crackPose = pose; explorer.ropePose = nil; explorer.handTargets = nil; explorer.footTargets = nil
        }
        if agentMode, let target = agentTarget, agentAtTarget {
            let hand = WorldPoint(x: (target.x - interaction.position.x) * facing, y: target.y - interaction.position.y + interaction.controlPointerDrop)
            explorer.handTargets = (.init(x: -8, y: interaction.agentCeilingHanging ? 76 : (interaction.ropeSession == nil ? 44 : 61)), hand)
        }
        if interaction.hasPendingGrapple { explorer.handTargets = (.init(x: -4, y: 61), .init(x: 20, y: 46)) }
        pointerExtension.isHidden = interaction.controlPointerDrop < 1
        if !pointerExtension.isHidden {
            let tip = agentMode && agentAtTarget ? agentTarget! : CGPoint(x: interaction.controlClickPoint.x, y: interaction.controlClickPoint.y)
            controlMarker.position = tip
            let extensionPath = CGMutablePath(); extensionPath.move(to: .init(x: tip.x, y: tip.y + interaction.controlPointerDrop)); extensionPath.addLine(to: tip)
            pointerExtension.path = extensionPath
        }
        props.update(mission: interaction.mission, explorer: interaction.position, target: target, facing: facing, viewport: usableFrame, held: interaction.state == .held)
        explorer.select(motion)
        explorer.render(delta: 0)
        rope.isHidden = interaction.ropeAnchor == nil && interaction.hookPosition == nil
        hook.isHidden = interaction.ropeSession == nil
        let path = CGMutablePath()
        let flyingPath = CGMutablePath()
        if let flying = interaction.hookPosition, let target = interaction.grappleTarget {
            let muzzle = explorer.grappleMuzzle(in: self)
            flyingPath.move(to: muzzle)
            flyingPath.addQuadCurve(to: .init(x: flying.x, y: flying.y), control: .init(x: (muzzle.x + flying.x) / 2, y: (muzzle.y + flying.y) / 2 - 8))
            hook.position = .init(x: flying.x, y: flying.y)
            hook.zRotation = atan2(target.y - flying.y, target.x - flying.x)
        }
        if let support = interaction.ropeGuide {
            let grip = interaction.ropeSession?.body.position ?? WorldPoint(x: interaction.position.x, y: interaction.position.y + ropeGripHeight)
            let guide = interaction.edgeMotion == .lowering ? support : support.taut(toward: grip)
            func cg(_ point: WorldPoint) -> CGPoint { .init(x: point.x, y: point.y) }
            path.addEllipse(in: .init(x: guide.anchor.x - 2, y: guide.anchor.y - 1, width: 4, height: 2))
            path.move(to: cg(guide.anchor)); path.addLine(to: cg(guide.topTangent))
            path.addCurve(to: cg(guide.sideTangent), control1: cg(guide.control1), control2: cg(guide.control2))
            if interaction.edgeMotion == .lowering {
                path.addLine(to: .init(x: guide.sideTangent.x, y: guide.sideTangent.y - 50))
            } else {
                let slack = max(0, (interaction.ropeSession?.body.length ?? guide.length(to: grip)) - guide.length(to: grip))
                if slack > 1 {
                    let dx = grip.x - guide.sideTangent.x, dy = grip.y - guide.sideTangent.y
                    // Preserve the corner's outgoing tangent even when the free line bows.
                    path.addCurve(to: cg(grip), control1: .init(x: guide.sideTangent.x + dx / 3, y: guide.sideTangent.y + dy / 3), control2: .init(x: guide.sideTangent.x + dx * 2 / 3, y: guide.sideTangent.y + dy * 2 / 3 - min(60, slack)))
                } else { path.addLine(to: cg(grip)) }
                path.addEllipse(in: .init(x: grip.x - 1.5, y: grip.y - 1.5, width: 3, height: 3))
                path.move(to: cg(grip)); path.addLine(to: .init(x: grip.x, y: max(agentMode ? 0 : usableFrame.minY, interaction.position.y - 16)))
            }
            if interaction.hookPosition == nil { hook.position = cg(guide.anchor); hook.zRotation = -.pi / 2 }
        }
        rope.path = path; shotRope.path = flyingPath; shotRope.isHidden = interaction.hookPosition == nil

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
