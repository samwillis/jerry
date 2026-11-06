import Foundation

/// Three cycles per second with 56 points of travel per cycle. Each planted
/// sole moves backwards at that exact rate; flight separates the foot contacts.
public enum RunningGait {
    public static let cadence = 3.0
    public static let stride = 56.0
    public static let speed = cadence * stride
    public static func distance(from start: Double, to end: Double) -> Double { max(0, end - start) * speed }
    public static func pose(at time: Double) -> ExplorerPose {
        func foot(offset: Double, hipX: Double) -> WorldPoint {
            let cycle = max(0, time) * cadence + offset
            let phase = cycle - floor(cycle)
            if phase < 0.32 { return .init(x: hipX + 14 - stride * phase, y: 0) }
            let t = (phase - 0.32) / 0.68, u = 1 - t
            let x = u*u*u * (14 - stride * 0.32) + 3*u*u*t * -22 + 3*u*t*t * 14 + t*t*t * 14
            return .init(x: hipX + x, y: sin(.pi * t) * 13)
        }
        var pose = ExplorerPose()
        pose.leftFoot = foot(offset: 0, hipX: -7)
        pose.rightFoot = foot(offset: 0.5, hipX: 7)
        func hipLimit(_ foot: WorldPoint, x: Double) -> Double {
            let reach = 26.6, dx = foot.x - x
            return foot.y + ExpeditionConfiguration.ankleHeight + sqrt(max(0, reach * reach - dx * dx))
        }
        pose.hips.y = min(32, hipLimit(pose.leftFoot, x: -7), hipLimit(pose.rightFoot, x: 7)) - 0.3
        let phase = time * cadence * 2 * .pi
        pose.leftHand = .init(x: -2 + sin(phase) * 8, y: pose.hips.y + 15 + cos(phase) * 3)
        pose.rightHand = .init(x: 18 - sin(phase) * 8, y: pose.hips.y + 16 - cos(phase) * 3)
        pose.leftElbowBend = -1; pose.rightElbowBend = -1
        pose.headTilt = 0.04; pose.backpackTilt = 0.08 + sin(phase + 0.5) * 0.045
        return pose
    }
}
