import Foundation

public enum TravelKind: String, Sendable { case walking, climbing, abseiling, parachuting, mantling, lowering }

public struct TravelStep: Equatable, Sendable {
    public let from: TerrainAttachment
    public let to: TerrainAttachment
    public let kind: TravelKind
}

/// Small directed graph of safe stand points and exposed wall contacts. All vertices are
/// window-relative; segment indices never become persistent attachment identities.
public struct NavigationGraph {
    public private(set) var vertices: [TerrainAttachment] = []
    public private(set) var steps: [TravelStep] = []
    public let terrain: TerrainSnapshot

    public init(terrain: TerrainSnapshot) {
        self.terrain = terrain
        let platforms = terrain.surfaces.filter { $0.id.edge == .top || $0.id.edge == .floor }
        for platform in platforms where platform.end.x - platform.start.x >= 48 {
            let inset = min(56.0, (platform.end.x - platform.start.x) / 2)
            for x in [platform.start.x + 24, platform.start.x + inset, (platform.start.x + platform.end.x) / 2, platform.end.x - inset, platform.end.x - 24] {
                add(horizontalAnchor(platform, x: x))
            }
        }
        for wall in terrain.surfaces where wall.id.owner != .screen && wall.id.edge != .top {
            guard case .window(let id) = wall.id.owner,
                  let window = terrain.windows.first(where: { $0.id == id }) else { continue }
            let outside = wall.start.x + (wall.id.edge == .left ? -24.0 : 24.0)
            for platform in platforms where platform.start.y >= wall.start.y - 64 && platform.start.y <= wall.end.y {
                let y = platform.start.y
                let side = TerrainAttachment(owner: wall.id.owner, edge: wall.id.edge, offset: (platform.id.owner == wall.id.owner && platform.id.edge == .top ? y - EdgeTraversal.lipHeight : y) - window.frame.minY)
                if platform.id.owner == wall.id.owner && platform.id.edge == .top {
                    let inside = horizontalAnchor(platform, x: wall.start.x + (wall.id.edge == .left ? 24 : -24))
                    if add(side), add(inside) { connect(side, inside, .mantling); connect(inside, side, .lowering) }
                } else if y <= window.frame.maxY - EdgeTraversal.lipHeight, outside >= platform.start.x + 24 && outside <= platform.end.x - 24 {
                    let standing = horizontalAnchor(platform, x: outside)
                    if add(side), add(standing) { connect(side, standing, .walking); connect(standing, side, .walking) }
                }
            }
        }
        let nodes = vertices
        for a in nodes {
            for b in nodes where a != b && a.owner == b.owner && a.edge == b.edge {
                guard let p = TerrainSupport.resolve(a, in: terrain), let q = TerrainSupport.resolve(b, in: terrain) else { continue }
                if a.edge == .top || a.edge == .floor {
                    if clear(a, b) { connect(a, b, .walking) }
                } else if abs(p.y - q.y) <= 1200, clear(a, b) {
                    connect(a, b, q.y > p.y ? .climbing : .abseiling)
                }
            }
        }
        // Flight begins with an animated push from a supported top, then clears the roof.
        for a in nodes where a.edge == .top {
            guard let p = launchPoint(from: a) else { continue }
            for b in nodes where b.edge == .top || b.edge == .floor {
                guard b.owner != a.owner, let q = TerrainSupport.resolve(b, in: terrain) else { continue }
                let drop = p.y - q.y
                if drop >= 100, abs(q.x - p.x) <= flightReach(drop), safeLanding(b, at: q), flightClear(p, q) { connect(a, b, .parachuting) }
            }
        }
    }

