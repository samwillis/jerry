import XCTest
@testable import ExpeditionCore

final class ExplorerInteractionTests: XCTestCase {
    private typealias Point = ExplorerInteraction.Point

    private func airborne() -> ExplorerInteraction {
        ExplorerInteraction(position: .init(x: 200, y: 800), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 976, y: 1124)))
    }

    private var emptySky: TerrainSnapshot { .init(windows: [], viewport: .init(x: 0, y: 0, width: 1000, height: 1200)) }

    func testSidewaysReleaseKeepsMomentumThenAirResistanceReducesIt() {
        var subject = airborne()
        subject.beginDrag(at: subject.position, time: 0)
        subject.drag(to: .init(x: 250, y: 800), time: 0.05)
        subject.endDrag(on: emptySky)
        let released = subject.position.x
        subject.advance(by: 0.1)
        let early = subject.position.x - released
        XCTAssertGreaterThan(early, 0)
        subject.advance(by: 0.9)
        let before = subject.position.x
        subject.advance(by: 0.1)
        XCTAssertGreaterThan(subject.position.x, before)
        XCTAssertLessThan(subject.position.x - before, early)
    }

    func testUpwardThrowRisesBeforeFallingBackDown() {
        var subject = airborne()
        subject.beginDrag(at: subject.position, time: 0)
        subject.drag(to: .init(x: 200, y: 850), time: 0.05)
        subject.endDrag(on: emptySky)
        subject.advance(by: 0.1)
        XCTAssertGreaterThan(subject.position.y, 850)
        subject.advance(by: 2)
        XCTAssertLessThan(subject.position.y, 850)
    }

    func testHoldingStillBeforeReleaseDoesNotReuseOldThrowVelocity() {
        var subject = airborne()
        subject.beginDrag(at: subject.position, time: 0)
        subject.drag(to: .init(x: 250, y: 800), time: 0.05)
        subject.drag(to: subject.position, time: 0.4)
        subject.endDrag(on: emptySky)
        subject.advance(by: 0.1)
        XCTAssertEqual(subject.position.x, 250)
    }

    func testGrabbingAgainCancelsThePreviousFlightMomentum() {
        var subject = airborne()
        subject.beginDrag(at: subject.position, time: 0)
        subject.drag(to: .init(x: 250, y: 800), time: 0.05)
        subject.endDrag(on: emptySky)
        subject.advance(by: 0.1)
        subject.beginDrag(at: subject.position, time: 1)
        let x = subject.position.x
        subject.drag(to: subject.position, time: 1.3)
        subject.endDrag(on: emptySky)
        subject.advance(by: 0.1)
        XCTAssertEqual(subject.position.x, x)
    }

    private func makeInteraction() -> ExplorerInteraction {
        ExplorerInteraction(position: Point(x: 100, y: 100), bounds: .init(minimum: .init(x: 24, y: 0), maximum: .init(x: 776, y: 524)))
    }

    func testGrabOffsetIsPreservedInsteadOfSnappingToPointer() {
        var subject = makeInteraction()
        subject.beginDrag(at: Point(x: 108, y: 148))
        subject.drag(to: Point(x: 308, y: 348))
        XCTAssertEqual(subject.position, Point(x: 300, y: 300))
        XCTAssertEqual(subject.state, .held)
    }

    func testPointerCanLeaveCharacterAndDisplayWhileDragStaysCaptured() {
        var subject = makeInteraction()
        subject.beginDrag(at: Point(x: 100, y: 100))
        subject.drag(to: Point(x: -500, y: 4000))
        XCTAssertEqual(subject.position, Point(x: 24, y: 524))
        subject.drag(to: Point(x: 300, y: 200))
        XCTAssertEqual(subject.position, Point(x: 300, y: 200))
        subject.endDrag()
        subject.drag(to: .zero)
        XCTAssertEqual(subject.position, Point(x: 300, y: 200))
    }

    func testReleaseSettlesBeforeReturningToIdleAndDuplicateReleaseDoesNotRestartIt() {
        var subject = makeInteraction()
        subject.beginDrag(at: subject.position)
        subject.endDrag()
        subject.advance(by: 0.5)
        XCTAssertEqual(subject.state, .settling)
        subject.endDrag()
        subject.advance(by: 0.31)
        XCTAssertEqual(subject.state, .idle)
    }

    func testNewGrabInterruptsSettling() {
        var subject = makeInteraction()
        subject.beginDrag(at: subject.position)
        subject.endDrag()
        subject.beginDrag(at: Point(x: 105, y: 120))
        subject.advance(by: 10)
        subject.drag(to: Point(x: 205, y: 220))
        XCTAssertEqual(subject.state, .held)
        XCTAssertEqual(subject.position, Point(x: 200, y: 200))
    }

    func testDisplayChangeCancelsDragAndClampsPosition() {
        var subject = makeInteraction()
        subject.beginDrag(at: subject.position)
        subject.updateBounds(.init(minimum: .init(x: 10, y: 10), maximum: .init(x: 60, y: 60)))
        XCTAssertEqual(subject.state, .settling)
        XCTAssertEqual(subject.position, Point(x: 60, y: 60))
        subject.drag(to: Point(x: 500, y: 500))
        XCTAssertEqual(subject.position, Point(x: 60, y: 60))
    }

    func testInvalidTimeCannotEndSettling() {
        var subject = makeInteraction()
        subject.beginDrag(at: subject.position)
        subject.endDrag()
        subject.advance(by: -.infinity)
        subject.advance(by: .nan)
        subject.advance(by: -1)
        XCTAssertEqual(subject.state, .settling)
    }
}
