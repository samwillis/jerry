import XCTest
@testable import ExpeditionCore

final class RunningAndFastWorkTests: XCTestCase {
    let layout = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))], viewport: .init(x: 0, y: 0, width: 1500, height: 900))
    func actor() -> ExplorerInteraction {
        var value = ExplorerInteraction(position: .init(x: 100, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1476, y: 824)))
        value.autonomous = true; value.updateTerrain(layout); value.setKeyboardControl(true)
        return value
    }
    func advance(_ value: inout ExplorerInteraction, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { value.advance(by: 1.0 / 120) }
    }
    func testShiftRunsAtTheSameSpeedAsTheAnimatedStrideAndReleasesToWalk() {
        var value = actor(); value.setControlDirection(horizontal: 1, vertical: 0); value.setControlFastPace(true)
        advance(&value, seconds: 1)
        XCTAssertEqual(value.state, .running)
        XCTAssertEqual(value.position.x, 100 + RunningGait.speed, accuracy: 0.01)
        XCTAssertEqual(value.runningTime, 1, accuracy: 0.0001)
        value.setControlFastPace(false)
        let x = value.position.x; advance(&value, seconds: 1)
        XCTAssertEqual(value.state, .walking)
        XCTAssertEqual(value.position.x - x, 80, accuracy: 0.01)
        value.setKeyboardControl(false)
        XCTAssertFalse(value.controlFastPace)
    }
    func testRunningHasAFlightPhaseAndPlantedSolesDoNotSlide() {
        var flightFrames = 0
        for tick in 0..<600 {
            let t = Double(tick) / 600, next = t + 0.00001
            let pose = RunningGait.pose(at: t), after = RunningGait.pose(at: next)
            if pose.leftFoot.y > 0 && pose.rightFoot.y > 0 { flightFrames += 1 }
            for (a, b) in [(pose.leftFoot, after.leftFoot), (pose.rightFoot, after.rightFoot)] where a.y == 0 && b.y == 0 {
                XCTAssertEqual(b.x - a.x + RunningGait.distance(from: t, to: next), 0, accuracy: 0.00001)
            }
            for (root, foot) in [(WorldPoint(x: -7, y: pose.hips.y), pose.leftFoot), (.init(x: 7, y: pose.hips.y), pose.rightFoot)] {
                XCTAssertFalse(TwoBoneIK.solve(root: root, target: .init(x: foot.x, y: foot.y + 3), upper: 13.5, lower: 13.5).isClamped)
            }
        }
        XCTAssertGreaterThan(flightFrames, 100)
    }
    func testFastRopeWorkChangesMotorClockWithoutSpeedingGravityOrSwingTime() {
        let anchor = RopeAnchor(windowID: 1, edge: .front, offset: 150), guide = anchor.resolve(in: layout)!
        var normal = RopeSession(anchor: anchor, guide: guide, feet: .init(x: 450, y: 100), mode: .climbing)
        var fast = normal
        for _ in 0..<300 {
            normal.advance(by: 1.0 / 120, guide: guide, minimumLength: 25)
            fast.advance(by: 1.0 / 120, guide: guide, minimumLength: 25, workRate: 1.8)
        }
        XCTAssertEqual(fast.pullTime, normal.pullTime * 1.8, accuracy: 0.00001)
        XCTAssertEqual(fast.age, normal.age, accuracy: 0.00001)
        XCTAssertEqual((237 - fast.body.length) / (237 - normal.body.length), 1.8, accuracy: 0.001)
        var a = RopeSession(anchor: anchor, guide: guide, feet: .init(x: 350, y: 100), mode: .swinging)
        a.climbsAfterSwing = false; var b = a
        for _ in 0..<120 {
            a.advance(by: 1.0 / 120, guide: guide, minimumLength: 25)
            b.advance(by: 1.0 / 120, guide: guide, minimumLength: 25, workRate: 1.8)
        }
        XCTAssertEqual(a.body.position, b.body.position)
        XCTAssertEqual(a.body.velocity, b.body.velocity)
    }
    func testFastDescentPaysOutFasterAndKeepsTheSameRope() {
        let anchor = RopeAnchor(windowID: 1, edge: .front, offset: 150), guide = anchor.resolve(in: layout)!
        var a = RopeSession(anchor: anchor, guide: guide, feet: .init(x: 450, y: 250), mode: .descending), b = a
        let initial = a.body.length
        for _ in 0..<120 {
            a.advance(by: 1.0 / 120, guide: guide, minimumLength: 25)
            b.advance(by: 1.0 / 120, guide: guide, minimumLength: 25, workRate: 1.8)
        }
        XCTAssertEqual(a.body.length - initial, 48, accuracy: 0.001)
        XCTAssertEqual(b.body.length - initial, 86.4, accuracy: 0.001)
        XCTAssertEqual(a.anchor, b.anchor)
    }
    func testOptionalIdleRunningAndFastWorkDoNotEnableExplorationByThemselves() {
        var value = actor(); value.setKeyboardControl(false); value.setIdleExploration(false)
        value.setRunWhenExploring(true); value.setFasterRopeWork(true)
        advance(&value, seconds: 5)
        XCTAssertEqual(value.position.x, 100)
        XCTAssertEqual(value.ropeWorkRate, 1.8)
        let destination = TerrainAttachment(owner: .screen, edge: .floor, offset: 700)
        XCTAssertTrue(value.follow([.init(from: value.attachment!, to: destination, kind: .walking)]))
        advance(&value, seconds: 1)
        XCTAssertEqual(value.state, .running)
        XCTAssertEqual(value.position.x, 268, accuracy: 0.01)
        value.setIdleExploration(false)
        let point = value.position; advance(&value, seconds: 5)
        XCTAssertEqual(value.position, point)
    }
    func testRunMomentumCarriesIntoJumpWithoutChangingItsHeight() {
        var walk = actor(), run = actor()
        walk.setControlDirection(horizontal: 1, vertical: 0)
        run.setControlDirection(horizontal: 1, vertical: 0); run.setControlFastPace(true)
        walk.controlJump(); run.controlJump()
        advance(&walk, seconds: 0.6); advance(&run, seconds: 0.6)
        XCTAssertEqual(walk.position.y, run.position.y, accuracy: 0.001)
        XCTAssertGreaterThan(run.position.x - 100, (walk.position.x - 100) * 2)
    }
}
