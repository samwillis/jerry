import XCTest
@testable import ExpeditionCore

final class ResponsesEventStreamTests: XCTestCase {
    func testCompleteEventsDoNotNeedEmptySeparators() throws {
        var stream = ResponsesEventStream()
        XCTAssertNil(try stream.consume("event: response.output_text.delta"))
        let first = try XCTUnwrap(stream.consume("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}"))
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("Hello"))
        XCTAssertNotNil(try stream.consume("data: {\"type\":\"response.completed\",\"response\":{\"output\":[]}}"))
        XCTAssertNil(try stream.consume("data: [DONE]"))
        XCTAssertNoThrow(try stream.finish())
    }
    func testMultiLineAndIncompleteEvents() throws {
        var stream = ResponsesEventStream()
        XCTAssertNil(try stream.consume("data: {\"type\":"))
        XCTAssertNotNil(try stream.consume("data: \"response.completed\"}"))
        XCTAssertNil(try stream.consume("data: {\"unfinished\":"))
        XCTAssertThrowsError(try stream.finish())
    }
    func testOversizedInputIsBounded() {
        var stream = ResponsesEventStream()
        XCTAssertThrowsError(try stream.consume("data: " + String(repeating: "x", count: 2_000_001)))
    }
}
