import XCTest
@testable import ExpeditionCore

final class ActivityAndTraversalTests: XCTestCase {
    private let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
    private var terrain: TerrainSnapshot { .init(windows: [.init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))], viewport: viewport) }
    private func explorer(at point: WorldPoint) -> ExplorerInteraction {
        var subject = ExplorerInteraction(position: point, bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        subject.autonomous = true; subject.runsMission = true; subject.updateTerrain(terrain)
        return subject
    }
    func testEveryMenuActivityCanRunAndManualActivitiesStop() {
        for activity in [ExplorerActivity.walk, .climb, .abseil, .parachute] {
            var subject = explorer(at: .init(x: 450, y: 370))
            subject.setIdleExploration(false)
            XCTAssertTrue(subject.availableActivities.contains(activity), activity.title)
            XCTAssertTrue(subject.requestActivity(activity))
            var states = Set<ExplorerInteraction.State>(), edgeMotions = Set<ExplorerMotion>()
            for _ in 0..<12000 {
                subject.advance(by: 1.0 / 60)
                states.insert(subject.state)
                if let motion = subject.edgeMotion { edgeMotions.insert(motion) }
                if !subject.hasPendingTravel && subject.state == .idle { break }
            }
            let expected: ExplorerInteraction.State = activity == .walk ? .walking : (activity == .climb ? .climbing : (activity == .abseil ? .abseiling : .recovering))
            XCTAssertTrue(states.contains(expected), "\(activity): \(states)")
            if activity == .climb { XCTAssertTrue(edgeMotions.contains(.mantling)) }
            if activity == .abseil { XCTAssertTrue(edgeMotions.contains(.lowering)) }
            if activity == .parachute { XCTAssertTrue(edgeMotions.contains(.launching)) }
            XCTAssertFalse(subject.hasPendingTravel)
            let resting = subject.position
            for _ in 0..<600 { subject.advance(by: 1.0 / 60) }
            XCTAssertEqual(subject.position, resting)
            XCTAssertEqual(subject.requestedActivity, activity)
            XCTAssertTrue(subject.requestActivity(.automatic))
            XCTAssertTrue(subject.runsMission)
        }
    }
    func testUnavailableActivitiesAreHonestOnAnEmptyDesktop() {
        var subject = explorer(at: .init(x: 450, y: 0))
        subject.updateTerrain(.init(windows: [], viewport: viewport))
        XCTAssertFalse(subject.availableActivities.contains(.abseil))
        XCTAssertFalse(subject.requestActivity(.abseil))
        XCTAssertEqual(subject.activityIssue, "Abseil: no reachable route")
    }
    func testActivityDuringFlightQueuesForLandingWithoutTeleporting() {
        var subject = explorer(at: .init(x: 450, y: 600))
        XCTAssertEqual(subject.state, .recovering)
        let before = subject.position
        XCTAssertTrue(subject.requestActivity(.walk))
        XCTAssertEqual(subject.position, before)
        XCTAssertEqual(subject.pendingActivity, .walk)
        var walked = false
        for _ in 0..<12000 { subject.advance(by: 1.0 / 60); walked = walked || subject.state == .walking; if walked && !subject.hasPendingTravel { break } }
        XCTAssertTrue(walked)
        XCTAssertNil(subject.pendingActivity)
    }
    func testWalkingUsesUnchangedFootCycleAndHasNoStanceSlip() {
        let tuning = AnimationTuning()
        XCTAssertEqual(WalkingGait.distance(from: 0, to: 1), 40, accuracy: 0.00001)
        for tick in 1..<119 {
            let t = Double(tick) / 120
            let next = t + 1.0 / 120
            let pose = AnimationClips.sample(.walking, time: t, tuning: tuning)
            let after = AnimationClips.sample(.walking, time: next, tuning: tuning)
            let beforeFoot = t < 0.5 ? pose.rightFoot : pose.leftFoot
            let afterFoot = t < 0.5 ? after.rightFoot : after.leftFoot
            let distance = WalkingGait.distance(from: t, to: next)
            XCTAssertEqual(beforeFoot.x, distance + afterFoot.x, accuracy: 0.000001)
        }
        // The actual movement state uses the exact same clock and integral, in both directions.
        for start in [100.0, 850] {
            var subject = explorer(at: .init(x: start, y: 0))
            XCTAssertTrue(subject.requestActivity(.walk))
            for _ in 0..<20 { subject.advance(by: 1.0 / 60) }
            XCTAssertEqual(abs(subject.position.x - start), WalkingGait.distance(from: 0, to: subject.walkingTime), accuracy: 0.00001)
        }
    }
    func testClimbingFeetNeverCrossHipsOrFlipKneeBranch() {
        for tick in 0..<480 {
            let contacts = ClimbingContacts(heightAlongWall: Double(tick) / 10)
            for time in [0.0, 0.5, 1, 1.5] {
                let pose = AnimationClips.sample(.climbing, time: time, tuning: .init())
                for (root, sole) in [(WorldPoint(x: pose.hips.x - 7, y: pose.hips.y), contacts.leftFoot), (WorldPoint(x: pose.hips.x + 7, y: pose.hips.y), contacts.rightFoot)] {
                    let ankle = WorldPoint(x: sole.x, y: sole.y + 3)
                    XCTAssertLessThan(ankle.y, root.y)
                    let solution = TwoBoneIK.solve(root: root, target: ankle, upper: 13.5, lower: 13.5)
                    XCTAssertFalse(solution.isClamped)
                    XCTAssertGreaterThan(solution.joint.x, (root.x + ankle.x) / 2)
                }
            }
        }
    }
    func testCornerPathsAndPosesHaveContinuousEndpoints() {
        let outside = WorldPoint(x: 276, y: 318), inside = WorldPoint(x: 324, y: 370)
        XCTAssertEqual(EdgeTraversal.position(.mantling, progress: 0, from: outside, to: inside), outside)
        XCTAssertEqual(EdgeTraversal.position(.mantling, progress: 1, from: outside, to: inside), inside)
        XCTAssertEqual(EdgeTraversal.position(.lowering, progress: 0, from: inside, to: outside), inside)
        XCTAssertEqual(EdgeTraversal.position(.lowering, progress: 1, from: inside, to: outside), outside)
        for motion in [ExplorerMotion.mantling, .lowering, .launching] {
            var previous = EdgeTraversal.pose(motion, progress: 0)
            for tick in 1...120 {
                let pose = EdgeTraversal.pose(motion, progress: Double(tick) / 120)
                XCTAssertLessThan(hypot(pose.hips.x - previous.hips.x, pose.hips.y - previous.hips.y), 2)
                for foot in [pose.leftFoot, pose.rightFoot] { XCTAssertLessThan(foot.y + 3, pose.hips.y) }
                previous = pose
            }
        }
    }
    func testGrabAndSupportLossInterruptCornerAndLaunch() {
        for activity in [ExplorerActivity.climb, .abseil, .parachute] {
            var subject = explorer(at: .init(x: 450, y: 370))
            XCTAssertTrue(subject.requestActivity(activity))
            for _ in 0..<12000 { subject.advance(by: 1.0 / 60); if subject.state == .traversingEdge { break } }
            XCTAssertEqual(subject.state, .traversingEdge)
            var grabbed = subject
            grabbed.beginDrag(at: grabbed.position)
            XCTAssertNil(grabbed.edgeMotion)
            XCTAssertFalse(grabbed.hasPendingTravel)
            let position = subject.position
            subject.updateTerrain(.init(windows: [], viewport: viewport))
            XCTAssertEqual(subject.state, .recovering)
            XCTAssertEqual(subject.position, position)
        }
    }
}

