import XCTest
@testable import ExpeditionCore

final class JumpAnimationTests: XCTestCase {
    func actor() -> ExplorerInteraction {
        var value = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        value.autonomous = true
        value.updateTerrain(.init(windows: [], viewport: .init(x: 0, y: 0, width: 1000, height: 800)))
        value.setKeyboardControl(true)
        return value
    }
    func testFeetStaySupportedUntilLegPushCompletesThenLiftStarts() {
        var value = actor()
        value.controlJump()
        XCTAssertEqual(value.state, .preparingJump)
        for _ in 0..<14 {
            value.advance(by: 1.0 / 120)
            XCTAssertEqual(value.position.y, 0)
            XCTAssertNotNil(value.attachment)
            XCTAssertEqual(value.keyboardJumpPose?.leftFoot.y, 0)
            XCTAssertEqual(value.keyboardJumpPose?.rightFoot.y, 0)
            value.controlJump() // Repeats cannot restart the preparation.
        }
        value.advance(by: 1.0 / 120)
        XCTAssertEqual(value.state, .jumping)
        XCTAssertNil(value.attachment)
        XCTAssertEqual(value.position.y, 0)
        value.advance(by: 1.0 / 120)
        XCTAssertGreaterThan(value.position.y, 2)
    }
    func testCountermovementExtendsLegsBeforeAirborneTuck() {
        let crouch = JumpAnimation.preparation(at: JumpAnimation.compressionDuration)
        let launch = JumpAnimation.preparation(at: JumpAnimation.preparationDuration)
        XCTAssertLessThan(crouch.hips.y, ExpeditionConfiguration.standingHipHeight - 6)
        XCTAssertGreaterThan(launch.hips.y, crouch.hips.y + 7)
        let firstAir = JumpAnimation.airborne(elapsed: 0, verticalSpeed: JumpAnimation.launchSpeed, landingDistance: 0)
        XCTAssertEqual(firstAir.hips, launch.hips)
        XCTAssertEqual(firstAir.leftFoot, launch.leftFoot)
        let apex = JumpAnimation.airborne(elapsed: 0.475, verticalSpeed: 0, landingDistance: 68)
        XCTAssertGreaterThan(apex.leftFoot.y, launch.leftFoot.y + 5)
        let reaching = JumpAnimation.airborne(elapsed: 0.95, verticalSpeed: -285, landingDistance: 1)
        XCTAssertEqual(reaching.leftFoot.y, 0, accuracy: 0.01)
    }
    func testJumpPosesStayInsideLimbReach() {
        for tick in 0...240 {
            let pose = JumpAnimation.previewPose(at: Double(tick) / 120)
            for (root, foot) in [(WorldPoint(x: pose.hips.x - 7, y: pose.hips.y), pose.leftFoot), (.init(x: pose.hips.x + 7, y: pose.hips.y), pose.rightFoot)] {
                let ankle = WorldPoint(x: foot.x, y: foot.y + ExpeditionConfiguration.ankleHeight)
                XCTAssertFalse(TwoBoneIK.solve(root: root, target: ankle, upper: 13.5, lower: 13.5).isClamped, "leg at \(tick)")
            }
            for (root, hand) in [(WorldPoint(x: pose.hips.x - 10, y: pose.hips.y + 20), pose.leftHand), (.init(x: pose.hips.x + 10, y: pose.hips.y + 20), pose.rightHand)] {
                XCTAssertFalse(TwoBoneIK.solve(root: root, target: hand, upper: 12, lower: 12).isClamped, "arm at \(tick)")
            }
        }
    }
    func testAirSteeringPreservesMomentumOnReleaseAndLandingIsOneContact() {
        var value = actor()
        value.setControlDirection(horizontal: 1, vertical: 0)
        value.controlJump()
        for _ in 0..<30 { value.advance(by: 1.0 / 120) }
        value.setControlDirection(horizontal: 0, vertical: 0)
        let x = value.position.x
        for _ in 0..<12 { value.advance(by: 1.0 / 120) }
        XCTAssertGreaterThan(value.position.x - x, 6)
        for _ in 0..<240 { value.advance(by: 1.0 / 120) }
        XCTAssertEqual(value.landingCount, 1)
        XCTAssertGreaterThan(value.lastLandingSpeed, 275)
        XCTAssertEqual(value.position.y, 0)
    }
    func testMovingOrLosingSupportDuringWindupDoesNotLaunchFromStaleFloor() {
        let frame = WorldRect(x: 200, y: 20, width: 300, height: 200)
        var value = actor()
        value.beginDrag(at: value.position)
        value.drag(to: .init(x: 300, y: 220))
        value.endDrag(on: .init(windows: [.init(id: 1, frame: frame)], viewport: .init(x: 0, y: 0, width: 1000, height: 800)))
        value.controlJump()
        value.advance(by: 0.05)
        value.updateTerrain(.init(windows: [.init(id: 1, frame: .init(x: 220, y: 40, width: 300, height: 200))], viewport: .init(x: 0, y: 0, width: 1000, height: 800)))
        XCTAssertEqual(value.position, .init(x: 320, y: 240))
        value.updateTerrain(.init(windows: [], viewport: .init(x: 0, y: 0, width: 1000, height: 800)))
        value.advance(by: 0.05)
        XCTAssertNil(value.attachment)
        XCTAssertLessThan(value.position.y, 240)
        XCTAssertEqual(value.state, .jumping)
    }
    func testCeilingContactStopsTheRiseWithoutHovering() {
        var value = actor()
        value.updateBounds(.init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 20)))
        value.updateTerrain(.init(windows: [], viewport: .init(x: 0, y: 0, width: 1000, height: 800)))
        value.controlJump()
        for _ in 0..<96 { value.advance(by: 1.0 / 120) }
        XCTAssertEqual(value.position.y, 0)
        XCTAssertEqual(value.landingCount, 1)
    }

}
