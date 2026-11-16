import Foundation

/// Tunable constants for Marchers mode, in logical points and seconds.
public enum MarcherTuning {
    public static let height = 14
    public static let walkSpeed = 24.0
    public static let fallSpeed = 150.0
    public static let floatSpeed = 42.0
    /// A floater's umbrella opens after this much free fall.
    public static let umbrellaOpenDistance = 18
    /// Falls longer than this kill a marcher without an umbrella.
    public static let lethalFall = 140
    public static let stepUp = 6
    public static let stepDown = 4
    public static let climbSpeed = 18.0
    public static let buildInterval = 0.5
    public static let bricksPerBuilder = 12
    public static let brickWidth = 8.0
    public static let brickHeight = 2
    public static let brickAdvance = 4
    public static let digRate = 14.0
    public static let bashRate = 18.0
    public static let mineRate = 10.0
    public static let fuse = 5.0
    public static let blastRadius = 16.0
    public static let blockerReach = 4
    public static let exitDuration = 0.6
    public static let splatDuration = 0.7
    public static let explosionDuration = 0.5
    /// Window material model: a solid title band, thin side walls and a thin bottom rim.
    /// The interior is a hollow room. Small windows are solid throughout.
    public static let titleBand = 28.0
    public static let wallThickness = 6.0
    public static let rimThickness = 6.0
    public static let solidBelow = 40.0
}