extension ActivityAndTraversalTests {
    func testMantlePlantsTheFrontBootWhileWeightTransfersOntoTheTop() {
        for facing in [-1.0, 1] {
            let outside = WorldPoint(x: -24 * facing, y: -52), inside = WorldPoint(x: 24 * facing, y: 0)
            for tick in 70...100 {
                let p = Double(tick) / 100
                let root = EdgeTraversal.position(.mantling, progress: p, from: outside, to: inside)
                let pose = EdgeTraversal.pose(.mantling, progress: p)
                XCTAssertEqual(root.x + pose.leftFoot.x * facing, 16 * facing, accuracy: 0.00001)
                XCTAssertEqual(root.y + pose.leftFoot.y, 0, accuracy: 0.00001)
            }
        }
    }
}

extension ActivityAndTraversalTests {
    func testClimbingLiftMatchesPullsAndContactClock() {
        XCTAssertEqual(ClimbingGait.distance(from: 0, to: 0.5), 12, accuracy: 0.000001)
        XCTAssertEqual(ClimbingGait.distance(from: 0, to: 1), 24, accuracy: 0.000001)
        XCTAssertGreaterThan(ClimbingGait.distance(from: 0.2, to: 0.3), ClimbingGait.distance(from: 0.45, to: 0.55))
        for tick in -640...1200 {
            let height = Double(tick) / 10
            XCTAssertEqual(ClimbingGait.height(at: ClimbingGait.time(atHeight: height)), height, accuracy: 0.000001)
        }
        for t in [0.05, 0.15, 0.55, 0.65] {
            let height = ClimbingGait.height(at: t)
            XCTAssertEqual(height + ClimbingContacts(heightAlongWall: height).leftHand.y, 55, accuracy: 0.000001)
        }
        var subject = explorer(at: .init(x: 100, y: 0))
        XCTAssertTrue(subject.requestActivity(.climb))
        for _ in 0..<12000 { subject.advance(by: 1.0 / 120); if subject.state == .climbing { break } }
        let start = subject.position.y, clock = subject.climbingTime
        for _ in 0..<30 { subject.advance(by: 1.0 / 120) }
        XCTAssertEqual(subject.position.y - start, ClimbingGait.distance(from: clock, to: subject.climbingTime), accuracy: 0.000001)
    }
    func testRopePinsToTopAndWrapsRoundedCornersSymmetrically() {
        let frame = WorldRect(x: 100, y: 100, width: 400, height: 200)
        let left = AbseilRope(window: frame, edge: .left), right = AbseilRope(window: frame, edge: .right)
        XCTAssertEqual(left.anchor, .init(x: 128, y: 301))
        XCTAssertEqual(left.topTangent, .init(x: 110, y: 301))
        XCTAssertEqual(left.sideTangent, .init(x: 99, y: 290))
        for (a, b) in zip([left.anchor, left.topTangent, left.control1, left.control2, left.sideTangent], [right.anchor, right.topTangent, right.control1, right.control2, right.sideTangent]) {
            XCTAssertEqual(a.x + b.x, 600, accuracy: 0.000001)
            XCTAssertEqual(a.y, b.y)
        }
        for tick in 0...20 {
            let t = Double(tick) / 20, u = 1 - t
            let x = u*u*u*left.topTangent.x + 3*u*u*t*left.control1.x + 3*u*t*t*left.control2.x + t*t*t*left.sideTangent.x
            let y = u*u*u*left.topTangent.y + 3*u*u*t*left.control1.y + 3*u*t*t*left.control2.y + t*t*t*left.sideTangent.y
            XCTAssertEqual(hypot(x - 110, y - 290), 11, accuracy: 0.005)
        }
    }
    func testCoveredTopPinInvalidatesRopeEvenIfCornerAndWallStayVisible() {
        let step = TravelStep(from: .init(owner: .window(1), edge: .left, offset: 150), to: .init(owner: .window(1), edge: .left, offset: -20), kind: .abseiling)
        let covered = TerrainSnapshot(windows: [.init(id: 2, frame: .init(x: 318, y: 360, width: 40, height: 80))] + terrain.windows, viewport: viewport)
        XCTAssertNotNil(TerrainSupport.resolve(step.from, in: covered))
        XCTAssertFalse(NavigationGraph(terrain: covered).isValid(step))
    }
}

