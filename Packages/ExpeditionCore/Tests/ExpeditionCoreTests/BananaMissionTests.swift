import XCTest
@testable import ExpeditionCore

final class BananaMissionTests: XCTestCase {
    private let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
    private func terrain(_ windows: [DesktopWindow] = []) -> TerrainSnapshot { .init(windows: windows, viewport: viewport) }
    private func explorer(_ terrain: TerrainSnapshot, at position: WorldPoint = .init(x: 100, y: 0)) -> ExplorerInteraction {
        var result = ExplorerInteraction(position: position, bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 724)))
        result.autonomous = true; result.runsMission = true; result.updateTerrain(terrain)
        return result
    }
    func testSparseDesktopCompletesAllComicBeatsAndRepeatsUnattended() {
        var subject = explorer(terrain())
        var stages = Set<String>()
        for _ in 0..<24000 {
            subject.advance(by: 1.0 / 60)
            stages.insert(subject.mission.stage.rawValue)
            if subject.mission.completedExpeditions >= 2 { break }
        }
        XCTAssertGreaterThanOrEqual(subject.mission.completedExpeditions, 2)
        XCTAssertTrue(stages.isSuperset(of: ["selecting", "spotting", "crossing", "investigating", "revealing", "updatingMap", "resting"]))
    }
    func testSuitableLayoutUsesParachuteAndCompletesBananaAdventure() {
        let t = terrain([.init(id: 1, frame: .init(x: 300, y: 20, width: 300, height: 350))])
        var subject = explorer(t, at: .init(x: 450, y: 370))
        var stages = Set<String>(), states = Set<String>()
        for _ in 0..<18000 {
            subject.advance(by: 1.0 / 60)
            stages.insert(subject.mission.stage.rawValue); states.insert(subject.state.rawValue)
            if subject.mission.completedExpeditions > 0 { break }
        }
        XCTAssertEqual(subject.mission.completedExpeditions, 1)
        XCTAssertTrue(stages.contains("approaching"), "\(stages)")
        XCTAssertTrue(states.contains("recovering"), "\(states)")
    }
    func testGrabAtEveryBeatCancelsOldTargetAndCanCompleteNewMission() {
        var subject = explorer(terrain())
        var checked = Set<String>()
        for _ in 0..<24000 {
            subject.advance(by: 1.0 / 60)
            let stage = subject.mission.stage.rawValue
            if !checked.contains(stage) {
                var copy = subject
                copy.beginDrag(at: copy.position)
                copy.advance(by: 0.1)
                XCTAssertNil(copy.mission.target)
                XCTAssertEqual(copy.mission.stage, .selecting)
                copy.drag(to: .init(x: 500, y: 300))
                copy.endDrag(on: terrain())
                for _ in 0..<12000 {
                    copy.advance(by: 1.0 / 60)
                    if copy.mission.completedExpeditions > subject.mission.completedExpeditions { break }
                }
                XCTAssertGreaterThan(copy.mission.completedExpeditions, subject.mission.completedExpeditions, stage)
                checked.insert(stage)
            }
            if checked.count == 7 { break }
        }
        XCTAssertEqual(checked.count, 7)
    }
    func testMovingPropTracksSupportAndRemovingDestinationDoesNotStrandMission() {
        let source = DesktopWindow(id: 1, frame: .init(x: 300, y: 200, width: 300, height: 350))
        let destination = DesktopWindow(id: 2, frame: .init(x: 40, y: 20, width: 200, height: 200))
        let initial = terrain([source, destination])
        var subject = explorer(initial, at: .init(x: 450, y: 550))
        for _ in 0..<6000 {
            subject.advance(by: 1.0 / 60)
            if subject.mission.target?.owner == .window(2) { break }
        }
        let target = subject.mission.target
        XCTAssertEqual(target?.owner, .window(2))
        let moved = terrain([source, .init(id: 2, frame: .init(x: 60, y: 30, width: 200, height: 200))])
        if let target {
            let before = TerrainSupport.resolve(target, in: initial)!
            let after = TerrainSupport.resolve(target, in: moved)!
            XCTAssertEqual(after.x, before.x + 20)
            XCTAssertEqual(after.y, before.y + 10)
        }
        subject.updateTerrain(terrain())
        subject.advance(by: 0.1)
        XCTAssertNotEqual(subject.mission.target?.owner, .window(2))
        for _ in 0..<18000 { subject.advance(by: 1.0 / 60); if subject.mission.completedExpeditions > 0 { break } }
        XCTAssertGreaterThan(subject.mission.completedExpeditions, 0)
    }
}

extension BananaMissionTests {
    func testGrabAndReleaseWithoutAdvancingClockCancelsMissionImmediately() {
        var subject = explorer(terrain())
        for _ in 0..<300 { subject.advance(by: 1.0 / 60); if subject.mission.target != nil { break } }
        XCTAssertNotNil(subject.mission.target)
        subject.beginDrag(at: subject.position)
        // This is the paused-drag path: no simulation tick occurs while held.
        XCTAssertNil(subject.mission.target)
        subject.drag(to: .init(x: 800, y: 0))
        subject.endDrag(on: terrain())
        for _ in 0..<12000 { subject.advance(by: 1.0 / 60); if subject.mission.completedExpeditions > 0 { break } }
        XCTAssertGreaterThan(subject.mission.completedExpeditions, 0)
    }
}
