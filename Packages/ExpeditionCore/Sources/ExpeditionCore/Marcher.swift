import Foundation

/// The eight standard abilities Jerry can hand to a marcher.
public enum MarcherSkill: String, CaseIterable, Sendable {
    case climber, floater, bomber, blocker, builder, basher, miner, digger

    public var title: String { rawValue.capitalized }
    /// Climbers and floaters keep their ability for the rest of the level.
    public var isPermanent: Bool { self == .climber || self == .floater }
    /// A one-letter badge for the skill token Jerry signals with.
    public var badge: String {
        switch self {
        case .climber: "C"
        case .floater: "F"
        case .bomber: "!"
        case .blocker: "T"
        case .builder: "B"
        case .basher: "H"
        case .miner: "M"
        case .digger: "D"
        }
    }
}

/// A small, single-minded walker. Positions are integer points: `x` is the column the marcher
/// stands in and `y` the line its feet rest on, so the cell at `(x, y - 1)` is its ground.
public struct Marcher: Equatable, Sendable {
    public enum State: String, Sendable {
        case falling, walking, climbing, building, bashing, mining, digging, blocking
        case exiting, splatting, exploding, saved, lost
    }

    public let id: Int
    public internal(set) var x: Int
    public internal(set) var y: Int
    /// +1 walks right, -1 walks left.
    public internal(set) var direction: Int
    public internal(set) var state: State
    public internal(set) var isClimber = false
    public internal(set) var isFloater = false
    /// Remaining bomber countdown, if lit.
    public internal(set) var fuse: Double?
    public internal(set) var fallDistance = 0
    public internal(set) var bricksLeft = 0
    /// Time in the current state, for animation and timed actions.
    public internal(set) var stateTime = 0.0
    /// Total simulated walking distance, used to phase the stride.
    public internal(set) var stride = 0.0
    /// The window the marcher is standing on or climbing, so it rides that window.
    public internal(set) var supportID: UInt32?
    var progress = 0.0

    public init(id: Int, x: Int, y: Int, direction: Int = 1, state: State = .falling) {
        self.id = id; self.x = x; self.y = y; self.direction = direction >= 0 ? 1 : -1; self.state = state
    }

    public var position: WorldPoint { WorldPoint(x: Double(x), y: Double(y)) }
    /// Still on the field and able to take a skill.
    public var isActive: Bool {
        switch state {
        case .exiting, .splatting, .exploding, .saved, .lost: false
        default: true
        }
    }
    public var isFinished: Bool { state == .saved || state == .lost }
    public var umbrellaOpen: Bool { isFloater && state == .falling && fallDistance >= MarcherTuning.umbrellaOpenDistance }
    /// True while carrying out a task skill that another task skill may replace.
    var isWorking: Bool {
        switch state {
        case .building, .bashing, .mining, .digging: true
        default: false
        }
    }

    public func canTake(_ skill: MarcherSkill) -> Bool {
        guard isActive else { return false }
        switch skill {
        case .climber: return !isClimber
        case .floater: return !isFloater
        case .bomber: return fuse == nil
        case .blocker: return state == .walking || isWorking
        case .builder, .basher, .miner, .digger:
            return (state == .walking || isWorking) && state != skill.workingState
        }
    }

    /// Applies a skill without range or stock checks. Returns false if it cannot take it now.
    @discardableResult
    public mutating func take(_ skill: MarcherSkill) -> Bool {
        guard canTake(skill) else { return false }
        switch skill {
        case .climber: isClimber = true
        case .floater: isFloater = true
        case .bomber: fuse = MarcherTuning.fuse
        case .blocker: enter(.blocking)
        case .builder: enter(.building); bricksLeft = MarcherTuning.bricksPerBuilder
        case .basher: enter(.bashing)
        case .miner: enter(.mining)
        case .digger: enter(.digging)
        }
        return true
    }

    mutating func enter(_ next: State) {
        state = next; stateTime = 0; progress = 0
        if next == .falling { fallDistance = 0 }
    }
}

extension MarcherSkill {
    var workingState: Marcher.State? {
        switch self {
        case .builder: .building
        case .basher: .bashing
        case .miner: .mining
        case .digger: .digging
        default: nil
        }
    }
}

/// Deterministic marcher behaviour. The live level and Jerry's look-ahead planner share it.
public enum MarcherPhysics {
    public struct Context: Sendable {
        public var blockers: [(id: Int, x: Int, y: Int)]
        public var exit: WorldPoint?
        public init(blockers: [(id: Int, x: Int, y: Int)] = [], exit: WorldPoint? = nil) { self.blockers = blockers; self.exit = exit }
    }

