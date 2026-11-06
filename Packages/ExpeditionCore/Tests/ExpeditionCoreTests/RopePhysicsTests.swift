import XCTest
@testable import ExpeditionCore

final class RopePhysicsTests: XCTestCase {
    private let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
    private func terrain(x: Double = 300, y: Double = 20) -> TerrainSnapshot {
        .init(windows: [.init(id: 1, frame: .init(x: x, y: y, width: 300, height: 350))], viewport: viewport)
    }
    private func explorer(_ point: WorldPoint = .init(x: 100, y: 0)) -> ExplorerInteraction {
        var value = ExplorerInteraction(position: point, bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        value.autonomous = true; value.runsMission = true; value.updateTerrain(terrain())
        return value
    }
    func testSlackLineFallsFreelyRatherThanPushingTheExplorerOutward() {
        var body = RopeDynamics(position: .init(x: 0, y: -20), length: 200)
        body.damping = 0
        body.advance(by: 0.1, support: .point(.zero))
        XCTAssertFalse(body.isTaut)
        XCTAssertEqual(body.position.x, 0)
        XCTAssertEqual(body.position.y, -22.4, accuracy: 0.11)
        XCTAssertEqual(body.velocity.y, -48, accuracy: 0.0001)
    }
    func testSmallPendulumHasGravityDrivenPeriodAndDoesNotGainEnergy() {
        let length = 240.0, angle = 0.15
        var body = RopeDynamics(position: .init(x: sin(angle) * length, y: -cos(angle) * length), length: length)
        body.damping = 0
        let initial = RopeDynamics.gravity * (body.position.y + length)
        var crossings: [Double] = [], previousX = body.position.x
        for tick in 1...1440 {
            body.advance(by: 1.0 / 120, support: .point(.zero))
            let energy = 0.5 * (body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y) + RopeDynamics.gravity * (body.position.y + length)
            XCTAssertLessThanOrEqual(energy, initial * 1.01)
            XCTAssertLessThanOrEqual(hypot(body.position.x, body.position.y), length + 0.00001)
            if previousX > 0 && body.position.x <= 0 { crossings.append(Double(tick) / 120) }
            previousX = body.position.x
        }
        XCTAssertGreaterThanOrEqual(crossings.count, 2)
        if crossings.count > 1 { XCTAssertEqual(crossings[1] - crossings[0], 2 * .pi * sqrt(length / RopeDynamics.gravity), accuracy: 0.08) }
    }
    func testReelingPreservesAngularMomentumWithoutGravityOrFriction() {
        let length = hypot(100.0, 200)
        var body = RopeDynamics(position: .init(x: -100, y: -200), velocity: .init(x: 140, y: -70), length: length)
        body.acceleration = .zero; body.damping = 0
        let initial = body.position.x * body.velocity.y - body.position.y * body.velocity.x
        for _ in 0..<20 { body.advance(by: 0.001, support: .point(.zero), payOut: -1) }
        let final = body.position.x * body.velocity.y - body.position.y * body.velocity.x
        XCTAssertEqual(final, initial, accuracy: abs(initial) * 0.015)
        XCTAssertEqual(body.length, length - 20, accuracy: 0.000001)
    }
    func testGrappleFiresSwingsClimbsAndMantlesOntoARealSurfaceRoute() {
        var value = explorer()
        XCTAssertTrue(value.availableActivities.contains(.grapple))
        XCTAssertTrue(value.requestActivity(.grapple))
        var states = Set<ExplorerInteraction.State>(), maximumSweep = 0.0
        for _ in 0..<18000 {
            value.advance(by: 1.0 / 120)
            states.insert(value.state)
            if let rope = value.ropeSession, rope.mode != .firing && rope.mode != .supported {
                maximumSweep = max(maximumSweep, abs(rope.feet.x - 100))
                if let guide = rope.anchor.resolve(in: terrain()) {
                    XCTAssertLessThanOrEqual(guide.length(to: rope.body.position), rope.body.length + 1)
                }
            }
            if value.state == .idle && !value.hasPendingTravel { break }
        }
        XCTAssertTrue(states.isSuperset(of: [.grappling, .swinging, .ropeClimbing, .traversingEdge]), "\(states)")
        XCTAssertGreaterThan(maximumSweep, 40)
        XCTAssertEqual(value.attachment?.owner, .window(1))
        XCTAssertEqual(value.attachment?.edge, .top)
        XCTAssertFalse(value.hasPendingTravel)
    }
    func testRopeModesSwitchOnSameAnchorWithoutTeleportingOrDroppingMomentum() {
        var value = explorer(.init(x: 450, y: 370))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<10000 { value.advance(by: 1.0 / 120); if value.state == .abseiling && value.position.y < 240 { break } }
        XCTAssertEqual(value.state, .abseiling)
        for activity in [ExplorerActivity.ropeClimb, .abseil, .swing] {
            let point = value.position, anchor = value.ropeSession?.anchor, length = value.ropeSession?.body.length
            let velocity = value.ropeSession?.body.velocity
            XCTAssertTrue(value.requestActivity(activity))
            XCTAssertEqual(value.position, point)
            XCTAssertEqual(value.ropeSession?.anchor, anchor)
            XCTAssertEqual(value.ropeSession?.body.length, length)
            if activity != .swing { XCTAssertEqual(value.ropeSession?.body.velocity, velocity) }
            for _ in 0..<60 { value.advance(by: 1.0 / 120) }
        }
        XCTAssertNotNil(value.ropeSession)
        let velocity = value.ropeSession!.body.velocity, point = value.position
        XCTAssertTrue(value.requestActivity(.releaseRope))
        XCTAssertEqual(value.state, .recovering)
        XCTAssertNil(value.ropeSession)
        value.advance(by: 1.0 / 120)
        XCTAssertEqual(value.position.x - point.x, velocity.x / 120, accuracy: 0.02)
        XCTAssertEqual(value.position.y - point.y, (velocity.y - 4) / 120, accuracy: 0.02)
    }
    func testAbseilCanLandThenClimbTheExistingRopeWithoutRefiring() {
        var value = explorer(.init(x: 450, y: 370))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<12000 { value.advance(by: 1.0 / 120); if value.state == .idle && !value.hasPendingTravel { break } }
        XCTAssertEqual(value.ropeSession?.mode, .supported)
        let anchor = value.ropeSession?.anchor
        XCTAssertTrue(value.requestActivity(.ropeClimb))
        var fired = false
        for _ in 0..<18000 {
            value.advance(by: 1.0 / 120); fired = fired || value.state == .grappling
            if let session = value.ropeSession { XCTAssertEqual(session.anchor, anchor) }
            if value.state == .idle && !value.hasPendingTravel { break }
        }
        XCTAssertFalse(fired)
        XCTAssertEqual(value.attachment?.owner, .window(1))
        XCTAssertEqual(value.attachment?.edge, .top)
    }
    func testAnchorMotionAndLossPreserveRopeStateThenRecoverSafely() {
        var value = explorer(.init(x: 450, y: 370))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<12000 { value.advance(by: 1.0 / 120); if value.state == .abseiling { break } }
        let point = value.position, anchor = value.ropeSession?.anchor
        value.updateTerrain(terrain(x: 320, y: 30))
        XCTAssertEqual(value.position.x, point.x + 20, accuracy: 0.0001)
        XCTAssertEqual(value.position.y, point.y + 10, accuracy: 0.0001)
        XCTAssertEqual(value.ropeSession?.anchor, anchor)
        value.updateTerrain(.init(windows: [], viewport: viewport))
        XCTAssertEqual(value.state, .recovering)
        XCTAssertNil(value.ropeSession)
        value.beginDrag(at: value.position)
        XCTAssertNil(value.hookPosition)
        XCTAssertFalse(value.hasPendingTravel)
    }
}

extension RopePhysicsTests {
    func testConstraintResultsMatchAcrossPresentationFrameRates() {
        let guide = RopeSupport.point(.init(x: 0, y: 300))
        var a = RopeDynamics(position: .init(x: -100, y: 100), velocity: .init(x: 20, y: 0), length: hypot(100, 200))
        var b = a
        for _ in 0..<120 { a.advance(by: 1.0 / 120, support: guide) }
        for _ in 0..<30 { b.advance(by: 1.0 / 30, support: guide) }
        XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.001)
        XCTAssertEqual(a.position.y, b.position.y, accuracy: 0.001)
    }
    func testRopeClimbingHandsStayOnLineAndLimbsRemainFiniteAtAngles() {
        for degrees in stride(from: -80.0, through: 80, by: 5) {
            let angle = degrees * .pi / 180
            let direction = WorldPoint(x: sin(angle), y: cos(angle))
            for tick in 0..<60 {
                let pose = RopeAnimation.pose(mode: .climbing, direction: direction, velocity: .zero, pullTime: Double(tick) / 60)
                XCTAssertTrue(pose.sway.isFinite)
                for (root, hand) in [(WorldPoint(x: -10, y: pose.hips.y + 20), pose.leftHand), (WorldPoint(x: 10, y: pose.hips.y + 20), pose.rightHand)] {
                    let limb = TwoBoneIK.solve(root: root, target: hand, upper: 12, lower: 12, pole: .init(x: root.x + 24, y: root.y - 16))
                    XCTAssertFalse(limb.isClamped, "\(degrees)° at \(tick): \(hand)")
                }
            }
        }
    }
    func testSwingCanHoldThenAbseilOrClimbWithoutChangingLine() {
        var value = explorer(.init(x: 450, y: 370))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<12000 { value.advance(by: 1.0 / 120); if value.state == .abseiling && value.position.y < 250 { break } }
        XCTAssertTrue(value.requestActivity(.swing))
        let anchor = value.ropeSession?.anchor, length = value.ropeSession?.body.length
        var leftWall = false
        for _ in 0..<600 {
            value.advance(by: 1.0 / 120)
            leftWall = leftWall || (value.ropeSession?.anchor.edge == .left ? value.position.x < 266 : value.position.x > 634)
        }
        XCTAssertTrue(leftWall)
        XCTAssertEqual(value.ropeSession?.anchor, anchor)
        XCTAssertEqual(value.ropeSession?.body.length, length)
        XCTAssertEqual(value.state, .swinging)
        XCTAssertTrue(value.requestActivity(.ropeClimb))
        XCTAssertEqual(value.ropeSession?.anchor, anchor)
        XCTAssertEqual(value.state, .ropeClimbing)
    }
}

