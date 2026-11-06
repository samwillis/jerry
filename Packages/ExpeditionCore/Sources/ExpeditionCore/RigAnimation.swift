import Foundation

public enum ExplorerMotion: String, CaseIterable, Sendable {
    case idle, walking, running, jumping, climbing, abseiling, grappling, ropeClimbing, ropeSwinging, parachuting, mantling, lowering, launching, held, investigating, landing, comic
}

public enum RecoveryAnimation {
    public static let deploymentStart: Double = 0.18
    public static let deploymentDuration: Double = 0.55
    public static let freeFallSpeed: Double = 270
    public static let openChuteSpeed: Double = 140

    public static func duration(for distance: Double, startingAt time: Double = 0) -> Double {
        var low = 0.0, high = max(0, distance) / openChuteSpeed + 1
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if self.distance(from: time, to: time + middle) < distance { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    public static func deployment(at time: Double) -> Double {
        let u = min(max((time - deploymentStart) / deploymentDuration, 0), 1)
        return u * u * (3 - 2 * u)
    }

    /// Integrating the speed makes travel independent of the size of simulation steps.
    public static func distance(from start: Double, to end: Double) -> Double {
        func travelled(_ time: Double) -> Double {
            let t = max(0, time)
            let u = min(max((t - deploymentStart) / deploymentDuration, 0), 1)
            let opening = deploymentDuration * (freeFallSpeed * u - (freeFallSpeed - openChuteSpeed) * (pow(u, 3) - 0.5 * pow(u, 4)))
            return freeFallSpeed * min(t, deploymentStart) + opening + openChuteSpeed * max(0, t - deploymentStart - deploymentDuration)
        }
        return max(0, travelled(end) - travelled(start))
    }
}

public enum BlinkAnimation {
    /// Slightly irregular, repeatable timing. Adjacent entries occasionally produce a double blink.
    public static func openness(time: Double, eye: Int) -> Double {
        guard time.isFinite, time >= 0 else { return 1 }
        let clock = time.truncatingRemainder(dividingBy: 38)
        let starts = [2.4, 6.7, 12.1, 15.8, 21.3, 21.63, 27.0, 32.5]
        for (index, start) in starts.enumerated() {
            let delay = eye == index % 2 ? 0.0 : 0.018
            let t = clock - start - delay
            guard t >= 0, t < 0.21 else { continue }
            func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
            if t < 0.065 { return max(0.08, 1 - smooth(t / 0.065)) }
            if t < 0.08 { return 0.08 }
            return max(0.08, smooth((t - 0.08) / 0.13))
        }
        return 1
    }
}

public enum LandingAnimation {
    public static let duration: Double = 0.36

    public static func apply(to source: ExplorerPose, elapsed: Double, strength: Double = 1) -> ExplorerPose {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return source }
        func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
        let amount = elapsed < 0.08 ? smooth(elapsed / 0.08) : 1 - smooth((elapsed - 0.08) / 0.28)
        let compression = 4 * amount * min(max(strength, 0), 1)
        var pose = source
        pose.hips.y -= compression
        pose.leftHand.y -= compression
        pose.rightHand.y -= compression
        pose.leftFoot.y = 0
        pose.rightFoot.y = 0
        pose.backpackTilt += amount * 0.06
        return pose
    }
}

public struct LimbSolution {
    public let joint: WorldPoint
    public let end: WorldPoint
    public let isClamped: Bool
}

public enum TwoBoneIK {
    public static func solve(root: WorldPoint, target: WorldPoint, upper: Double, lower: Double, bend: Double = 1, pole: WorldPoint? = nil) -> LimbSolution {
        guard upper > 0, lower > 0, upper.isFinite, lower.isFinite,
              root.x.isFinite, root.y.isFinite, target.x.isFinite, target.y.isFinite else {
            return .init(joint: root, end: root, isClamped: true)
        }
        let dx = target.x - root.x, dy = target.y - root.y
        let distance = hypot(dx, dy)
        let reach = min(max(distance, abs(upper - lower) + 0.000001), upper + lower - 0.000001)
        let ux = distance > 0.000001 ? dx / distance : 0
        let uy = distance > 0.000001 ? dy / distance : -1
        let along = (upper * upper - lower * lower + reach * reach) / (2 * reach)
        // A pole expresses anatomical direction instead of assigning unrelated left/right signs.
        // In the canonical facing, knee poles are ahead of the body and elbow poles behind it.
        var direction = bend < 0 ? -1.0 : 1.0
        if let pole, pole.x.isFinite, pole.y.isFinite {
            let cross = dx * (pole.y - root.y) - dy * (pole.x - root.x)
            if abs(cross) > 0.000001 { direction = cross < 0 ? -1 : 1 }
        }
        let sideways = sqrt(max(0, upper * upper - along * along)) * direction
        return .init(
            joint: .init(x: root.x + ux * along - uy * sideways, y: root.y + uy * along + ux * sideways),
            end: .init(x: root.x + ux * reach, y: root.y + uy * reach),
            isClamped: abs(reach - distance) > 0.00001
        )
    }
}

public struct AnimationTuning: Sendable {
    public var cadence: Double = 1
    public var stride: Double = 10
    public var bounce: Double = 1
    public var blendDuration: Double = 0.2
    public init() {}
}

public struct ExplorerPose: Sendable {
    public init() {}
    public var hips = WorldPoint(x: 0, y: ExpeditionConfiguration.standingHipHeight)
    public var leftHand = WorldPoint(x: -20, y: 31.5)
    public var rightHand = WorldPoint(x: 20, y: 31.5)
    public var leftFoot = WorldPoint(x: -8, y: 0)
    public var rightFoot = WorldPoint(x: 8, y: 0)
    public var headTilt: Double = 0
    public var backpackTilt: Double = 0
    public var sway: Double = 0
    public var elbowPole = WorldPoint(x: -24, y: -6)
    public var leftElbowBend: Double?
    public var rightElbowBend: Double?

