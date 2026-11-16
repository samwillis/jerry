import Foundation

/// One Marchers-mode level: a hatch at the top centre of the screen releases a line of
/// marchers onto the user's windows, and an exit door sits on a window top.
/// Everything attached to a window (marchers, exit, tunnels, bridges) moves with it.
public struct MarcherLevel: Equatable, Sendable {
    public enum Phase: String, Sendable { case waiting, releasing, running, finished }
    public struct Exit: Equatable, Sendable {
        public let windowID: UInt32
        /// Distance from the window's left edge.
        public let offset: Double
    }

    public static let tick = 1.0 / 30

    public private(set) var world: MarcherWorld
    public private(set) var marchers: [Marcher] = []
    public private(set) var phase: Phase = .waiting
    public private(set) var exit: Exit?
    public let total: Int
    public let number: Int
    public private(set) var released = 0
    public private(set) var elapsed = 0.0
    public private(set) var stock: [MarcherSkill: Int]
    public var releaseInterval = 1.6
    public var timeLimit = 300.0
    private var releaseClock = 0.0
    private var accumulator = 0.0
    private let seed: UInt64

    public static let defaultStock: [MarcherSkill: Int] = [
        .climber: 20, .floater: 20, .bomber: 10, .blocker: 6, .builder: 15, .basher: 10, .miner: 10, .digger: 10
    ]

    public init(terrain: TerrainSnapshot, total: Int = 20, number: Int = 1, seed: UInt64 = 1) {
        world = MarcherWorld(terrain: terrain)
        self.total = total; self.number = number; self.seed = seed
        stock = Self.defaultStock
        placeExit()
    }

    public var savedCount: Int { marchers.filter { $0.state == .saved }.count }
    public var lostCount: Int { marchers.filter { $0.state == .lost }.count }
    public var activeCount: Int { marchers.filter { !$0.isFinished }.count }
    public var remainingToRelease: Int { total - released }
    public var hatch: WorldPoint { WorldPoint(x: (world.viewport.minX + world.viewport.maxX) / 2, y: world.viewport.maxY - 6) }
    public var spawnPoint: (x: Int, y: Int) { (Int(hatch.x.rounded()), Int(hatch.y.rounded()) - 10) }
    public var exitPoint: WorldPoint? {
        guard let exit, let frame = world.block(exit.windowID)?.frame else { return nil }
        return WorldPoint(x: (frame.minX + exit.offset).rounded(), y: frame.maxY)
    }
    public var context: MarcherPhysics.Context {
        MarcherPhysics.Context(blockers: marchers.filter { $0.state == .blocking }.map { ($0.id, $0.x, $0.y) }, exit: exitPoint)
    }

    public func marcher(_ id: Int) -> Marcher? { marchers.first { $0.id == id } }

    public mutating func updateTerrain(_ terrain: TerrainSnapshot) {
        let moves = world.update(terrain: terrain)
        for index in marchers.indices where marchers[index].isActive {
            guard let support = marchers[index].supportID else { continue }
            if let move = moves[support] {
                marchers[index].x += Int(move.dx.rounded())
                marchers[index].y += Int(move.dy.rounded())
            } else if world.block(support) == nil {
                marchers[index].supportID = nil
            }
        }
        for index in marchers.indices { MarcherPhysics.unbury(&marchers[index], world: world) }
        if !exitIsUsable { placeExit() }
    }

    public mutating func advance(by dt: Double) {
        guard dt.isFinite, dt > 0, phase != .finished else { return }
        accumulator = min(accumulator + dt, 0.25)
        while accumulator >= Self.tick && phase != .finished {
            accumulator -= Self.tick
            step()
        }
    }

    public func canAssign(_ skill: MarcherSkill, to id: Int) -> Bool {
        guard (stock[skill] ?? 0) > 0, let marcher = marcher(id), marcher.canTake(skill) else { return false }
        if skill == .blocker {
            return !marchers.contains { $0.id != id && $0.state == .blocking && abs($0.x - marcher.x) < 10 && abs($0.y - marcher.y) < 10 }
        }
        return true
    }