/// Destructible, window-attached terrain used only by Marchers mode.
///
/// Material is decided by the frontmost window containing a point, so covered parts of
/// windows behind are hidden exactly as they are on screen. Carved holes and built bricks are
/// stored relative to their window's top-left corner, so they travel with the window when it
/// moves or resizes. Points outside the viewport's sides, and above its top, are solid; below
/// the viewport is open air, and falling there loses the marcher.
public struct MarcherWorld: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public let id: UInt32
        public internal(set) var frame: WorldRect
        /// Removed material, stored with the block so material queries avoid lookups.
        public internal(set) var carves: [Carve] = []
        let hollow: Bool
        init(id: UInt32, frame: WorldRect) {
            self.id = id; self.frame = frame
            hollow = frame.height >= MarcherTuning.solidBelow + MarcherTuning.titleBand && frame.width >= MarcherTuning.solidBelow
        }
    }
    /// Shapes in window-local coordinates: `x` from the window's left edge, `y` from its top (≤ 0 inside).
    public enum Carve: Equatable, Sendable {
        case rect(WorldRect)
        case circle(x: Double, y: Double, radius: Double)
    }
    public struct Brick: Equatable, Sendable {
        /// The window the brick travels with; nil means fixed to the screen.
        public let anchor: UInt32?
        public let local: WorldRect
    }

    public private(set) var blocks: [Block]
    public private(set) var viewport: WorldRect
    /// Carved shapes by window.
    public var carves: [UInt32: [Carve]] {
        Dictionary(blocks.filter { !$0.carves.isEmpty }.map { ($0.id, $0.carves) }, uniquingKeysWith: { first, _ in first })
    }
    public private(set) var bricks: [Brick] = []
    /// World rectangles for `bricks`, in the same order.
    public private(set) var brickRects: [WorldRect] = []
    /// Increments whenever carves or bricks change.
    public private(set) var revision = 0

    public init(terrain: TerrainSnapshot) {
        viewport = terrain.viewport
        blocks = Self.blocks(from: terrain)
    }

    public init(blocks: [Block], viewport: WorldRect) {
        self.blocks = blocks
        self.viewport = viewport
    }

    static func blocks(from terrain: TerrainSnapshot) -> [Block] {
        terrain.windows.filter { $0.canClimb && $0.frame.width >= 8 && $0.frame.height >= 8 }
            .map { Block(id: $0.id, frame: $0.frame) }
    }

    public func block(_ id: UInt32) -> Block? { blocks.first { $0.id == id } }

    /// Replaces the window geometry and returns each surviving window's top-left movement.
    @discardableResult
    public mutating func update(terrain: TerrainSnapshot) -> [UInt32: (dx: Double, dy: Double)] {
        var next = Self.blocks(from: terrain)
        var moves: [UInt32: (dx: Double, dy: Double)] = [:]
        let previous = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in next.indices {
            guard let old = previous[next[index].id] else { continue }
            next[index].carves = old.carves
            let dx = next[index].frame.minX - old.frame.minX, dy = next[index].frame.maxY - old.frame.maxY
            if dx != 0 || dy != 0 { moves[next[index].id] = (dx, dy) }
        }
        let ids = Set(next.map(\.id))
        let lostCarves = blocks.contains { !ids.contains($0.id) && !$0.carves.isEmpty }
        let before = bricks.count
        bricks.removeAll { $0.anchor.map { !ids.contains($0) } ?? false }
        if lostCarves || bricks.count != before { revision += 1 }
        blocks = next
        viewport = terrain.viewport
        rebuildBrickRects()
        return moves
    }

    // MARK: Material

    /// True for solid material at an exact point.
    public func isSolid(_ x: Double, _ y: Double) -> Bool {
        if x < viewport.minX || x >= viewport.maxX || y >= viewport.maxY { return true }
        for rect in brickRects where x >= rect.minX && x < rect.maxX && y >= rect.minY && y < rect.maxY { return true }
        for block in blocks {
            let f = block.frame
            guard x >= f.minX && x < f.maxX && y >= f.minY && y < f.maxY else { continue }
            if block.hollow && !Self.isFrame(f, x, y) { return false }
            if !block.carves.isEmpty && Self.carved(block.carves, x - f.minX, y - f.maxY) { return false }
            return true
        }
        return false
    }

    /// The solid state of the 1-point cell whose lower-left corner is (x, y).
    @inline(__always) public func cell(_ x: Int, _ y: Int) -> Bool { isSolid(Double(x) + 0.5, Double(y) + 0.5) }

    /// The window (or brick anchor) whose material fills a cell, used to ride moving windows.
    public func owner(ofCell x: Int, _ y: Int) -> UInt32? {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        for (index, rect) in brickRects.enumerated() where px >= rect.minX && px < rect.maxX && py >= rect.minY && py < rect.maxY {
            return bricks[index].anchor
        }
        for block in blocks {
            let f = block.frame
            guard px >= f.minX && px < f.maxX && py >= f.minY && py < f.maxY else { continue }
            return block.id
        }
        return nil
    }

    @inline(__always) static func isFrame(_ f: WorldRect, _ x: Double, _ y: Double) -> Bool {
        return f.maxY - y < MarcherTuning.titleBand || y - f.minY < MarcherTuning.rimThickness
            || x - f.minX < MarcherTuning.wallThickness || f.maxX - x < MarcherTuning.wallThickness
    }

    static func carved(_ list: [Carve], _ lx: Double, _ ly: Double) -> Bool {
        for carve in list {
            switch carve {
            case .rect(let r): if lx >= r.minX && lx < r.maxX && ly >= r.minY && ly < r.maxY { return true }
            case .circle(let cx, let cy, let radius): if (lx - cx) * (lx - cx) + (ly - cy) * (ly - cy) < radius * radius { return true }
            }
        }
        return false
    }

    // MARK: Changes

    /// Removes material from every window under a world rectangle, and any bricks it touches.
    public mutating func carve(_ rect: WorldRect) {
        var changed = false
        for index in blocks.indices where blocks[index].frame.intersects(rect) {
            let f = blocks[index].frame
            append(.rect(WorldRect(x: rect.minX - f.minX, y: rect.minY - f.maxY, width: rect.width, height: rect.height)), to: index)
            changed = true
        }
        if removeBricks(touching: rect) { changed = true }
        if changed { revision += 1 }
    }

    public mutating func blast(x: Double, y: Double, radius: Double) {
        let bounds = WorldRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        for index in blocks.indices where blocks[index].frame.intersects(bounds) {
            let f = blocks[index].frame
            append(.circle(x: x - f.minX, y: y - f.maxY, radius: radius), to: index)
        }
        _ = removeBricks(touching: bounds)
        revision += 1
    }

    public mutating func addBrick(_ rect: WorldRect, anchor: UInt32?) {
        let origin = anchor.flatMap { block($0)?.frame }
        let local = origin.map { WorldRect(x: rect.minX - $0.minX, y: rect.minY - $0.maxY, width: rect.width, height: rect.height) } ?? rect
        bricks.append(Brick(anchor: origin == nil ? nil : anchor, local: local))
        brickRects.append(rect)
        revision += 1
    }

    /// Removes every carve and brick, keeping the windows.
    public mutating func clearChanges() {
        for index in blocks.indices { blocks[index].carves.removeAll() }
        bricks.removeAll(); brickRects.removeAll(); revision += 1
    }

    /// World-space carve shapes, for drawing tunnels over the windows.
    public func worldCarves() -> [(windowID: UInt32, carve: Carve)] {
        var result: [(UInt32, Carve)] = []
        for block in blocks {
            for carve in block.carves {
                switch carve {
                case .rect(let r):
                    result.append((block.id, .rect(WorldRect(x: r.minX + block.frame.minX, y: r.minY + block.frame.maxY, width: r.width, height: r.height))))
                case .circle(let x, let y, let radius):
                    result.append((block.id, .circle(x: x + block.frame.minX, y: y + block.frame.maxY, radius: radius)))
                }
            }
        }
        return result
    }

    private mutating func append(_ carve: Carve, to index: Int) {
        var list = blocks[index].carves
        defer { blocks[index].carves = list }
        // Merge the strips a digger or basher leaves behind so long tunnels stay one shape.
        if case .rect(let r) = carve, case .rect(let last)? = list.last {
            if abs(last.minX - r.minX) < 0.01 && abs(last.width - r.width) < 0.01 && r.maxY >= last.minY - 0.01 && r.minY <= last.maxY + 0.01 {
                let minY = min(last.minY, r.minY), maxY = max(last.maxY, r.maxY)
                list[list.count - 1] = .rect(WorldRect(x: r.minX, y: minY, width: r.width, height: maxY - minY))
                return
            }
            if abs(last.minY - r.minY) < 0.01 && abs(last.height - r.height) < 0.01 && r.maxX >= last.minX - 0.01 && r.minX <= last.maxX + 0.01 {
                let minX = min(last.minX, r.minX), maxX = max(last.maxX, r.maxX)
                list[list.count - 1] = .rect(WorldRect(x: minX, y: r.minY, width: maxX - minX, height: r.height))
                return
            }
        }
        list.append(carve)
    }

    private mutating func removeBricks(touching rect: WorldRect) -> Bool {
        let keep = brickRects.indices.filter { !brickRects[$0].intersects(rect) }
        guard keep.count != bricks.count else { return false }
        bricks = keep.map { bricks[$0] }
        brickRects = keep.map { brickRects[$0] }
        return true
    }

    private mutating func rebuildBrickRects() {
        brickRects = bricks.map { brick in
            guard let anchor = brick.anchor, let frame = block(anchor)?.frame else { return brick.local }
            return WorldRect(x: brick.local.minX + frame.minX, y: brick.local.minY + frame.maxY, width: brick.local.width, height: brick.local.height)
        }
    }
}