    public func blended(from other: ExplorerPose, fraction: Double) -> ExplorerPose {
        let f = min(max(fraction, 0), 1)
        func point(_ a: WorldPoint, _ b: WorldPoint) -> WorldPoint { .init(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f) }
        func value(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        var pose = self
        pose.hips = point(other.hips, hips)
        pose.leftHand = point(other.leftHand, leftHand)
        pose.rightHand = point(other.rightHand, rightHand)
        pose.leftFoot = point(other.leftFoot, leftFoot)
        pose.rightFoot = point(other.rightFoot, rightFoot)
        pose.headTilt = value(other.headTilt, headTilt)
        pose.backpackTilt = value(other.backpackTilt, backpackTilt)
        pose.sway = value(other.sway, sway)
        pose.elbowPole = point(other.elbowPole, elbowPole)
        pose.leftElbowBend = f < 0.5 ? other.leftElbowBend : leftElbowBend
        pose.rightElbowBend = f < 0.5 ? other.rightElbowBend : rightElbowBend
        return pose
    }

    public mutating func translate(x: Double = 0, y: Double = 0) {
        hips.x += x; leftHand.x += x; rightHand.x += x; leftFoot.x += x; rightFoot.x += x
        hips.y += y; leftHand.y += y; rightHand.y += y; leftFoot.y += y; rightFoot.y += y
    }
}

public enum AnimationClips {
    public static func sample(_ motion: ExplorerMotion, time: Double, tuning: AnimationTuning) -> ExplorerPose {
        let t = max(0, time), phase = t * 2 * Double.pi * max(0.1, tuning.cadence)
        var pose = ExplorerPose()
        switch motion {
        case .idle:
            pose.hips.y += sin(phase * 0.4) * 0.15 * tuning.bounce
            pose.headTilt = sin(phase * 0.2) * 0.035
        case .running:
            pose = RunningGait.pose(at: t)
        case .jumping:
            pose = JumpAnimation.previewPose(at: t)
        case .walking:
            let stride = min(max(tuning.stride, 0), 12)
            // A lifted foot swings towards +x; a planted foot moves backwards relative to the body.
            pose.leftFoot = .init(x: -7 - cos(phase) * stride, y: max(0, sin(phase)) * 6)
            pose.rightFoot = .init(x: 7 + cos(phase) * stride, y: max(0, -sin(phase)) * 6)
            // Keep the planted leg almost extended. Lower the hips only as the stride widens.
            let reach = ExpeditionConfiguration.legSegmentLength * 2 - 0.3
            func hipLimit(foot: WorldPoint, hipX: Double) -> Double {
                let dx = foot.x - hipX
                return foot.y + ExpeditionConfiguration.ankleHeight + sqrt(max(0, reach * reach - dx * dx))
            }
            pose.hips.y = min(hipLimit(foot: pose.leftFoot, hipX: -7), hipLimit(foot: pose.rightFoot, hipX: 7)) - abs(sin(phase)) * 0.1 * tuning.bounce
            let lift = pose.hips.y - ExpeditionConfiguration.standingHipHeight
            pose.leftHand.y += lift
            pose.rightHand.y += lift
            pose.leftHand.x -= sin(phase) * 4
            pose.rightHand.x += sin(phase) * 4
            pose.backpackTilt = sin(phase + 0.5) * 0.08 * tuning.bounce
        case .climbing:
            pose.hips.x = 8
            pose.hips.y = 27 + sin(phase * 0.5) * 1.5 * tuning.bounce
            // Fixed contacts while the body shifts; the playground can move these handholds.
            pose.leftHand = .init(x: 20, y: 55)
            pose.rightHand = .init(x: 20, y: 65)
            pose.leftFoot = .init(x: 20, y: 12)
            pose.rightFoot = .init(x: 20, y: 0)
            pose.headTilt = -0.08
        case .abseiling:
            pose.hips.x = -2
            pose.elbowPole = .init(x: 24, y: -16)
            pose.leftHand = .init(x: 0, y: 61)
            pose.rightHand = .init(x: 8, y: 62)
            pose.leftFoot = .init(x: 10, y: 9)
            pose.rightFoot = .init(x: 20, y: 11)
            pose.backpackTilt = 0.1 + sin(phase * 0.4) * 0.03
        case .grappling:
            pose.leftHand = .init(x: 12, y: 46); pose.rightHand = .init(x: 5, y: 42)
            pose.headTilt = 0.08
        case .ropeClimbing, .ropeSwinging:
            pose = RopeAnimation.pose(mode: motion == .ropeClimbing ? .climbing : .swinging, direction: .init(x: 0.3, y: 0.95), velocity: .zero, pullTime: t)
        case .parachuting:
            // First half-second is the crouch/launch anticipation.
            let launch = min(t * 2, 1)
            pose.hips.y -= (1 - launch) * 5
            pose.leftHand = .init(x: -17, y: 66)
            pose.rightHand = .init(x: 17, y: 66)
            pose.leftFoot.y += 1.5 + sin(phase * 0.45) * 1.5
            pose.rightFoot.y += 1.5 - sin(phase * 0.45) * 1.5
            pose.sway = sin(phase * 0.3) * 0.06
        case .mantling, .lowering, .launching:
            let duration = EdgeTraversal.duration(motion)
            let progress = min(t.truncatingRemainder(dividingBy: duration + 1) / duration, 1)
            pose = EdgeTraversal.pose(motion, progress: progress)
        case .held:
            pose.leftHand = .init(x: -16, y: 29.5 + sin(phase * 0.8))
            pose.rightHand = .init(x: 16, y: 29.5 - sin(phase * 0.8))
            pose.leftFoot.x += sin(phase * 0.6) * 3
            pose.rightFoot.x += sin(phase * 0.6 + 0.4) * 3
            pose.headTilt = -0.08
            pose.backpackTilt = sin(phase * 0.6 + 0.7) * 0.1 * tuning.bounce
            pose.sway = sin(phase * 0.6) * 0.13
        case .investigating:
            pose.headTilt = -0.25 + sin(phase * 0.3) * 0.06
            pose.leftHand = .init(x: -4, y: 56)
            pose.rightHand = .init(x: 13, y: 58)
            pose.hips.y -= 1
        case .landing:
            pose = LandingAnimation.apply(to: pose, elapsed: t.truncatingRemainder(dividingBy: 2.5) - 0.6)
        case .comic:
            let beat = t.truncatingRemainder(dividingBy: 9)
            if beat < 2 {
                pose = sample(.walking, time: t, tuning: tuning)
                pose.translate(x: -40 + beat * 20)
            } else if beat < 3.5 {
                pose = sample(.investigating, time: beat - 2, tuning: tuning)
                pose.headTilt = -0.4
            } else if beat < 5 {
                pose = sample(.walking, time: t, tuning: tuning)
                pose.translate(x: -(beat - 3.5) * 12)
                pose.headTilt = 0.2
            } else {
                pose = sample(.held, time: beat - 5, tuning: tuning)
                pose.translate(x: -18, y: min((beat - 5) * 2, 1) * 18)
                var beforeGrab = sample(.walking, time: 5, tuning: tuning)
                beforeGrab.translate(x: -18)
                beforeGrab.headTilt = 0.2
                pose = pose.blended(from: beforeGrab, fraction: min((beat - 5) / 0.3, 1))
            }
        }
        return pose
    }
}

/// Numeric blending only: no asynchronous completion callbacks can survive an interruption.
public struct RigAnimator {
    public private(set) var motion: ExplorerMotion = .idle
    public private(set) var pose = ExplorerPose()
    public private(set) var time: Double = 0
    public var tuning = AnimationTuning()
    private var transitionFrom = ExplorerPose()
    private var blendTime: Double = 1
    public init() {}

