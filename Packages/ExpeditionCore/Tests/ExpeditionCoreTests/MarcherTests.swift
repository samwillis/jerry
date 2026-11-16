import XCTest
@testable import ExpeditionCore

final class MarcherTests: XCTestCase {
    let viewport = WorldRect(x: 0, y: 0, width: 1200, height: 800)

    func terrain(_ windows: [DesktopWindow]) -> TerrainSnapshot { TerrainSnapshot(windows: windows, viewport: viewport) }

    func run(_ m: inout Marcher, _ world: inout MarcherWorld, seconds: Double, context: MarcherPhysics.Context = .init(), until stop: ((Marcher) -> Bool)? = nil) {
        var time = 0.0
        while time < seconds {
            MarcherPhysics.step(&m, by: MarcherLevel.tick, world: &world, context: context)
            time += MarcherLevel.tick
            if stop?(m) == true { return }
        }
    }

    // MARK: Material

    func testWindowsAreHollowRoomsWithSolidTitleBands() {
        let world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 100, width: 400, height: 300))]))
        XCTAssertTrue(world.isSolid(300, 399))   // title band
        XCTAssertTrue(world.isSolid(300, 373))
        XCTAssertFalse(world.isSolid(300, 360))  // hollow interior
        XCTAssertTrue(world.isSolid(102, 200))   // side wall
        XCTAssertTrue(world.isSolid(300, 102))   // bottom rim
        XCTAssertFalse(world.isSolid(300, 401))  // air above
        XCTAssertTrue(world.isSolid(-1, 50))     // screen side
        XCTAssertTrue(world.isSolid(600, 800))   // screen top
        XCTAssertFalse(world.isSolid(600, -50))  // open below the screen
    }

    func testFrontWindowHidesTheFrameBehindIt() {
        let front = DesktopWindow(id: 1, frame: .init(x: 200, y: 100, width: 400, height: 300))
        let back = DesktopWindow(id: 2, frame: .init(x: 100, y: 200, width: 400, height: 300))
        let world = MarcherWorld(terrain: terrain([front, back]))
        // The back window's title band at y≈490 lies above the front window and stays solid.
        XCTAssertTrue(world.isSolid(300, 490))
        // Inside the front window's room, the back window's side wall is hidden.
        XCTAssertFalse(world.isSolid(495, 300))
    }

    func testCarvesAndBricksTravelWithTheirWindow() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 100, width: 400, height: 300))]))
        world.carve(.init(x: 296, y: 380, width: 9, height: 20))
        world.addBrick(.init(x: 500, y: 400, width: 8, height: 2), anchor: 1)
        XCTAssertFalse(world.isSolid(300, 390))
        XCTAssertTrue(world.isSolid(503, 401))
        world.update(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 150, y: 50, width: 400, height: 300))]))
        XCTAssertTrue(world.isSolid(300, 340))
        XCTAssertFalse(world.isSolid(350, 340))
        XCTAssertTrue(world.isSolid(553, 351))
        world.update(terrain: terrain([]))
        XCTAssertTrue(world.bricks.isEmpty)
        XCTAssertTrue(world.carves.isEmpty)
    }

    // MARK: Movement

    func testWalkerLandsWalksAndFallsOffTheScreen() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 400, y: 600, width: 300, height: 100))]))
        var m = Marcher(id: 0, x: 600, y: 784)
        run(&m, &world, seconds: 2) { $0.state == .walking }
        XCTAssertEqual(m.state, .walking)
        XCTAssertEqual(m.y, 700)
        XCTAssertEqual(m.supportID, 1)
        run(&m, &world, seconds: 20) { $0.isFinished }
        XCTAssertEqual(m.state, .lost)
        XCTAssertGreaterThan(m.x, 699)
    }

    func testLongFallsSplatUnlessFloating() {
        let windows = [DesktopWindow(id: 1, frame: .init(x: 400, y: 300, width: 400, height: 200))]
        var world = MarcherWorld(terrain: terrain(windows))
        var m = Marcher(id: 0, x: 600, y: 784)
        run(&m, &world, seconds: 4) { !$0.isActive }
        XCTAssertEqual(m.state, .splatting)

        var floater = Marcher(id: 1, x: 600, y: 784)
        floater.take(.floater)
        run(&floater, &world, seconds: 10) { $0.state == .walking }
        XCTAssertEqual(floater.state, .walking)
        XCTAssertEqual(floater.y, 500)
    }

    func testWalkerRidesAMovingWindow() {
        var level = MarcherLevel(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 400, y: 600, width: 600, height: 100))]), total: 1)
        for _ in 0..<60 { level.advance(by: 0.1) }
        guard let before = level.marchers.first, before.state == .walking else { return XCTFail("not walking") }
        level.updateTerrain(terrain([DesktopWindow(id: 1, frame: .init(x: 300, y: 560, width: 600, height: 100))]))
        let after = level.marchers[0]
        XCTAssertEqual(after.x, before.x - 100)
        XCTAssertEqual(after.y, 660)
    }

    func testBlockerTurnsWalkersAround() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 600, width: 800, height: 100))]))
        var m = Marcher(id: 0, x: 300, y: 700, direction: 1, state: .walking)
        let context = MarcherPhysics.Context(blockers: [(9, 340, 700)])
        run(&m, &world, seconds: 3, context: context)
        XCTAssertEqual(m.direction, -1)
        XCTAssertLessThan(m.x, 340)
    }

    func testWallsTurnWalkersAndClimbersScaleThem() {
        let low = DesktopWindow(id: 1, frame: .init(x: 100, y: 500, width: 400, height: 100))
        let tall = DesktopWindow(id: 2, frame: .init(x: 500, y: 300, width: 300, height: 360))
        var world = MarcherWorld(terrain: terrain([tall, low]))
        var walker = Marcher(id: 0, x: 450, y: 600, direction: 1, state: .walking)
        run(&walker, &world, seconds: 4)
        XCTAssertEqual(walker.direction, -1)

        var climber = Marcher(id: 1, x: 450, y: 600, direction: 1, state: .walking)
        climber.take(.climber)
        run(&climber, &world, seconds: 3) { $0.state == .climbing }
        XCTAssertEqual(climber.state, .climbing)
        run(&climber, &world, seconds: 8) { $0.state == .walking }
        XCTAssertEqual(climber.y, 660)
        XCTAssertGreaterThanOrEqual(climber.x, 500)
    }

    func testBuilderLaysAStaircase() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 600, width: 300, height: 100))]))
        var m = Marcher(id: 0, x: 380, y: 700, direction: 1, state: .walking)
        XCTAssertTrue(m.take(.builder))
        run(&m, &world, seconds: 8) { $0.state != .building }
        XCTAssertEqual(world.bricks.count, MarcherTuning.bricksPerBuilder)
        XCTAssertEqual(world.bricks.first?.anchor, 1)
        XCTAssertEqual(m.state, .walking)
        XCTAssertEqual(m.y, 700 + MarcherTuning.bricksPerBuilder * MarcherTuning.brickHeight)
        XCTAssertEqual(m.x, 380 + MarcherTuning.bricksPerBuilder * MarcherTuning.brickAdvance)
    }

    func testDiggerBreaksThroughTheTitleBand() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 300, width: 600, height: 400))]))
        var m = Marcher(id: 0, x: 400, y: 700, direction: 1, state: .walking)
        XCTAssertTrue(m.take(.digger))
        run(&m, &world, seconds: 4) { $0.state == .falling }
        XCTAssertEqual(m.state, .falling)
        XCTAssertLessThanOrEqual(m.y, 700 - Int(MarcherTuning.titleBand))
        XCTAssertFalse(world.isSolid(400.5, 690))
    }

    func testBasherCutsThroughAWall() {
        let low = DesktopWindow(id: 1, frame: .init(x: 100, y: 500, width: 400, height: 100))
        let tall = DesktopWindow(id: 2, frame: .init(x: 500, y: 450, width: 300, height: 300))
        var world = MarcherWorld(terrain: terrain([tall, low]))
        var m = Marcher(id: 0, x: 496, y: 600, direction: 1, state: .walking)
        XCTAssertTrue(m.take(.basher))
        run(&m, &world, seconds: 3) { $0.state != .bashing }
        XCTAssertNotEqual(m.state, .bashing)
        XCTAssertGreaterThanOrEqual(m.x, 500)
        XCTAssertFalse(world.isSolid(503.5, 605))
    }

    func testBomberBlastsAHole() {
        var world = MarcherWorld(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 100, y: 600, width: 400, height: 100))]))
        var m = Marcher(id: 0, x: 300, y: 700, direction: 1, state: .blocking)
        XCTAssertTrue(m.take(.bomber))
        run(&m, &world, seconds: 6) { $0.isFinished }
        XCTAssertEqual(m.state, .lost)
        XCTAssertFalse(world.isSolid(300.5, 695))
    }

    func testExitIsPlacedOnAnExposedWindowTop() {
        let level = MarcherLevel(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 400, y: 600, width: 300, height: 100)),
                                                    DesktopWindow(id: 2, frame: .init(x: 800, y: 100, width: 300, height: 200))]))
        let exit = try! XCTUnwrap(level.exitPoint)
        XCTAssertEqual(level.exit?.windowID, 2)
        XCTAssertEqual(exit.y, 300)
    }

    // MARK: Solving

    func solve(_ windows: [DesktopWindow], exitOn id: UInt32, offset: Double, total: Int = 10, seconds: Double = 200) -> MarcherCoach {
        var coach = MarcherCoach(terrain: terrain(windows), marchersPerLevel: total)
        coach.setExit(windowID: id, offset: offset)
        var time = 0.0
        while time < seconds && coach.level.phase != .finished {
            coach.advance(by: 0.1, hand: nil)
            time += 0.1
        }
        return coach
    }

    func testDoingNothingLosesEveryone() {
        var level = MarcherLevel(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                                                  DesktopWindow(id: 2, frame: .init(x: 700, y: 200, width: 450, height: 100))]), total: 5)
        level.setExit(windowID: 2, offset: 380)
        for _ in 0..<3000 where level.phase != .finished { level.advance(by: 0.1) }
        XCTAssertEqual(level.savedCount, 0)
    }

    func testJerryHandsOutUmbrellasForALongDrop() {
        let coach = solve([DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                           DesktopWindow(id: 2, frame: .init(x: 700, y: 200, width: 450, height: 100))], exitOn: 2, offset: 380)
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 9, coach.status)
        XCTAssertLessThan(coach.level.stock[.floater]!, MarcherLevel.defaultStock[.floater]!)
    }

    func testJerryBridgesAGap() {
        let coach = solve([DesktopWindow(id: 1, frame: .init(x: 300, y: 640, width: 400, height: 60)),
                           DesktopWindow(id: 2, frame: .init(x: 736, y: 630, width: 400, height: 60))], exitOn: 2, offset: 300)
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 8, coach.status)
        XCTAssertLessThan(coach.level.stock[.builder]!, MarcherLevel.defaultStock[.builder]!)
    }

    func testJerryTurnsTheLineAroundWithABlocker() {
        // Marchers start walking right, but the exit is to the left and the right edge is a drop to nothing.
        let coach = solve([DesktopWindow(id: 1, frame: .init(x: 200, y: 640, width: 700, height: 60))], exitOn: 1, offset: 60)
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 8, coach.status)
        XCTAssertLessThan(coach.level.stock[.blocker]!, MarcherLevel.defaultStock[.blocker]!)
    }

    func testJerryDigsDownThroughAWindow() {
        // A full-width window traps the line on its roof; the exit is on a window beneath it.
        let coach = solve([DesktopWindow(id: 1, frame: .init(x: 0, y: 450, width: 1200, height: 250)),
                           DesktopWindow(id: 2, frame: .init(x: 300, y: 150, width: 600, height: 200))], exitOn: 2, offset: 300, total: 6, seconds: 280)
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 4, coach.status)
    }

    func testPlannerAdaptsWhenAWindowMoves() {
        var coach = MarcherCoach(terrain: terrain([DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                                                   DesktopWindow(id: 2, frame: .init(x: 700, y: 200, width: 450, height: 100))]), marchersPerLevel: 8)
        coach.setExit(windowID: 2, offset: 380)
        for step in 0..<2500 where coach.level.phase != .finished {
            if step == 60 {
                // Slide the exit window left beneath the hatch window; the exit travels with it.
                coach.updateTerrain(terrain([DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                                             DesktopWindow(id: 2, frame: .init(x: 200, y: 260, width: 450, height: 100))]))
                XCTAssertEqual(coach.level.exitPoint?.x, 580)
            }
            coach.advance(by: 0.1, hand: nil)
        }
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 5, coach.status)
    }

    func testPlanningCostOnACrowdedDesktop() {
        // Overlapping windows of mixed sizes on a laptop-sized screen.
        let frames: [(Double, Double, Double, Double)] = [
            (40, 520, 520, 330), (300, 380, 640, 300), (820, 600, 520, 250), (980, 120, 480, 380),
            (120, 60, 600, 260), (620, 240, 300, 200), (1180, 520, 300, 360), (60, 300, 260, 160),
            (700, 720, 260, 150), (420, 60, 300, 120), (1300, 60, 180, 300), (520, 520, 220, 90)
        ]
        let windows = frames.enumerated().map { DesktopWindow(id: UInt32($0.offset + 1), frame: WorldRect(x: $0.element.0, y: $0.element.1, width: $0.element.2, height: $0.element.3)) }
        var coach = MarcherCoach(terrain: TerrainSnapshot(windows: windows, viewport: WorldRect(x: 0, y: 0, width: 1512, height: 920)), marchersPerLevel: 20)
        var worst = 0.0, total = 0.0, count = 0
        for step in 0..<900 {
            coach.advance(by: 0.1, hand: nil)
            guard step % 40 == 0 else { continue }
            for marcher in coach.level.marchers where marcher.isActive {
                let start = Date()
                _ = MarcherPlanner.plan(for: marcher.id, in: coach.level, options: coach.planner)
                let elapsed = Date().timeIntervalSince(start)
                worst = max(worst, elapsed); total += elapsed; count += 1
            }
        }
        print(String(format: "MARCHER PLAN mean %.1f ms · worst %.1f ms · %d plans · %@", total / Double(max(1, count)) * 1000, worst * 1000, count, coach.status))
        XCTAssertGreaterThan(count, 0)
        XCTAssertGreaterThanOrEqual(coach.level.savedCount + coach.totalSaved, 10, coach.status)
    }

    func testBackgroundPlanningProducesTheSameRescue() {
        let windows = [DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                       DesktopWindow(id: 2, frame: .init(x: 700, y: 200, width: 450, height: 100))]
        var coach = MarcherCoach(terrain: terrain(windows), marchersPerLevel: 10)
        coach.plansInline = false
        coach.setExit(windowID: 2, offset: 380)
        var pending: MarcherPlanningRequest?
        for _ in 0..<2000 where coach.level.phase != .finished {
            coach.advance(by: 0.1, hand: nil)
            // Answers arrive one frame late, as they would from a worker thread.
            if let request = pending { coach.receive(request.solve(), for: request) }
            pending = coach.nextPlanningRequest()
        }
        XCTAssertGreaterThanOrEqual(coach.level.savedCount, 9, coach.status)
    }

    func testJerryOnlySignalsWithinReachAndWalksTowardsTheLine() {
        let windows = [DesktopWindow(id: 1, frame: .init(x: 450, y: 650, width: 300, height: 60)),
                       DesktopWindow(id: 2, frame: .init(x: 700, y: 200, width: 450, height: 100))]
        let snapshot = terrain(windows)
        var coach = MarcherCoach(terrain: snapshot, marchersPerLevel: 6)
        coach.setExit(windowID: 2, offset: 380)
        coach.reach = 260
        var jerry = ExplorerInteraction(position: .init(x: 60, y: 0), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 1176, y: 724)))
        jerry.autonomous = true
        jerry.updateTerrain(snapshot)
        jerry.setIdleExploration(false)
        var startedTravel = false
        for _ in 0..<12000 where coach.level.phase != .finished {
            jerry.advance(by: 1.0 / 60)
            let hand = WorldPoint(x: jerry.position.x, y: jerry.position.y + 44)
            let before = coach.signals.count
            coach.advance(by: 1.0 / 60, hand: hand)
            coach.steer(&jerry, terrain: snapshot, by: 1.0 / 60)
            if jerry.hasPendingTravel { startedTravel = true }
            for signal in coach.signals.suffix(max(0, coach.signals.count - before)) {
                XCTAssertLessThanOrEqual(hypot(signal.to.x - hand.x, signal.to.y - hand.y), coach.reach + 2)
            }
        }
        XCTAssertTrue(startedTravel)
        XCTAssertGreaterThan(coach.level.savedCount, 0, coach.status)
    }

    func testBlockersAreDetonatedToFinishTheLevel() {
        let coach = solve([DesktopWindow(id: 1, frame: .init(x: 200, y: 640, width: 700, height: 60))], exitOn: 1, offset: 60, total: 4)
        XCTAssertEqual(coach.level.phase, .finished)
        XCTAssertEqual(coach.level.savedCount + coach.level.lostCount, 4)
    }
}
