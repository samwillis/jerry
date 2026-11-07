import Foundation

/// Input state in scene coordinates. The supplied bounds constrain the character's origin.
public struct ExplorerInteraction {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
        public static let zero = Point(x: 0, y: 0)
    }

    public struct Bounds {
        public let minimum: Point
        public let maximum: Point
        public init(minimum: Point, maximum: Point) {
            self.minimum = minimum
            self.maximum = Point(x: max(minimum.x, maximum.x), y: max(minimum.y, maximum.y))
        }
    }

    public enum State: String { case idle, held, settling, recovering, preparingJump, jumping, walking, running, climbing, abseiling, traversingEdge, grappling, swinging, ropeClimbing, dropping, transferringHold }
    public private(set) var position: Point
    public private(set) var state: State = .idle
    public private(set) var attachment: TerrainAttachment?
    public private(set) var keyboardControlEnabled = false
    public private(set) var controlHorizontal = 0.0
    public private(set) var controlVertical = 0.0
    public private(set) var controlFastPace = false
    public private(set) var runWhenExploring = false
    public private(set) var fasterRopeWork = false
    public var ropeWorkRate: Double { fasterRopeWork || (keyboardControlEnabled && controlFastPace) ? 1.8 : 1 }
    public mutating func setRunWhenExploring(_ enabled: Bool) {
        runWhenExploring = enabled
        if !keyboardControlEnabled, route.first?.kind == .walking { startTravel() }
    }
    public mutating func setFasterRopeWork(_ enabled: Bool) { fasterRopeWork = enabled }
    public private(set) var runningTime = 0.0
    private var crouchHeld = false
    private var pointerLowered = false
    public var controlPointerDrop: Double { pointerLowered && canCrouch ? crouchBlend * 16 : 0 }
    public mutating func setControlPointerLowered(_ held: Bool) { pointerLowered = keyboardControlEnabled && held }
    private var agentSteering = false
    public private(set) var agentCeilingHanging = false
    public private(set) var crouchAmount = 0.0
    public var crouchBlend: Double { crouchAmount * crouchAmount * (3 - 2 * crouchAmount) }
    public var canCrouch: Bool {
        keyboardControlEnabled && attachment?.edge.isStandable == true && ropeSession == nil
            && [.idle, .settling, .walking, .running].contains(state)
    }
    public var isCrouching: Bool { canCrouch && (crouchHeld || crouchAmount > 0) }
    public mutating func setControlCrouch(_ held: Bool) { crouchHeld = keyboardControlEnabled && held }
    private mutating func advanceCrouch(by dt: Double) {
        guard canCrouch else { crouchAmount = 0; return }
        let target = crouchHeld ? 1.0 : 0
        crouchAmount += min(dt / 0.16, max(-dt / 0.16, target - crouchAmount))
    }
    public var controlClickPoint: Point { .init(x: position.x + facing * 32, y: position.y + 44 - (canCrouch ? crouchBlend * 28 : 0) - controlPointerDrop) }
    public var manualTravelSpeed: Double { isCrouching ? 80 - 40 * crouchBlend : (controlFastPace ? RunningGait.speed : 80) }
    public mutating func setControlFastPace(_ fast: Bool) { controlFastPace = keyboardControlEnabled && fast }
    private var controlVelocity = Point.zero
    public private(set) var jumpPreparationElapsed = 0.0
    public private(set) var jumpAirElapsed = 0.0
    public private(set) var landingCount = 0
    public private(set) var lastLandingSpeed = 0.0
    public var keyboardJumpPose: ExplorerPose? {
        if state == .preparingJump { return JumpAnimation.preparation(at: jumpPreparationElapsed) }
        guard state == .jumping else { return nil }
        let landingY = terrain?.surfaces.filter {
            $0.id.edge.isStandable && $0.start.y <= position.y
                && position.x - 24 >= $0.start.x && position.x + 24 <= $0.end.x
        }.map { $0.start.y }.max() ?? bounds.minimum.y
        return JumpAnimation.airborne(elapsed: jumpAirElapsed, verticalSpeed: controlVelocity.y, landingDistance: max(0, position.y - landingY))
    }
    private var holdTransferElapsed = 0.0
    private var holdTransferStart = Point.zero
    private mutating func advanceHoldTransfer(by dt: Double) {
        guard let terrain, let attachment, let target = TerrainSupport.resolve(attachment, in: terrain) else { recover(); return }
        holdTransferElapsed += dt
        let t = min(1, holdTransferElapsed / 0.22)
        let blend = t * t * (3 - 2 * t)
        position = .init(x: holdTransferStart.x + (target.x - holdTransferStart.x) * blend, y: holdTransferStart.y + (target.y - holdTransferStart.y) * blend)
        if t >= 1 { state = .idle }
    }
    private var dropElapsed = 0.0
    private var dropStart = Point.zero
    private var dropEnd = Point.zero
    private var downConsumed = false
    public var dropPose: ExplorerPose? { state == .dropping ? EdgeTraversal.pose(.launching, progress: dropElapsed / EdgeTraversal.duration(.launching)) : nil }
    public var attachedWindowID: UInt32? {
        if let session = ropeSession { return session.anchor.windowID }
        if case .window(let id) = attachment?.owner { return id }
        return nil
    }
    public var internalClimbing: Bool { attachment?.edge.isInternal == true && attachment?.edge.isStandable == false }
    public var internalClimbingPose: ExplorerPose? {
        guard internalClimbing else { return nil }
        return CrackAnimation.pose(horizontal: attachment?.edge == .horizontalCrack, time: climbingTime, offset: (attachment?.offset ?? 0) * (attachment?.edge == .horizontalCrack ? facing : 1))
    }
    private var dropThroughRemaining = 0.0
    public private(set) var idleExplorationEnabled = true
    public var autonomous = false
    public var runsMission = false
    public private(set) var mission = SockMission()
    public private(set) var requestedActivity: ExplorerActivity?
    public private(set) var pendingActivity: ExplorerActivity?
    public private(set) var activityIssue: String?
    public private(set) var ropeSession: RopeSession?
    private var pendingGrapple: RopeSession?
    private var pendingContinuation: [TravelStep] = []
    public var hasPendingGrapple: Bool { pendingGrapple != nil }
    private var ropeContinuation: [TravelStep] = []
    private var physicalRelease = false
    public var activityStatus: String {
        if keyboardControlEnabled { return "Keyboard control: \(state.rawValue)" }
        if let pendingActivity { return "Queued: \(pendingActivity.title)" }
        if let activityIssue { return activityIssue }
        if let ropeSession {
            if ropeSession.mode == .supported { return "Rope attached · standing" }
            return "\(requestedActivity?.title ?? "Rope"): \(ropeSession.mode.rawValue)"
        }
        guard let requestedActivity else { return "Automatic adventures" }
        return "\(requestedActivity.title): \(hasPendingTravel ? state.rawValue : "finished")"
    }
    public var availableActivities: Set<ExplorerActivity> {
        var result: Set<ExplorerActivity> = [.automatic, .sockSearch]
        if ropeSession != nil {
            result.formUnion([.abseil, .ropeClimb, .swing, .releaseRope])
            if ropeSession?.mode != .supported { return result }
        }
        if state == .recovering || state == .traversingEdge { return Set(ExplorerActivity.allCases.filter { $0 != .releaseRope }) }
        guard let source = currentSupport, let graph else { return result }
        for activity in ExplorerActivity.allCases where activity.travelKind != nil {
            if graph.activityRoute(activity, from: source) != nil { result.insert(activity) }
        }
        return result
    }
    private var currentSupport: TerrainAttachment? {
        if let step = route.first, step.from.owner == step.to.owner, step.from.edge == step.to.edge && step.from.featureID == step.to.featureID {
            return .init(owner: step.from.owner, edge: step.from.edge, offset: step.from.offset + (step.to.offset - step.from.offset) * travelFraction, featureID: step.from.featureID)
        }
        return attachment
    }

    @discardableResult public mutating func requestActivity(_ activity: ExplorerActivity) -> Bool {
        mission.cancel()
        activityIssue = nil
        if ropeSession != nil && [.abseil, .ropeClimb, .swing, .releaseRope].contains(activity) {
            requestedActivity = activity; pendingActivity = nil; runsMission = false
            ropeContinuation.removeAll(); route.removeAll(); afterLanding.removeAll()
            if activity == .releaseRope {
                pendingGrapple = nil; pendingContinuation = []
                let velocity = ropeSession?.releaseVelocity ?? .zero
                let grounded = ropeSession?.mode == .supported || ropeSession?.mode == .firing
                ropeSession = nil
                if grounded { state = .settling; settlingRemaining = 0.3 }
                else { releaseRope(velocity: velocity) }
            } else {
                let mode: RopeSession.Mode = activity == .abseil ? .descending : (activity == .ropeClimb ? .climbing : .swinging)
                ropeSession?.climbsAfterSwing = false
                if ropeSession?.mode == .firing { ropeSession?.modeAfterLatch = mode }
                else {
                    ropeSession?.switchMode(mode)
                    if mode == .swinging, let terrain, let guide = ropeSession?.anchor.resolve(in: terrain) { ropeSession?.pushOff(guide: guide) }
                }
                attachment = nil
                applyRopeState()
            }
            return true
        }
        if ropeSession != nil && ropeSession?.mode != .supported {
            pendingActivity = activity; requestedActivity = activity; runsMission = false
            ropeContinuation.removeAll(); afterLanding.removeAll()
            ropeSession?.climbsAfterSwing = true
            if ropeSession?.mode == .swinging { ropeSession?.switchMode(.climbing) }
            return true
        }
        if activity == .releaseRope { activityIssue = "No rope attached"; return false }
        if state == .recovering || state == .traversingEdge || state == .held {
            pendingActivity = activity
            requestedActivity = activity
            runsMission = false
            flightContinuation.removeAll()
            afterLanding.removeAll()
            return true
        }
        if activity == .automatic || activity == .sockSearch {
            if activity == .automatic { idleExplorationEnabled = true }
            if let source = currentSupport { attachment = source }
            route.removeAll(); afterLanding.removeAll(); ropeSession = nil
            requestedActivity = nil; pendingActivity = nil
            runsMission = true
            state = .settling; settlingRemaining = 0.3
            return true
        }
        guard let source = currentSupport, let graph, let plan = graph.activityRoute(activity, from: source) else {
            activityIssue = "\(activity.title): no reachable route"
            pendingActivity = nil
            return false
        }
        attachment = source
        requestedActivity = activity; pendingActivity = nil; runsMission = false
        return follow(plan)
    }
    public private(set) var facing: Double = 1
    public private(set) var simulationSteps = 0
    public var recoveryElapsed: Double { recoveryTime }
    public private(set) var walkingTime: Double = 0
    public private(set) var climbingTime: Double = 0
    public var walkingTuning = AnimationTuning()
    public var edgeProgress: Double { state == .dropping ? dropElapsed / EdgeTraversal.duration(.launching) : travelFraction }
    public var edgeMotion: ExplorerMotion? {
        guard state == .traversingEdge, let step = route.first else { return nil }
        switch step.kind { case .mantling: return .mantling; case .lowering: return .lowering; case .parachuting: return .launching; default: return nil }
    }
    public var heightAlongWall: Double {
        guard let terrain, let owner = route.first?.from.owner ?? attachment?.owner,
              let window = terrain.windows.first(where: { .window($0.id) == owner }) else { return position.y }
        return position.y - window.frame.minY
    }
    public var activeTravel: TravelStep? { route.first }
    public var hasPendingTravel: Bool { !route.isEmpty || !afterLanding.isEmpty || flightGoal != nil || (ropeSession.map { $0.mode != .supported } ?? false) }
    public var ropeGuide: AbseilRope? {
        if let ropeSession, let terrain, ropeSession.mode != .firing { return ropeSession.anchor.resolve(in: terrain) }
        guard state == .abseiling || edgeMotion == .lowering,
              let step = route.first, let terrain,
              let window = terrain.windows.first(where: { .window($0.id) == step.from.owner }) else { return nil }
        return AbseilRope(window: window.frame, edge: step.kind == .lowering ? step.to.edge : step.from.edge)
    }
    public var ropeAnchor: Point? { ropeGuide?.anchor }
    public var grappleTarget: Point? {
        guard let shot = pendingGrapple ?? ropeSession, shot.mode == .firing, let terrain else { return nil }
        return shot.anchor.resolve(in: terrain)?.anchor
    }
    public var hookPosition: Point? {
        guard let shot = pendingGrapple ?? ropeSession, shot.mode == .firing, let terrain, let guide = shot.anchor.resolve(in: terrain) else { return nil }
        return shot.hookPosition(guide: guide)
    }

    private var graph: NavigationGraph?
    private var route: [TravelStep] = []
    private var travelFraction: Double = 0
    private var flightGoal: TerrainAttachment?
    private var flightContinuation: [TravelStep] = []
    private var afterLanding: [TravelStep] = []
    private var idleRemaining: Double = 1.5
    private var seed: UInt64 = 0x50C7
    private var accumulator: Double = 0
    private var bounds: Bounds
    private var grabOffset = Point.zero
    private var settlingRemaining: Double = 0
    private var terrain: TerrainSnapshot?
    private var recoveryTime: Double = 0
    private var lastDragTime: Double?
    private var dragVelocity = Point.zero
    private var flightVelocity = Point.zero

    public init(position: Point, bounds: Bounds) {
        self.position = position
        self.bounds = bounds
        clampPosition()
    }

    public mutating func beginDrag(at pointer: Point, time: Double? = nil) {
        mission.cancel()
        pendingActivity = nil
        ropeSession = nil; pendingGrapple = nil; pendingContinuation = []; ropeContinuation.removeAll(); physicalRelease = false
        if requestedActivity != nil { activityIssue = "Activity interrupted by dragging" }
        route.removeAll()
        afterLanding.removeAll()
        flightContinuation.removeAll()
        flightGoal = nil
        travelFraction = 0
        idleRemaining = 2
        grabOffset = Point(x: pointer.x - position.x, y: pointer.y - position.y)
        settlingRemaining = 0
        attachment = nil
        lastDragTime = time
        dragVelocity = .zero
        flightVelocity = .zero
        state = .held
    }

    public mutating func drag(to pointer: Point, time: Double? = nil) {
        guard state == .held else { return }
        let previous = position
        position = Point(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        clampPosition()
        if let time, time.isFinite {
            if let last = lastDragTime, time > last {
                let dt = time - last
                if dt > 0.15 {
                    dragVelocity = .zero
                } else {
                    let weight = 1 - exp(-dt / 0.035)
                    dragVelocity.x += ((position.x - previous.x) / dt - dragVelocity.x) * weight
                    dragVelocity.y += ((position.y - previous.y) / dt - dragVelocity.y) * weight
                    let speed = hypot(dragVelocity.x, dragVelocity.y)
                    if speed > 900 { dragVelocity.x *= 900 / speed; dragVelocity.y *= 900 / speed }
                }
            }
            lastDragTime = time
        }
    }

    public mutating func endDrag(on terrain: TerrainSnapshot? = nil) {
        guard state == .held else { return }
        if hypot(dragVelocity.x, dragVelocity.y) > 60 {
            if let terrain { self.terrain = terrain }
            recoveryTime = 0
            flightVelocity = dragVelocity
            state = .recovering
            return
        }
        state = .settling
        settlingRemaining = 0.8
        if let terrain { updateTerrain(terrain) }
    }

    /// Called only while the expedition is running. Pausing preserves the settling interval.
    public mutating func advance(by elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        guard autonomous else { advancePhysics(by: elapsed); return }
        // Discard excess stalled time rather than teleporting through seconds of movement.
        accumulator = min(accumulator + elapsed, 0.25)
        let dt = 1.0 / 120
        while accumulator + 0.0000001 >= dt {
            accumulator -= dt
            simulationSteps += 1
            advancePendingGrapple(by: dt)
            if state == .dropping { advanceDrop(by: dt); continue }
            if state == .transferringHold { advanceHoldTransfer(by: dt); continue }
            if keyboardControlEnabled {
                advanceCrouch(by: dt)
                advanceKeyboardControl(by: dt)
                continue
            }
            if ropeSession != nil && ropeSession?.mode != .supported {
                advanceRope(by: dt)
            } else if state == .walking || state == .running || state == .climbing || state == .abseiling || state == .traversingEdge {
                advanceTravel(by: dt)
            } else {
                advancePhysics(by: dt)
                if state == .idle && !runsMission {
                    if let pendingActivity { _ = requestActivity(pendingActivity) }
                    else if requestedActivity != nil && idleExplorationEnabled {
                        idleRemaining -= dt
                        if idleRemaining <= 0 { requestedActivity = nil; runsMission = true }
                    } else if requestedActivity == nil && idleExplorationEnabled { advanceAutonomy(by: dt) }
                }
            }
            if runsMission, let terrain {
                var nextMission = mission
                nextMission.advance(by: dt, explorer: &self, terrain: terrain)
                let completedSearch = nextMission.completedExpeditions > mission.completedExpeditions
                mission = nextMission
                if completedSearch && !idleExplorationEnabled { runsMission = false }
            }
        }
    }

    public mutating func follow(_ steps: [TravelStep]) -> Bool {
        guard state != .held, state != .recovering, let graph,
              !steps.isEmpty, steps.allSatisfy({ graph.isValid($0) }),
              let terrain, let start = TerrainSupport.resolve(steps[0].from, in: terrain),
              hypot(start.x - position.x, start.y - position.y) < 2 else { return false }
        for pair in zip(steps, steps.dropFirst()) where pair.0.to != pair.1.from { return false }
        afterLanding.removeAll()
        flightContinuation.removeAll()
        route = steps
        travelFraction = 0
        startTravel()
        return true
    }

    private mutating func advancePhysics(by elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        if state == .recovering {
            var remaining = min(elapsed, 10)
            while remaining > 0.000001, state == .recovering {
                let dt = min(remaining, 1.0 / 120)
                remaining -= dt
                let distance = physicalRelease ? 0 : RecoveryAnimation.distance(from: recoveryTime, to: recoveryTime + dt)
                if physicalRelease {
                    flightVelocity.y -= RopeDynamics.gravity * dt
                    let opening = RecoveryAnimation.deployment(at: recoveryTime)
                    flightVelocity.y += (-RecoveryAnimation.openChuteSpeed - flightVelocity.y) * (1 - exp(-opening * 6 * dt))
                }
                let drag = 1.2 + 5 * RecoveryAnimation.deployment(at: recoveryTime + dt / 2)
                let decay = exp(-drag * dt)
                if let flightGoal, let terrain, let target = TerrainSupport.resolve(flightGoal, in: terrain) {
                    let remainingDrop = max(1, position.y - target.y)
                    let remainingTime = RecoveryAnimation.duration(for: remainingDrop, startingAt: recoveryTime)
                    flightVelocity.x = max(-65, min(65, (target.x - position.x) / max(dt, remainingTime)))
                }
                var next = Point(x: position.x + flightVelocity.x * (1 - decay) / drag, y: position.y - distance + flightVelocity.y * (1 - decay) / drag)
                flightVelocity.x *= decay
                if !physicalRelease { flightVelocity.y *= decay }
                recoveryTime += dt
                if next.x < bounds.minimum.x || next.x > bounds.maximum.x { flightVelocity.x = 0 }
                if next.y > bounds.maximum.y { flightVelocity.y = min(0, flightVelocity.y) }
                next.x = min(max(next.x, bounds.minimum.x), bounds.maximum.x)
                next.y = min(max(next.y, bounds.minimum.y), bounds.maximum.y)
                if (!keyboardControlEnabled || dropThroughRemaining <= 0),
                   let terrain, let (anchor, landed) = TerrainSupport.landing(from: position, to: next, in: terrain) {
                    attachment = anchor
                    position = landed
                    settle()
                } else {
                    position = next
                    if position.y <= bounds.minimum.y { settle() }
                }
            }
            return
        }
        guard state == .settling else { return }
        settlingRemaining -= elapsed
        if settlingRemaining <= 0 {
            state = .idle
            if !afterLanding.isEmpty {
                route = afterLanding
                afterLanding.removeAll()
                travelFraction = 0
                startTravel()
            }
        }
    }

    public mutating func updateBounds(_ bounds: Bounds) {
        agentCeilingHanging = false
        self.bounds = bounds
        ropeSession = nil; pendingGrapple = nil; pendingContinuation = []; ropeContinuation.removeAll(); physicalRelease = false
        mission.cancel()
        route.removeAll()
        afterLanding.removeAll()
        flightContinuation.removeAll()
        flightGoal = nil
        graph = nil
        accumulator = 0
        terrain = nil
        attachment = nil
        dragVelocity = .zero
        flightVelocity = .zero
        // A changed display invalidates the pointer's coordinate space and any active drag.
        if state == .held { endDrag() }
        else { state = .settling; settlingRemaining = 0.8 }
        clampPosition()
    }

    public mutating func updateTerrain(_ terrain: TerrainSnapshot, sampleElapsed: Double = 0.1) {
        self.terrain = terrain
        if let pendingGrapple, pendingGrapple.anchor.resolve(in: terrain) == nil { self.pendingGrapple = nil; pendingContinuation = [] }
        if autonomous { graph = NavigationGraph(terrain: terrain) }
        guard state != .held && state != .dropping && state != .transferringHold else { return }
        if var session = ropeSession {
            if let guide = session.anchor.resolve(in: terrain) {
                session.followSupport(guide, sampleElapsed: sampleElapsed)
                if session.mode == .firing, let attachment {
                    if let support = TerrainSupport.resolve(attachment, in: terrain) {
                        session.contact(feet: support, horizontal: true, vertical: true)
                    } else {
                        // Capture may switch to the target window as soon as the
                        // shot starts. Losing its departure hold must not cancel
                        // an otherwise valid flying hook: continue in free flight.
                        self.attachment = nil
                        session.freeFlightWhileFiring = true
                    }
                }
                if session.mode != .supported {
                    position = session.feet
                    let unbounded = position
                    clampPosition()
                    if position != unbounded { releaseRope(velocity: session.releaseVelocity); return }
                }
                ropeSession = session
                if session.mode != .supported { return }
            } else if session.mode == .supported {
                ropeSession = nil
                // Still validate the landing attachment in this same snapshot.
            } else { releaseRope(velocity: session.releaseVelocity); return }
        }
        if let step = route.first {
            if graph?.isValid(step) == true,
               let from = TerrainSupport.resolve(step.from, in: terrain),
               let to = TerrainSupport.resolve(step.to, in: terrain) {
                position = travelPosition(step, from: from, to: to)
                return
            }
            recover()
            return
        }
        if let flightGoal, TerrainSupport.resolve(flightGoal, in: terrain) == nil { self.flightGoal = nil }
        if let attachment {
            if let supported = TerrainSupport.resolve(attachment, in: terrain) {
                position = supported
                clampPosition()
                if var session = ropeSession, session.mode == .supported {
                    session.contact(feet: position, horizontal: true, vertical: true)
                    if let guide = session.anchor.resolve(in: terrain), guide.length(to: session.body.position) > session.body.length + 1 {
                        session.switchMode(.swinging); session.climbsAfterSwing = false
                        self.attachment = nil; state = .swinging
                    }
                    ropeSession = session
                }
                return
            }
            self.attachment = nil
            if ropeSession?.mode == .supported {
                ropeSession?.switchMode(.swinging); ropeSession?.climbsAfterSwing = false
                state = .swinging
            } else {
                recoveryTime = 0; flightVelocity = .zero; state = .recovering
            }
            return
        }
        guard state != .recovering && state != .jumping else { return }
        if let (anchor, supported) = TerrainSupport.attach(at: position, in: terrain) {
            attachment = anchor
            position = supported
            clampPosition()
        } else {
            recoveryTime = 0
            flightVelocity = .zero
            state = .recovering
        }
    }

    private mutating func recover() {
        ropeSession = nil; pendingGrapple = nil; pendingContinuation = []; ropeContinuation.removeAll(); physicalRelease = false
        route.removeAll()
        afterLanding.removeAll()
        flightContinuation.removeAll()
        travelFraction = 0
        attachment = nil
        flightGoal = nil
        flightVelocity = .zero
        recoveryTime = 0
        state = .recovering
    }

    private mutating func advanceAutonomy(by dt: Double) {
        idleRemaining -= dt
        guard idleRemaining <= 0, let graph, let attachment else { return }
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        route = graph.route(from: attachment, seed: seed, allowParachute: ((seed >> 32) & 1) == 1)
        idleRemaining = 2
        travelFraction = 0
        startTravel()
    }

    private mutating func startTravel() {
        guard let step = route.first else { state = .idle; return }
        guard let terrain, graph?.isValid(step) == true,
              let from = TerrainSupport.resolve(step.from, in: terrain),
              let to = TerrainSupport.resolve(step.to, in: terrain) else { recover(); return }
        switch step.kind {
        case .walking:
            if hypot(to.x - from.x, to.y - from.y) > 1 { ropeSession = nil }
            let direction: Double = to.x >= from.x ? 1 : -1
            if state != .walking || facing != direction { walkingTime = 0 }
            let runs = runWhenExploring && !keyboardControlEnabled && requestedActivity == nil && hypot(to.x - from.x, to.y - from.y) >= 90
            if runs && state != .running { runningTime = 0 }
            state = runs ? .running : .walking; facing = direction
        case .shimmying, .transferring:
            state = .climbing
            if step.from.edge.isInternal { attachment = step.from }
        case .climbing:
            if state != .climbing { climbingTime = ClimbingGait.time(atHeight: heightAlongWall) }
            state = .climbing; facing = step.from.edge.isInternal || step.from.edge == .left ? 1 : -1
        case .abseiling:
            beginRope(step, mode: .descending)
        case .grappling:
            beginRope(step, mode: .firing)
        case .mantling:
            state = .traversingEdge; facing = step.from.edge == .left ? 1 : -1
        case .lowering:
            state = .traversingEdge; facing = step.to.edge == .left ? 1 : -1
        case .parachuting:
            state = .traversingEdge
            facing = (graph?.launchPoint(from: step.from)?.x ?? from.x) >= from.x ? 1 : -1
        }
    }

    private mutating func advanceTravel(by dt: Double) {
        guard let step = route.first, let terrain,
              let from = TerrainSupport.resolve(step.from, in: terrain),
              let to = TerrainSupport.resolve(step.to, in: terrain) else { recover(); return }
        let distance = hypot(to.x - from.x, to.y - from.y)
        if step.kind == .transferring {
            travelFraction = min(1, travelFraction + dt / 0.35)
        } else if step.kind == .shimmying {
            climbingTime += dt * ropeWorkRate
            travelFraction = min(1, travelFraction + 30 * dt * ropeWorkRate / max(0.01, distance))
        } else if let motion = edgeMotion {
            travelFraction = min(1, travelFraction + dt / EdgeTraversal.duration(motion))
        } else if step.kind == .walking {
            let travelled: Double
            if state == .running {
                travelled = RunningGait.distance(from: runningTime, to: runningTime + dt)
                runningTime += dt
            } else {
                travelled = WalkingGait.distance(from: walkingTime, to: walkingTime + dt, tuning: walkingTuning)
                walkingTime += dt
            }
            travelFraction = min(1, travelFraction + travelled / max(0.01, distance))
        } else if step.kind == .climbing {
            let workStep = dt * ropeWorkRate
            let lifted = ClimbingGait.distance(from: climbingTime, to: climbingTime + workStep)
            climbingTime += workStep
            travelFraction = min(1, travelFraction + lifted / max(0.01, distance))
        } else {
            travelFraction = min(1, travelFraction + 48 * dt / max(0.01, distance))
        }
        position = travelPosition(step, from: from, to: to)
        if step.from.edge.isInternal && step.from.featureID == step.to.featureID {
            attachment = .init(owner: step.from.owner, edge: step.from.edge, offset: step.from.offset + (step.to.offset - step.from.offset) * travelFraction, featureID: step.from.featureID)
        }
        clampPosition()
        if travelFraction >= 1 {
            if step.kind == .parachuting {
                flightGoal = step.to
                flightContinuation = Array(route.dropFirst())
                route.removeAll()
                attachment = nil
                recoveryTime = 0
                flightVelocity = .zero
                state = .recovering
            } else {
                attachment = step.to
                route.removeFirst()
                if pendingActivity != nil { route.removeAll() }
                travelFraction = 0
                if route.isEmpty { settle() } else { startTravel() }
            }
        }
    }

    private func travelPosition(_ step: TravelStep, from: Point, to: Point) -> Point {
        if let motion = edgeMotion {
            let end = motion == .launching ? (graph?.launchPoint(from: step.from) ?? from) : to
            return EdgeTraversal.position(motion, progress: travelFraction, from: from, to: end)
        }
        return .init(x: from.x + (to.x - from.x) * travelFraction, y: from.y + (to.y - from.y) * travelFraction)
    }

    private mutating func beginRope(_ step: TravelStep, mode: RopeSession.Mode) {
        guard let terrain,
              case .window(let id) = (mode == .firing ? step.to.owner : step.from.owner) else { recover(); return }
        let edge = mode == .firing ? step.to.edge : step.from.edge
        let anchor = RopeAnchor(windowID: id, edge: edge, offset: edge == .front ? step.to.offset : nil)
        guard let guide = anchor.resolve(in: terrain) else { recover(); return }
        var session = RopeSession(anchor: anchor, guide: guide, feet: position, mode: mode)
        session.climbsAfterSwing = requestedActivity != .swing
        if requestedActivity == .ropeClimb { session.modeAfterLatch = .climbing }
        ropeContinuation = Array(route.dropFirst())
        route.removeAll(); travelFraction = 0
        if mode != .firing { attachment = nil }
        ropeSession = session
        facing = edge == .left ? 1 : -1
        applyRopeState()
    }

    private mutating func applyRopeState() {
        guard let session = ropeSession else { return }
        switch session.mode {
        case .firing: state = .grappling
        case .swinging: state = .swinging
        case .climbing: state = .ropeClimbing
        case .descending: state = .abseiling
        case .supported: break
        }
    }

    private mutating func releaseRope(velocity: Point) {
        ropeSession = nil; ropeContinuation.removeAll(); route.removeAll(); afterLanding.removeAll()
        attachment = nil; flightGoal = nil
        flightVelocity = velocity; physicalRelease = true; recoveryTime = 0
        state = .recovering
    }

    private mutating func advanceRope(by dt: Double) {
        guard var session = ropeSession, let terrain,
              let guide = session.anchor.resolve(in: terrain),
              let window = terrain.windows.first(where: { $0.id == session.anchor.windowID }) else {
            releaseRope(velocity: ropeSession?.releaseVelocity ?? .zero)
            return
        }
        let edge = session.anchor.edge
        let lip = TerrainAttachment(owner: .window(window.id), edge: edge, offset: edge == .front ? (session.anchor.offset ?? window.frame.width / 2) : window.frame.height - EdgeTraversal.lipHeight)
        guard let lipPoint = TerrainSupport.resolve(lip, in: terrain) else { releaseRope(velocity: session.releaseVelocity); return }
        let lipHarness = Point(x: lipPoint.x, y: lipPoint.y + RopeSession.harnessHeight)
        let minimum = guide.length(to: lipHarness)
        let previous = position
        let wasFiring = session.mode == .firing
        session.advance(by: dt, guide: guide, minimumLength: minimum, workRate: ropeWorkRate)
        var next = session.feet
        if wasFiring && session.mode != .firing { attachment = nil }
        if !wasFiring || session.freeFlightWhileFiring {
            // Feet brace against the host wall. A swing may pass below its bottom,
            // but cannot tunnel through the window while the body overlaps its side.
            var sideContact = false
            if next.y < window.frame.maxY && next.y + 74 > window.frame.minY {
                if edge == .left && next.x > window.frame.minX - 24 { next.x = window.frame.minX - 24; sideContact = true }
                if edge == .right && next.x < window.frame.maxX + 24 { next.x = window.frame.maxX + 24; sideContact = true }
            }
            // Hands brace below the front rim until the pull-over animation takes
            // over. This also stops a fast reeled-in swing orbiting above the pin.
            let rimContact = edge == .front && session.mode == .climbing && next.y > lipPoint.y
            if rimContact {
                next.y = lipPoint.y
                let horizontalReach = sqrt(max(0, session.body.length * session.body.length - minimum * minimum))
                next.x = min(max(next.x, lipPoint.x - horizontalReach), lipPoint.x + horizontalReach)
                sideContact = true
            }
            let bounded = Point(x: min(max(next.x, bounds.minimum.x), bounds.maximum.x), y: min(max(next.y, bounds.minimum.y), bounds.maximum.y))
            session.contact(feet: bounded, horizontal: sideContact || bounded.x != next.x, vertical: rimContact || bounded.y != next.y)
            next = bounded
            if let (landed, point) = TerrainSupport.landing(from: previous, to: next, in: terrain), previous.y >= point.y {
                session.contact(feet: point, vertical: true)
                next = point
                if session.mode == .descending || (session.mode == .swinging && !session.isTakingUp) {
                    session.contact(feet: point, horizontal: true, vertical: true)
                    session.switchMode(.supported)
                    ropeSession = session; position = point; attachment = landed
                    let continuation = ropeContinuation
                    ropeContinuation.removeAll()
                    if let first = continuation.first, let start = TerrainSupport.resolve(first.from, in: terrain), hypot(start.x - point.x, start.y - point.y) < 12 {
                        route = continuation
                        travelFraction = 0
                        startTravel()
                    } else { settle() }
                    return
                }
            }
        }
        position = next
        ropeSession = session
        applyRopeState()
        if !keyboardControlEnabled, (session.mode == .descending || session.mode == .climbing), transferToWindowHold() { return }
        if session.mode == .descending && session.body.length >= RopeDynamics.maximumLength - 0.01 {
            releaseRope(velocity: session.releaseVelocity)
            activityIssue = "Rope end reached — parachuting"
            return
        }
        if session.mode == .climbing && session.body.length <= minimum + 0.5,
           hypot(next.x - lipPoint.x, next.y - lipPoint.y) < 7 {
            session.contact(feet: lipPoint, horizontal: true, vertical: true)
            position = lipPoint; attachment = lip
            ropeSession = nil
            let continuation = ropeContinuation
            ropeContinuation.removeAll()
            if let first = continuation.first, first.from == lip {
                route = continuation
            } else if let mantle = graph?.frontMantle(from: lip) ?? graph?.steps.first(where: { $0.kind == .mantling && $0.from == lip }) {
                route = [mantle]
            } else {
                // The pin can be usable even when there is no standing room
                // above this window. Stay on the rope beneath the rim.
                session.switchMode(.swinging); session.climbsAfterSwing = false
                ropeSession = session; attachment = nil; state = .swinging
                return
            }
            travelFraction = 0
            startTravel()
        }
    }

    private mutating func clampPosition() {
        position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
        position.y = min(max(position.y, bounds.minimum.y), bounds.maximum.y)
    }

    private mutating func settle() {
        physicalRelease = false
        var continuation: [TravelStep] = []
        if let goal = flightGoal, let terrain, let point = TerrainSupport.resolve(goal, in: terrain),
           attachment?.owner == goal.owner, attachment?.edge == goal.edge,
           hypot(position.x - point.x, position.y - point.y) < 12 {
            continuation = flightContinuation
            if let landed = attachment, let first = continuation.first {
                continuation[0] = .init(from: landed, to: first.to, kind: first.kind)
            }
        }
        route.removeAll()
        afterLanding = continuation
        flightContinuation.removeAll()
        flightGoal = nil
        idleRemaining = 1.5
        flightVelocity = .zero
        state = .settling
        settlingRemaining = 0.8
    }

    public mutating func setIdleExploration(_ enabled: Bool) {
        idleExplorationEnabled = enabled
        guard !keyboardControlEnabled else { return }
        mission.cancel(); runsMission = enabled
        requestedActivity = nil; pendingActivity = nil
        afterLanding.removeAll(); flightContinuation.removeAll()
        if enabled { idleRemaining = 0.8; return }
        if state == .traversingEdge { route = Array(route.prefix(1)); return }
        if ropeSession != nil {
            ropeContinuation.removeAll(); route.removeAll()
            ropeSession?.climbsAfterSwing = false
            if ropeSession?.mode == .climbing || ropeSession?.mode == .descending { ropeSession?.switchMode(.swinging) }
            return
        }
        if state == .walking || state == .running || state == .climbing, let terrain, let support = currentSupport,
           let point = TerrainSupport.resolve(support, in: terrain) {
            attachment = support; position = point; route.removeAll(); state = .idle
        }
    }

    public func suggestedGrappleAim() -> Point? {
        guard keyboardControlEnabled, let terrain else { return nil }
        return terrain.surfaces.filter { $0.id.edge == .top && $0.end.x - $0.start.x >= 48 }
            .compactMap { surface -> Point? in
                let point = Point(x: min(max(position.x, surface.start.x + 24), surface.end.x - 24), y: surface.start.y + 1)
                return aimedGrappleTarget(toward: point)
            }.min { hypot($0.x - position.x, $0.y - position.y) < hypot($1.x - position.x, $1.y - position.y) }
    }
    public func aimedGrappleTarget(toward point: Point) -> Point? {
        guard keyboardControlEnabled, let terrain, let anchor = graph?.aimedGrapple(from: position, toward: point) else { return nil }
        return anchor.resolve(in: terrain)?.anchor
    }
    @discardableResult public mutating func fireGrapple(toward point: Point) -> Bool {
        guard keyboardControlEnabled, pendingGrapple == nil, state != .held, state != .traversingEdge,
              let terrain, let graph, let anchor = graph.aimedGrapple(from: position, toward: point),
              let guide = anchor.resolve(in: terrain), let offset = anchor.offset else { return false }
        let velocity = ropeSession?.releaseVelocity ?? (state == .jumping ? controlVelocity : .zero)
        let airborne = attachment == nil || ropeSession.map { $0.mode != .supported && $0.mode != .firing } == true
        var session = RopeSession(anchor: anchor, guide: guide, feet: position, mode: .firing, velocity: velocity)
        session.freeFlightWhileFiring = airborne
        session.climbsAfterSwing = false
        let lip = TerrainAttachment(owner: .window(anchor.windowID), edge: .front, offset: offset)
        let continuation = graph.frontMantle(from: lip).map { [$0] } ?? []
        route.removeAll(); afterLanding.removeAll(); flightContinuation.removeAll(); flightGoal = nil
        if let old = ropeSession, old.mode != .firing {
            // Stay supported by the old line throughout the new hook's flight.
            session.freeFlightWhileFiring = false
            pendingGrapple = session; pendingContinuation = continuation
        } else {
            ropeContinuation = continuation; ropeSession = session
            applyRopeState()
        }
        facing = guide.anchor.x >= position.x ? 1 : -1
        return true
    }

    private mutating func advancePendingGrapple(by dt: Double) {
        guard var shot = pendingGrapple, let terrain, let guide = shot.anchor.resolve(in: terrain) else { pendingGrapple = nil; pendingContinuation = []; return }
        shot.advance(by: dt, guide: guide, minimumLength: 1)
        guard shot.mode != .firing else { pendingGrapple = shot; return }
        let velocity = ropeSession?.releaseVelocity ?? controlVelocity
        var secured = RopeSession(anchor: shot.anchor, guide: guide, feet: position, mode: .swinging, velocity: velocity)
        secured.climbsAfterSwing = false
        ropeSession = secured; attachment = nil; ropeContinuation = pendingContinuation
        pendingGrapple = nil; pendingContinuation = []
        applyRopeState()
    }

    /// Local keyboard input belongs to an explicit play session, never a global hook.
    public mutating func setKeyboardControl(_ enabled: Bool) {
        guard keyboardControlEnabled != enabled else { return }
        let corner = state == .traversingEdge ? route : []
        if enabled, corner.isEmpty, let terrain {
            // A walking route's stored attachment is its start, not its current
            // interpolated stand point. Capture the current support before cancelling.
            if let current = currentSupport, let point = TerrainSupport.resolve(current, in: terrain), hypot(point.x - position.x, point.y - position.y) < 2 {
                attachment = current
            } else { attachment = TerrainSupport.attach(at: position, in: terrain, tolerance: 0.1)?.0 }
        }
        crouchHeld = false; crouchAmount = 0
        downConsumed = false
        keyboardControlEnabled = enabled
        agentSteering = false
        pointerLowered = false
        agentCeilingHanging = false
        controlHorizontal = 0; controlVertical = 0; controlFastPace = false
        mission.cancel(); runsMission = !enabled && idleExplorationEnabled
        requestedActivity = nil; pendingActivity = nil
        route.removeAll(); afterLanding.removeAll(); flightContinuation.removeAll(); ropeContinuation.removeAll()
        flightGoal = nil
        if state == .dropping || state == .transferringHold { return }
        if !corner.isEmpty { route = corner; return } // Finish an in-progress corner safely.
        if enabled {
            controlVelocity = state == .recovering ? flightVelocity : .zero
            if ropeSession != nil { ropeSession?.climbsAfterSwing = false }
            else if attachment != nil { state = .idle }
            else if state != .recovering { state = .jumping }
        } else if state == .jumping {
            releaseRope(velocity: controlVelocity)
        } else if ropeSession != nil {
            ropeSession?.climbsAfterSwing = true
            if ropeSession?.mode == .swinging { ropeSession?.switchMode(.climbing) }
        } else { state = attachment == nil ? .recovering : .idle }
    }

    public mutating func setControlDirection(horizontal: Double, vertical: Double) {
        controlHorizontal = min(1, max(-1, horizontal))
        controlVertical = min(1, max(-1, vertical))
        if controlVertical >= 0 { downConsumed = false }
    }

    /// Physical autopilot: walking and the existing hook, reel and swing motor.
    /// The caller may click only once the rig's hand can reach the target.
    public mutating func steerAgent(towardHand target: Point) {
        guard keyboardControlEnabled, let terrain, target.x.isFinite, target.y.isFinite else { return }
        agentSteering = true
        guard ![State.dropping, .preparingJump, .transferringHold, .traversingEdge].contains(state) else { return }
        let wantsRim = target.y >= terrain.viewport.maxY - 40
        if wantsRim, abs(position.y - (terrain.viewport.maxY - 76)) < 5,
           ropeSession?.anchor.windowID == UInt32.max {
            agentCeilingHanging = true; ropeSession = nil
            attachment = .init(owner: .screen, edge: .top, offset: position.x - terrain.viewport.minX)
            position.y = terrain.viewport.maxY - 76
        }
        if agentCeilingHanging {
            if wantsRim {
                let destination = min(max(target.x - 20, bounds.minimum.x), bounds.maximum.x)
                setControlDirection(horizontal: abs(destination - position.x) > 3 ? (destination > position.x ? 1 : -1) : 0, vertical: 0)
                if controlHorizontal == 0 { facing = target.x >= position.x ? 1 : -1 }
                setControlFastPace(true)
                return
            }
            // Lower from the planted top-edge grip onto the same rope system.
            let anchor = RopeAnchor(windowID: UInt32.max, edge: .front, offset: position.x - terrain.viewport.minX)
            if let guide = anchor.resolve(in: terrain) {
                ropeSession = RopeSession(anchor: anchor, guide: guide, feet: position, mode: .descending)
                ropeSession?.climbsAfterSwing = false; attachment = nil; state = .abseiling
            }
            agentCeilingHanging = false
        }
        let feet = Point(x: min(max(target.x - 20, bounds.minimum.x), bounds.maximum.x), y: min(max(target.y - 45, bounds.minimum.y), bounds.maximum.y))
        let dx = feet.x - position.x, dy = feet.y - position.y
        facing = target.x >= position.x ? 1 : -1
        if ropeSession?.mode == .supported, attachment?.edge.isStandable == true { ropeSession = nil }
        setControlFastPace(true)
        setControlCrouch(target.y < position.y + 30 && canCrouch)
        setControlPointerLowered(target.y < position.y + 14 && canCrouch)
        if let support = attachment, support.edge.isStandable, ropeSession == nil, abs(dy) < 8 || (abs(dx) > 36 && support.edge == .floor) {
            setControlDirection(horizontal: abs(dx) > 3 ? (dx > 0 ? 1 : -1) : 0, vertical: 0)
            if abs(dx) <= 3 { facing = target.x >= position.x ? 1 : -1 }
            return
        }
        let anchorX = min(max(feet.x, 24), terrain.viewport.maxX - 24)
        if ropeSession == nil || abs((ropeSession?.anchor.resolve(in: terrain)?.anchor.x ?? 0) - anchorX) > 90 {
            // Prefer an actual window roof above the destination. The display
            // rim is the fallback for global menus and otherwise empty desktop.
            let roofs = terrain.surfaces.filter { $0.id.edge == .top && anchorX >= $0.start.x + 24 && anchorX <= $0.end.x - 24 && ($0.id.owner == .window(UInt32.max) || $0.start.y > target.y + 60) && $0.start.y > position.y + 65 }.sorted { $0.start.y < $1.start.y }
            if let roof = roofs.first { _ = fireGrapple(toward: .init(x: anchorX, y: roof.start.y)) }
        }
        let velocity = ropeSession?.body.velocity.x ?? 0
        let steer = min(1, max(-1, dx * 0.06 - velocity * 0.08))
        setControlDirection(horizontal: abs(dx) < 3 && abs(velocity) < 6 ? 0 : steer, vertical: abs(dy) > 3 ? (dy > 0 ? 1 : -1) : 0)
    }

    public mutating func controlJump() {
        pendingGrapple = nil; pendingContinuation = []
        guard keyboardControlEnabled, state != .held, state != .traversingEdge, state != .preparingJump, state != .dropping, state != .transferringHold else { return }
        if let session = ropeSession, session.mode != .supported && session.mode != .firing {
            controlVelocity = session.releaseVelocity
            controlVelocity.y = max(250, controlVelocity.y)
            controlVelocity.x += facing * 65
            ropeSession = nil; ropeContinuation.removeAll(); attachment = nil
        } else {
            guard let support = attachment else { return } // No mid-air double jumps.
            ropeSession = nil; ropeContinuation.removeAll()
            if controlVertical >= 0, support.edge == .floor || support.edge == .top {
                jumpPreparationElapsed = 0; jumpAirElapsed = 0
                route.removeAll(); state = .preparingJump
                return
            }
            controlVelocity = .init(x: controlHorizontal * manualTravelSpeed, y: controlVertical < 0 ? -30 : 260)
            if controlVertical < 0 {
                dropThroughRemaining = 0.3; downConsumed = true
                releaseRope(velocity: controlVelocity)
                return
            }
            attachment = nil
        }
        jumpAirElapsed = 0
        route.removeAll(); state = .jumping
    }

    public mutating func controlGrapple() {
        guard keyboardControlEnabled, ropeSession == nil, let source = currentSupport,
              let graph, let terrain,
              let shot = graph.grappleSteps(from: source).min(by: {
                  guard let a = TerrainSupport.resolve($0.to, in: terrain), let b = TerrainSupport.resolve($1.to, in: terrain) else { return false }
                  return hypot(a.x - position.x, a.y - position.y) < hypot(b.x - position.x, b.y - position.y)
              }) else { return }
        let finish = graph.frontMantle(from: shot.to) ?? graph.steps.first { $0.kind == .mantling && $0.from == shot.to }
        _ = follow([shot] + (finish.map { [$0] } ?? []))
        ropeSession?.climbsAfterSwing = false
    }

    /// Reach for a nearby internal hold. Called deliberately by input, or during
    /// slow autonomous rope work; it never grabs a crack during a fast swing.
    @discardableResult public mutating func transferToWindowHold() -> Bool {
        guard let terrain, state != .held, state != .transferringHold, let (anchor, _) = TerrainSupport.grip(at: position, in: terrain, reach: ropeSession == nil && attachment != nil ? 68 : 24, excluding: attachment, direction: ropeSession == nil ? .init(x: controlHorizontal, y: controlVertical) : .zero) else { return false }
        if let session = ropeSession {
            guard session.mode != .firing, session.age >= 0.25,
                  hypot(session.releaseVelocity.x, session.releaseVelocity.y) <= 220 else { return false }
        }
        ropeSession = nil; ropeContinuation.removeAll(); route.removeAll(); afterLanding.removeAll()
        flightGoal = nil; holdTransferStart = position; holdTransferElapsed = 0
        attachment = anchor; state = .transferringHold; climbingTime = 0
        controlVelocity = .zero
        return true
    }

    private mutating func advanceDrop(by dt: Double) {
        dropElapsed += dt
        let progress = min(1, dropElapsed / EdgeTraversal.duration(.launching))
        position = EdgeTraversal.position(.launching, progress: progress, from: dropStart, to: dropEnd)
        // The shared launch arc ends at its original height. A deliberate drop
        // must finish below the ledge so a central drop cannot catch it again.
        let u = max(0, (progress - 0.7) / 0.3)
        position.y += (dropEnd.y - dropStart.y) * u * u * (3 - 2 * u)
        if dropElapsed >= EdgeTraversal.duration(.launching) {
            attachment = nil; state = .recovering; physicalRelease = true; recoveryTime = 0
            flightVelocity = .init(x: facing * 45, y: -35)
        }
    }

    private mutating func startDrop() {
        guard let support = attachment else { return }
        downConsumed = true
        route.removeAll(); afterLanding.removeAll(); ropeContinuation.removeAll(); ropeSession = nil
        mission.cancel()
        if support.edge == .horizontalCrack {
            attachment = nil; physicalRelease = true; recoveryTime = 0
            flightVelocity = .init(x: controlHorizontal * 60, y: -35); state = .recovering
            return
        }
        dropStart = position
        // Move past the nearest exposed end, so a swept landing cannot immediately
        // catch the same ledge. Native windows remain platforms, not solid boxes.
        let surface = terrain?.surfaces.filter { $0.id.owner == support.owner && $0.id.edge == support.edge && (support.featureID == nil || $0.id.segment == support.featureID) }.min { abs(($0.start.x + $0.end.x) / 2 - position.x) < abs(($1.start.x + $1.end.x) / 2 - position.x) }
        let side: Double
        if let surface {
            side = controlHorizontal != 0 ? controlHorizontal : (position.x - surface.start.x < surface.end.x - position.x ? -1 : 1)
            let x = side < 0 ? surface.start.x - 25 : surface.end.x + 25
            // A central drop-through does not teleport across a wide toolbar.
            dropEnd = .init(x: abs(x - position.x) <= 70 ? x : position.x + side * 14, y: position.y - 8)
        } else { side = facing; dropEnd = .init(x: position.x + side * 14, y: position.y - 8) }
        facing = side; dropElapsed = 0; state = .dropping
    }

    private mutating func advanceInternalClimbing(by dt: Double, anchor: TerrainAttachment, terrain: TerrainSnapshot) {
        guard let feature = terrain.features.first(where: { $0.id == anchor.featureID && .window($0.windowID) == anchor.owner }) else { recover(); return }
        let horizontal = anchor.edge == .horizontalCrack
        let direction = horizontal ? controlHorizontal : controlVertical
        if horizontal { if controlHorizontal != 0 { facing = controlHorizontal } }
        else { facing = 1 }
        let work = dt * ropeWorkRate
        let movement = horizontal ? 30 * work : ClimbingGait.distance(from: climbingTime, to: climbingTime + work)
        let end = WindowFeatureDetector.length(feature) - (horizontal ? 20 : 62)
        let offset = min(max(horizontal ? 20 : 0, anchor.offset + direction * movement), end)
        let next = TerrainAttachment(owner: anchor.owner, edge: anchor.edge, offset: offset, featureID: anchor.featureID)
        if let point = TerrainSupport.resolve(next, in: terrain) {
            attachment = next; position = point
            state = direction == 0 ? .idle : .climbing
            if direction != 0 { climbingTime += work }
        }
        // At intersections, an input perpendicular to the current route reaches
        // for the adjoining hold. Up can also pull onto a nearby standing ledge.
        if horizontal ? controlVertical > 0 : (controlHorizontal != 0 || (controlVertical > 0 && offset >= end - 1)) {
            _ = transferToWindowHold()
        }
    }

    private mutating func advanceKeyboardControl(by dt: Double) {
        guard state != .held, let terrain else { return }
        if agentCeilingHanging, let support = attachment, support.owner == .screen, support.edge == .top {
            let work = dt * ropeWorkRate
            if controlHorizontal != 0 {
                facing = controlHorizontal
                position.x += controlHorizontal * 30 * work
                climbingTime += work; state = .climbing
            } else { state = .idle }
            position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
            position.y = terrain.viewport.maxY - 76
            attachment = .init(owner: .screen, edge: .top, offset: position.x - terrain.viewport.minX)
            return
        }
        dropThroughRemaining = max(0, dropThroughRemaining - dt)
        // Every manual fall shares the chute clock, including walking off an
        // edge, dropping through one, losing a hold and taking control mid-fall.
        if state == .recovering {
            if !agentSteering, controlVertical > 0, transferToWindowHold() { return }
            flightVelocity.x += controlHorizontal * 90 * dt
            advancePhysics(by: dt)
            return
        }
        if controlVertical < 0, !downConsumed, let support = attachment,
           (support.edge.isStandable && support.edge != .floor) || support.edge == .horizontalCrack {
            startDrop(); return
        }
        if !agentSteering, ropeSession != nil, controlVertical > 0, transferToWindowHold() { return }
        if ropeSession == nil, let support = attachment, support.edge.isInternal && !support.edge.isStandable {
            advanceInternalClimbing(by: dt, anchor: support, terrain: terrain); return
        }
        if !agentSteering, controlVertical > 0, transferToWindowHold() { return }
        if state == .traversingEdge { advanceTravel(by: dt); return }
        if state == .preparingJump {
            guard let attachment, let point = TerrainSupport.resolve(attachment, in: terrain) else {
                self.attachment = nil; controlVelocity = .zero; jumpAirElapsed = 0; state = .jumping; return
            }
            position = point // Keep the soles planted, including on a moving window.
            jumpPreparationElapsed += dt
            if jumpPreparationElapsed + 0.000001 >= JumpAnimation.preparationDuration {
                jumpPreparationElapsed = JumpAnimation.preparationDuration
                self.attachment = nil
                controlVelocity = .init(x: controlHorizontal * manualTravelSpeed, y: JumpAnimation.launchSpeed)
                jumpAirElapsed = 0; state = .jumping
            }
            return
        }
        if var session = ropeSession, session.mode != .supported || controlVertical != 0 {
            let mode: RopeSession.Mode = controlVertical > 0 ? .climbing : (controlVertical < 0 ? .descending : .swinging)
            session.climbsAfterSwing = false
            if session.mode == .firing { session.modeAfterLatch = mode }
            else if session.mode != mode { session.switchMode(mode) }
            if session.mode != .firing, let guide = session.anchor.resolve(in: terrain) {
                session.steerSwing(horizontal: controlHorizontal, elapsed: dt, guide: guide)
            }
            ropeSession = session
            advanceRope(by: dt)
            return
        }
        if state == .jumping || attachment == nil {
            let previous = position
            jumpAirElapsed += dt
            let targetSpeed = controlHorizontal * manualTravelSpeed
            let acceleration = controlHorizontal == 0 ? 120.0 : 400.0
            controlVelocity.x += min(acceleration * dt, max(-acceleration * dt, targetSpeed - controlVelocity.x))
            // Exact constant-acceleration displacement avoids a take-off timing bias.
            position.x += controlVelocity.x * dt
            position.y += controlVelocity.y * dt - JumpAnimation.gravity * dt * dt / 2
            controlVelocity.y -= JumpAnimation.gravity * dt
            if position.y > bounds.maximum.y { controlVelocity.y = min(0, controlVelocity.y) }
            if position.x < bounds.minimum.x || position.x > bounds.maximum.x { controlVelocity.x = 0 }
            clampPosition()
            if controlVelocity.y < 0, dropThroughRemaining <= 0,
               let (anchor, point) = TerrainSupport.landing(from: previous, to: position, in: terrain) {
                lastLandingSpeed = abs(controlVelocity.y); landingCount += 1
                attachment = anchor; position = point; controlVelocity = .zero
                state = .settling; settlingRemaining = LandingAnimation.duration
            } else if position.y <= bounds.minimum.y {
                attachment = TerrainSupport.attach(at: position, in: terrain)?.0
                lastLandingSpeed = abs(controlVelocity.y); landingCount += 1
                controlVelocity = .zero; state = .settling; settlingRemaining = LandingAnimation.duration
            } else if controlVelocity.y < -JumpAnimation.launchSpeed {
                // A jump that falls beyond its ordinary arc becomes a parachute
                // descent; short hops still land with the normal jump animation.
                releaseRope(velocity: controlVelocity)
            } else { state = .jumping }
            return
        }
        if state == .settling {
            settlingRemaining -= dt
            if settlingRemaining > LandingAnimation.duration - 0.08 { return }
            state = .idle
        }
        // Up/down grabs an exposed side within arm's reach. Front-of-window
        // climbing uses G and the shared rope, rather than an invisible wall.
        if controlVertical != 0, attachment?.edge == .top || attachment?.edge == .floor {
            if controlVertical < 0, let source = attachment,
               let lowering = graph?.steps.first(where: { $0.kind == .lowering && $0.from.owner == source.owner && abs($0.from.offset - source.offset) < 4 }) {
                _ = follow([.init(from: source, to: lowering.to, kind: .lowering)])
                return
            }
            for window in terrain.windows {
                for edge in [TerrainEdge.left, .right] {
                    let wall = TerrainAttachment(owner: .window(window.id), edge: edge, offset: position.y - window.frame.minY)
                    if let point = TerrainSupport.resolve(wall, in: terrain), abs(point.x - position.x) <= 8, position.y < window.frame.maxY - EdgeTraversal.lipHeight {
                        attachment = wall; position = point; break
                    }
                }
                if attachment?.owner == .window(window.id), attachment?.edge != .top { break }
            }
        }
        if let wall = attachment, wall.edge == .left || wall.edge == .right,
           case .window(let id) = wall.owner, let window = terrain.windows.first(where: { $0.id == id }) {
            if controlVertical < 0 {
                beginRope(.init(from: wall, to: wall, kind: .abseiling), mode: .descending)
                return
            }
            let climbStep = dt * ropeWorkRate
            let lift = ClimbingGait.distance(from: climbingTime, to: climbingTime + climbStep)
            let height = min(window.frame.height - EdgeTraversal.lipHeight, wall.offset + (controlVertical > 0 ? lift : 0))
            let next = TerrainAttachment(owner: wall.owner, edge: wall.edge, offset: height)
            if let point = TerrainSupport.resolve(next, in: terrain) {
                attachment = next; position = point
                facing = wall.edge == .left ? 1 : -1
                state = controlVertical > 0 ? .climbing : .idle
                if controlVertical > 0 { climbingTime += climbStep }
                if controlVertical > 0, height >= window.frame.height - EdgeTraversal.lipHeight - 0.001,
                   let mantle = graph?.steps.first(where: { $0.kind == .mantling && $0.from == next }) { _ = follow([mantle]) }
            }
            return
        }
        if controlHorizontal != 0 {
            ropeSession = nil
            facing = controlHorizontal
            let stride: Double
            let runs = controlFastPace && !isCrouching
            if runs {
                stride = RunningGait.distance(from: runningTime, to: runningTime + dt)
                runningTime += dt
            } else {
                let gaitStep = dt * (2 - crouchBlend)
                stride = WalkingGait.distance(from: walkingTime, to: walkingTime + gaitStep, tuning: walkingTuning)
                walkingTime += gaitStep
            }
            position.x += facing * stride
            clampPosition()
            if let (anchor, point) = TerrainSupport.attach(at: position, in: terrain, tolerance: 0.1) {
                attachment = anchor; position = point; state = runs ? .running : .walking
            } else { releaseRope(velocity: .init(x: facing * manualTravelSpeed, y: 0)) }
        } else {
            if state == .settling { settlingRemaining -= dt; if settlingRemaining > 0 { return } }
            state = .idle
        }
    }

}
