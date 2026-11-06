import Foundation

/// An interruptible, deterministic comic sequence. No asynchronous animation callbacks:
/// every beat is driven by the same fixed simulation clock as movement.
public struct BananaMission {
    public enum Stage: String, CaseIterable, Sendable {
        case selecting, spotting, approaching, crossing, investigating, revealing, updatingMap, resting
    }
    public private(set) var stage: Stage = .selecting
    public private(set) var target: TerrainAttachment?
    public private(set) var completedExpeditions = 0
    public private(set) var elapsed: Double = 0
    private var planned: [TravelStep] = []
    private var crossing: [TravelStep] = []
    private var generation: UInt64 = 0

    public init() {}

    public mutating func advance(by dt: Double, explorer: inout ExplorerInteraction, terrain: TerrainSnapshot) {
        guard dt.isFinite, dt > 0 else { return }
        // A grab cancels the entire beat and its old destination. A drop starts a new expedition.
        if explorer.state == .held {
            reset()
            return
        }
        if explorer.state == .recovering && stage != .crossing {
            reset()
            return
        }
        if let target, TerrainSupport.resolve(target, in: terrain) == nil {
            reset()
            return
        }
        if stage == .approaching || stage == .crossing {
            if explorer.state == .recovering {
                // A planned flight has no remaining surface route; wait for its swept landing.
                if stage == .approaching { reset() }
                return
            }
            if explorer.state != .idle && explorer.state != .settling { return }
            guard !explorer.hasPendingTravel else { return }
            if stage == .approaching {
                if crossing.isEmpty { transition(.investigating) }
                else if explorer.follow(crossing) { transition(.crossing) }
                else { reset() }
            } else if let target, let goal = TerrainSupport.resolve(target, in: terrain),
                      abs(explorer.position.y - goal.y) < 2 && abs(explorer.position.x - goal.x) <= 38 {
                transition(.investigating)
            } else { reset() }
            return
        }
        guard explorer.state == .idle || explorer.state == .settling else { return }
        elapsed += dt
        switch stage {
        case .selecting:
            guard elapsed >= 2, let anchor = explorer.attachment else { return }
            let graph = NavigationGraph(terrain: terrain)
            // Usually favour a chute, but occasionally let the rope expert have a turn.
            let allowFlight = generation % 3 != 2
            var choices: [(TerrainAttachment, [TravelStep])] = []
            for destination in graph.vertices where destination.edge.isStandable {
                guard let point = TerrainSupport.resolve(destination, in: terrain),
                      hypot(point.x - explorer.position.x, point.y - explorer.position.y) > 80 else { continue }
                // Stop beside the discovery rather than standing on top of the prop.
                let direction: Double = explorer.position.x < point.x ? -1 : 1
                let arrivals = [direction, -direction].map { TerrainAttachment(owner: destination.owner, edge: destination.edge, offset: destination.offset + $0 * 32, featureID: destination.featureID) }
                for arrival in arrivals {
                    guard let stand = TerrainSupport.resolve(arrival, in: terrain), abs(stand.x - point.x) >= 28 else { continue }
                    let route = graph.route(from: anchor, to: arrival, seed: 1, allowParachute: allowFlight, allowGrapple: generation % 4 == 3)
                    if !route.isEmpty { choices.append((destination, route)); break }
                }
            }
            if choices.isEmpty {
                if anchor.edge.isInternal {
                    _ = explorer.follow(graph.route(from: anchor, seed: generation))
                    generation &+= 1
                }
                elapsed = 0; return
            }
            // Prefer parachuting when a safe launch/landing pair is actually reachable.
            let flights = choices.filter { $0.1.contains { $0.kind == .parachuting } }
            let candidates = flights.isEmpty ? choices : flights
            let choice = candidates[Int(generation % UInt64(candidates.count))]
            generation &+= 1
            target = choice.0
            planned = choice.1
            transition(.spotting)
        case .spotting:
            guard elapsed >= 1.8 else { return }
            if let launch = planned.firstIndex(where: { $0.kind == .parachuting }) {
                crossing = Array(planned[launch...])
                let approach = Array(planned[..<launch])
                if approach.isEmpty {
                    if explorer.follow(crossing) { transition(.crossing) } else { reset() }
                } else if explorer.follow(approach) { transition(.approaching) }
                else { reset() }
            } else {
                crossing = []
                if explorer.follow(planned) { transition(.crossing) } else { reset() }
            }
        case .investigating:
            if elapsed >= 2 { transition(.revealing) }
        case .revealing:
            if elapsed >= 2.8 { transition(.updatingMap) }
        case .updatingMap:
            if elapsed >= 2 { completedExpeditions += 1; transition(.resting) }
        case .resting:
            if elapsed >= 5 { reset() }
        case .approaching, .crossing: break
        }
    }

    public mutating func cancel() { reset() }

    private mutating func transition(_ next: Stage) { stage = next; elapsed = 0 }
    private mutating func reset() {
        target = nil
        planned.removeAll()
        crossing.removeAll()
        transition(.selecting)
    }
}