extension ActivityAndTraversalTests {
    func testRopeCurveIsTangentToBothStraightLeadsAsHandsDescend() {
        let window = WorldRect(x: 100, y: 100, width: 400, height: 200)
        for edge in [TerrainEdge.left, .right] {
            for handY in [284.0, 260, 220, 150, 80] {
                let grip = WorldPoint(x: edge == .left ? 76 : 524, y: handY)
                let guide = AbseilRope(window: window, edge: edge, grip: grip)
                let topLine = WorldPoint(x: guide.topTangent.x - guide.anchor.x, y: guide.topTangent.y - guide.anchor.y)
                let curveStart = WorldPoint(x: guide.control1.x - guide.topTangent.x, y: guide.control1.y - guide.topTangent.y)
                let curveEnd = WorldPoint(x: guide.sideTangent.x - guide.control2.x, y: guide.sideTangent.y - guide.control2.y)
                let freeLine = WorldPoint(x: grip.x - guide.sideTangent.x, y: grip.y - guide.sideTangent.y)
                func sameDirection(_ a: WorldPoint, _ b: WorldPoint) {
                    XCTAssertEqual((a.x*b.y - a.y*b.x) / (hypot(a.x,a.y)*hypot(b.x,b.y)), 0, accuracy: 0.0000001)
                    XCTAssertGreaterThan(a.x*b.x + a.y*b.y, 0)
                }
                sameDirection(topLine, curveStart)
                sameDirection(curveEnd, freeLine)
            }
        }
    }
}