    public static func step(_ m: inout Marcher, by dt: Double, world: inout MarcherWorld, context: Context) {
        guard dt > 0, !m.isFinished else { return }
        m.stateTime += dt
        if m.isActive, let fuse = m.fuse {
            let remaining = fuse - dt
            if remaining <= 0 {
                m.fuse = 0
                world.blast(x: Double(m.x) + 0.5, y: Double(m.y) + 5, radius: MarcherTuning.blastRadius)
                m.enter(.exploding)
                return
            }
            m.fuse = remaining
        }
        switch m.state {
        case .saved, .lost: return
        case .exiting: if m.stateTime >= MarcherTuning.exitDuration { m.enter(.saved) }
        case .splatting: if m.stateTime >= MarcherTuning.splatDuration { m.enter(.lost) }
        case .exploding: if m.stateTime >= MarcherTuning.explosionDuration { m.enter(.lost) }
        case .falling:
            fall(&m, dt, world)
            if m.state == .walking { checkExit(&m, context) }
        case .walking: walk(&m, dt, world, context)
        case .climbing: climb(&m, dt, world)
        case .blocking: if !grounded(m, world) { m.enter(.falling) }
        case .building: build(&m, dt, &world)
        case .digging: dig(&m, dt, &world)
        case .bashing: bash(&m, dt, &world)
        case .mining: mine(&m, dt, &world)
        }
        if m.isActive, m.state != .falling {
            let below = m.state == .climbing ? world.owner(ofCell: m.x + m.direction, m.y) : world.owner(ofCell: m.x, m.y - 1)
            if let below { m.supportID = below }
        } else if m.state == .falling { m.supportID = nil }
    }

    static func grounded(_ m: Marcher, _ world: MarcherWorld) -> Bool { world.cell(m.x, m.y - 1) }

    /// Moves a marcher out of material after its window moved onto it.
    public static func unbury(_ m: inout Marcher, world: MarcherWorld) {
        guard m.isActive, world.cell(m.x, m.y) else { return }
        for rise in 1...48 where !world.cell(m.x, m.y + rise) && !world.cell(m.x, m.y + rise + 6) {
            m.y += rise
            if m.state == .climbing { m.enter(.walking) }
            return
        }
        // Deeply buried: drop into whatever room lies beneath instead.
        for depth in 1...80 where !world.cell(m.x, m.y - depth) {
            m.y -= depth; m.enter(.falling); return
        }
    }

    static func fall(_ m: inout Marcher, _ dt: Double, _ world: MarcherWorld) {
        m.progress += (m.umbrellaOpen ? MarcherTuning.floatSpeed : MarcherTuning.fallSpeed) * dt
        while m.progress >= 1 {
            m.progress -= 1
            if world.cell(m.x, m.y - 1) {
                if m.fallDistance > MarcherTuning.lethalFall && !m.isFloater { m.enter(.splatting) }
                else { m.enter(.walking) }
                return
            }
            m.y -= 1; m.fallDistance += 1
            if Double(m.y) < world.viewport.minY - 24 { m.enter(.lost); return }
            if m.isFloater && m.fallDistance == MarcherTuning.umbrellaOpenDistance {
                m.progress = min(m.progress, 1); return
            }
        }
    }

    static func walk(_ m: inout Marcher, _ dt: Double, _ world: MarcherWorld, _ context: Context) {
        if !grounded(m, world) { m.enter(.falling); return }
        m.progress += MarcherTuning.walkSpeed * dt
        while m.progress >= 1 && m.state == .walking {
            m.progress -= 1
            stepForward(&m, world, context)
        }
    }

    static func stepForward(_ m: inout Marcher, _ world: MarcherWorld, _ context: Context) {
        let nx = m.x + m.direction
        for blocker in context.blockers where blocker.id != m.id && abs(blocker.y - m.y) <= 8 {
            let ahead = (blocker.x - m.x) * m.direction
            if ahead >= 0 && ahead <= MarcherTuning.blockerReach + 1 && abs(nx - blocker.x) <= MarcherTuning.blockerReach {
                m.direction = -m.direction; return
            }
        }
        if world.cell(nx, m.y) || world.cell(nx, m.y + 6) {
            var rise: Int?
            if !world.cell(nx, m.y + 6) {
                for k in 1...MarcherTuning.stepUp where !world.cell(nx, m.y + k) { rise = k; break }
            }
            if let rise, !world.cell(nx, m.y + rise + 6), !world.cell(nx, m.y + rise + MarcherTuning.height - 2) {
                m.x = nx; m.y += rise
            } else if m.isClimber && world.cell(nx, m.y) {
                m.enter(.climbing)
            } else {
                m.direction = -m.direction
            }
        } else if world.cell(nx, m.y - 1) {
            m.x = nx
        } else {
            m.x = nx
            var landed = false
            for k in 1...MarcherTuning.stepDown where world.cell(nx, m.y - 1 - k) { m.y -= k; landed = true; break }
            if !landed { m.enter(.falling); return }
        }
        m.stride += 1
        checkExit(&m, context)
    }