    public mutating func seek(to time: Double) {
        self.time = time.isFinite ? max(0, time) : 0
        pose = AnimationClips.sample(motion, time: self.time, tuning: tuning)
        transitionFrom = pose
        blendTime = max(0, tuning.blendDuration)
    }

    public mutating func select(_ motion: ExplorerMotion, restart: Bool = false, from presentedPose: ExplorerPose? = nil) {
        guard motion != self.motion || restart else { return }
        if restart {
            self.motion = motion
            time = 0
            blendTime = max(0, tuning.blendDuration)
            pose = AnimationClips.sample(motion, time: 0, tuning: tuning)
            transitionFrom = pose
            return
        }
        transitionFrom = presentedPose ?? pose
        self.motion = motion
        time = 0
        blendTime = 0
    }

    @discardableResult public mutating func advance(by elapsed: Double, synchronizedTime: Double? = nil) -> ExplorerPose {
        let dt = elapsed.isFinite ? min(max(elapsed, 0), 0.1) : 0
        time = synchronizedTime ?? (time + dt)
        blendTime += dt
        let fraction = tuning.blendDuration > 0 ? min(blendTime / tuning.blendDuration, 1) : 1
        let smooth = fraction * fraction * (3 - 2 * fraction)
        pose = AnimationClips.sample(motion, time: time, tuning: tuning).blended(from: transitionFrom, fraction: smooth)
        return pose
    }
}

/// Wall-relative contacts: stance targets follow the support while the body climbs past them.
/// Near/far hand heights account for the rig's offset shoulders and finite arm reach.
public struct ClimbingContacts {
    public let leftHand: WorldPoint
    public let rightHand: WorldPoint
    public let leftFoot: WorldPoint
    public let rightFoot: WorldPoint
    public init(heightAlongWall: Double) {
        func contact(height: Double, offset: Double, x: Double = 20) -> WorldPoint {
            let cycle = (heightAlongWall + offset) / 24
            let phase = cycle - floor(cycle)
            let swing = max(0, (phase - 0.65) / 0.35)
            let lift = swing * swing * (3 - 2 * swing) * 24
            return .init(x: x - sin(swing * .pi) * 5, y: height - phase * 24 + lift)
        }
        leftHand = contact(height: 55, offset: 0)
        rightHand = contact(height: 65, offset: 12)
        leftFoot = contact(height: 18, offset: 12, x: 14)
        rightFoot = contact(height: 18, offset: 0, x: 14)
    }
}

/// Integral of the backward travel of whichever foot is in stance. The existing
/// cosine gait travels 2×stride in each half-cycle: 40 pt/s at stride 10, cadence 1.
public enum WalkingGait {
    public static func distance(from start: Double, to end: Double, tuning: AnimationTuning = .init()) -> Double {
        func travelled(_ time: Double) -> Double {
            let stride = min(max(tuning.stride, 0), 12)
            let cycle = max(0, time) * max(0.1, tuning.cadence)
            let turns = floor(cycle), angle = (cycle - turns) * 2 * Double.pi
            return turns * 4 * stride + stride * (angle <= .pi ? 1 - cos(angle) : 3 + cos(angle))
        }
        return max(0, travelled(end) - travelled(start))
    }
}

/// Named, interruptible corner beats shared by desktop movement and the playground.
public enum EdgeTraversal {
    public static let lipHeight = 52.0
    public static func duration(_ motion: ExplorerMotion) -> Double { motion == .launching ? 1.0 : 1.35 }
    private static func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    public static func position(_ motion: ExplorerMotion, progress: Double, from: WorldPoint, to: WorldPoint) -> WorldPoint {
        let p = min(max(progress, 0), 1)
        if motion == .lowering { return position(.mantling, progress: 1 - p, from: to, to: from) }
        if motion == .launching {
            let u = smooth((p - 0.3) / 0.7)
            return .init(x: from.x + (to.x - from.x) * u, y: from.y + sin(.pi * u) * 12)
        }
        let keys = [0.0, 0.4, 0.7, 1.0], xs = [0.0, 0, 28.0 / 48, 1], ys = [0.0, 28.0 / 52, 45.0 / 52, 1]
        let i = min(keys.count - 2, keys.firstIndex(where: { $0 > p }).map { max(0, $0 - 1) } ?? keys.count - 2)
        let f = smooth((p - keys[i]) / (keys[i + 1] - keys[i]))
        return .init(x: from.x + (to.x - from.x) * (xs[i] + (xs[i + 1] - xs[i]) * f), y: from.y + (to.y - from.y) * (ys[i] + (ys[i + 1] - ys[i]) * f))
    }

