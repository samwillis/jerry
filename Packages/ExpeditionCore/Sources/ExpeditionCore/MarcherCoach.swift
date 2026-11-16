import Foundation

/// A skill Jerry has just signalled to a marcher, kept briefly for the throw animation.
public struct MarcherSignal: Equatable, Sendable {
    public let skill: MarcherSkill
    public let marcherID: Int
    public let from: WorldPoint
    public let to: WorldPoint
    public internal(set) var age = 0.0
    public static let duration = 0.6
}

/// A snapshot for planning one marcher's next skill away from the main thread.
public struct MarcherPlanningRequest: Sendable {
    public let marcherID: Int
    public let level: MarcherLevel
    public let options: MarcherPlanner.Options
    let issuedAt: Double
    public func solve() -> MarcherPlan? { MarcherPlanner.plan(for: marcherID, in: level, options: options) }
}

/// Jerry's side of Marchers mode: runs the level, plans skills, walks Jerry towards the
/// action and hands skills over only when the marcher is within his reach.
public struct MarcherCoach: Sendable {
    public private(set) var level: MarcherLevel
    public private(set) var plans: [Int: MarcherPlan] = [:]
    public private(set) var signals: [MarcherSignal] = []
    public private(set) var levelsCompleted = 0
    public private(set) var totalSaved = 0
    public private(set) var totalReleased = 0
    /// Distance from Jerry's hand within which he can signal a skill.
    public var reach = 420.0
    public var planner = MarcherPlanner.Options()
    /// When false, the host calls `nextPlanningRequest()` and `receive(_:for:)`, so the
    /// search can run on a background thread; the level itself always runs in `advance`.
    public var plansInline = true
    public let marchersPerLevel: Int
    private var terrain: TerrainSnapshot
    private var clock = 0.0
    private var planClock = 0.0
    private var moveClock = 0.0
    private var moveCooldown = 0.0
    private var finishClock = 0.0
    private var stallClock = 0.0
    private var lastProgress = 0
    private var dueTimes: [Int: Double] = [:]
    private var lastPlanned: [Int: Double] = [:]
    private var routeSeed: UInt64 = 1

    public init(terrain: TerrainSnapshot, marchersPerLevel: Int = 20) {
        self.terrain = terrain
        self.marchersPerLevel = marchersPerLevel
        level = MarcherLevel(terrain: terrain, total: marchersPerLevel, number: 1, seed: 1)
    }

    /// The point Jerry should stay near: the next planned skill, the line of marchers, or the hatch.
    public var focus: WorldPoint {
        if let next = plans.values.min(by: { (dueTimes[$0.marcherID] ?? 0) < (dueTimes[$1.marcherID] ?? 0) }),
           let marcher = level.marcher(next.marcherID) {
            return (dueTimes[next.marcherID] ?? clock) - clock > 1.5 ? next.position : marcher.position
        }
        let active = level.marchers.filter { $0.isActive && $0.state != .blocking }
        if !active.isEmpty {
            let x = active.map(\.position.x).reduce(0, +) / Double(active.count)
            let y = active.map(\.position.y).reduce(0, +) / Double(active.count)
            return WorldPoint(x: x, y: y)
        }
        return WorldPoint(x: level.hatch.x, y: level.hatch.y - 200)
    }

    public var status: String {
        let level = self.level
        let phase: String
        switch level.phase {
        case .waiting: phase = level.exitPoint == nil ? "Looking for a window to put the exit on" : "Get ready…"
        case .releasing, .running: phase = "Out \(level.marchers.filter(\.isActive).count) · In \(level.savedCount) · Lost \(level.lostCount)"
        case .finished: phase = "Rescued \(level.savedCount) of \(level.total)"
        }
        return "Level \(level.number) · \(phase)"
    }

    /// Places the exit by hand, for fixtures and tests.
    mutating func setExit(windowID: UInt32, offset: Double) { level.setExit(windowID: windowID, offset: offset) }

    public mutating func updateTerrain(_ snapshot: TerrainSnapshot) {
        terrain = snapshot
        level.updateTerrain(snapshot)
    }

    /// Advances the level and Jerry's decisions. `hand` is where Jerry signals from; nil
    /// means unlimited reach (used by tests of the solver alone).
    public mutating func advance(by dt: Double, hand: WorldPoint?) {
        guard dt.isFinite, dt > 0 else { return }
        clock += dt
        level.advance(by: dt)
        for index in signals.indices { signals[index].age += dt }
        signals.removeAll { $0.age >= MarcherSignal.duration }

        if level.phase == .finished {
            finishClock += dt
            if finishClock >= 6 { startNextLevel() }
            return
        }
        let progress = level.savedCount + level.lostCount
        if progress != lastProgress { lastProgress = progress; stallClock = 0 } else { stallClock += dt }
        let remaining = level.marchers.filter { $0.isActive }
        if level.remainingToRelease == 0, !remaining.isEmpty,
           remaining.allSatisfy({ $0.state == .blocking }) || stallClock > 75 {
            level.detonateAll()
            plans.removeAll()
            return
        }

        executeDuePlans(hand: hand)
        planClock += dt
        if plansInline, let request = nextPlanningRequest() { receive(request.solve(), for: request) }
    }

