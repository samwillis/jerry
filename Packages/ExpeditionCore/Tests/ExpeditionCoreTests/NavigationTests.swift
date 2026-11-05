import XCTest
@testable import ExpeditionCore

final class NavigationTests: XCTestCase {
    private let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
    private func terrain(_ windows: [DesktopWindow] = []) -> TerrainSnapshot { .init(windows: windows, viewport: viewport) }
    private func window(_ id: UInt32 = 1, x: Double = 300, y: Double = 20, w: Double = 300, h: Double = 350) -> DesktopWindow {
        .init(id: id, frame: .init(x: x, y: y, width: w, height: h))
    }
    private func explorer(at point: WorldPoint, in terrain: TerrainSnapshot) -> ExplorerInteraction {
        var subject = ExplorerInteraction(position: point, bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        subject.autonomous = true
        subject.updateTerrain(terrain)
        return subject
    }
    private func run(_ subject: inout ExplorerInteraction, seconds: Double) -> Set<String> {
        var states = Set<String>()
        for _ in 0..<Int(seconds * 60) { subject.advance(by: 1.0 / 60); states.insert(subject.state.rawValue) }
        return states
    }

    func testGraphConnectsFloorToExposedWallAndTopInBothDirections() {
        let graph = NavigationGraph(terrain: terrain([window()]))
        XCTAssertTrue(graph.steps.contains { $0.kind == .climbing })
        XCTAssertTrue(graph.steps.contains { $0.kind == .abseiling })
        XCTAssertTrue(graph.steps.contains { $0.kind == .parachuting })
        let floor = TerrainAttachment(owner: .screen, edge: .floor, offset: 100)
        let routes = (0..<20).map { graph.route(from: floor, seed: UInt64($0)) }
        XCTAssertTrue(routes.contains { $0.contains { $0.kind == .climbing } })
        XCTAssertTrue(graph.steps.allSatisfy { graph.isValid($0) })
    }

    func testCannotWalkAcrossCoveredTopAndFloorRemainsRescueTerrain() {
        let t = terrain([window(2, x: 400, y: 360, w: 80, h: 100), window()])
        let graph = NavigationGraph(terrain: t)
        XCTAssertFalse(graph.steps.contains {
            $0.from.owner == .window(1) && $0.from.edge == .top && $0.to.edge == .top
                && $0.from.offset < 100 && $0.to.offset > 180
        })
        XCTAssertTrue(graph.isValid(.init(from: .init(owner: .screen, edge: .floor, offset: 100), to: .init(owner: .screen, edge: .floor, offset: 900), kind: .walking)))
    }

    func testTallOrFloatingUnreachableWallsAreNotConnectedToFloor() {
        let graph = NavigationGraph(terrain: terrain([window(y: 200)]))
        let route = graph.route(from: .init(owner: .screen, edge: .floor, offset: 100), seed: 2)
        XCTAssertFalse(route.contains { $0.kind == .climbing })
        let huge = NavigationGraph(terrain: .init(windows: [window(y: 0, h: 1500)], viewport: .init(x: 0, y: 0, width: 1000, height: 1800)))
        XCTAssertFalse(huge.steps.contains { $0.kind == .climbing })
    }

    func testAutonomousExplorerWalksClimbsAbseilsAndParachutes() {
        var subject = explorer(at: .init(x: 100, y: 0), in: terrain([window()]))
        let states = run(&subject, seconds: 500)
        XCTAssertTrue(states.contains("walking"), "\(states)")
        XCTAssertTrue(states.contains("climbing"), "\(states)")
        XCTAssertTrue(states.contains("abseiling"), "\(states)")
        XCTAssertTrue(states.contains("recovering"), "\(states)")
        XCTAssertTrue(states.contains("settling"))
        XCTAssertGreaterThanOrEqual(subject.position.y, 0)
    }

    func testFixedStepIsDeterministicAndCatchUpIsBounded() {
        var a = explorer(at: .init(x: 100, y: 0), in: terrain())
        var b = a
        for _ in 0..<600 { a.advance(by: 1.0 / 60) }
        for _ in 0..<300 { b.advance(by: 1.0 / 30) }
        XCTAssertEqual(a.position, b.position)
        XCTAssertEqual(a.state, b.state)
        let before = a.simulationSteps
        a.advance(by: 60)
        XCTAssertLessThanOrEqual(a.simulationSteps - before, 30)
    }

    func testMovingWindowCarriesInProgressClimbAndClosingItRecovers() {
        var subject = explorer(at: .init(x: 100, y: 0), in: terrain([window()]))
        for _ in 0..<6000 {
            subject.advance(by: 1.0 / 60)
            if subject.state == .climbing { break }
        }
        XCTAssertEqual(subject.state, .climbing)
        let before = subject.position
        let contactHeight = subject.heightAlongWall
        subject.updateTerrain(terrain([window(x: 340, y: 30)]))
        XCTAssertEqual(subject.heightAlongWall, contactHeight, accuracy: 0.01)
        XCTAssertEqual(subject.position.x, before.x + 40, accuracy: 0.01)
        XCTAssertEqual(subject.position.y, before.y + 10, accuracy: 0.01)
        subject.updateTerrain(terrain())
        XCTAssertEqual(subject.state, .recovering)
        XCTAssertNil(subject.activeTravel)
        _ = run(&subject, seconds: 4)
        XCTAssertGreaterThanOrEqual(subject.position.y, 0)
    }

    func testGrabInterruptsEveryAutonomousMovementAndDoesNotResumeOldRoute() {
        var subject = explorer(at: .init(x: 100, y: 0), in: terrain([window()]))
        var checked = Set<String>()
        for _ in 0..<40000 {
            subject.advance(by: 1.0 / 60)
            let state = subject.state.rawValue
            if ["walking", "climbing", "abseiling", "recovering"].contains(state), !checked.contains(state) {
                var copy = subject
                copy.beginDrag(at: copy.position)
                XCTAssertNil(copy.activeTravel)
                let held = copy.position
                _ = run(&copy, seconds: 2)
                XCTAssertEqual(copy.position, held)
                copy.drag(to: .init(x: 850, y: 500))
                copy.endDrag(on: terrain([window()]))
                XCTAssertEqual(copy.state, .recovering)
                XCTAssertNil(copy.activeTravel)
                checked.insert(state)
            }
        }
        XCTAssertEqual(checked, ["walking", "climbing", "abseiling", "recovering"])
    }
}

extension NavigationTests {
    func testCoveredWallInvalidatesAnActiveClimbWithoutTeleporting() {
        let initial = terrain([window()])
        var subject = explorer(at: .init(x: 100, y: 0), in: initial)
        for _ in 0..<12000 { subject.advance(by: 1.0 / 60); if subject.state == .climbing, subject.position.y > 80 { break } }
        XCTAssertEqual(subject.state, .climbing)
        let position = subject.position
        let occluder = window(2, x: position.x - 30, y: position.y, w: 80, h: 200)
        subject.updateTerrain(terrain([occluder, window()]))
        XCTAssertEqual(subject.state, .recovering)
        XCTAssertEqual(subject.position, position)
        XCTAssertNil(subject.ropeAnchor)
    }