    public static func pose(_ motion: ExplorerMotion, progress: Double) -> ExplorerPose {
        let p = min(max(progress, 0), 1)
        if motion == .lowering { return pose(.mantling, progress: 1 - p) }
        let idle = ExplorerPose()
        var a = idle, b = idle, c = idle
        let keys: [Double], poses: [ExplorerPose]
        if motion == .launching {
            a.hips.y = 25.5; a.leftHand = .init(x: -19, y: 35); a.rightHand = .init(x: 14, y: 36); a.headTilt = -0.12
            b.hips.y = 31; b.leftFoot.y = 3; b.rightFoot.y = 2; b.leftHand = .init(x: -8, y: 55); b.rightHand = .init(x: 18, y: 56)
            c = AnimationClips.sample(.parachuting, time: 0, tuning: .init())
            keys = [0, 0.3, 0.55, 1]; poses = [idle, a, b, c]
        } else {
            a.hips = .init(x: 10, y: 28); a.leftHand = .init(x: 22, y: 52); a.rightHand = .init(x: 23, y: 55)
            a.leftFoot = .init(x: 14, y: 18); a.rightFoot = .init(x: 14, y: 6); a.headTilt = -0.15
            b.hips = .init(x: 12, y: 14); b.leftHand = .init(x: 22, y: 24); b.rightHand = .init(x: 23, y: 26)
            b.leftFoot = .init(x: 16, y: 0); b.rightFoot = .init(x: 18, y: -4); b.headTilt = -0.3; b.backpackTilt = 0.12
            c.hips = .init(x: 0, y: 24); c.leftHand = .init(x: -12, y: 38); c.rightHand = .init(x: 18, y: 45)
            c.leftFoot = .init(x: 12, y: 7); c.rightFoot = .init(x: 14, y: 13); c.headTilt = -0.15
            keys = [0, 0.4, 0.7, 1]; poses = [a, b, c, idle]
        }
        let i = min(keys.count - 2, keys.firstIndex(where: { $0 > p }).map { max(0, $0 - 1) } ?? keys.count - 2)
        return poses[i + 1].blended(from: poses[i], fraction: smooth((p - keys[i]) / (keys[i + 1] - keys[i])))
    }
}

/// Each alternating hand pull lifts 12 points. The body slows at hand exchanges
/// and rises fastest during the loaded part of the pull (24 points per full cycle).
public enum ClimbingGait {
    public static func height(at time: Double) -> Double {
        let turns = floor(time), angle = (time - turns) * 2 * Double.pi
        return turns * 24 + 6 * (angle <= .pi ? 1 - cos(angle) : 3 + cos(angle))
    }
    public static func time(atHeight height: Double) -> Double {
        let turns = floor(height / 24), part = height - turns * 24
        let angle = part <= 12 ? acos(min(1, max(-1, 1 - part / 6))) : 2 * Double.pi - acos(min(1, max(-1, part / 6 - 3)))
        return turns + angle / (2 * .pi)
    }
    public static func distance(from start: Double, to end: Double) -> Double { max(0, height(at: end) - height(at: start)) }
}


public enum RopeAnimation {
    public static func pose(mode: RopeSession.Mode, direction: WorldPoint, velocity: WorldPoint, pullTime: Double) -> ExplorerPose {
        var pose = AnimationClips.sample(mode == .descending ? .abseiling : .held, time: pullTime, tuning: .init())
        pose.hips.x = 0
        pose.sway = min(0.4, max(-0.4, -atan2(direction.x, max(0.1, direction.y)) * 0.35))
        let c = cos(pose.sway), s = sin(pose.sway)
        let u = WorldPoint(x: c * direction.x + s * direction.y, y: -s * direction.x + c * direction.y)
        func distance(_ upper: Double, offset: Double, shoulderX: Double, handX: Double) -> Double {
            guard mode == .climbing else { return upper }
            // Keep the far glove inside its shoulder as the line leans: crossing
            // that shoulder would reverse the arm's hinge during each hand swap.
            let sideLimit = u.x * shoulderX > 0 ? (abs(shoulderX - handX) - 1) / max(0.001, abs(u.x)) : 30
            let base = WorldPoint(x: shoulderX - handX, y: pose.hips.y + 20 - RopeSession.harnessHeight)
            let along = base.x * u.x + base.y * u.y
            let perpendicularSquared = base.x * base.x + base.y * base.y - along * along
            let reachLimit = along + sqrt(max(0, 23.5 * 23.5 - perpendicularSquared))
            let high = min(22, sideLimit, reachLimit)
            let low = max(4, high - 12)
            let cycle = (ClimbingGait.height(at: pullTime) + offset) / 24
            let part = (cycle - floor(cycle)) * 24
            let stroke = high - low
            // During a loaded pull the glove drops by exactly the distance reeled
            // in, keeping its world contact fixed until the other hand takes over.
            if part < stroke { return high - part }
            let t = (part - stroke) / (24 - stroke)
            return low + stroke * t * t * (3 - 2 * t)
        }
        let leftHigh = u.x < 0
        let left = distance(leftHigh ? 22 : 12, offset: 0, shoulderX: -10, handX: -2)
        let right = distance(leftHigh ? 12 : 22, offset: 12, shoulderX: 10, handX: 2)
        pose.leftHand = .init(x: u.x * left - 2, y: RopeSession.harnessHeight + u.y * left)
        pose.rightHand = .init(x: u.x * right + 2, y: RopeSession.harnessHeight + u.y * right)
        pose.elbowPole = .init(x: 24, y: -16)
        pose.headTilt = min(0.15, max(-0.15, direction.x * 0.12))
        if mode == .climbing {
            // Explicit anatomical hinges avoid pole-target sign changes as a
            // glove passes shoulder height. Mirroring the rig mirrors these too.
            pose.leftElbowBend = -1
            pose.rightElbowBend = 1
            let phase = pullTime * 2 * Double.pi
            pose.leftFoot = .init(x: -4 + sin(phase) * 3, y: max(0, sin(phase)) * 8)
            pose.rightFoot = .init(x: 5 - sin(phase) * 3, y: max(0, -sin(phase)) * 8)
        } else if mode == .swinging {
            let trail = min(7, max(-7, -velocity.x / 35))
            pose.leftFoot = .init(x: -8 + trail, y: 2)
            pose.rightFoot = .init(x: 8 + trail, y: 1)
        }
        return pose
    }
}


/// Hanging traverse and narrow vertical crack contacts. Both elbows bend down;
/// the feet brace and search instead of using the standing/walking pose.
public enum CrackAnimation {
    public static func pose(horizontal: Bool, time: Double, offset: Double) -> ExplorerPose {
        var pose = ExplorerPose()
        let phase = time * .pi * 2
        pose.leftElbowBend = -1; pose.rightElbowBend = -1
        pose.hips = .init(x: horizontal ? 0 : 2, y: 25)
        if horizontal {
            func grip(_ phaseOffset: Double, x: Double) -> WorldPoint {
                let cycle = offset / 30 + phaseOffset
                let phase = cycle - floor(cycle)
                let swing = max(0, (phase - 0.65) / 0.35)
                let reach = swing * swing * (3 - 2 * swing) * 30
                return .init(x: x + 9 - phase * 30 + reach, y: 58 - sin(swing * .pi) * 5)
            }
            pose.leftHand = grip(0, x: -10); pose.rightHand = grip(0.5, x: 10)
            pose.leftFoot = .init(x: -10, y: 4 + max(0, sin(phase)) * 5)
            pose.rightFoot = .init(x: 10, y: 4 + max(0, -sin(phase)) * 5)
        } else {
            let contacts = ClimbingContacts(heightAlongWall: offset)
            pose.leftHand = .init(x: 11, y: contacts.leftHand.y)
            pose.rightHand = .init(x: 14, y: contacts.rightHand.y)
            pose.leftFoot = .init(x: 11, y: contacts.leftFoot.y)
            pose.rightFoot = .init(x: 14, y: contacts.rightFoot.y)
        }
        pose.headTilt = -0.08
        return pose
    }
}