    /// The next marcher to think about, at most four times a second.
    public mutating func nextPlanningRequest() -> MarcherPlanningRequest? {
        guard planClock >= 0.25, level.phase != .finished else { return nil }
        let candidates = level.marchers.filter { $0.isActive && $0.state != .blocking }
            .filter { clock - (lastPlanned[$0.id] ?? -.infinity) >= 1 }
        guard let next = candidates.min(by: { (lastPlanned[$0.id] ?? -.infinity) < (lastPlanned[$1.id] ?? -.infinity) }) else { return nil }
        planClock = 0
        lastPlanned[next.id] = clock
        return MarcherPlanningRequest(marcherID: next.id, level: level, options: planner, issuedAt: clock)
    }

    public mutating func receive(_ plan: MarcherPlan?, for request: MarcherPlanningRequest) {
        guard request.level.number == level.number, level.marcher(request.marcherID)?.isActive == true else { return }
        if let plan {
            plans[request.marcherID] = plan
            dueTimes[request.marcherID] = request.issuedAt + plan.delay
        } else {
            drop(request.marcherID)
        }
    }

    /// Walks Jerry towards the action when he is out of reach of it.
    public mutating func steer(_ explorer: inout ExplorerInteraction, terrain: TerrainSnapshot, by dt: Double) {
        moveClock += dt
        moveCooldown = max(0, moveCooldown - dt)
        guard moveClock >= 1, moveCooldown == 0 else { return }
        moveClock = 0
        guard !explorer.keyboardControlEnabled, explorer.state == .idle || explorer.state == .settling,
              !explorer.hasPendingTravel, let anchor = explorer.attachment else { return }
        let goal = focus
        let here = explorer.position
        guard hypot(here.x - goal.x, here.y + 40 - goal.y) > reach * 0.55 else { return }
        let graph = NavigationGraph(terrain: terrain)
        let options = graph.vertices.filter { $0.edge.isStandable }.compactMap { vertex -> (TerrainAttachment, Double)? in
            guard let point = TerrainSupport.resolve(vertex, in: terrain), hypot(point.x - here.x, point.y - here.y) > 60 else { return nil }
            return (vertex, hypot(point.x - goal.x, point.y + 40 - goal.y))
        }.sorted { $0.1 < $1.1 }
        let current = hypot(here.x - goal.x, here.y + 40 - goal.y)
        for (vertex, distance) in options.prefix(6) where distance < current - 40 {
            routeSeed &+= 1
            let route = graph.route(from: anchor, to: vertex, seed: routeSeed, allowParachute: true, allowGrapple: true)
            if !route.isEmpty, explorer.follow(route) { return }
        }
        moveCooldown = 3
    }

    public func inReach(_ marcher: Marcher, from hand: WorldPoint?) -> Bool {
        guard let hand else { return true }
        return hypot(Double(marcher.x) - hand.x, Double(marcher.y) + 7 - hand.y) <= reach
    }

    private mutating func executeDuePlans(hand: WorldPoint?) {
        for plan in plans.values.sorted(by: { $0.marcherID < $1.marcherID }) {
            let due = dueTimes[plan.marcherID] ?? clock
            guard clock >= due - 0.12 else { continue }
            guard let marcher = level.marcher(plan.marcherID), marcher.isActive else { drop(plan.marcherID); continue }
            if clock > due + 1.2 { drop(plan.marcherID); continue }
            guard inReach(marcher, from: hand), level.canAssign(plan.skill, to: plan.marcherID) else { continue }
            if level.assign(plan.skill, to: plan.marcherID) {
                signals.append(MarcherSignal(skill: plan.skill, marcherID: plan.marcherID, from: hand ?? marcher.position,
                                             to: WorldPoint(x: Double(marcher.x), y: Double(marcher.y) + 7)))
            }
            drop(plan.marcherID)
            lastPlanned[plan.marcherID] = clock - 2 // Re-plan with the new ability soon.
        }
    }

    private mutating func drop(_ id: Int) { plans[id] = nil; dueTimes[id] = nil }

    private mutating func startNextLevel() {
        levelsCompleted += 1
        totalSaved += level.savedCount
        totalReleased += level.total
        let number = level.number + 1
        level = MarcherLevel(terrain: terrain, total: marchersPerLevel, number: number, seed: UInt64(number) &* 7)
        plans.removeAll(); dueTimes.removeAll(); lastPlanned.removeAll(); signals.removeAll()
        finishClock = 0; stallClock = 0; lastProgress = 0
    }
}
