import Foundation

/// A skill Jerry intends to hand to one marcher after `delay` seconds.
public struct MarcherPlan: Equatable, Sendable {
    public let marcherID: Int
    public let skill: MarcherSkill
    public let delay: Double
    /// Where the marcher is predicted to be when the skill is due.
    public let position: WorldPoint
    public let score: Double
}

/// Receding-horizon search over the deterministic marcher physics.
///
/// For one marcher it simulates doing nothing, then each skill applied now or at sampled
/// moments along that baseline path. Each outcome is scored for the marcher itself and for a
/// probe follower dropped from the hatch into the resulting terrain, so tunnels, bridges and
/// blockers that help the rest of the line are preferred. Plans are recomputed often, so a
/// window moved by the user simply produces a different answer next time.
public enum MarcherPlanner {
    public struct Options: Sendable {
        public var horizon = 20.0
        public var step = 0.15
        public var sampleInterval = 1.0
        public var lookahead = 7.5
        public var probeHorizon = 24.0
        public var probedCandidates = 4
        public var followerWeight = 0.6
        public init() {}
    }

    enum Outcome { case saved(Double), died(Double), alive }

    struct Run {
        var outcome: Outcome
        var marcher: Marcher
        var world: MarcherWorld
        /// The closest the marcher came to the exit while alive.
        var closest: Double
    }

    static let cost: [MarcherSkill: Double] = [
        .floater: 8, .climber: 14, .builder: 26, .basher: 26, .miner: 28, .digger: 28, .blocker: 70, .bomber: 400
    ]
    static let taskSkills: [MarcherSkill] = [.builder, .basher, .digger, .miner, .blocker]

    public static func plan(for id: Int, in level: MarcherLevel, options: Options = Options()) -> MarcherPlan? {
        guard let start = level.marcher(id), start.isActive, start.state != .blocking,
              let exit = level.exitPoint else { return nil }
        let context = level.context
        let followers = level.remainingToRelease > 0 || level.marchers.contains { $0.id != id && $0.isActive && $0.state != .blocking }
        let weight = followers ? options.followerWeight : 0

        // Baseline path, sampled regularly and just before each edge, wall or turn.
        var samples: [Sample] = []
        var previous: Sample?
        let workers = level.marchers.filter { $0.id != id && $0.isWorking }
        let base = simulate(start, world: level.world, workers: workers, context: context, duration: options.horizon, step: options.step) { time, marcher, world, workers in
            guard time <= options.lookahead + 0.001 else { return false }
            let current = Sample(time: time, marcher: marcher, world: world, workers: workers)
            defer { previous = current }
            if let previous, previous.marcher.state != marcher.state || previous.marcher.direction != marcher.direction,
               previous.time - (samples.last?.time ?? -1) > 0.2 {
                samples.append(previous)
            }
            if time - (samples.last?.time ?? -.infinity) >= options.sampleInterval - 0.001 { samples.append(current) }
            return true
        }
        if case .saved = base.outcome { return nil }
        let baseProbe = followers ? probe(level: level, world: base.world, context: context, extra: nil, climber: false, options: options) : 0
        let baseline = value(base, offset: 0, exit: exit) + weight * baseProbe

        struct Candidate {
            var skill: MarcherSkill
            var sample: Sample
            var run: Run
            var umbrellaFirst: Bool
            var preliminary: Double
        }
        var candidates: [Candidate] = []
        func add(_ skill: MarcherSkill, _ sample: Sample, _ run: Run, umbrellaFirst: Bool = false) {
            let extra = umbrellaFirst ? (cost[.floater] ?? 8) : 0
            let score = value(run, offset: sample.time, exit: exit) - (cost[skill] ?? 30) - extra - sample.time * 0.5
            candidates.append(Candidate(skill: skill, sample: sample, run: run, umbrellaFirst: umbrellaFirst, preliminary: score))
        }

        let now = Sample(time: 0, marcher: start, world: level.world, workers: workers)
        var best: (score: Double, plan: MarcherPlan)?
        func offer(_ score: Double, _ skill: MarcherSkill, _ sample: Sample) {
            if score > (best?.score ?? -.infinity) {
                best = (score, MarcherPlan(marcherID: id, skill: skill, delay: sample.time, position: sample.marcher.position, score: score))
            }
        }
        for skill in [MarcherSkill.floater, .climber] where level.canAssign(skill, to: id) {
            var marcher = start
            guard marcher.take(skill) else { continue }
            let run = simulate(marcher, world: level.world, workers: workers, context: context, duration: options.horizon, step: options.step)
            // Permanent abilities change nothing for followers, so they share the baseline probe.
            let probeScore = baseProbe
            offer(value(run, offset: 0, exit: exit) + weight * probeScore - (cost[skill] ?? 10), skill, now)
        }

        for sample in samples {
            for skill in taskSkills where (level.stock[skill] ?? 0) > 0 {
                var marcher = sample.marcher
                guard marcher.canTake(skill), marcher.take(skill) else { continue }
                if skill == .blocker, context.blockers.contains(where: { abs($0.x - marcher.x) < 10 && abs($0.y - marcher.y) < 10 }) { continue }
                let run = simulate(marcher, world: sample.world, workers: sample.workers, context: context, duration: options.horizon - sample.time, step: options.step)
                add(skill, sample, run)
                // A task that ends in a fatal fall may still be right with an umbrella first.
                if run.marcher.state == .splatting, !start.isFloater, level.canAssign(.floater, to: id) {
                    marcher.isFloater = true
                    add(skill, sample, simulate(marcher, world: sample.world, workers: sample.workers, context: context, duration: options.horizon - sample.time, step: options.step), umbrellaFirst: true)
                }
            }
        }

        // Only the most promising terrain changes, and a spread of blocker positions, get a follower probe.
        var probed: [Int] = []
        if followers {
            let ranked = candidates.indices.filter { candidates[$0].skill != .blocker }.sorted { candidates[$0].preliminary > candidates[$1].preliminary }
            probed += ranked.prefix(options.probedCandidates)
            let blockers = candidates.indices.filter { candidates[$0].skill == .blocker }
            if !blockers.isEmpty {
                let picks = Set([0, blockers.count / 3, (2 * blockers.count) / 3, blockers.count - 1])
                probed += picks.sorted().map { blockers[$0] }
            }
        } else {
            probed = Array(candidates.indices)
        }
        for index in probed {
            let candidate = candidates[index]
            var probeScore = 0.0
            if followers {
                let extra = candidate.run.marcher.state == .blocking ? (id, candidate.run.marcher.x, candidate.run.marcher.y) : nil
                probeScore = probe(level: level, world: candidate.run.world, context: context, extra: extra, climber: false, options: options)
            }
            let score = candidate.preliminary + weight * probeScore
            offer(score, candidate.umbrellaFirst ? .floater : candidate.skill, candidate.umbrellaFirst ? now : candidate.sample)
        }
        guard let best, best.score > baseline + 5 else { return nil }
        return best.plan
    }

