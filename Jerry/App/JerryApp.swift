import AppKit
import CoreGraphics

@main
@MainActor
enum JerryApp {
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
        if ProcessInfo.processInfo.arguments.contains("--jol-preview") || ProcessInfo.processInfo.arguments.contains("--journal-preview") || ProcessInfo.processInfo.arguments.contains("--live-photo-preview") {
            application.setActivationPolicy(.regular); application.finishLaunching()
            let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
            appMenu.addItem(withTitle: "Quit Jerry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.submenu = appMenu; menu.addItem(item); application.mainMenu = menu
            Task { do {
                if ProcessInfo.processInfo.arguments.contains("--jol-preview") { AgentPrototypeChecks.showJOLPreview() }
                else if ProcessInfo.processInfo.arguments.contains("--live-photo-preview") { try await AgentPrototypeChecks.showLivePhotoPreview() }
                else { try await AgentPrototypeChecks.showJournalPreview() }
            } catch { print(error); exit(1) } }
            application.run(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--agent-checks") {
            application.setActivationPolicy(.accessory); application.finishLaunching()
            Task { let passed = await AgentPrototypeChecks.run(); exit(passed ? 0 : 1) }
            application.run(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--feature-checks") {
            application.setActivationPolicy(.accessory)
            application.finishLaunching()
            Task {
                let standard = await WindowFeatureCapture.runNativeChecks()
                let large = await WindowFeatureCapture.runNativeChecks(size: .init(width: 1372, height: 920))
                exit(standard && large ? 0 : 1)
            }
            application.run()
            return
        }
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
            print("Jerry is already running. Use its hiking menu to quit before launching another build.")
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