    @discardableResult
    public mutating func assign(_ skill: MarcherSkill, to id: Int) -> Bool {
        guard canAssign(skill, to: id), let index = marchers.firstIndex(where: { $0.id == id }) else { return false }
        guard marchers[index].take(skill) else { return false }
        stock[skill, default: 0] -= 1
        return true
    }

    /// Lights every remaining fuse, the classic way to end a level held by blockers.
    public mutating func detonateAll() {
        for index in marchers.indices where marchers[index].isActive && marchers[index].fuse == nil {
            marchers[index].fuse = 1 + Double(index % 5) * 0.2
        }
        released = total
    }

    private mutating func step() {
        let dt = Self.tick
        elapsed += dt
        switch phase {
        case .waiting:
            if exitPoint != nil && elapsed >= 2 { phase = .releasing; releaseClock = releaseInterval }
            else if exitPoint == nil { placeExit() }
        case .releasing:
            releaseClock += dt
            if releaseClock >= releaseInterval && released < total {
                releaseClock = 0
                let spawn = spawnPoint
                var next = Marcher(id: released, x: spawn.x, y: spawn.y, direction: 1)
                MarcherPhysics.unbury(&next, world: world)
                marchers.append(next)
                released += 1
            }
            if released >= total { phase = .running }
        case .running, .finished: break
        }
        let context = self.context
        for index in marchers.indices {
            MarcherPhysics.step(&marchers[index], by: dt, world: &world, context: context)
        }
        if phase == .running && marchers.allSatisfy(\.isFinished) { phase = .finished }
        if elapsed >= timeLimit && phase != .finished {
            for index in marchers.indices where !marchers[index].isFinished { marchers[index].enter(.lost) }
            released = total
            phase = .finished
        }
    }

    // MARK: Exit placement

    var exitIsUsable: Bool {
        guard let point = exitPoint, let exit, let frame = world.block(exit.windowID)?.frame else { return false }
        return Self.isOpenTop(world, x: Int(point.x), top: Int(frame.maxY.rounded())) && world.owner(ofCell: Int(point.x), Int(frame.maxY.rounded()) - 1) == exit.windowID
    }

    static func isOpenTop(_ world: MarcherWorld, x: Int, top: Int) -> Bool {
        guard world.cell(x, top - 1), world.cell(x - 6, top - 1), world.cell(x + 6, top - 1) else { return false }
        return !(0...22).contains { world.cell(x, top + $0) || world.cell(x - 8, top + $0) || world.cell(x + 8, top + $0) }
    }

    /// Places the exit by hand, for fixtures and tests.
    mutating func setExit(windowID: UInt32, offset: Double) { exit = Exit(windowID: windowID, offset: offset) }

    /// Picks an exposed window top away from the hatch, favouring lower and farther windows.
    mutating func placeExit() {
        let hatchX = hatch.x
        var candidates: [(score: Double, exit: Exit)] = []
        for block in world.blocks {
            let frame = block.frame
            let top = Int(frame.maxY.rounded())
            guard frame.width >= 60, Double(top) < world.viewport.maxY - 40 else { continue }
            var x = frame.minX + 24
            while x <= frame.maxX - 24 {
                let column = Int(x.rounded())
                if world.owner(ofCell: column, top - 1) == block.id, Self.isOpenTop(world, x: column, top: top) {
                    let height = (Double(top) - world.viewport.minY) / max(1, world.viewport.height)
                    let spread = min(1, abs(x - hatchX) / max(1, world.viewport.width / 2))
                    candidates.append((spread * 1.2 + (1 - height), Exit(windowID: block.id, offset: x - frame.minX)))
                }
                x += 24
            }
        }
        guard !candidates.isEmpty else { exit = nil; return }
        candidates.sort { $0.score > $1.score }
        let shortlist = candidates.prefix(4)
        exit = shortlist[shortlist.startIndex + Int((seed &+ UInt64(number)) % UInt64(shortlist.count))].exit
    }
}
