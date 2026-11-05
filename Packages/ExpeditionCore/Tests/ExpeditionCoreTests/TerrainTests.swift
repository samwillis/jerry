import XCTest
@testable import ExpeditionCore

final class TerrainTests: XCTestCase {
    private let viewport = WorldRect(x: 0, y: 0, width: 800, height: 600)

    func testDiagonalDescentUsesTheActualCrossingPointToLand() {
        let terrain = TerrainSnapshot(windows: [window(1)], viewport: viewport)
        let landed = TerrainSupport.landing(from: .init(x: 50, y: 500), to: .init(x: 700, y: 0), in: terrain)
        XCTAssertEqual(landed?.0.owner, .window(1))
        XCTAssertEqual(landed?.1, .init(x: 310, y: 300))
    }
    private func window(_ id: UInt32, x: Double = 0, y: Double = 0, width: Double = 400, height: Double = 300, canClimb: Bool = true) -> DesktopWindow {
        DesktopWindow(id: id, frame: .init(x: x, y: y, width: width, height: height), canClimb: canClimb)
    }
    private func tops(_ terrain: TerrainSnapshot, id: UInt32) -> [TerrainSurface] {
        terrain.surfaces.filter { $0.id.owner == .window(id) && $0.id.edge == .top }
    }

    func testCoordinateConversionAccountsForBothAxisDirectionAndDisplayOrigin() {
        let converted = DesktopCoordinates.sceneRect(.init(x: -700, y: 50, width: 200, height: 200), primaryTop: 900, displayOrigin: .init(x: -800, y: 100))
        XCTAssertEqual(converted, WorldRect(x: 100, y: 550, width: 200, height: 200))
    }

    func testFrontWindowSplitsRearTopIntoExposedSegments() {
        let terrain = TerrainSnapshot(windows: [window(1, x: 100, y: 200, width: 100, height: 150), window(2)], viewport: viewport)
        let exposed = tops(terrain, id: 2)
        XCTAssertEqual(exposed.map(\.start.x), [0, 200])
        XCTAssertEqual(exposed.map(\.end.x), [100, 400])
        XCTAssertTrue(exposed.allSatisfy { $0.start.y == 300 })
    }

    func testSeveralOverlappingOccludersDoNotLeaveDuplicateOrCoveredSegments() {
        let terrain = TerrainSnapshot(windows: [window(1, x: 50, y: 200, width: 100), window(2, x: 100, y: 200, width: 150), window(3)], viewport: viewport)
        XCTAssertEqual(tops(terrain, id: 3).map(\.start.x), [0, 250])
        XCTAssertEqual(tops(terrain, id: 3).map(\.end.x), [50, 400])
    }

    func testFullyCoveredWindowHasNoTerrain() {
        let terrain = TerrainSnapshot(windows: [window(1, width: 500, height: 400), window(2, x: 20, y: 20, width: 200, height: 200)], viewport: viewport)
        XCTAssertFalse(terrain.surfaces.contains { $0.id.owner == .window(2) })
    }

    func testNonClimbablePanelStillOccludesAndScreenBoundariesRemain() {
        let terrain = TerrainSnapshot(windows: [window(1, x: 100, y: 200, width: 100, canClimb: false), window(2)], viewport: viewport)
        XCTAssertFalse(terrain.surfaces.contains { $0.id.owner == .window(1) })
        XCTAssertEqual(tops(terrain, id: 2).count, 2)
        XCTAssertEqual(terrain.surfaces.filter { $0.id.owner == .screen }.count, 3)
    }

    func testClippingDoesNotInventAPlatformAtTheScreenCeiling() {
        let terrain = TerrainSnapshot(windows: [window(1, x: -100, y: 100, width: 400, height: 600)], viewport: viewport)
        XCTAssertTrue(tops(terrain, id: 1).isEmpty)
        XCTAssertFalse(terrain.surfaces.contains { $0.id.owner == .window(1) && $0.id.edge == .left })
        let right = terrain.surfaces.first { $0.id.owner == .window(1) && $0.id.edge == .right }
        XCTAssertEqual(right?.start, .init(x: 300, y: 100))
        XCTAssertEqual(right?.end, .init(x: 300, y: 600))
    }

    func testTouchingWindowDoesNotRemoveUncoveredTopButBlocksSharedSide() {
        let terrain = TerrainSnapshot(windows: [window(1, x: 400, width: 100), window(2)], viewport: viewport)
        XCTAssertEqual(tops(terrain, id: 2).count, 1)
        XCTAssertEqual(tops(terrain, id: 2).first?.end.x, 400)
        XCTAssertFalse(terrain.surfaces.contains { $0.id.owner == .window(2) && $0.id.edge == .right })
    }

    func testWindowRelativeAnchorFollowsMoveAndResize() {
        let initial = TerrainSnapshot(windows: [window(1)], viewport: viewport)
        let attachment = TerrainSupport.attach(at: .init(x: 100, y: 310), in: initial)!.0
        let moved = TerrainSnapshot(windows: [window(1, x: 50, y: 40, width: 500, height: 320)], viewport: viewport)
        XCTAssertEqual(TerrainSupport.resolve(attachment, in: moved), .init(x: 150, y: 360))
    }