extension RopePhysicsTests {
    func testAStandingExplorerCanLoseTheLandingWindowAndStayOnTheSameRope() {
        let host = terrain().windows[0]
        let lower = DesktopWindow(id: 2, frame: .init(x: 100, y: 40, width: 220, height: 160))
        let layout = TerrainSnapshot(windows: [lower, host], viewport: viewport)
        var value = explorer(.init(x: 450, y: 370))
        value.updateTerrain(layout)
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<15000 { value.advance(by: 1.0 / 120); if value.state == .idle && !value.hasPendingTravel { break } }
        XCTAssertEqual(value.attachment?.owner, .window(2))
        let anchor = value.ropeSession?.anchor
        XCTAssertNotNil(anchor)
        value.updateTerrain(terrain())
        XCTAssertEqual(value.state, .swinging)
        XCTAssertEqual(value.ropeSession?.anchor, anchor)
        value.advance(by: 0.1)
        XCTAssertNotNil(value.ropeSession)
    }
}

extension RopePhysicsTests {
    func testMirroredGrappleCompletesFromTheRight() {
        var value = explorer(.init(x: 850, y: 0))
        XCTAssertTrue(value.requestActivity(.grapple))
        XCTAssertTrue([TerrainEdge.right, .front].contains(value.ropeSession!.anchor.edge))
        for _ in 0..<18000 { value.advance(by: 1.0 / 120); if value.state == .idle && !value.hasPendingTravel { break } }
        XCTAssertEqual(value.attachment?.owner, .window(1))
        XCTAssertEqual(value.attachment?.edge, .top)
    }
    func testTallAbseilHasEnoughLineToReachTheFloor() {
        let layout = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 1000))], viewport: .init(x: 0, y: 0, width: 1000, height: 1400))
        var value = ExplorerInteraction(position: .init(x: 450, y: 1020), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 1324)))
        value.autonomous = true; value.updateTerrain(layout)
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<6000 { value.advance(by: 1.0 / 120); if value.state == .idle && !value.hasPendingTravel { break } }
        XCTAssertEqual(value.attachment?.edge, .floor)
        XCTAssertEqual(value.ropeSession?.mode, .supported)
        XCTAssertGreaterThan(value.ropeSession?.body.length ?? 0, 700)
    }
    func testLosingBothTheRopeAndLandingSupportDoesNotLeaveAnIdleFloater() {
        let lower = DesktopWindow(id: 2, frame: .init(x: 100, y: 40, width: 220, height: 160))
        var value = explorer(.init(x: 450, y: 370))
        value.updateTerrain(.init(windows: [lower] + terrain().windows, viewport: viewport))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<12000 { value.advance(by: 1.0 / 120); if value.state == .idle && !value.hasPendingTravel { break } }
        value.updateTerrain(.init(windows: [], viewport: viewport))
        XCTAssertNil(value.ropeSession)
        XCTAssertEqual(value.state, .recovering)
    }
}