    func testAbseilRopeIsWindowAnchoredAndRemovalCancelsIt() {
        var subject = explorer(at: .init(x: 450, y: 370), in: terrain([window()]))
        for _ in 0..<30000 { subject.advance(by: 1.0 / 60); if subject.state == .abseiling { break } }
        XCTAssertEqual(subject.state, .abseiling)
        let anchor = subject.ropeAnchor
        XCTAssertEqual(anchor?.y, 370)
        XCTAssertTrue([300.0, 600.0].contains(anchor?.x ?? -1))
        subject.updateTerrain(terrain([window(x: 320, y: 30)]))
        XCTAssertEqual(subject.ropeAnchor?.y, 380)
        XCTAssertEqual(subject.ropeAnchor?.x, (anchor?.x ?? 0) + 20)
        subject.updateTerrain(terrain())
        XCTAssertNil(subject.ropeAnchor)
        XCTAssertEqual(subject.state, .recovering)
    }

    func testOneHourOfChangingTerrainAndMissionInterruptionsStaysBounded() {
        var subject = explorer(at: .init(x: 100, y: 0), in: terrain([window()]))
        subject.runsMission = true
        var successes = 0
        for tick in 0..<216000 {
            if tick % 3600 == 0 {
                let phase = (tick / 3600) % 5
                let windows: [DesktopWindow] = phase == 0 ? [] : [window(x: 300 + Double(phase * 10), y: 20, w: phase == 4 ? 100 : 300)]
                subject.updateTerrain(terrain(windows))
            }
            if tick % 18000 == 0 {
                subject.beginDrag(at: subject.position)
                subject.drag(to: .init(x: 100, y: 600))
                subject.endDrag(on: terrain())
            }
            subject.advance(by: 1.0 / 60)
            XCTAssertTrue(subject.position.x.isFinite && subject.position.y.isFinite)
            XCTAssertTrue((24...976).contains(subject.position.x))
            XCTAssertTrue((0...724).contains(subject.position.y))
            successes = max(successes, subject.mission.completedExpeditions)
        }
        XCTAssertGreaterThan(successes, 0)
    }
}

extension NavigationTests {
    func testPlannedParachuteLandsOnItsWindowInsteadOfMissingTheEdge() {
        let t = terrain([window(1, x: 600, y: 260, w: 320, h: 240), window(2, x: 240, y: 20, w: 320, h: 180)])
        let start = TerrainAttachment(owner: .window(1), edge: .top, offset: 160)
        let goal = TerrainAttachment(owner: .window(2), edge: .top, offset: 264)
        let graph = NavigationGraph(terrain: t)
        let route = graph.route(from: start, to: goal, seed: 1)
        XCTAssertTrue(route.contains { $0.kind == .parachuting })
        XCTAssertEqual(route.first(where: { $0.kind == .parachuting })?.to.owner, .window(2))
        var subject = explorer(at: TerrainSupport.resolve(start, in: t)!, in: t)
        XCTAssertTrue(subject.follow(route))
        var flew = false
        for _ in 0..<12000 {
            subject.advance(by: 1.0 / 60)
            if subject.state == .recovering { flew = true }
            if flew && subject.state == .settling { break }
        }
        XCTAssertTrue(flew)
        XCTAssertEqual(subject.attachment?.owner, .window(2))
        XCTAssertEqual(subject.position.y, 200)
    }
}

extension NavigationTests {
    func testRouteContinuesAfterIntermediateParachuteLanding() {
        let t = terrain([window(1, x: 600, y: 260, w: 320, h: 240), window(2, x: 200, y: 20, w: 320, h: 180)])
        let start = TerrainAttachment(owner: .window(1), edge: .top, offset: 160)
        let goal = TerrainAttachment(owner: .window(2), edge: .top, offset: 264)
        let graph = NavigationGraph(terrain: t)
        let route = graph.route(from: start, to: goal, seed: 1)
        XCTAssertEqual(route.first(where: { $0.kind == .parachuting })?.to.owner, .screen)
        var subject = explorer(at: TerrainSupport.resolve(start, in: t)!, in: t)
        XCTAssertTrue(subject.follow(route))
        var flew = false, climbed = false
        for _ in 0..<12000 {
            subject.advance(by: 1.0 / 60)
            flew = flew || subject.state == .recovering
            climbed = climbed || subject.state == .climbing
            if flew && !subject.hasPendingTravel && subject.state == .settling { break }
        }
        XCTAssertTrue(flew && climbed)
        XCTAssertEqual(subject.attachment?.owner, .window(2))
        XCTAssertEqual(subject.position.x, 464, accuracy: 0.1)
        XCTAssertEqual(subject.position.y, 200)
    }

    func testRearWindowsDoNotBlockForegroundWallContacts() {
        let t = terrain([window(), window(2, x: 0, y: 0, w: 1000, h: 600)])
        let side = TerrainAttachment(owner: .window(1), edge: .left, offset: 100)
        XCTAssertNotNil(TerrainSupport.resolve(side, in: t))
        XCTAssertTrue(NavigationGraph(terrain: t).steps.contains { $0.kind == .climbing && $0.from.owner == .window(1) })
    }
}

extension NavigationTests {
    func testRopeAnchorMustStayVisibleEvenWhenLowerWallIsStillClear() {
        let step = TravelStep(from: .init(owner: .window(1), edge: .left, offset: 150), to: .init(owner: .window(1), edge: .left, offset: -20), kind: .abseiling)
        XCTAssertTrue(NavigationGraph(terrain: terrain([window()])).isValid(step))
        let covered = terrain([window(2, x: 240, y: 360, w: 100, h: 100), window()])
        XCTAssertNotNil(TerrainSupport.resolve(step.from, in: covered))
        XCTAssertFalse(NavigationGraph(terrain: covered).isValid(step))
    }
}
