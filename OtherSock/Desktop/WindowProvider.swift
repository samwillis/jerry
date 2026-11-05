import AppKit
import CoreGraphics
import ExpeditionCore

@MainActor
struct WindowProvider {
    /// Conservatively hide in a full-screen Space. A normally zoomed window occupies only
    /// visibleFrame and leaves the menu bar/Dock strip, so it does not trigger this guard.
    func isSupportedDesktop(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first,
              let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        for record in records {
            guard (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == front.processIdentifier,
                  (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dict = record[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            let world = DesktopCoordinates.sceneRect(.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height), primaryTop: primary.frame.maxY, displayOrigin: .init(x: screen.frame.minX, y: screen.frame.minY))
            return !DesktopCoordinates.isFullScreen(window: world, display: .init(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height))
        }
        return true
    }

    /// Reads geometry only: no window titles, images, Accessibility calls, or permission prompts.
    func snapshot(on screen: NSScreen) -> TerrainSnapshot? {
        guard let primary = NSScreen.screens.first,
              let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let viewport = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let worldViewport = WorldRect(x: viewport.minX, y: viewport.minY + 2, width: viewport.width, height: max(0, viewport.height - 2))
        var windows: [DesktopWindow] = []
        for record in records {
            guard let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  let layer = (record[kCGWindowLayer as String] as? NSNumber)?.intValue, layer >= 0,
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
                  let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary), frame.width > 1, frame.height > 1 else { continue }
            let converted = DesktopCoordinates.sceneRect(
                WorldRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                primaryTop: primary.frame.maxY,
                displayOrigin: .init(x: screen.frame.minX, y: screen.frame.minY)
            )
            guard converted.intersects(worldViewport) else { continue }
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            if bundle == Bundle.main.bundleIdentifier { continue }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fixture-terrain"), bundle != "com.othersock.terrainfixture" { continue }
            #endif
            let systemOwner = bundle == "com.apple.dock" || bundle == "com.apple.WindowManager" || bundle == "com.apple.controlcenter" || bundle == "com.apple.notificationcenterui"
            // Shell helper windows often have transparent, screen-sized backing rectangles.
            guard !systemOwner else { continue }
            windows.append(DesktopWindow(id: id, frame: converted, canClimb: layer == 0 && frame.width >= 80 && frame.height >= 60))
        }
        return TerrainSnapshot(windows: windows, viewport: worldViewport)
    }
}