    /// Breadth-first route to a seeded destination. The caller varies the seed after each rest.
    public func route(from anchor: TerrainAttachment, to destination: TerrainAttachment? = nil, seed: UInt64, allowParachute: Bool = true) -> [TravelStep] {
        guard let point = TerrainSupport.resolve(anchor, in: terrain) else { return [] }
        let starts = vertices.filter { $0.owner == anchor.owner && $0.edge == anchor.edge && clear(anchor, $0) }
            .sorted { distance(point, TerrainSupport.resolve($0, in: terrain)!) < distance(point, TerrainSupport.resolve($1, in: terrain)!) }
        guard let start = starts.first else { return [] }
        var reached = [start]
        var paths: [[TravelStep]] = [[]]
        var index = 0
        while index < reached.count {
            let outgoing = steps.filter { $0.from == reached[index] && (allowParachute || $0.kind != .parachuting) }
            for step in outgoing where !reached.contains(step.to) {
                reached.append(step.to); paths.append(paths[index] + [step])
            }
            index += 1
        }
        let candidates = paths.indices.filter { !paths[$0].isEmpty && (reached[$0].edge == .top || reached[$0].edge == .floor) }
        if let destination, let goal = TerrainSupport.resolve(destination, in: terrain) {
            let matches = paths.indices.filter { reached[$0].owner == destination.owner && reached[$0].edge == destination.edge && clear(reached[$0], destination) }
            guard let match = matches.min(by: { distance(TerrainSupport.resolve(reached[$0], in: terrain)!, goal) < distance(TerrainSupport.resolve(reached[$1], in: terrain)!, goal) }) else { return [] }
            var result = paths[match]
            if distance(point, TerrainSupport.resolve(start, in: terrain)!) > 0.1 {
                result.insert(.init(from: anchor, to: start, kind: anchor.edge == .top || anchor.edge == .floor ? .walking : (TerrainSupport.resolve(start, in: terrain)!.y > point.y ? .climbing : .abseiling)), at: 0)
            }
            if distance(TerrainSupport.resolve(reached[match], in: terrain)!, goal) > 0.1 {
                let kind: TravelKind = destination.edge == .top || destination.edge == .floor ? .walking : (goal.y > TerrainSupport.resolve(reached[match], in: terrain)!.y ? .climbing : .abseiling)
                result.append(.init(from: reached[match], to: destination, kind: kind))
            }
            return result
        }
        guard destination == nil, !candidates.isEmpty else { return [] }
        // Prefer actual adventures over shuffling on the same platform whenever possible.
        let adventures = candidates.filter { paths[$0].contains { $0.kind != .walking } }
        let choices = adventures.isEmpty ? candidates : adventures
        let chosen = choices[Int(seed % UInt64(choices.count))]
        var result = paths[chosen]
        if distance(point, TerrainSupport.resolve(start, in: terrain)!) > 0.1 {
            result.insert(.init(from: anchor, to: start, kind: anchor.edge == .top || anchor.edge == .floor ? .walking : (TerrainSupport.resolve(start, in: terrain)!.y > point.y ? .climbing : .abseiling)), at: 0)
        }
        return result
    }

    public func isValid(_ step: TravelStep) -> Bool {
        guard let p = TerrainSupport.resolve(step.from, in: terrain), let q = TerrainSupport.resolve(step.to, in: terrain) else { return false }
        switch step.kind {
        case .walking: guard abs(q.y - p.y) < 0.1 else { return false }
        case .climbing: guard abs(q.x - p.x) < 0.1, q.y > p.y, q.y - p.y <= 1200 else { return false }
        case .abseiling: guard abs(q.x - p.x) < 0.1, q.y < p.y, p.y - q.y <= 1200, validRope(step.from) else { return false }
        case .mantling:
            guard step.from.owner == step.to.owner, step.to.edge == .top, [.left, .right].contains(step.from.edge), abs(q.y - p.y - EdgeTraversal.lipHeight) < 0.1, abs(abs(q.x - p.x) - 48) < 0.1 else { return false }
        case .lowering:
            guard step.from.owner == step.to.owner, step.from.edge == .top, [.left, .right].contains(step.to.edge), abs(p.y - q.y - EdgeTraversal.lipHeight) < 0.1, abs(abs(q.x - p.x) - 48) < 0.1, validRope(step.to) else { return false }
        case .parachuting: break
        }
        if step.kind == .parachuting {
            guard let launch = launchPoint(from: step.from) else { return false }
            return launch.y - q.y >= 100 && abs(q.x - launch.x) <= flightReach(launch.y - q.y) && safeLanding(step.to, at: q) && flightClear(launch, q)
        }
        return clear(step.from, step.to)
    }