    func testAnchorSurvivesSegmentSplitAwayFromExplorer() {
        let initial = TerrainSnapshot(windows: [window(2)], viewport: viewport)
        let attachment = TerrainSupport.attach(at: .init(x: 300, y: 300), in: initial)!.0
        let split = TerrainSnapshot(windows: [window(1, x: 100, y: 200, width: 100), window(2)], viewport: viewport)
        XCTAssertEqual(TerrainSupport.resolve(attachment, in: split), .init(x: 300, y: 300))
    }

    func testCoveredBodyInvalidatesSupportEvenIfFootLineRemainsVisible() {
        let initial = TerrainSnapshot(windows: [window(2)], viewport: viewport)
        let attachment = TerrainSupport.attach(at: .init(x: 100, y: 300), in: initial)!.0
        let covered = TerrainSnapshot(windows: [window(1, x: 50, y: 320, width: 100, height: 150), window(2)], viewport: viewport)
        XCTAssertNil(TerrainSupport.resolve(attachment, in: covered))
    }

    func testClosingSupportStartsControlledRecoveryAndFinishesOnFloor() {
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 300), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1)], viewport: viewport))
        XCTAssertNotNil(explorer.attachment)
        explorer.updateTerrain(TerrainSnapshot(windows: [], viewport: viewport))
        XCTAssertEqual(explorer.state, .recovering)
        explorer.advance(by: 0.1)
        XCTAssertGreaterThan(explorer.position.y, 0)
        XCTAssertLessThan(explorer.position.y, 300)
        explorer.advance(by: 3)
        XCTAssertEqual(explorer.position.y, 0)
        XCTAssertEqual(explorer.state, .settling)
    }

    func testTerrainRefreshDoesNotReattachHeldExplorer() {
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 300), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
        let terrain = TerrainSnapshot(windows: [window(1)], viewport: viewport)
        explorer.beginDrag(at: explorer.position)
        explorer.updateTerrain(terrain)
        XCTAssertNil(explorer.attachment)
        XCTAssertEqual(explorer.state, .held)
        explorer.endDrag(on: terrain)
        XCTAssertNotNil(explorer.attachment)
        XCTAssertEqual(explorer.state, .settling)
    }

    func testAttachedExplorerFollowsWindowAndRecoversWhenResizeRemovesItsFoothold() {
        var explorer = ExplorerInteraction(position: .init(x: 300, y: 300), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1)], viewport: viewport))
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1, x: 50, y: 40)], viewport: viewport))
        XCTAssertEqual(explorer.position, .init(x: 350, y: 340))
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1, x: 50, y: 40, width: 200)], viewport: viewport))
        XCTAssertNil(explorer.attachment)
        XCTAssertEqual(explorer.state, .recovering)
        XCTAssertEqual(explorer.position, .init(x: 350, y: 340))
    }

    func testPlatformWithInsufficientHeadroomIsNotAttachable() {
        let terrain = TerrainSnapshot(windows: [window(1, height: 550)], viewport: viewport)
        XCTAssertNil(TerrainSupport.attach(at: .init(x: 100, y: 550), in: terrain))
    }

    func testDropWellAboveWindowLandsAndFollowsThatWindow() {
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 450), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
        explorer.beginDrag(at: explorer.position)
        explorer.endDrag(on: TerrainSnapshot(windows: [window(1)], viewport: viewport))
        XCTAssertEqual(explorer.state, .recovering)
        // One large step crosses the whole platform height, exercising swept collision.
        explorer.advance(by: 2)
        XCTAssertEqual(explorer.position, .init(x: 100, y: 300))
        XCTAssertEqual(explorer.attachment?.owner, .window(1))
        XCTAssertEqual(explorer.state, .settling)
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1, x: 50, y: 20)], viewport: viewport))
        XCTAssertEqual(explorer.position, .init(x: 150, y: 320))
    }

    func testDescentLandsOnHighestValidTopAndNeverSnapsUpFromBelow() {
        let terrain = TerrainSnapshot(windows: [window(1, height: 350), window(2, height: 200)], viewport: viewport)
        let landing = TerrainSupport.landing(from: .init(x: 100, y: 500), to: .init(x: 100, y: 0), in: terrain)
        XCTAssertEqual(landing?.0.owner, .window(1))
        XCTAssertEqual(landing?.1.y, 350)
        let below = TerrainSupport.landing(from: .init(x: 100, y: 150), to: .init(x: 100, y: 0), in: terrain)
        XCTAssertEqual(below?.0.owner, .screen)
    }

    func testDescentOutsideWindowWidthContinuesToFloor() {
        let terrain = TerrainSnapshot(windows: [window(1)], viewport: viewport)
        let landing = TerrainSupport.landing(from: .init(x: 500, y: 500), to: .init(x: 500, y: 0), in: terrain)
        XCTAssertEqual(landing?.0.owner, .screen)
    }

    func testWindowMovingDuringDescentUsesFreshTerrain() {
        var explorer = ExplorerInteraction(position: .init(x: 100, y: 450), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
        explorer.beginDrag(at: explorer.position)
        explorer.endDrag(on: TerrainSnapshot(windows: [window(1)], viewport: viewport))
        explorer.advance(by: 0.2)
        explorer.updateTerrain(TerrainSnapshot(windows: [window(1, x: 500, width: 200)], viewport: viewport))
        explorer.advance(by: 5)
        XCTAssertEqual(explorer.position.y, 0)
        XCTAssertEqual(explorer.attachment?.owner, .screen)
    }
}
