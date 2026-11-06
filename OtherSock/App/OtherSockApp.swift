import AppKit
import CoreGraphics

@main
@MainActor
enum OtherSockApp {
    static func main() {
        let application = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--terrain-report") {
            guard let screen = NSScreen.screens.first, let terrain = WindowProvider().snapshot(on: screen) else {
                print("Window geometry unavailable")
                return
            }
            print("Geometry readable: \(terrain.windows.count) windows; \(terrain.windows.filter(\.canClimb).count) climbable; \(terrain.surfaces.count) exposed segments (including screen boundaries)")
            print("Screen capture permission already granted: \(CGPreflightScreenCaptureAccess()). No permission requested.")
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--native-checks") {
            application.setActivationPolicy(.accessory)
            application.finishLaunching()
            let overlay = OverlayController()
            let passed = overlay.runNativeChecks()
            let menusPassed = AppDelegate().runActivityMenuChecks()
            exit(passed && menusPassed ? 0 : 1)
        }
        #endif
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            print("The Other Sock is already running. Use its hiking menu to quit before launching another build.")
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
