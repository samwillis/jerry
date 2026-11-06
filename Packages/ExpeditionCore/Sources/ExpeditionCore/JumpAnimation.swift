import Foundation

/// Ground contact, leg extension and ballistic lift share one take-off instant.
public enum JumpAnimation {
    public static let preparationDuration = 0.12
    public static let compressionDuration = 0.065
    public static let launchSpeed = 285.0
    public static let gravity = 600.0
    public static let flightDuration = 2 * launchSpeed / gravity
    public static let previewDuration = 2.0
    private static func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x)); return t * t * (3 - 2 * t)
    }
    public static func preparation(at time: Double) -> ExplorerPose {
        let idle = ExplorerPose()
        var crouch = idle
        crouch.hips.y = 22
        crouch.leftHand = .init(x: -25, y: 33)
        crouch.rightHand = .init(x: 12, y: 34)
        crouch.headTilt = -0.08; crouch.backpackTilt = 0.09
        var pushOff = idle
        pushOff.hips.y = 29.8
        pushOff.leftHand = .init(x: -14, y: 64)
        pushOff.rightHand = .init(x: 22, y: 61)
        pushOff.headTilt = 0.06; pushOff.backpackTilt = -0.06
        if time < compressionDuration {
            return crouch.blended(from: idle, fraction: smooth(time / compressionDuration))
        }
        return pushOff.blended(from: crouch, fraction: smooth((time - compressionDuration) / (preparationDuration - compressionDuration)))
    }
    public static func airborne(elapsed: Double, verticalSpeed: Double, landingDistance: Double) -> ExplorerPose {
        let launch = preparation(at: preparationDuration)
        var tuck = ExplorerPose()
        tuck.hips.y = 28.5
        tuck.leftFoot = .init(x: -12, y: 8)
        tuck.rightFoot = .init(x: 13, y: 5)
        tuck.leftHand = .init(x: -22, y: 58)
        tuck.rightHand = .init(x: 24, y: 55)
        tuck.backpackTilt = -0.04; tuck.headTilt = 0.04
        let rising = tuck.blended(from: launch, fraction: smooth(elapsed / 0.16))
        var ready = ExplorerPose()
        ready.leftHand = .init(x: -25, y: 43)
        ready.rightHand = .init(x: 25, y: 44)
        ready.headTilt = -0.06; ready.backpackTilt = 0.04
        // Extend before contact, rather than holding a tucked pose into the floor.
        let approach = verticalSpeed < 0 ? smooth((38 - landingDistance) / 34) : 0
        return ready.blended(from: rising, fraction: approach)
    }
    public static func previewHeight(at time: Double) -> Double {
        let air = time - preparationDuration
        guard air > 0, air < flightDuration else { return 0 }
        return max(0, launchSpeed * air - gravity * air * air / 2)
    }
    public static func previewPose(at time: Double) -> ExplorerPose {
        let t = max(0, time).truncatingRemainder(dividingBy: previewDuration)
        if t <= preparationDuration { return preparation(at: t) }
        let air = t - preparationDuration
        if air < flightDuration {
            return airborne(elapsed: air, verticalSpeed: launchSpeed - gravity * air, landingDistance: previewHeight(at: t))
        }
        let landed = air - flightDuration
        let ready = airborne(elapsed: flightDuration, verticalSpeed: -launchSpeed, landingDistance: 0)
        let recovery = ExplorerPose().blended(from: ready, fraction: smooth(landed / 0.2))
        return LandingAnimation.apply(to: recovery, elapsed: landed)
    }
}
