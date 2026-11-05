import XCTest
@testable import ExpeditionCore

final class RuntimePolicyTests: XCTestCase {
    func testWakeAndDesktopReturnDoNotOverrideUserPause() {
        var policy = RuntimePolicy()
        policy.manuallyPaused = true
        policy.sleeping = true; policy.desktopSupported = false
        XCTAssertFalse(policy.shouldShow)
        XCTAssertFalse(policy.shouldPollTerrain)
        policy.sleeping = false; policy.desktopSupported = true
        XCTAssertTrue(policy.shouldShow)
        XCTAssertFalse(policy.shouldRun)
        XCTAssertFalse(policy.shouldPollTerrain)
        policy.manuallyPaused = false
        XCTAssertTrue(policy.shouldRun)
    }
    func testUnsupportedDesktopAndSleepSuspendRenderingAndPolling() {
        var policy = RuntimePolicy()
        for supported in [false, true] {
            for sleeping in [false, true] {
                policy.desktopSupported = supported; policy.sleeping = sleeping
                XCTAssertEqual(policy.shouldRun, supported && !sleeping)
                XCTAssertEqual(policy.shouldPollTerrain, supported && !sleeping)
                XCTAssertEqual(policy.shouldShow, supported && !sleeping)
            }
        }
    }
}

extension RuntimePolicyTests {
    func testFullScreenGuardDistinguishesZoomedWindowsAndDifferentDisplayOrigins() {
        let display = WorldRect(x: -1000, y: 100, width: 1000, height: 800)
        XCTAssertTrue(DesktopCoordinates.isFullScreen(window: display, display: display))
        XCTAssertTrue(DesktopCoordinates.isFullScreen(window: .init(x: -1001, y: 99, width: 1002, height: 802), display: display))
        XCTAssertFalse(DesktopCoordinates.isFullScreen(window: .init(x: -1000, y: 130, width: 1000, height: 740), display: display))
        XCTAssertFalse(DesktopCoordinates.isFullScreen(window: .init(x: 0, y: 100, width: 1000, height: 800), display: display))
    }
}