extension RopePhysicsTests {
    func testGrapplePlanAvoidsAWindowBlockingTheFinalMantle() {
        let layout = TerrainSnapshot(windows: [
            .init(id: 1, frame: .init(x: 600, y: 260, width: 325, height: 272)),
            .init(id: 2, frame: .init(x: 240, y: 20, width: 325, height: 212))
        ], viewport: viewport)
        let graph = NavigationGraph(terrain: layout)
        XCTAssertTrue(graph.steps.allSatisfy { graph.isValid($0) })
        var value = explorer(.init(x: 855, y: 0))
        value.updateTerrain(layout)
        XCTAssertTrue(value.requestActivity(.grapple))
        var fired = false
        for _ in 0..<18000 {
            value.advance(by: 1.0 / 120); fired = fired || value.state == .grappling
            if fired && value.state == .idle && !value.hasPendingTravel { break }
        }
        XCTAssertTrue(fired)
        XCTAssertEqual(value.attachment?.edge, .top)
    }
}

extension RopePhysicsTests {
    func testWindowVelocityUsesTheActualSnapshotIntervalAfterAPause() {
        var value = explorer(.init(x: 450, y: 370))
        XCTAssertTrue(value.requestActivity(.abseil))
        for _ in 0..<12000 { value.advance(by: 1.0 / 120); if value.state == .abseiling { break } }
        var fast = value, resumed = value
        fast.updateTerrain(terrain(x: 320), sampleElapsed: 0.1)
        resumed.updateTerrain(terrain(x: 320), sampleElapsed: 10)
        let fastRope = fast.ropeSession!, resumedRope = resumed.ropeSession!
        XCTAssertEqual(fastRope.releaseVelocity.x - fastRope.body.velocity.x, 200, accuracy: 0.000001)
        XCTAssertEqual(resumedRope.releaseVelocity.x - resumedRope.body.velocity.x, 2, accuracy: 0.000001)
    }
}


