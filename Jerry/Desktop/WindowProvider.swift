import AppKit
import CoreGraphics
import ExpeditionCore

@MainActor
final class WindowProvider {
    private(set) var frontWindowID: UInt32?
    private(set) var keyboardWindowID: UInt32?
    /// Screenshot's selection/dimming windows and its unbundled screencapture
    /// helper are recording UI, never terrain or opaque desktop occluders.
    static func isScreenRecorder(bundle: String?, owner: String?) -> Bool {
        ["com.apple.screencaptureui", "com.apple.screenshot.launcher"].contains(bundle ?? "") ||
            (bundle == nil && owner == "screencapture")
    }
    /// Accessibility Keyboard keeps screen-sized highlight/capture backdrops at
    /// very high levels. Their WindowServer alpha is 1 despite transparent pixels.
    /// Keep the real keyboard panel as an occluder; exclude only these backdrops.
    static func isKeyboardBackdrop(bundle: String?, layer: Int, frame: CGRect, display: CGRect) -> Bool {
        ["com.apple.inputmethod.AssistiveControl", "com.apple.KeyboardViewer"].contains(bundle ?? "") &&
            layer >= Int(CGWindowLevelForKey(.screenSaverWindow)) && frame.insetBy(dx: -2, dy: -2).contains(display)
    }
    static func canClimbWindow(bundle: String?, layer: Int, frame: CGRect) -> Bool {
        let keyboard = ["com.apple.inputmethod.AssistiveControl", "com.apple.KeyboardViewer"].contains(bundle ?? "")
        return frame.width >= 80 && frame.height >= 60 &&
            (layer == 0 || (keyboard && layer > 0 && layer < Int(CGWindowLevelForKey(.screenSaverWindow))))
    }

    /// Solid app UI participates in terrain; only the transparent renderer,
    /// character hit area, invisible keyboard target and prompt stay excluded.
    static func isAppTerrainWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !window.ignoresMouseEvents
            && window.frame.width >= 80 && window.frame.height >= 60
    }

    /// Conservatively hide in a full-screen Space. A normally zoomed window occupies only
    /// visibleFrame and leaves the menu bar/Dock strip, so it does not trigger this guard.
    func isSupportedDesktop(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first,
              let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        if Self.isScreenRecorder(bundle: front.bundleIdentifier, owner: front.localizedName) { return true }
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
        frontWindowID = nil; keyboardWindowID = nil
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var fallbackWindowID: UInt32?
        for record in records {
            guard let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
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
            let ownWindow = pid == ownPID ? NSApp.windows.first(where: { $0.windowNumber == Int(id) }) : nil
            if pid == ownPID {
                guard let ownWindow, Self.isAppTerrainWindow(ownWindow) else { continue }
            } else if bundle == Bundle.main.bundleIdentifier { continue }
            if Self.isScreenRecorder(bundle: bundle, owner: record[kCGWindowOwnerName as String] as? String) { continue }
            if Self.isKeyboardBackdrop(bundle: bundle, layer: layer,
                                       frame: CGRect(x: converted.minX, y: converted.minY, width: converted.width, height: converted.height),
                                       display: CGRect(origin: .zero, size: screen.frame.size)) { continue }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fixture-terrain"), pid != ownPID, bundle != "com.jerry.terrainfixture" { continue }
            #endif
            let systemOwner = bundle == "com.apple.dock" || bundle == "com.apple.WindowManager" || bundle == "com.apple.controlcenter" || bundle == "com.apple.notificationcenterui"
            // Shell helper windows often have transparent, screen-sized backing rectangles.
            guard !systemOwner else { continue }
            let climbable = ownWindow != nil || Self.canClimbWindow(bundle: bundle, layer: layer, frame: frame)
            // WindowServer does not publish the outline radius. Match our own
            // notebook outline exactly and estimate standard AppKit windows by OS.
            let radius: Double
            if ownWindow is NotebookWindow { radius = Double(NotebookTheme.cornerRadius) }
            else if #available(macOS 26.0, *) { radius = 16 }
            else { radius = AbseilRope.cornerRadius }
            windows.append(DesktopWindow(id: id, frame: converted, canClimb: climbable, cornerRadius: radius))
            if climbable {
                if ["com.apple.inputmethod.AssistiveControl", "com.apple.KeyboardViewer"].contains(bundle ?? "") {
                    if keyboardWindowID == nil { keyboardWindowID = id }
                } else {
                    if fallbackWindowID == nil { fallbackWindowID = id }
                    if frontWindowID == nil && pid == frontPID { frontWindowID = id }
                }
            }
        }
        if frontWindowID == nil { frontWindowID = fallbackWindowID }
        return TerrainSnapshot(windows: windows, viewport: worldViewport)
    }
}
