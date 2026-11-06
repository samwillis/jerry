import XCTest
@testable import ExpeditionCore

final class ManualControlFollowupTests: XCTestCase {
    let layout = TerrainSnapshot(windows: [
        .init(id: 2, frame: .init(x: 650, y: 50, width: 300, height: 550)),
        .init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))
    ], viewport: .init(x: 0, y: 0, width: 1200, height: 900))
    func actor() -> ExplorerInteraction {
        var value = ExplorerInteraction(position: .init(x: 450, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1176, y: 824)))
        value.autonomous = true; value.runsMission = true; value.updateTerrain(layout)
        return value
    }
    func advance(_ value: inout ExplorerInteraction, _ seconds: Double) {
        for _ in 0..<Int(seconds * 120) { value.advance(by: 1.0 / 120) }
    }
    func testDisabledIdleExplorationRestsAndCanBeEnabledAgain() {
        var value = actor(); value.setIdleExploration(false)
        advance(&value, 20)
        XCTAssertEqual(value.position, .init(x: 450, y: 0))
        XCTAssertEqual(value.mission.completedExpeditions, 0)
        value.setIdleExploration(true); advance(&value, 60)
        XCTAssertGreaterThan(value.mission.completedExpeditions, 0)
    }
    func testDisablingMidWalkStopsAtCurrentPointAndRemainsThere() {
        var value = actor()
        XCTAssertTrue(value.requestActivity(.walk)); advance(&value, 0.5)
        let point = value.position
        value.setIdleExploration(false); value.updateTerrain(layout); advance(&value, 5)
        XCTAssertEqual(value.position, point)
    }
    func testRestingExplorerStillFallsOntoWindowAndCanBeDragged() {
        var value = actor(); value.setIdleExploration(false)
        value.beginDrag(at: value.position); value.drag(to: .init(x: 450, y: 650)); value.endDrag(on: layout)
        advance(&value, 10)
        XCTAssertEqual(value.position.y, 370, accuracy: 0.01)
        XCTAssertEqual(value.attachment?.owner, .window(1))
        let point = value.position; advance(&value, 20)
        XCTAssertEqual(value.position, point)
        XCTAssertFalse(value.runsMission)
    }
    func testLeavingKeyboardControlRespectsDisabledIdleExploration() {
        var value = actor(); value.setIdleExploration(false); value.setKeyboardControl(true)
        value.setControlDirection(horizontal: 1, vertical: 0); advance(&value, 1)
        value.setKeyboardControl(false)
        let point = value.position; advance(&value, 10)
        XCTAssertEqual(value.position, point)
        XCTAssertFalse(value.runsMission)
    }
    func testPointerSelectsTheAimedWindowAndRejectsEmptyOrCoveredRims() {
        var value = actor(); value.setKeyboardControl(true)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 780, y: 600)))
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 2)
        XCTAssertEqual(value.grappleTarget?.x, 780)
        var empty = actor(); empty.setKeyboardControl(true)
        XCTAssertFalse(empty.fireGrapple(toward: .init(x: 100, y: 700)))
        let cover = DesktopWindow(id: 3, frame: .init(x: 600, y: 580, width: 400, height: 200), canClimb: false)
        empty.updateTerrain(.init(windows: [cover] + layout.windows, viewport: layout.viewport))
        XCTAssertFalse(empty.fireGrapple(toward: .init(x: 780, y: 600)))
    }
    func testCanFireWhileJumpingAndContinueBallisticFlightUntilLatch() {
        var value = actor(); value.setKeyboardControl(true); value.controlJump(); advance(&value, 0.3)
        XCTAssertEqual(value.state, .jumping)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 450, y: 370)))
        XCTAssertTrue(value.ropeSession?.freeFlightWhileFiring == true)
        let point = value.position; advance(&value, 0.1)
        XCTAssertNotEqual(value.position.y, point.y)
        XCTAssertEqual(value.ropeSession?.mode, .firing)
    }
    func testRefiringFromRopeKeepsMomentumAndUsesNewAnchor() {
        var value = actor(); value.setKeyboardControl(true)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 450, y: 370))); advance(&value, 2)
        value.setControlDirection(horizontal: 1, vertical: 0); advance(&value, 0.2)
        let velocity = value.ropeSession!.releaseVelocity
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 780, y: 600)))
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 2)
        XCTAssertEqual(value.ropeSession?.body.velocity, velocity)
        advance(&value, 1)
        XCTAssertNotNil(value.ropeSession)
        XCTAssertTrue(value.keyboardControlEnabled)
    }
    func testLeftAndRightPumpAndBrakeAlongTangentWithoutChangingLineLength() {
        let anchor = RopeAnchor(windowID: 1, edge: .front, offset: 150)
        let guide = anchor.resolve(in: layout)!
        var session = RopeSession(anchor: anchor, guide: guide, feet: .init(x: 450, y: 150), mode: .swinging)
        let length = session.body.length
        for _ in 0..<24 { session.steerSwing(horizontal: 1, elapsed: 1.0 / 120, guide: guide) }
        XCTAssertGreaterThan(session.body.velocity.x, 60)
        for _ in 0..<48 { session.steerSwing(horizontal: -1, elapsed: 1.0 / 120, guide: guide) }
        XCTAssertLessThan(session.body.velocity.x, -60)
        XCTAssertEqual(session.body.length, length)
        var fast = RopeSession(anchor: anchor, guide: guide, feet: .init(x: 450, y: 150), mode: .swinging, velocity: .init(x: 500, y: 0))
        fast.steerSwing(horizontal: -1, elapsed: 1.0 / 120, guide: guide)
        XCTAssertGreaterThan(fast.body.velocity.x, 490) // Brake gradually; do not clip gravity-driven momentum.
        XCTAssertLessThan(fast.body.velocity.x, 500)
    }
    func testExplicitSockSearchRunsOnceWhenIdleExplorationIsOff() {
        var value = actor(); value.setIdleExploration(false)
        XCTAssertTrue(value.requestActivity(.bananaAdventure))
        advance(&value, 120)
        XCTAssertEqual(value.mission.completedExpeditions, 1)
        XCTAssertFalse(value.runsMission)
        let point = value.position; advance(&value, 20)
        XCTAssertEqual(value.position, point)
    }

    func testActionsReturnToIdleExplorationWhenItIsEnabled() {
        var value = actor()
        XCTAssertTrue(value.requestActivity(.walk))
        advance(&value, 120)
        XCTAssertTrue(value.runsMission)
        XCTAssertNil(value.requestedActivity)
        XCTAssertGreaterThan(value.mission.completedExpeditions, 0)
    }

}
