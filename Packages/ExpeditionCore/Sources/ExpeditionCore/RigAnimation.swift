import Foundation

public enum ExplorerMotion: String, CaseIterable, Sendable {
    case idle, walking, climbing, abseiling, parachuting, held, investigating, comic
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
    public var hips = WorldPoint(x: 0, y: 27)
    public var leftHand = WorldPoint(x: -20, y: 29)
    public var rightHand = WorldPoint(x: 20, y: 29)
    public var leftFoot = WorldPoint(x: -8, y: 0)
    public var rightFoot = WorldPoint(x: 8, y: 0)
    public var headTilt: Double = 0
    public var backpackTilt: Double = 0
    public var sway: Double = 0

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
            pose.hips.y += sin(phase * 0.4) * 0.5 * tuning.bounce
            pose.headTilt = sin(phase * 0.2) * 0.035
        case .walking:
            let stride = min(max(tuning.stride, 0), 12)
            pose.hips.y += abs(sin(phase)) * 0.8 * tuning.bounce
            pose.leftFoot = .init(x: -7 + cos(phase) * stride, y: max(0, sin(phase)) * 6)
            pose.rightFoot = .init(x: 7 - cos(phase) * stride, y: max(0, -sin(phase)) * 6)
            pose.leftHand.x -= sin(phase) * 4
            pose.rightHand.x += sin(phase) * 4
            pose.backpackTilt = sin(phase + 0.5) * 0.08 * tuning.bounce
        case .climbing:
            pose.hips.x = 8
            pose.hips.y += sin(phase * 0.5) * 1.5 * tuning.bounce
            // Fixed contacts while the body shifts; the playground can move these handholds.
            pose.leftHand = .init(x: 20, y: 55)
            pose.rightHand = .init(x: 20, y: 65)
            pose.leftFoot = .init(x: 20, y: 12)
            pose.rightFoot = .init(x: 20, y: 0)
            pose.headTilt = -0.08
        case .abseiling:
            pose.hips.x = -2
            pose.leftHand = .init(x: 0, y: 61)
            pose.rightHand = .init(x: 8, y: 62)
            pose.leftFoot = .init(x: 10, y: 9)
            pose.rightFoot = .init(x: 20, y: 11)
            pose.backpackTilt = 0.1 + sin(phase * 0.4) * 0.03
        case .parachuting:
            // First half-second is the crouch/launch anticipation.
            let launch = min(t * 2, 1)
            pose.hips.y -= (1 - launch) * 5
            pose.leftHand = .init(x: -17, y: 66)
            pose.rightHand = .init(x: 17, y: 66)
            pose.leftFoot.y += 1.5 + sin(phase * 0.45) * 1.5
            pose.rightFoot.y += 1.5 - sin(phase * 0.45) * 1.5
            pose.sway = sin(phase * 0.3) * 0.06
        case .held:
            pose.leftHand = .init(x: -16, y: 27 + sin(phase * 0.8))
            pose.rightHand = .init(x: 16, y: 27 - sin(phase * 0.8))
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

    public mutating func select(_ motion: ExplorerMotion, restart: Bool = false) {
        guard motion != self.motion || restart else { return }
        if restart {
            self.motion = motion
            time = 0
            blendTime = max(0, tuning.blendDuration)
            pose = AnimationClips.sample(motion, time: 0, tuning: tuning)
            transitionFrom = pose
            return
        }
        transitionFrom = pose
        self.motion = motion
        time = 0
        blendTime = 0
    }

    @discardableResult public mutating func advance(by elapsed: Double) -> ExplorerPose {
        let dt = elapsed.isFinite ? min(max(elapsed, 0), 0.1) : 0
        time += dt
        blendTime += dt
        let fraction = tuning.blendDuration > 0 ? min(blendTime / tuning.blendDuration, 1) : 1
        let smooth = fraction * fraction * (3 - 2 * fraction)
        pose = AnimationClips.sample(motion, time: time, tuning: tuning).blended(from: transitionFrom, fraction: smooth)
        return pose
    }
}
