import XCTest
@testable import ExpeditionCore

final class ExplorerInteractionTests: XCTestCase {
    private typealias Point = ExplorerInteraction.Point

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
