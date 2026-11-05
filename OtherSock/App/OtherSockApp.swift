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
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
