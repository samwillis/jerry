import XCTest
@testable import ExpeditionCore

final class KeyboardControlTests: XCTestCase {
    let layout = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
    func explorer(x: Double = 100, y: Double = 0) -> ExplorerInteraction {
        var value = ExplorerInteraction(position: .init(x: x, y: y), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        value.autonomous = true; value.runsMission = true
        value.updateTerrain(layout); value.setKeyboardControl(true)
        return value
    }
    func advance(_ value: inout ExplorerInteraction, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { value.advance(by: 1.0 / 120) }
    }
    func testControlStaysStillWithoutAutonomousAdventures() {
        var value = explorer()
        advance(&value, seconds: 20)
        XCTAssertEqual(value.position, .init(x: 100, y: 0))
        XCTAssertFalse(value.runsMission)
        XCTAssertEqual(value.mission.completedExpeditions, 0)
        XCTAssertTrue(value.activityStatus.hasPrefix("Keyboard control"))
    }
    func testWalkingMatchesDoubleCadenceAndStopsOnRelease() {
        var value = explorer()
        value.setControlDirection(horizontal: 1, vertical: 0)
        advance(&value, seconds: 2)
        XCTAssertEqual(value.position.x, 260, accuracy: 0.01)
        XCTAssertEqual(value.walkingTime, 4, accuracy: 0.01)
        value.setControlDirection(horizontal: 0, vertical: 0)
        let stopped = value.position
        advance(&value, seconds: 3)
        XCTAssertEqual(value.position, stopped)
        XCTAssertEqual(value.state, .idle)
    }
    func testJumpHasGravityAirSteeringAndNoDoubleJump() {
        var value = explorer()
        value.controlJump(); advance(&value, seconds: 0.35)
        let height = value.position.y
        XCTAssertGreaterThan(height, 40)
        value.controlJump() // No second impulse in the air.
        value.setControlDirection(horizontal: 1, vertical: 0)
        advance(&value, seconds: 0.25)
        XCTAssertGreaterThan(value.position.x, 110)
        XCTAssertLessThan(value.position.y, 72)
        advance(&value, seconds: 1)
        XCTAssertEqual(value.attachment?.edge, .floor)
        XCTAssertEqual(value.position.y, 0)
    }
    func testWalkingOffPlatformFallsAndDropThroughDoesNotImmediatelyReland() {
        var value = explorer(x: 575, y: 370)
        value.setControlDirection(horizontal: 1, vertical: 0)
        advance(&value, seconds: 0.5)
        XCTAssertEqual(value.state, .jumping)
        XCTAssertLessThan(value.position.y, 370)
        value = explorer(x: 450, y: 370)
        value.setControlDirection(horizontal: 0, vertical: -1)
        value.controlJump(); advance(&value, seconds: 0.2)
        XCTAssertNil(value.attachment)
        XCTAssertLessThan(value.position.y, 360)
        advance(&value, seconds: 2)
        XCTAssertEqual(value.attachment?.edge, .floor)
    }
    func testClimbWallHoldsWhenReleasedThenMantles() {
        var value = explorer(x: 276)
        value.setControlDirection(horizontal: 0, vertical: 1)
        advance(&value, seconds: 3)
        XCTAssertEqual(value.attachment?.edge, .left)
        XCTAssertGreaterThan(value.position.y, 60)
        value.setControlDirection(horizontal: 0, vertical: 0)
        let stopped = value.position
        advance(&value, seconds: 1)
        XCTAssertEqual(value.position, stopped)
        value.setControlDirection(horizontal: 0, vertical: 1)
        advance(&value, seconds: 15)
        XCTAssertEqual(value.attachment?.edge, .top)
        XCTAssertEqual(value.position.y, 370)
    }
    func testKeyboardHookHoldsClimbsAndDescendsSameFrontRope() {
        var value = explorer(x: 450)
        value.controlGrapple()
        advance(&value, seconds: 5)
        let anchor = value.ropeSession?.anchor
        XCTAssertEqual(anchor?.edge, .front)
        XCTAssertEqual(value.ropeSession?.mode, .swinging)
        value.setControlDirection(horizontal: 0, vertical: 1)
        advance(&value, seconds: 2)
        let climbed = value.position.y
        XCTAssertEqual(value.ropeSession?.mode, .climbing)
        value.setControlDirection(horizontal: 0, vertical: -1)
        advance(&value, seconds: 0.5)
        XCTAssertLessThan(value.position.y, climbed)
        XCTAssertEqual(value.ropeSession?.anchor, anchor)
        value.setControlDirection(horizontal: 0, vertical: 1)
        advance(&value, seconds: 20)
        XCTAssertEqual(value.attachment?.edge, .top)
    }
    func testDownStepsOffRoofAndParachutesWithoutCreatingRope() {
        var value = explorer(x: 324, y: 370)
        value.setControlDirection(horizontal: 0, vertical: -1)
        advance(&value, seconds: 0.05)
        XCTAssertEqual(value.state, .dropping)
        XCTAssertNotNil(value.dropPose)
        advance(&value, seconds: 1.4)
        XCTAssertNil(value.ropeSession)
        XCTAssertEqual(value.state, .recovering)
        XCTAssertLessThan(value.position.y, 370)
        XCTAssertGreaterThan(value.recoveryElapsed, 0.3)
        advance(&value, seconds: 12)
        XCTAssertEqual(value.attachment?.edge, .floor)
        XCTAssertNotEqual(value.state, .dropping, "Holding Down must not repeatedly drop after landing")
    }
    func testLeavingControlInMidairUsesRecoveryAndClearsDirections() {
        var value = explorer()
        value.controlJump(); advance(&value, seconds: 0.2)
        value.setControlDirection(horizontal: 1, vertical: 1)
        value.setKeyboardControl(false)
        XCTAssertFalse(value.keyboardControlEnabled)
        XCTAssertEqual(value.controlHorizontal, 0)
        XCTAssertEqual(value.controlVertical, 0)
        XCTAssertEqual(value.state, .recovering)
        advance(&value, seconds: 4)
        XCTAssertTrue(value.position.x.isFinite && value.position.y.isFinite)
    }
    func testMovingWindowAndLostAnchorRemainSafeDuringControl() {
        var value = explorer(x: 450)
        value.controlGrapple(); advance(&value, seconds: 2)
        let point = value.position
        let moved = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 330, y: 40, width: 300, height: 350))], viewport: layout.viewport)
        value.updateTerrain(moved)
        XCTAssertEqual(value.position.x - point.x, 30, accuracy: 0.01)
        value.updateTerrain(.init(windows: [], viewport: layout.viewport))
        advance(&value, seconds: 3)
        XCTAssertNil(value.ropeSession)
        XCTAssertEqual(value.attachment?.edge, .floor)
    }
    func testTakingControlMidWalkCapturesCurrentSupportWithoutSnapBack() {
        var value = explorer()
        value.setKeyboardControl(false)
        XCTAssertTrue(value.requestActivity(.walk))
        advance(&value, seconds: 0.5)
        let point = value.position
        value.setKeyboardControl(true)
        value.updateTerrain(layout)
        XCTAssertEqual(value.position.x, point.x, accuracy: 0.01)
        advance(&value, seconds: 1)
        XCTAssertEqual(value.position.x, point.x, accuracy: 0.01)
    }
    func testStoppingControlDuringMantleFinishesTheCorner() {
        var value = explorer(x: 276)
        value.setControlDirection(horizontal: 0, vertical: 1)
        for _ in 0..<2400 {
            value.advance(by: 1.0 / 120)
            if value.state == .traversingEdge { break }
        }
        XCTAssertEqual(value.state, .traversingEdge)
        value.setKeyboardControl(false)
        XCTAssertEqual(value.state, .traversingEdge)
        advance(&value, seconds: 1.5)
        XCTAssertEqual(value.attachment?.edge, .top)
        XCTAssertEqual(value.position.y, 370, accuracy: 0.01)
    }

}
