import Foundation

public enum ExplorerActivity: String, CaseIterable, Sendable {
    case walk, climb, abseil, grapple, ropeClimb, swing, releaseRope, parachute, bananaAdventure, automatic
    public var title: String {
        switch self {
        case .walk: return "Walk"
        case .climb: return "Climb a window"
        case .abseil: return "Abseil"
        case .grapple: return "Grappling hook"
        case .ropeClimb: return "Climb rope"
        case .swing: return "Swing on rope"
        case .releaseRope: return "Release rope"
        case .parachute: return "Parachute"
        case .bananaAdventure: return "Find the sock"
        case .automatic: return "Automatic adventures"
        }
    }
    var travelKind: TravelKind? {
        switch self { case .walk: return .walking; case .climb: return .climbing; case .abseil: return .abseiling; case .parachute: return .parachuting; case .grapple, .ropeClimb, .swing: return .grappling; default: return nil }
    }
}

extension NavigationGraph {
    /// Find the nearest reachable approach, perform the requested activity, and finish
    /// on standing terrain. Never teleport to a demonstration or invent a support.
    public func activityRoute(_ activity: ExplorerActivity, from source: TerrainAttachment) -> [TravelStep]? {
        guard let kind = activity.travelKind, let origin = TerrainSupport.resolve(source, in: terrain) else { return nil }
        var best: [TravelStep]?, bestCost = Double.infinity
        let directShots = kind == .grappling ? grappleSteps(from: source) : []
        for step in (directShots + steps.filter { $0.kind == kind }) {
            guard let start = TerrainSupport.resolve(step.from, in: terrain), let end = TerrainSupport.resolve(step.to, in: terrain) else { continue }
            if kind == .walking && (step.from.edge != .top && step.from.edge != .floor || hypot(end.x - start.x, end.y - start.y) < 60) { continue }
            let prefix = hypot(origin.x - start.x, origin.y - start.y) < 0.1 ? [] : route(from: source, to: step.from, seed: 0, allowParachute: false)
            if prefix.isEmpty && hypot(origin.x - start.x, origin.y - start.y) >= 0.1 { continue }
            var plan = prefix + [step]
            if step.to.edge == .left || step.to.edge == .right {
                guard let finish = steps.first(where: { $0.from == step.to && ($0.to.edge == .top || $0.to.edge == .floor) }) else { continue }
                plan.append(finish)
            }
            guard plan.allSatisfy({ isValid($0) }) else { continue }
            let cost = plan.reduce(0.0) { cost, leg in
                guard let a = TerrainSupport.resolve(leg.from, in: terrain), let b = TerrainSupport.resolve(leg.to, in: terrain) else { return Double.infinity }
                switch leg.kind {
                case .mantling, .lowering: return cost + 1.35
                case .grappling: return cost + 3.5 + max(0, b.y - a.y) / 24
                case .parachuting: return cost + 1 + RecoveryAnimation.duration(for: max(0, a.y - b.y))
                default: return cost + hypot(a.x - b.x, a.y - b.y) / (leg.kind == .walking ? 40 : (leg.kind == .climbing ? 24 : 48))
                }
            }
            if cost < bestCost { bestCost = cost; best = plan }
        }
        return best
    }
}
