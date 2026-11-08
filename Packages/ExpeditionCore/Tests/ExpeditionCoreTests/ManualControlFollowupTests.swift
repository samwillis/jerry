import XCTest
@testable import ExpeditionCore

final class ManualControlFollowupTests: XCTestCase {
    let layout = TerrainSnapshot(windows: [
        .init(id: 2, frame: .init(x: 650, y: 50, width: 300, height: 550)),
        .init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))
    ], viewport: .init(x: 0, y: 0, width: 1200, height: 900))
    func actor(x: Double = 450) -> ExplorerInteraction {
        var value = ExplorerInteraction(position: .init(x: x, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1176, y: 824)))
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
        var value = actor(x: 780); value.setKeyboardControl(true)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 780, y: 600)))
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 2)
        XCTAssertEqual(value.grappleTarget?.x, 780)
        var empty = actor(x: 780); empty.setKeyboardControl(true)
        XCTAssertFalse(empty.fireGrapple(toward: .init(x: 100, y: 700)))
        let cover = DesktopWindow(id: 3, frame: .init(x: 600, y: 580, width: 400, height: 200), canClimb: false)
        empty.updateTerrain(.init(windows: [cover] + layout.windows, viewport: layout.viewport))
        XCTAssertFalse(empty.fireGrapple(toward: .init(x: 780, y: 600)))
    }
    func testHookCanAttachToRoofWithoutStandingRoomAndHangAtTheRim() {
        let roof = DesktopWindow(id: 7, frame: .init(x: 100, y: 100, width: 600, height: 700))
        let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
        let terrain = TerrainSnapshot(windows: [roof], viewport: viewport)
        XCTAssertNil(TerrainSupport.resolve(.init(owner: .window(7), edge: .top, offset: 250), in: terrain))
        var value = ExplorerInteraction(position: .init(x: 350, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        value.autonomous = true; value.updateTerrain(terrain); value.setKeyboardControl(true)
        XCTAssertEqual(value.aimedGrappleTarget(toward: .init(x: 350, y: 800)), .init(x: 350, y: 801))
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 350, y: 800)))
        advance(&value, 1)
        value.setControlDirection(horizontal: 0, vertical: 1); advance(&value, 30)
        XCTAssertNotNil(value.ropeSession, "No room to mantle must leave the hook attached")
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 7)
        XCTAssertGreaterThan(value.position.y, 710)
        XCTAssertLessThanOrEqual(value.position.y, 724)
        XCTAssertNil(value.attachment)
        // Once the window is lower, the same attached rope can finish its mantle.
        let lower = DesktopWindow(id: 7, frame: .init(x: 100, y: 0, width: 600, height: 700))
        value.updateTerrain(.init(windows: [lower], viewport: viewport))
        advance(&value, 20)
        XCTAssertEqual(value.attachment?.edge, .top)
        XCTAssertEqual(value.position.y, 700)
    }
    func testSwitchingCaptureAwayFromDepartureLedgeDoesNotCancelShot() {
        let ledge = WindowFeature(id: 9, windowID: 1, edge: .ledge, start: .init(x: 30, y: 150), end: .init(x: 270, y: 150))
        let sourceTerrain = TerrainSnapshot(windows: layout.windows, viewport: layout.viewport, features: [ledge])
        var value = ExplorerInteraction(position: .init(x: 450, y: 170), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1176, y: 824)))
        value.autonomous = true; value.updateTerrain(sourceTerrain); value.setKeyboardControl(true)
        XCTAssertEqual(value.attachment?.featureID, 9)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 680, y: 600)))
        advance(&value, 0.1)
        // The capture prioritiser now supplies the destination window's data,
        // removing the source window's internal holds from the snapshot.
        value.updateTerrain(layout, sampleElapsed: 0.05)
        XCTAssertEqual(value.ropeSession?.mode, .firing)
        XCTAssertTrue(value.ropeSession?.freeFlightWhileFiring == true)
        XCTAssertNil(value.attachment)
        advance(&value, 1)
        XCTAssertNotNil(value.ropeSession)
        XCTAssertNotEqual(value.ropeSession?.mode, .firing)
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 2)
    }
    func testNearbyInternalHoldCannotCancelAnInFlightGrapple() {
        let feature = WindowFeature(id: 1, windowID: 1, edge: .horizontalCrack,
                                    start: .init(x: 30, y: 100), end: .init(x: 270, y: 100))
        let terrain = TerrainSnapshot(windows: layout.windows, viewport: layout.viewport, features: [feature])
        var value = actor(); value.setKeyboardControl(true)
        value.beginDrag(at: value.position); value.drag(to: .init(x: 450, y: 62)); value.endDrag(on: terrain)
        value.updateTerrain(terrain)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 450, y: 370)))
        XCTAssertFalse(value.transferToWindowHold())
        value.setControlDirection(horizontal: 0, vertical: 1)
        advance(&value, 0.15)
        XCTAssertEqual(value.ropeSession?.mode, .firing)
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 1)
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
    func testRefiringKeepsOldRopeUntilNewHookIsSecure() {
        var value = actor(); value.setKeyboardControl(true)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 450, y: 370))); advance(&value, 2)
        value.setControlDirection(horizontal: 1, vertical: 0); advance(&value, 0.2)
        let velocity = value.ropeSession!.releaseVelocity
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 780, y: 600)))
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 1)
        XCTAssertTrue(value.hasPendingGrapple)
        XCTAssertEqual(value.ropeSession?.body.velocity, velocity)
        advance(&value, 0.1)
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 1)
        advance(&value, 1)
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 2)
        XCTAssertFalse(value.hasPendingGrapple)
        XCTAssertNotNil(value.ropeSession)
        XCTAssertTrue(value.keyboardControlEnabled)
    }
    func testMissingNewAnchorDoesNotRemoveTheOldRope() {
        var value = actor(); value.setKeyboardControl(true)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 450, y: 370))); advance(&value, 2)
        XCTAssertTrue(value.fireGrapple(toward: .init(x: 780, y: 600)))
        let surviving = TerrainSnapshot(windows: layout.windows.filter { $0.id != 2 }, viewport: layout.viewport)
        value.updateTerrain(surviving)
        XCTAssertFalse(value.hasPendingGrapple)
        XCTAssertEqual(value.ropeSession?.anchor.windowID, 1)
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
        XCTAssertTrue(value.requestActivity(.sockSearch))
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
