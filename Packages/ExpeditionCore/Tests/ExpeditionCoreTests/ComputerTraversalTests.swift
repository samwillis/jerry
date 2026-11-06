import XCTest
@testable import ExpeditionCore

final class ComputerTraversalTests: XCTestCase {
    func testPhysicalAutopilotUsesARealRopeAndMakesProgress() {
        let rim = DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1))
        let terrain = TerrainSnapshot(windows: [rim], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        var usedRope = false
        for _ in 0..<120 * 30 {
            explorer.steerAgent(towardHand: .init(x: 600, y: 450)); explorer.advance(by: 1.0 / 120)
            usedRope = usedRope || explorer.ropeSession != nil
            XCTAssertTrue(explorer.position.x.isFinite && explorer.position.y.isFinite)
        }
        XCTAssertTrue(usedRope)
        XCTAssertLessThan(abs(explorer.position.x - 580), 35)
        XCTAssertLessThan(abs(explorer.position.y - 405), 35)
    }
    func testAutopilotCanCrossTheMenuBarAndReturnToTheDock() {
        let terrain = TerrainSnapshot(windows: [DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        for target in [WorldPoint(x: 19, y: 788), .init(x: 260, y: 788), .init(x: 600, y: 35), .init(x: 460, y: 440)] {
            for _ in 0..<120 * 35 { explorer.steerAgent(towardHand: target); explorer.advance(by: 1.0 / 120); explorer.updateTerrain(terrain) }
            if target.y > 760 { XCTAssertTrue(explorer.agentCeilingHanging, "Menu-bar targets should finish with a planted top-edge grip") }
            let localX = (target.x - explorer.position.x) * explorer.facing
            let localY = target.y - explorer.position.y
            let shoulderY = 46.0 - (explorer.canCrouch ? explorer.crouchBlend * 28 : 0)
            XCTAssertLessThan(hypot(localX - 10, localY - shoulderY), 29, "target \(target), feet \(explorer.position), state \(explorer.state)")
        }
    }

    func testTopEdgeGripLowersOntoConnectedRopeForAnOpenMenu() {
        let terrain = TerrainSnapshot(windows: [DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        for _ in 0..<120 * 30 { explorer.steerAgent(towardHand: .init(x: 260, y: 788)); explorer.advance(by: 1.0 / 120) }
        XCTAssertTrue(explorer.agentCeilingHanging)
        let gripX = explorer.position.x
        explorer.steerAgent(towardHand: .init(x: gripX + 20, y: 700))
        XCTAssertFalse(explorer.agentCeilingHanging)
        XCTAssertEqual(explorer.ropeSession?.anchor.windowID, UInt32.max)
        XCTAssertEqual(explorer.ropeSession?.anchor.offset ?? -1, gripX, accuracy: 0.1)
        XCTAssertEqual(explorer.ropeSession?.mode, .descending)
        for _ in 0..<120 * 3 { explorer.steerAgent(towardHand: .init(x: gripX + 20, y: 700)); explorer.advance(by: 1.0 / 120) }
        XCTAssertLessThan(explorer.position.y, 690)
        XCTAssertNotNil(explorer.ropeSession)
    }

    func testMenuDescentCanPassAWindowRoofAndReachItsControls() {
        let terrain = TerrainSnapshot(windows: [DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1)), DesktopWindow(id: 42, frame: .init(x: 200, y: 100, width: 600, height: 400))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        for target in [WorldPoint(x: 260, y: 788), .init(x: 400, y: 350), .init(x: 600, y: 230)] {
            for tick in 0..<120 * 45 {
                explorer.steerAgent(towardHand: target); explorer.advance(by: 1.0 / 120)
                if tick % 12 == 0 { explorer.updateTerrain(terrain) }
            }
            XCTAssertLessThan(abs(explorer.position.x - max(24, target.x - 20)), 35, "x for \(target), \(explorer.position), \(explorer.state)")
            XCTAssertLessThan(abs(explorer.position.y - min(724, max(0, target.y - 45))), 35, "y for \(target), \(explorer.position), \(explorer.state)")
        }
    }

    func testLongFloorTravelWalksBeforeGrapplingUpward() {
        let terrain = TerrainSnapshot(windows: [DesktopWindow(id: UInt32.max, frame: .init(x: 0, y: 799, width: 1000, height: 1))], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true)
        for _ in 0..<60 { explorer.steerAgent(towardHand: .init(x: 800, y: 500)); explorer.advance(by: 1.0 / 120) }
        XCTAssertNil(explorer.ropeSession)
        XCTAssertGreaterThan(explorer.position.x, 110)
        XCTAssertTrue([ExplorerInteraction.State.walking, .running].contains(explorer.state))
    }

    func testLowerPointerDoesNotChangeTheCrouchPose() {
        let terrain = TerrainSnapshot(windows: [], viewport: .init(x: 0, y: 0, width: 1000, height: 800))
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        explorer.autonomous = true; explorer.updateTerrain(terrain); explorer.setKeyboardControl(true); explorer.setControlCrouch(true)
        for _ in 0..<60 { explorer.advance(by: 1.0 / 120) }
        let blend = explorer.crouchBlend, point = explorer.controlClickPoint
        explorer.setControlPointerLowered(true)
        XCTAssertEqual(explorer.crouchBlend, blend)
        XCTAssertEqual(explorer.controlClickPoint.x, point.x)
        XCTAssertEqual(explorer.controlClickPoint.y, point.y - 16, accuracy: 0.01)
        explorer.setControlPointerLowered(false)
        XCTAssertEqual(explorer.controlClickPoint, point)
    }

}