extension RopePhysicsTests {
    func testHighAlignedGrappleClimbsTheMiddleAndStandsOnTheRoof() {
        let layout = TerrainSnapshot(windows: [.init(id: 10, frame: .init(x: 200, y: 50, width: 600, height: 950))], viewport: .init(x: 0, y: 0, width: 1200, height: 1400))
        var value = ExplorerInteraction(position: .init(x: 487, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1176, y: 1324)))
        value.autonomous = true; value.updateTerrain(layout)
        XCTAssertTrue(value.requestActivity(.grapple))
        XCTAssertEqual(value.ropeSession?.anchor.edge, .front)
        XCTAssertEqual(value.grappleTarget?.x ?? 0, 487, accuracy: 0.01)
        XCTAssertEqual(value.grappleTarget?.y ?? 0, 1001, accuracy: 0.01)
        var climbed = false, mantled = false
        for _ in 0..<24000 {
            value.advance(by: 1.0 / 120)
            climbed = climbed || value.state == .ropeClimbing
            mantled = mantled || value.state == .traversingEdge
            if value.state == .idle && !value.hasPendingTravel { break }
        }
        XCTAssertTrue(climbed); XCTAssertTrue(mantled)
        XCTAssertEqual(value.attachment?.owner, .window(10))
        XCTAssertEqual(value.attachment?.edge, .top)
        XCTAssertEqual(value.position.x, 487, accuracy: 1)
        XCTAssertEqual(value.position.y, 1000, accuracy: 0.01)
    }
    func testFrontAnchorMovesWithWindowAndKeepsStraightRope() {
        let anchor = RopeAnchor(windowID: 1, edge: .front, offset: 150)
        let before = anchor.resolve(in: terrain())!
        let after = anchor.resolve(in: terrain(x: 340, y: 50))!
        XCTAssertEqual(after.anchor.x - before.anchor.x, 40)
        XCTAssertEqual(after.anchor.y - before.anchor.y, 30)
        XCTAssertEqual(before.wrappedLength, 0)
        XCTAssertEqual(before.sideTangent, before.anchor)
        XCTAssertEqual(before.length(to: .init(x: 450, y: 100)), 271, accuracy: 0.01)
    }
    func testGrappleAtDisplayEdgeDoesNotNeedAnExposedSide() {
        let layout = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 0, y: 20, width: 1000, height: 600))], viewport: viewport)
        let graph = NavigationGraph(terrain: layout)
        let floor = TerrainAttachment(owner: .screen, edge: .floor, offset: 500)
        let plan = graph.activityRoute(.grapple, from: floor)
        XCTAssertEqual(plan?.first?.kind, .grappling)
        XCTAssertEqual(plan?.first?.to.edge, .front)
        XCTAssertEqual(plan?.last?.to.edge, .top)
        XCTAssertTrue(plan?.allSatisfy { graph.isValid($0) } ?? false)
    }
}

