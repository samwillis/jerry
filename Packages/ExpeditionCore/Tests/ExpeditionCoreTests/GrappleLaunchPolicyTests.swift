import XCTest
@testable import ExpeditionCore

final class GrappleLaunchPolicyTests: XCTestCase {
    private func anchor(from feet: WorldPoint, angle: Double, side: Double = 1) -> WorldPoint {
        .init(x: feet.x + side * (8 + 400 * tan(angle * .pi / 180)), y: feet.y + 446)
    }
    func testFloorConeAcceptsItsBoundaryAndRejectsWiderShotsOnBothSides() {
        let feet = WorldPoint(x: 500, y: 0)
        for side in [-1.0, 1.0] {
            XCTAssertTrue(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 10, side: side), floorY: 0))
            XCTAssertFalse(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 10.1, side: side), floorY: 0))
        }
    }
    func testElevatedConeAcceptsItsBoundaryAndRejectsWiderShotsOnBothSides() {
        let feet = WorldPoint(x: 500, y: 200)
        for side in [-1.0, 1.0] {
            XCTAssertTrue(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 35, side: side), floorY: 0))
            XCTAssertFalse(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 35.1, side: side), floorY: 0))
        }
        XCTAssertFalse(GrappleLaunchPolicy.allows(feet: feet, anchor: .init(x: 500, y: 100), floorY: 0))
    }
    func testFloorRuleUsesTheViewportFloorRatherThanZero() {
        let feet = WorldPoint(x: 500, y: 300)
        XCTAssertFalse(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 20), floorY: 300))
        XCTAssertTrue(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor(from: feet, angle: 20), floorY: 0))
    }
    func testRoutingWalksUnderTheRoofBeforeUsingTheNarrowFloorCone() {
        let terrain = TerrainSnapshot(windows: [.init(id: 1, frame: .init(x: 680, y: 50, width: 100, height: 180))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        let graph = NavigationGraph(terrain: terrain)
        let floor = TerrainAttachment(owner: .screen, edge: .floor, offset: 100)
        XCTAssertTrue(graph.grappleSteps(from: floor).isEmpty)
        let plan = graph.activityRoute(.grapple, from: floor)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.first?.kind, .walking)
        for shot in plan ?? [] where shot.kind == .grappling {
            let feet = TerrainSupport.resolve(shot.from, in: terrain)!
            let anchor = RopeAnchor(windowID: 1, edge: shot.to.edge, offset: shot.to.offset).resolve(in: terrain)!.anchor
            XCTAssertTrue(GrappleLaunchPolicy.allows(feet: feet, anchor: anchor, floorY: 0))
        }
        XCTAssertNil(graph.aimedGrapple(from: .init(x: 100, y: 0), toward: .init(x: 730, y: 230)))
        XCTAssertNotNil(graph.aimedGrapple(from: .init(x: 730, y: 0), toward: .init(x: 730, y: 230)))
    }
    func testAIWalksAcrossTheFloorAndFiresOnlyInsideItsLaunchCone() {
        let terrain = TerrainSnapshot(windows: [.init(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        var walked = false, fired = false
        for _ in 0..<120 * 40 {
            let wasFiring = explorer.ropeSession?.mode == .firing || explorer.hasPendingGrapple
            let feet = explorer.position
            explorer.steerAgent(towardHand: .init(x: 900, y: 500))
            if !wasFiring, explorer.ropeSession?.mode == .firing || explorer.hasPendingGrapple {
                XCTAssertTrue(walked)
                XCTAssertTrue(GrappleLaunchPolicy.allows(feet: feet, anchor: explorer.grappleTarget!, floorY: 0))
                fired = true
            }
            explorer.advance(by: 1.0 / 120)
            walked = walked || [.walking, .running].contains(explorer.state)
        }
        XCTAssertTrue(fired)
        XCTAssertLessThan(abs(explorer.position.x - 880), 35)
        XCTAssertLessThan(abs(explorer.position.y - 455), 35)
    }

}
