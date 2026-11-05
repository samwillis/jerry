import Foundation
import XCTest
@testable import ExpeditionCore

final class RigAnimationTests: XCTestCase {
    private func distance(_ a: WorldPoint, _ b: WorldPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    func testStraighterWalkingStanceKeepsBothFootTargetsReachableAcrossTuningRange() {
        for stride in [2.0, 10, 12] {
            for bounce in [0.0, 1, 2] {
                var tuning = AnimationTuning()
                tuning.stride = stride; tuning.bounce = bounce
                for step in 0..<120 {
                    let pose = AnimationClips.sample(.walking, time: Double(step) / 120, tuning: tuning)
                    for (foot, offset) in [(pose.leftFoot, -7.0), (pose.rightFoot, 7.0)] {
                        let root = WorldPoint(x: pose.hips.x + offset, y: pose.hips.y)
                        let target = WorldPoint(x: foot.x, y: foot.y + ExpeditionConfiguration.ankleHeight)
                        let solution = TwoBoneIK.solve(root: root, target: target, upper: ExpeditionConfiguration.legSegmentLength, lower: ExpeditionConfiguration.legSegmentLength, pole: .init(x: root.x + 24, y: root.y - 6))
                        XCTAssertFalse(solution.isClamped)
                    }
                }
            }
        }
    }

    func testRecoverySlowsAsCanopyOpensAndIsIndependentOfStepSize() {
        XCTAssertGreaterThan(RecoveryAnimation.distance(from: 0, to: 0.1), RecoveryAnimation.distance(from: 1, to: 1.1))
        let whole = RecoveryAnimation.distance(from: 0, to: 2)
        let pieces = (0..<200).reduce(0.0) { $0 + RecoveryAnimation.distance(from: Double($1) / 100, to: Double($1 + 1) / 100) }
        XCTAssertEqual(whole, pieces, accuracy: 0.00001)
    }

    func testReachableLimbKeepsBothSegmentLengthsAndExactContact() {
        let root = WorldPoint(x: 10, y: 40), target = WorldPoint(x: 20, y: 22)
        let solution = TwoBoneIK.solve(root: root, target: target, upper: 12, lower: 13, bend: 1)
        XCTAssertEqual(distance(root, solution.joint), 12, accuracy: 0.00001)
        XCTAssertEqual(distance(solution.joint, solution.end), 13, accuracy: 0.00001)
        XCTAssertEqual(distance(solution.end, target), 0, accuracy: 0.00001)
        XCTAssertFalse(solution.isClamped)
    }

    func testUnreachableAndCoincidentTargetsStayFiniteAndWithinReach() {
        for target in [WorldPoint(x: 500, y: 0), .zero, .init(x: 0.001, y: 0)] {
            let solution = TwoBoneIK.solve(root: .zero, target: target, upper: 12, lower: 12, bend: -1)
            XCTAssertTrue(solution.joint.x.isFinite && solution.joint.y.isFinite)
            XCTAssertLessThanOrEqual(distance(.zero, solution.end), 24)
            XCTAssertEqual(distance(.zero, solution.joint), 12, accuracy: 0.0001)
            XCTAssertEqual(distance(solution.joint, solution.end), 12, accuracy: 0.0001)
        }
    }

    func testMirroredTargetAndBendProduceMirroredJoint() {
        let a = TwoBoneIK.solve(root: .zero, target: .init(x: 10, y: -18), upper: 12, lower: 12, bend: 1)
        let b = TwoBoneIK.solve(root: .zero, target: .init(x: -10, y: -18), upper: 12, lower: 12, bend: -1)
        XCTAssertEqual(a.joint.x, -b.joint.x, accuracy: 0.00001)
        XCTAssertEqual(a.joint.y, b.joint.y, accuracy: 0.00001)
    }

    func testClimbingContactsStayFixedWhileBodyMoves() {
        let a = AnimationClips.sample(.climbing, time: 0, tuning: .init())
        let b = AnimationClips.sample(.climbing, time: 0.4, tuning: .init())
        XCTAssertEqual(a.leftHand, b.leftHand)
        XCTAssertEqual(a.rightFoot, b.rightFoot)
        XCTAssertNotEqual(a.hips, b.hips)
    }

    func testEveryMotionProducesFinitePoseOverSeveralCycles() {
        for motion in ExplorerMotion.allCases {
            for step in 0..<600 {
                let pose = AnimationClips.sample(motion, time: Double(step) / 30, tuning: .init())
                for point in [pose.hips, pose.leftHand, pose.rightHand, pose.leftFoot, pose.rightFoot] {
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                }
            }
        }
    }

    func testGrabInterruptsBlendWithoutJumpingOrOldClipCompletion() {
        var animator = RigAnimator()
        animator.select(.walking)
        animator.advance(by: 0.1)
        let before = animator.pose
        animator.select(.held)
        let first = animator.advance(by: 0)
        XCTAssertEqual(first.hips, before.hips)
        XCTAssertEqual(first.leftHand, before.leftHand)
        for _ in 0..<30 { animator.advance(by: 0.1) }
        XCTAssertEqual(animator.motion, .held)
        animator.select(.idle)
        for _ in 0..<30 { animator.advance(by: 0.1) }
        XCTAssertEqual(animator.motion, .idle)
    }

    func testPausedClockAndRestartAreDeterministic() {
        var animator = RigAnimator()
        animator.select(.walking)
        animator.advance(by: 0.1)
        let time = animator.time
        animator.advance(by: 0)
        XCTAssertEqual(animator.time, time)
        animator.select(.walking, restart: true)
        XCTAssertEqual(animator.time, 0)
        animator.advance(by: .nan)
        XCTAssertEqual(animator.time, 0)
    }

    func testRestartReturnsToSamePoseRegardlessOfPreviousClip() {
        var a = RigAnimator(), b = RigAnimator()
        a.select(.held)
        a.advance(by: 0.1)
        b.select(.climbing)
        b.advance(by: 0.1)
        a.select(.walking, restart: true)
        b.select(.walking, restart: true)
        XCTAssertEqual(a.pose.hips, b.pose.hips)
        XCTAssertEqual(a.pose.leftHand, b.pose.leftHand)
        XCTAssertEqual(a.pose.leftFoot, b.pose.leftFoot)
        XCTAssertEqual(a.time, b.time)
    }

    func testKneePoleBendsTowardsToesAndElbowPoleBehindBody() {
        let root = WorldPoint(x: 0, y: 30)
        let knee = TwoBoneIK.solve(root: root, target: .init(x: 0, y: 5), upper: 15, lower: 15, pole: .init(x: 24, y: 24))
        XCTAssertGreaterThan(knee.joint.x, root.x)
        for handY in [10.0, 50.0] {
            let elbow = TwoBoneIK.solve(root: root, target: .init(x: 0, y: handY), upper: 12, lower: 12, pole: .init(x: -24, y: 24))
            XCTAssertLessThan(elbow.joint.x, root.x)
        }
    }

    func testMirroringPolesFlipsKneesAndToesTogether() {
        let root = WorldPoint(x: 0, y: 30)
        let right = TwoBoneIK.solve(root: root, target: .init(x: 5, y: 5), upper: 15, lower: 15, pole: .init(x: 24, y: 24))
        let left = TwoBoneIK.solve(root: root, target: .init(x: -5, y: 5), upper: 15, lower: 15, pole: .init(x: -24, y: 24))
        XCTAssertEqual(right.joint.x, -left.joint.x, accuracy: 0.00001)
        XCTAssertEqual(right.joint.y, left.joint.y, accuracy: 0.00001)
    }

    func testLiftedFeetSwingForwardsAndPlantedFeetMoveBackwards() {
        let earlySwing = AnimationClips.sample(.walking, time: 0.125, tuning: .init())
        let lateSwing = AnimationClips.sample(.walking, time: 0.375, tuning: .init())
        XCTAssertGreaterThan(earlySwing.leftFoot.y, 0)
        XCTAssertGreaterThan(lateSwing.leftFoot.y, 0)
        XCTAssertGreaterThan(lateSwing.leftFoot.x, earlySwing.leftFoot.x)
        XCTAssertEqual(earlySwing.rightFoot.y, 0)
        XCTAssertEqual(lateSwing.rightFoot.y, 0)
        XCTAssertLessThan(lateSwing.rightFoot.x, earlySwing.rightFoot.x)

        let otherEarly = AnimationClips.sample(.walking, time: 0.625, tuning: .init())
        let otherLate = AnimationClips.sample(.walking, time: 0.875, tuning: .init())
        XCTAssertGreaterThan(otherEarly.rightFoot.y, 0)
        XCTAssertGreaterThan(otherLate.rightFoot.y, 0)
        XCTAssertGreaterThan(otherLate.rightFoot.x, otherEarly.rightFoot.x)
        XCTAssertEqual(otherEarly.leftFoot.y, 0)
        XCTAssertEqual(otherLate.leftFoot.y, 0)
        XCTAssertLessThan(otherLate.leftFoot.x, otherEarly.leftFoot.x)
    }
}