extension RopePhysicsTests {
    func testClimbingElbowsKeepTheirHingeThroughHandSwapsAtEveryRopeAngle() {
        for degrees in stride(from: -80.0, through: 80, by: 5) {
            let angle = degrees * .pi / 180
            var previous: [WorldPoint] = []
            for tick in 0...480 {
                let pose = RopeAnimation.pose(mode: .climbing, direction: .init(x: sin(angle), y: cos(angle)), velocity: .zero, pullTime: Double(tick) / 240)
                XCTAssertGreaterThan(pose.leftHand.x, -10)
                XCTAssertLessThan(pose.rightHand.x, 10)
                var joints: [WorldPoint] = []
                for (root, hand, bend) in [(WorldPoint(x: -10, y: pose.hips.y + 20), pose.leftHand, pose.leftElbowBend), (.init(x: 10, y: pose.hips.y + 20), pose.rightHand, pose.rightElbowBend)] {
                    XCTAssertNotNil(bend)
                    let arm = TwoBoneIK.solve(root: root, target: hand, upper: 12, lower: 12, bend: bend ?? 1)
                    XCTAssertFalse(arm.isClamped)
                    let cross = (hand.x - root.x) * (arm.joint.y - root.y) - (hand.y - root.y) * (arm.joint.x - root.x)
                    XCTAssertEqual(cross < 0 ? -1.0 : 1.0, bend)
                    joints.append(arm.joint)
                }
                if previous.count == 2 {
                    for i in 0..<2 { XCTAssertLessThan(hypot(joints[i].x - previous[i].x, joints[i].y - previous[i].y), 1.5, "Elbow snap at \(degrees)° / \(tick)") }
                }
                previous = joints
            }
        }
    }
}


extension RopePhysicsTests {
    func testVerticalRopeGripsStayPlantedDuringTheirLoadedPulls() {
        for tick in 0...60 {
            let t = Double(tick) / 120
            let left = RopeAnimation.pose(mode: .climbing, direction: .init(x: 0, y: 1), velocity: .zero, pullTime: t)
            XCTAssertEqual(ClimbingGait.height(at: t) + left.leftHand.y, 56, accuracy: 0.0001)
            let rightTime = t + 0.5
            let right = RopeAnimation.pose(mode: .climbing, direction: .init(x: 0, y: 1), velocity: .zero, pullTime: rightTime)
            XCTAssertEqual(ClimbingGait.height(at: rightTime) + right.rightHand.y, 68, accuracy: 0.0001)
        }
    }
}
