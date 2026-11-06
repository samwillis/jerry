import XCTest
@testable import ExpeditionCore

final class WindowFeatureTests: XCTestCase {
    let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
    let window = DesktopWindow(id: 7, frame: .init(x: 100, y: 100, width: 600, height: 600))
    func pixels(scroll: Int = 0, blank: Bool = false) -> TerrainPixels {
        let w = 240, h = 240
        var rgb = [UInt8](repeating: 235, count: w * h * 3)
        if !blank {
            for y in 0..<h {
                for x in 0..<w {
                    // Sustained two-colour block, separate hairline, vertical crack.
                    let block = y >= 60 + scroll && y < 105 + scroll && x >= 20 && x < 210
                    let line = y == 155 + scroll && x >= 20 && x < 210
                    let vertical = (x == 145 || x == 146) && y >= 170 + scroll && y < 225 + scroll
                    let text = y == 20 && x % 12 < 5
                    if block || line || vertical || text {
                        let i = (y * w + x) * 3
                        rgb[i] = 30; rgb[i + 1] = 45; rgb[i + 2] = 65
                    }
                }
            }
        }
        return .init(width: w, height: h, rgb: rgb, pointWidth: 600, pointHeight: 600)
    }
    func feature(_ id: Int = 1, _ edge: TerrainEdge = .ledge, y: Double = 300) -> WindowFeature {
        .init(id: id, windowID: 7, edge: edge, start: .init(x: 50, y: y), end: .init(x: 500, y: y))
    }
    func terrain(_ features: [WindowFeature], windows: [DesktopWindow]? = nil) -> TerrainSnapshot {
        .init(windows: windows ?? [window], viewport: viewport, features: features)
    }
    func explorer(at point: WorldPoint, terrain: TerrainSnapshot) -> ExplorerInteraction {
        var e = ExplorerInteraction(position: point, bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        e.autonomous = true; e.updateTerrain(terrain); e.setKeyboardControl(true)
        return e
    }
    func advance(_ e: inout ExplorerInteraction, _ seconds: Double) {
        for _ in 0..<Int(seconds * 120) { e.advance(by: 1.0 / 120) }
    }
    func testDetectorSeparatesRegionsFromHairlinesAndRejectsText() {
        let features = WindowFeatureDetector.detect(pixels(), windowID: 7)
        XCTAssertTrue(features.contains { $0.edge == .ledge && abs($0.start.y - 450) < 4 })
        XCTAssertTrue(features.contains { $0.edge == .horizontalCrack && abs($0.start.y - 212.5) < 4 })
        XCTAssertTrue(features.contains { $0.edge == .verticalCrack })
        XCTAssertTrue(features.contains { $0.edge == .verticalEdge })
        XCTAssertFalse(features.contains { $0.start.y > 530 }, "Short repeated glyph strokes cannot become ledges")
    }
    func testFaintSinglePixelRulesAndLowContrastColourBoundaries() {
        let w = 300, h = 220
        var rgb = [UInt8](repeating: 240, count: w * h * 3)
        for y in 0..<h {
            for x in 15..<285 {
                let value: UInt8 = y >= 45 && y < 85 ? 218 : (y == 130 ? 220 : 240)
                for c in 0..<3 { rgb[(y * w + x) * 3 + c] = value }
            }
        }
        let image = TerrainPixels(width: w, height: h, rgb: rgb, pointWidth: 600, pointHeight: 440)
        let features = WindowFeatureDetector.detect(image, windowID: 7)
        XCTAssertTrue(features.contains { $0.edge == .ledge && abs($0.start.y - 350) <= 3 })
        XCTAssertTrue(features.contains { $0.edge == .horizontalCrack && abs($0.start.y - 180) <= 3 })
    }
    func testTextRegionsRejectLongUnderlinesWithoutHidingNearbyDivider() {
        let w = 300, h = 220
        var rgb = [UInt8](repeating: 240, count: w * h * 3)
        for y in [80, 105] {
            for x in 20..<280 {
                for c in 0..<3 { rgb[(y * w + x) * 3 + c] = 80 }
            }
        }
        let unfiltered = TerrainPixels(width: w, height: h, rgb: rgb, pointWidth: 600, pointHeight: 440)
        XCTAssertTrue(WindowFeatureDetector.detect(unfiltered, windowID: 7).contains { abs($0.start.y - 280) < 2 })
        let filtered = TerrainPixels(width: w, height: h, rgb: rgb, pointWidth: 600, pointHeight: 440,
                                     textRegions: [.init(x: 35, y: 275, width: 530, height: 32)])
        let features = WindowFeatureDetector.detect(filtered, windowID: 7)
        XCTAssertFalse(features.contains { abs($0.start.y - 280) < 2 }, "A long text underline must not become a crack")
        XCTAssertTrue(features.contains { abs($0.start.y - 230) < 2 }, "The independent divider below the text must survive")
        var tracker = WindowFeatureTracker()
        tracker.update(unfiltered, windowID: 7, at: 1); tracker.confirmUnchanged(at: 1.05)
        let oldTextID = tracker.features(at: 1.05).first { abs($0.start.y - 280) < 2 }!.id
        tracker.update(filtered, windowID: 7, at: 1.1)
        XCTAssertFalse(tracker.features(at: 1.1).contains { $0.id == oldTextID }, "Recognised text must not retain an old hold through missed-frame grace")
    }
    func testGentleGradientDoesNotBecomeManyLedges() {
        let w = 120, h = 120
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<3 { rgb[(y * w + x) * 3 + c] = UInt8(100 + y / 2) }
            }
        }
        XCTAssertTrue(WindowFeatureDetector.detect(.init(width: w, height: h, rgb: rgb, pointWidth: 360, pointHeight: 360), windowID: 7).isEmpty)
    }
    func testTrackerKeepsIdentityAcrossFastScrollAndExpires() {
        var tracker = WindowFeatureTracker()
        tracker.update(pixels(), windowID: 7, at: 1)
        XCTAssertTrue(tracker.features(at: 1).isEmpty)
        tracker.confirmUnchanged(at: 1.05)
        let old = tracker.features(at: 1.05).first { $0.edge == .horizontalCrack }!
        tracker.update(pixels(scroll: -24), windowID: 7, at: 1.1)
        let moved = tracker.features(at: 1.1).first { $0.id == old.id }
        XCTAssertNotNil(moved)
        XCTAssertEqual(moved!.start.y - old.start.y, 60, accuracy: 3)
        XCTAssertTrue(tracker.features(at: 1.5).isEmpty)
        tracker.update(pixels(blank: true), windowID: 7, at: 1.15)
        XCTAssertFalse(tracker.features(at: 1.15).contains { $0.id == old.id })
    }
    func testInternalLedgeSweptLandingTracksScrollAndWindowMove() {
        let f = feature()
        let t = terrain([f])
        let landing = TerrainSupport.landing(from: .init(x: 300, y: 450), to: .init(x: 300, y: 350), in: t)!
        XCTAssertEqual(landing.0.edge, .ledge)
        var e = explorer(at: landing.1, terrain: t)
        var shifted = f; shifted.start.y += 35; shifted.end.y += 35
        e.updateTerrain(terrain([shifted]), sampleElapsed: 0.05)
        XCTAssertEqual(e.position.y, 435)
        let moved = DesktopWindow(id: 7, frame: .init(x: 140, y: 130, width: 600, height: 600))
        e.updateTerrain(terrain([shifted], windows: [moved]), sampleElapsed: 0.05)
        XCTAssertEqual(e.position, .init(x: 340, y: 465))
        e.updateTerrain(terrain([]))
        XCTAssertNil(e.attachment)
        XCTAssertEqual(e.state, .recovering)
    }
    func testCrackCanBeGrabbedTraversedAndFollowsScroll() {
        let f = feature(2, .horizontalCrack)
        let t = terrain([f])
        var e = explorer(at: .init(x: 300, y: 342), terrain: t)
        XCTAssertTrue(e.transferToWindowHold())
        advance(&e, 0.25)
        XCTAssertEqual(e.attachment?.featureID, 2)
        e.setControlDirection(horizontal: 1, vertical: 0)
        advance(&e, 1)
        XCTAssertEqual(e.position.x, 330, accuracy: 0.5)
        XCTAssertEqual(e.position.y, 342)
        XCTAssertNotNil(e.internalClimbingPose)
        var scrolled = f; scrolled.start.y += 40; scrolled.end.y += 40
        e.updateTerrain(terrain([scrolled]), sampleElapsed: 0.05)
        XCTAssertEqual(e.position.y, 382)
        e.setControlDirection(horizontal: 0, vertical: -1)
        advance(&e, 0.1)
        XCTAssertEqual(e.state, .recovering)
        XCTAssertNil(e.attachment)
    }
    func testDownFromMiddleOfWideInternalLedgeDoesNotRecatchIt() {
        let t = terrain([feature()])
        var e = explorer(at: .init(x: 350, y: 400), terrain: t)
        XCTAssertEqual(e.attachment?.edge, .ledge)
        e.setControlDirection(horizontal: 0, vertical: -1)
        advance(&e, 1.3)
        XCTAssertEqual(e.state, .recovering)
        XCTAssertLessThan(e.position.y, 392)
        XCTAssertNil(e.attachment)
    }
    func testVerticalRouteClimbsBothWaysAndConnectsToCrack() {
        let vertical = WindowFeature(id: 3, windowID: 7, edge: .verticalCrack, start: .init(x: 200, y: 60), end: .init(x: 200, y: 450))
        let t = terrain([vertical, feature(4, .horizontalCrack, y: 300), feature(5, .ledge, y: 450)])
        var e = explorer(at: .init(x: 288, y: 250), terrain: t)
        XCTAssertTrue(e.transferToWindowHold())
        advance(&e, 0.25)
        e.setControlDirection(horizontal: 0, vertical: 1); advance(&e, 1)
        let high = e.position.y
        XCTAssertGreaterThan(high, 250)
        e.setControlDirection(horizontal: 0, vertical: -1); advance(&e, 1)
        XCTAssertLessThan(e.position.y, high)
        let graph = NavigationGraph(terrain: t)
        XCTAssertTrue(graph.steps.contains { $0.kind == .transferring && $0.from.featureID == 3 && $0.to.featureID == 4 })
        XCTAssertTrue(graph.steps.filter { $0.from.featureID == 3 && $0.to.featureID == 3 }.allSatisfy { $0.kind == .climbing })
        e.setControlDirection(horizontal: 0, vertical: 1); advance(&e, 20)
        XCTAssertEqual(e.attachment?.edge, .ledge, "Up at the end of a vertical route pulls onto the adjoining ledge")
        XCTAssertEqual(e.position.y, 550)

    }
    func testForegroundWindowOccludesInternalHoldsAndBody() {
        let front = DesktopWindow(id: 8, frame: .init(x: 250, y: 300, width: 120, height: 240))
        let t = terrain([feature()], windows: [front, window])
        XCTAssertNil(TerrainSupport.grip(at: .init(x: 300, y: 400), in: t))
        XCTAssertNotNil(TerrainSupport.grip(at: .init(x: 450, y: 400), in: t))
    }
    func testRopeCanTransferToMovingCrackWithoutReturningToRoof() {
        let crack = feature(6, .horizontalCrack, y: 300)
        let t = terrain([crack])
        var e = explorer(at: .init(x: 350, y: 0), terrain: t)
        XCTAssertTrue(e.fireGrapple(toward: .init(x: 350, y: 700)))
        advance(&e, 2)
        e.setControlDirection(horizontal: 0, vertical: 1)
        for _ in 0..<2400 {
            e.advance(by: 1.0 / 120)
            if e.attachment?.featureID == 6 && e.state != .transferringHold { break }
        }
        XCTAssertEqual(e.attachment?.featureID, 6)
        XCTAssertNil(e.ropeSession)
        XCTAssertEqual(e.position.y, 342, accuracy: 24)
    }
}