    static func checkExit(_ m: inout Marcher, _ context: Context) {
        if let exit = context.exit, abs(Double(m.x) - exit.x) <= 5, abs(Double(m.y) - exit.y) <= 4 {
            m.enter(.exiting)
        }
    }

    static func climb(_ m: inout Marcher, _ dt: Double, _ world: MarcherWorld) {
        m.progress += MarcherTuning.climbSpeed * dt
        while m.progress >= 1 && m.state == .climbing {
            m.progress -= 1
            if !world.cell(m.x + m.direction, m.y) {
                // Over the lip.
                m.x += m.direction
                m.enter(world.cell(m.x, m.y - 1) ? .walking : .falling)
                return
            }
            if world.cell(m.x, m.y + MarcherTuning.height) {
                // An overhang: let go and drop back the way it came.
                m.direction = -m.direction
                m.enter(.falling)
                return
            }
            m.y += 1
        }
    }

    static func build(_ m: inout Marcher, _ dt: Double, _ world: inout MarcherWorld) {
        if !grounded(m, world) { m.enter(.falling); return }
        guard m.stateTime >= MarcherTuning.buildInterval else { return }
        m.stateTime -= MarcherTuning.buildInterval
        let anchor = world.owner(ofCell: m.x, m.y - 1) ?? m.supportID
        let minX = Double(m.x) + (m.direction > 0 ? -2 : -(MarcherTuning.brickWidth - 3))
        world.addBrick(WorldRect(x: minX, y: Double(m.y), width: MarcherTuning.brickWidth, height: Double(MarcherTuning.brickHeight)), anchor: anchor)
        m.bricksLeft -= 1
        let nx = m.x + m.direction * MarcherTuning.brickAdvance, ny = m.y + MarcherTuning.brickHeight
        let blocked = world.cell(nx + m.direction, ny) || world.cell(nx + m.direction, ny + 6) || world.cell(nx, ny + MarcherTuning.height)
            || (1..<MarcherTuning.brickAdvance).contains { world.cell(m.x + m.direction * $0, ny + 4) }
        if blocked {
            m.y = ny
            m.direction = -m.direction
            m.enter(.walking)
            return
        }
        m.x = nx; m.y = ny
        if m.bricksLeft <= 0 { m.enter(.walking) }
    }

    static func dig(_ m: inout Marcher, _ dt: Double, _ world: inout MarcherWorld) {
        m.progress += MarcherTuning.digRate * dt
        while m.progress >= 1 && m.state == .digging {
            m.progress -= 1
            let row = m.y - 1
            guard (-4...4).contains(where: { world.cell(m.x + $0, row) }) else { m.enter(.falling); return }
            world.carve(WorldRect(x: Double(m.x - 4), y: Double(row), width: 9, height: 1))
            m.y -= 1
            if !grounded(m, world) && !(-4...4).contains(where: { world.cell(m.x + $0, m.y - 1) }) { m.enter(.falling); return }
        }
    }

    static func bash(_ m: inout Marcher, _ dt: Double, _ world: inout MarcherWorld) {
        if !grounded(m, world) { m.enter(.falling); return }
        m.progress += MarcherTuning.bashRate * dt
        while m.progress >= 1 && m.state == .bashing {
            m.progress -= 1
            let ahead = (1...8).contains { k in world.cell(m.x + m.direction * k, m.y + 2) || world.cell(m.x + m.direction * k, m.y + 6) || world.cell(m.x + m.direction * k, m.y + 10) }
            guard ahead else { m.enter(.walking); return }
            let minX = m.direction > 0 ? Double(m.x + 1) : Double(m.x - 4)
            world.carve(WorldRect(x: minX, y: Double(m.y), width: 4, height: 12))
            m.x += m.direction
            if !grounded(m, world) {
                var landed = false
                for k in 1...MarcherTuning.stepDown where world.cell(m.x, m.y - 1 - k) { m.y -= k; landed = true; break }
                if !landed { m.enter(.falling); return }
            }
        }
    }

    static func mine(_ m: inout Marcher, _ dt: Double, _ world: inout MarcherWorld) {
        if !grounded(m, world) { m.enter(.falling); return }
        m.progress += MarcherTuning.mineRate * dt
        while m.progress >= 1 && m.state == .mining {
            m.progress -= 1
            let ahead = (0...6).contains { k in world.cell(m.x + m.direction * k, m.y - 1) || world.cell(m.x + m.direction * k, m.y + 3) || world.cell(m.x + m.direction * k, m.y + 8) }
            guard ahead else { m.enter(.walking); return }
            let minX = m.direction > 0 ? Double(m.x - 1) : Double(m.x - 4)
            world.carve(WorldRect(x: minX, y: Double(m.y - 1), width: 6, height: 12))
            m.x += m.direction; m.y -= 1
            if !grounded(m, world) { m.enter(.falling); return }
        }
    }
}
