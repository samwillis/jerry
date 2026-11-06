import XCTest
@testable import ExpeditionCore

final class KeyPressConfirmationTests: XCTestCase {
    func testMissingLastLetterCanBeRetried() {
        XCTAssertEqual(KeyPressConfirmation.assess(before: "hell", expected: "hello", actual: "hell", sameFocus: true), .missed)
    }
    func testRegisteredLetterMustNotBeRepeated() {
        XCTAssertEqual(KeyPressConfirmation.assess(before: "hell", expected: "hello", actual: "hello", sameFocus: true), .confirmed)
        XCTAssertEqual(KeyPressConfirmation.assess(before: "h", expected: "h", actual: "h", sameFocus: true), .confirmed)
    }
    func testUserEditsAutocorrectionOrLostFocusDoNotAllowBlindRetries() {
        XCTAssertEqual(KeyPressConfirmation.assess(before: "hell", expected: "hello", actual: "Hell", sameFocus: true), .changed)
        XCTAssertEqual(KeyPressConfirmation.assess(before: "hell", expected: "hello", actual: "hell", sameFocus: false), .changed)
        XCTAssertEqual(KeyPressConfirmation.assess(before: "hell", expected: "hello", actual: nil, sameFocus: true), .changed)
    }
}