    struct Sample {
        var time: Double
        var marcher: Marcher
        var world: MarcherWorld
        var workers: [Marcher]
    }

    /// Simulates one marcher alone. `observe` sees each step and returns false to stop sampling.
    /// A walker that turns again at a spot where it already turned is pacing, so the run stops early.
    /// Other marchers already digging, bashing, mining or building carry on alongside, so their
    /// unfinished tunnels and bridges are part of the terrain the marcher meets.
    static func simulate(_ marcher: Marcher, world: MarcherWorld, workers: [Marcher], context: MarcherPhysics.Context, duration: Double, step: Double,
                         observe: ((Double, Marcher, MarcherWorld, [Marcher]) -> Bool)? = nil) -> Run {
        var marcher = marcher, world = world, time = 0.0, workers = workers
        var observing = observe != nil
        let exit = context.exit
        func distance(_ m: Marcher) -> Double { exit.map { hypot(Double(m.x) - $0.x, Double(m.y) - $0.y) } ?? 0 }
        var closest = distance(marcher)
        var turns: [(x: Int, y: Int, direction: Int)] = []
        if observing { observing = observe!(0, marcher, world, workers) }
        while time < duration {
            if !workers.isEmpty {
                for index in workers.indices { MarcherPhysics.step(&workers[index], by: step, world: &world, context: context) }
                workers.removeAll { !$0.isWorking }
            }
            let direction = marcher.direction, revision = world.revision
            MarcherPhysics.step(&marcher, by: step, world: &world, context: context)
            time += step
            switch marcher.state {
            case .exiting, .saved: return Run(outcome: .saved(time), marcher: marcher, world: world, closest: 0)
            case .splatting, .exploding, .lost: return Run(outcome: .died(time), marcher: marcher, world: world, closest: closest)
            default: closest = min(closest, distance(marcher))
            }
            if observing { observing = observe!(time, marcher, world, workers) }
            if !observing, workers.isEmpty, marcher.state == .walking, marcher.direction != direction, world.revision == revision {
                let turn = (x: marcher.x, y: marcher.y, direction: marcher.direction)
                if turns.contains(where: { $0.direction == turn.direction && abs($0.x - turn.x) <= 2 && abs($0.y - turn.y) <= 2 }) { break }
                turns.append(turn)
            }
        }
        return Run(outcome: .alive, marcher: marcher, world: world, closest: closest)
    }

    static func value(_ run: Run, offset: Double, exit: WorldPoint) -> Double {
        switch run.outcome {
        case .saved(let time): return 1000 - (time + offset) * 3
        case .died(let time): return -1000 + min(60, time + offset)
        case .alive:
            // Still wandering: credit the best progress made towards the exit.
            return -60 - min(400, run.closest / 4)
        }
    }

    /// How a fresh follower from the hatch fares in the given terrain. Followers are assumed
    /// to receive umbrellas when needed, so this measures the route rather than single falls.
    static func probe(level: MarcherLevel, world: MarcherWorld, context: MarcherPhysics.Context,
                      extra: (id: Int, x: Int, y: Int)?, climber: Bool, options: Options) -> Double {
        guard let exit = context.exit else { return 0 }
        var context = context
        if let extra { context.blockers.append(extra) }
        let spawn = level.spawnPoint
        var follower = Marcher(id: -1, x: spawn.x, y: spawn.y, direction: 1)
        follower.isFloater = true
        follower.isClimber = climber
        MarcherPhysics.unbury(&follower, world: world)
        let run = simulate(follower, world: world, workers: [], context: context, duration: options.probeHorizon, step: options.step)
        return value(run, offset: 0, exit: exit)
    }
}