    public func launchPoint(from anchor: TerrainAttachment) -> WorldPoint? {
        guard anchor.edge == .top, let p = TerrainSupport.resolve(anchor, in: terrain),
              let window = terrain.windows.first(where: { .window($0.id) == anchor.owner }) else { return nil }
        let x: Double
        if abs(p.x - window.frame.minX - 24) < 0.1 { x = p.x - 48 }
        else if abs(p.x - window.frame.maxX + 24) < 0.1 { x = p.x + 48 }
        else { return nil }
        guard x >= terrain.viewport.minX + 24, x <= terrain.viewport.maxX - 24,
              p.y + 88 <= terrain.viewport.maxY,
              let index = terrain.windows.firstIndex(where: { $0.id == window.id }) else { return nil }
        let outside = WorldPoint(x: x, y: p.y)
        for i in 0...12 {
            let point = EdgeTraversal.position(.launching, progress: Double(i) / 12, from: p, to: outside)
            let body = WorldRect(x: point.x - 23, y: point.y + 1, width: 46, height: 74)
            if terrain.windows[..<index].contains(where: { $0.frame.intersects(body) }) { return nil }
        }
        return outside
    }

    private func horizontalAnchor(_ surface: TerrainSurface, x: Double) -> TerrainAttachment {
        let base = terrain.windows.first { .window($0.id) == surface.id.owner }?.frame.minX ?? terrain.viewport.minX
        return .init(owner: surface.id.owner, edge: surface.id.edge, offset: x - base)
    }
    @discardableResult private mutating func add(_ anchor: TerrainAttachment) -> Bool {
        guard TerrainSupport.resolve(anchor, in: terrain) != nil else { return false }
        if !vertices.contains(anchor) { vertices.append(anchor) }
        return true
    }
    private mutating func connect(_ a: TerrainAttachment, _ b: TerrainAttachment, _ kind: TravelKind) {
        if kind == .abseiling && !validRope(a) { return }
        let step = TravelStep(from: a, to: b, kind: kind)
        if !steps.contains(step) { steps.append(step) }
    }
    private func distance(_ a: WorldPoint, _ b: WorldPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private func clear(_ a: TerrainAttachment, _ b: TerrainAttachment) -> Bool {
        guard let p = TerrainSupport.resolve(a, in: terrain), let q = TerrainSupport.resolve(b, in: terrain) else { return false }
        let count = max(1, Int(ceil(distance(p, q) / 12)))
        for i in 0...count {
            let t = Double(i) / Double(count)
            let corner: ExplorerMotion? = a.owner == b.owner && a.edge != b.edge ? (a.edge == .top ? .lowering : (b.edge == .top ? .mantling : nil)) : nil
            let point = corner.map { EdgeTraversal.position($0, progress: t, from: p, to: q) } ?? WorldPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
            if a.edge == b.edge && a.owner == b.owner {
                let anchor = TerrainAttachment(owner: a.owner, edge: a.edge, offset: a.offset + (b.offset - a.offset) * t)
                if TerrainSupport.resolve(anchor, in: terrain) == nil { return false }
            } else {
                let body = WorldRect(x: point.x - 23, y: point.y + 1, width: 46, height: 74)
                let supportIndex = terrain.windows.firstIndex { .window($0.id) == a.owner } ?? terrain.windows.count
                if terrain.windows[..<supportIndex].contains(where: { $0.frame.intersects(body) }) { return false }
            }
        }
        return true
    }
    private func validRope(_ anchor: TerrainAttachment) -> Bool {
        guard let window = terrain.windows.first(where: { .window($0.id) == anchor.owner }) else { return false }
        let topOffset = anchor.edge == .left ? AbseilRope.anchorInset : window.frame.width - AbseilRope.anchorInset
        return TerrainSupport.resolve(.init(owner: anchor.owner, edge: anchor.edge, offset: window.frame.height), in: terrain) != nil
            && TerrainSupport.resolve(.init(owner: anchor.owner, edge: .top, offset: topOffset), in: terrain) != nil
    }
    private func flightReach(_ drop: Double) -> Double { min(drop * 0.4, RecoveryAnimation.duration(for: drop) * 52) }
    private func safeLanding(_ anchor: TerrainAttachment, at point: WorldPoint) -> Bool {
        if anchor.edge == .floor { return true }
        return terrain.surfaces.contains { $0.id.owner == anchor.owner && $0.id.edge == .top && point.x >= $0.start.x + 40 && point.x <= $0.end.x - 40 }
    }
    private func flightClear(_ p: WorldPoint, _ q: WorldPoint) -> Bool {
        // Windows are platforms rather than solid boxes. A rear window may fill the
        // background without blocking flight in front of it; only an earlier landing matters.
        guard let (_, landing) = TerrainSupport.landing(from: p, to: q, in: terrain) else { return false }
        return distance(landing, q) < 0.1
    }
}
