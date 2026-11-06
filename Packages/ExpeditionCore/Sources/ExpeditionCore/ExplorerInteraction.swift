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

    public enum State: String { case idle, held, settling, recovering, walking, climbing, abseiling, traversingEdge }
    public private(set) var position: Point
    public private(set) var state: State = .idle
    public private(set) var attachment: TerrainAttachment?
    public var autonomous = false
    public var runsMission = false
    public private(set) var mission = BananaMission()
    public private(set) var requestedActivity: ExplorerActivity?
    public private(set) var pendingActivity: ExplorerActivity?
    public private(set) var activityIssue: String?
    public var activityStatus: String {
        if let pendingActivity { return "Queued: \(pendingActivity.title)" }
        if let activityIssue { return activityIssue }
        guard let requestedActivity else { return "Automatic adventures" }
        return "\(requestedActivity.title): \(hasPendingTravel ? state.rawValue : "finished")"
    }
    public var availableActivities: Set<ExplorerActivity> {
        var result: Set<ExplorerActivity> = [.automatic, .bananaAdventure]
        if state == .recovering || state == .traversingEdge { return Set(ExplorerActivity.allCases) }
        guard let source = currentSupport, let graph else { return result }
        for activity in ExplorerActivity.allCases where activity.travelKind != nil {
            if graph.activityRoute(activity, from: source) != nil { result.insert(activity) }
        }
        return result
    }
    private var currentSupport: TerrainAttachment? {
        if let step = route.first, step.from.owner == step.to.owner, step.from.edge == step.to.edge {
            return .init(owner: step.from.owner, edge: step.from.edge, offset: step.from.offset + (step.to.offset - step.from.offset) * travelFraction)
        }
        return attachment
    }

    @discardableResult public mutating func requestActivity(_ activity: ExplorerActivity) -> Bool {
        mission.cancel()
        activityIssue = nil
        if state == .recovering || state == .traversingEdge || state == .held {
            pendingActivity = activity
            requestedActivity = activity
            runsMission = false
            flightContinuation.removeAll()
            afterLanding.removeAll()
            return true
        }
        if activity == .automatic || activity == .bananaAdventure {
            if let source = currentSupport { attachment = source }
            route.removeAll(); afterLanding.removeAll()
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
    public var edgeProgress: Double { travelFraction }
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
    public var hasPendingTravel: Bool { !route.isEmpty || !afterLanding.isEmpty || flightGoal != nil }
    public var ropeGuide: AbseilRope? {
        guard state == .abseiling || edgeMotion == .lowering,
              let step = route.first, let terrain,
              let window = terrain.windows.first(where: { .window($0.id) == step.from.owner }) else { return nil }
        return AbseilRope(window: window.frame, edge: step.kind == .lowering ? step.to.edge : step.from.edge)
    }
    public var ropeAnchor: Point? { ropeGuide?.anchor }

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
            if state == .walking || state == .climbing || state == .abseiling || state == .traversingEdge {
                advanceTravel(by: dt)
            } else {
                advancePhysics(by: dt)
                if state == .idle && !runsMission {
                    if let pendingActivity { _ = requestActivity(pendingActivity) }
                    else if requestedActivity == nil { advanceAutonomy(by: dt) }
                }
            }
            if runsMission, let terrain {
                var nextMission = mission
                nextMission.advance(by: dt, explorer: &self, terrain: terrain)
                mission = nextMission
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
                let distance = RecoveryAnimation.distance(from: recoveryTime, to: recoveryTime + dt)
                let drag = 1.2 + 5 * RecoveryAnimation.deployment(at: recoveryTime + dt / 2)
                let decay = exp(-drag * dt)
                if let flightGoal, let terrain, let target = TerrainSupport.resolve(flightGoal, in: terrain) {
                    let remainingDrop = max(1, position.y - target.y)
                    let remainingTime = RecoveryAnimation.duration(for: remainingDrop, startingAt: recoveryTime)
                    flightVelocity.x = max(-65, min(65, (target.x - position.x) / max(dt, remainingTime)))
                }
                var next = Point(x: position.x + flightVelocity.x * (1 - decay) / drag, y: position.y - distance + flightVelocity.y * (1 - decay) / drag)
                flightVelocity.x *= decay
                flightVelocity.y *= decay
                recoveryTime += dt
                if next.x < bounds.minimum.x || next.x > bounds.maximum.x { flightVelocity.x = 0 }
                if next.y > bounds.maximum.y { flightVelocity.y = min(0, flightVelocity.y) }
                next.x = min(max(next.x, bounds.minimum.x), bounds.maximum.x)
                next.y = min(max(next.y, bounds.minimum.y), bounds.maximum.y)
                if let terrain, let (anchor, landed) = TerrainSupport.landing(from: position, to: next, in: terrain) {
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
        self.bounds = bounds
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

    public mutating func updateTerrain(_ terrain: TerrainSnapshot) {
        self.terrain = terrain
        if autonomous { graph = NavigationGraph(terrain: terrain) }
        guard state != .held else { return }
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
                return
            }
            self.attachment = nil
            recoveryTime = 0
            flightVelocity = .zero
            state = .recovering
            return
        }
        guard state != .recovering else { return }
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
            let direction: Double = to.x >= from.x ? 1 : -1
            if state != .walking || facing != direction { walkingTime = 0 }
            state = .walking; facing = direction
        case .climbing:
            if state != .climbing { climbingTime = ClimbingGait.time(atHeight: heightAlongWall) }
            state = .climbing; facing = step.from.edge == .left ? 1 : -1
        case .abseiling: state = .abseiling; facing = step.from.edge == .left ? 1 : -1
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
        if let motion = edgeMotion {
            travelFraction = min(1, travelFraction + dt / EdgeTraversal.duration(motion))
        } else if step.kind == .walking {
            let travelled = WalkingGait.distance(from: walkingTime, to: walkingTime + dt, tuning: walkingTuning)
            walkingTime += dt
            travelFraction = min(1, travelFraction + travelled / max(0.01, distance))
        } else if step.kind == .climbing {
            let lifted = ClimbingGait.distance(from: climbingTime, to: climbingTime + dt)
            climbingTime += dt
            travelFraction = min(1, travelFraction + lifted / max(0.01, distance))
        } else {
            travelFraction = min(1, travelFraction + 48 * dt / max(0.01, distance))
        }
        position = travelPosition(step, from: from, to: to)
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

    private mutating func clampPosition() {
        position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
        position.y = min(max(position.y, bounds.minimum.y), bounds.maximum.y)
    }

    private mutating func settle() {
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
}
