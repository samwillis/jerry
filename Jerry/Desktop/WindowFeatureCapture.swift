import AppKit
import ScreenCaptureKit
import CoreMedia
import Vision
import ExpeditionCore

/// One bounded stream. The overlay pairs host/front-window and keyboard streams when needed.
/// Pixels are analysed on a serial background queue, never stored or sent anywhere.
@MainActor
final class WindowFeatureCapture {
    private var stream: SCStream?
    private var reader: FeatureFrameReader?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var started = 0.0
    private var retryAfter = 0.0
    private var target: DesktopWindow?
    private var features: [WindowFeature] = []
    private var velocity: [Int: WorldPoint] = [:]
    private var received = 0.0
    private var lastTimestamp = 0.0
    private(set) var status = "Explore inside windows is off"
    var onFeatures: (([WindowFeature]) -> Void)?
    var enabled = false

    func update(terrain: TerrainSnapshot, preferredWindow: UInt32?, running: Bool) {
        let desired = enabled && running && CGPreflightScreenCaptureAccess()
            ? (terrain.windows.first { $0.id == preferredWindow && $0.canClimb } ?? terrain.windows.first { $0.canClimb }) : nil
        let now = ProcessInfo.processInfo.systemUptime
        if desired == nil {
            if target != nil { stop() }
            status = enabled ? (CGPreflightScreenCaptureAccess() ? "Window exploration is resting" : "Screen Recording access needed") : "Explore inside windows is off"
            return
        }
        if desired != nil, target == nil, now < retryAfter { return }
        let stalled = stream != nil && now - max(received, started) > 1
        if !stalled, desired?.id == target?.id, desired?.frame.width == target?.frame.width, desired?.frame.height == target?.frame.height { return }
        stop()
        guard let desired else {
            if enabled { status = CGPreflightScreenCaptureAccess() ? "Window exploration is resting" : "Screen Recording access needed" }
            return
        }
        target = desired; started = now
        generation += 1
        let token = generation
        status = "Finding holds…"
        task = Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let self, !Task.isCancelled, self.generation == token,
                      let window = content.windows.first(where: { $0.windowID == desired.id }) else { return }
                let config = SCStreamConfiguration()
                let scale = min(1, 800 / desired.frame.width, 600 / desired.frame.height)
                config.width = max(24, Int(desired.frame.width * scale))
                config.height = max(24, Int(desired.frame.height * scale))
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                config.ignoreShadowsSingleWindow = true
                let reader = FeatureFrameReader(window: desired) { [weak self] features, timestamp in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        let dt = timestamp - self.lastTimestamp
                        var velocity: [Int: WorldPoint] = [:]
                        if dt > 0.01 && dt < 0.3 {
                            for feature in features {
                                if let old = self.features.first(where: { $0.id == feature.id }) {
                                    velocity[feature.id] = .init(x: max(-1200, min(1200, (feature.start.x - old.start.x) / dt)), y: max(-1200, min(1200, (feature.start.y - old.start.y) / dt)))
                                }
                            }
                        }
                        self.velocity = velocity
                        self.features = features; self.received = ProcessInfo.processInfo.systemUptime; self.lastTimestamp = timestamp
                        self.status = "\(features.count) holds · up to 20 updates/sec"
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--trace-features") {
                            print("FEATURE FRAME \(features.count) holds · age \(self.received - timestamp) · window \(desired.id)"); fflush(stdout)
                        }
                        #endif
                        self.onFeatures?(features)
                    }
                }
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: reader)
                self.reader = reader; self.stream = stream
                try stream.addStreamOutput(reader, type: .screen, sampleHandlerQueue: reader.queue)
                try await stream.startCapture()
                DesktopAccess.shared.captureStarted()
                if self.generation != token { try? await stream.stopCapture() }
            } catch {
                guard let self, self.generation == token else { return }
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain, failure.code == SCStreamError.Code.userDeclined.rawValue { DesktopAccess.shared.captureRejected() }
                self.status = "Window capture unavailable — check Screen Recording access"
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--trace-features") { print("FEATURE ERROR \(error)"); fflush(stdout) }
                #endif
                self.features = []; self.onFeatures?([])
                // Retry after a fresh geometry tick, without overlapping capture sessions.
                self.target = nil; self.stream = nil; self.reader = nil; self.retryAfter = ProcessInfo.processInfo.systemUptime + 3
            }
        }
    }
    func currentFeatures() -> [WindowFeature] {
        let now = ProcessInfo.processInfo.systemUptime
        // Age the published result from delivery, not from the start of OCR/analysis.
        // Otherwise a valid result can expire immediately on a large Debug frame.
        // Queued old frames are rejected by the reader; prediction still uses the
        // original observation time and is bounded to 50 ms.
        guard enabled, now - received < 0.25 else { return [] }
        let dt = min(0.05, max(0, now - lastTimestamp))
        return features.map {
            var feature = $0
            let v = velocity[feature.id] ?? .zero
            feature.start.x += v.x * dt; feature.end.x += v.x * dt
            feature.start.y += v.y * dt; feature.end.y += v.y * dt
            return feature
        }
    }
    func stop() {
        generation += 1; task?.cancel(); task = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil; reader = nil; target = nil; features = []; velocity = [:]; received = 0; lastTimestamp = 0
    }
}

private final class FeatureFrameReader: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.jerry.window-features", qos: .userInitiated)
    private let window: DesktopWindow
    private var tracker = WindowFeatureTracker()
    private var lastFrame = 0.0
    private var lastPixels: TerrainPixels?
    private let deliver: @Sendable ([WindowFeature], Double) -> Void
    init(window: DesktopWindow, deliver: @escaping @Sendable ([WindowFeature], Double) -> Void) {
        self.window = window; self.deliver = deliver
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if status == .idle {
            if lastPixels != nil {
                tracker.confirmUnchanged(at: now)
                deliver(tracker.features(at: now), now)
            }
            return
        }
        guard status == .complete, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            lastPixels = nil; deliver([], now); return
        }
        let presentation = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // Reject queued old frames instead of catching up with stale scrolling content.
        guard now - lastFrame >= 0.04, !presentation.isFinite || now - presentation < 0.15 else { return }
        lastFrame = now
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly); return
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        rgb.withUnsafeMutableBufferPointer { output in
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * stride + x * 4, o = (y * width + x) * 3
                    output[o] = bytes[i + 2]; output[o + 1] = bytes[i + 1]; output[o + 2] = bytes[i]
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        if lastPixels?.rgb == rgb {
            tracker.confirmUnchanged(at: now); deliver(tracker.features(at: now), now); return
        }
        // Text content is discarded immediately. Only exclusion rectangles survive
        // this request, on the same serial queue as boundary detection.
        let textRegions: [WorldRect]
        do { textRegions = try WindowTextExclusion.regions(in: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]), width: window.frame.width, height: window.frame.height) }
        catch {
            // Never publish unfiltered text as terrain when text detection fails.
            lastPixels = nil; deliver([], now); return
        }
        let pixels = TerrainPixels(width: width, height: height, rgb: rgb, pointWidth: window.frame.width, pointHeight: window.frame.height, textRegions: textRegions)
        tracker.update(pixels, windowID: window.id, at: now)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--trace-features") {
            print("FEATURE ANALYSIS \(Int((ProcessInfo.processInfo.systemUptime - now) * 1000)) ms · \(width) × \(height)"); fflush(stdout)
        }
        #endif
        lastPixels = pixels
        deliver(tracker.features(at: now), now)
    }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { deliver([], ProcessInfo.processInfo.systemUptime) }
}

/// Vision runs locally. No recognized strings are retained, logged or used by the app.
private enum WindowTextExclusion {
    static func regions(in handler: VNImageRequestHandler, width: Double, height: Double) throws -> [WorldRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        try handler.perform([request])
        return (request.results ?? []).compactMap {
            guard let text = $0.topCandidates(1).first, text.confidence >= 0.2,
                  text.string.contains(where: { $0.isLetter || $0.isNumber }),
                  text.string.contains(where: { !"Il1|_—- .".contains($0) }) else { return nil }
            let box = $0.boundingBox
            return WorldRect(x: box.minX * width - 2, y: box.minY * height - 3,
                             width: box.width * width + 4, height: box.height * height + 6)
        }
    }
}

#if DEBUG
@MainActor
private final class FeatureCheckCanvas: NSView {
    var scroll = 0.0 { didSet { needsDisplay = true } }
    var pulse = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); bounds.fill()
        NSColor(calibratedWhite: pulse ? 0.5 : 0.8, alpha: 1).setFill()
        CGRect(x: 5, y: 5, width: 8, height: 8).fill()
        NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
        CGRect(x: 40, y: 180 + scroll, width: 620, height: 85).fill()
        NSColor.black.setFill()
        CGRect(x: 40, y: 340 + scroll, width: 620, height: 2).fill()
        CGRect(x: 430, y: 30 + scroll, width: 2, height: 120).fill()
        NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
        CGRect(x: 40, y: 110 + scroll, width: 620, height: 1).fill()
        NSColor(calibratedWhite: 0.87, alpha: 1).setFill()
        CGRect(x: 40, y: 285 + scroll, width: 620, height: 25).fill()
        ("Some real text should never become a climbing ledge" as NSString).draw(at: .init(x: 60, y: 420 + scroll), withAttributes: [
            .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black, .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
    }
}

extension WindowFeatureCapture {
    /// Real ScreenCaptureKit frames of our disposable canvas, including a content scroll.
    static func runNativeChecks(size: CGSize = .init(width: 720, height: 520)) async -> Bool {
        guard CGPreflightScreenCaptureAccess() else { print("FEATURE SKIP Screen Recording access has not been granted"); return false }
        let window = NSWindow(contentRect: .init(origin: .init(x: 180, y: 100), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = FeatureCheckCanvas(frame: .init(origin: .zero, size: size))
        window.contentView = canvas; window.orderFrontRegardless()
        let capture = WindowFeatureCapture(); capture.enabled = true
        let viewport = WorldRect(x: 0, y: 0, width: 2000, height: 1400)
        let desktop = DesktopWindow(id: UInt32(window.windowNumber), frame: .init(x: 180, y: 100, width: size.width, height: size.height))
        capture.update(terrain: .init(windows: [desktop], viewport: viewport), preferredWindow: desktop.id, running: true)
        defer { capture.stop(); window.close() }
        var passed = true
        func check(_ condition: Bool, _ name: String) { print("FEATURE \(condition ? "PASS" : "FAIL") \(name)"); fflush(stdout); passed = passed && condition }
        let deadline = Date(timeIntervalSinceNow: 8)
        while Date() < deadline && !capture.currentFeatures().contains(where: { $0.edge == .horizontalCrack }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            if let image = bitmap.cgImage {
                let regions = try? WindowTextExclusion.regions(in: VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]), width: size.width, height: size.height)
                check(regions?.contains { $0.minY > 400 && $0.minY < 450 } == true, "local text recognition identifies the rendered text region")
            } else { check(false, "rendered text image available") }
        } else { check(false, "rendered text image available") }
        let first = capture.currentFeatures()
        check(first.contains { $0.edge == .ledge }, "real captured block creates a standing ledge")
        check(first.contains { $0.edge == .verticalCrack }, "real captured vertical line creates a climbing crack")
        check(first.contains { $0.edge == .horizontalCrack && abs($0.start.y - 110) < 4 }, "faint one-point rule survives real capture")
        check(first.contains { $0.edge == .ledge && abs($0.start.y - 310) < 4 }, "low-contrast block boundary survives real capture")
        check(!first.contains { $0.edge.isHorizontal && $0.start.y >= 414 && $0.start.y <= 452 }, "real underlined text is excluded from terrain")
        guard let crack = first.first(where: { $0.edge == .horizontalCrack && abs($0.start.y - 340) < 5 }) else {
            check(false, "real captured hairline creates a hanging traverse — \(capture.status)"); return false
        }
        check(true, "real captured hairline creates a hanging traverse")
        let localAnchor = TerrainAttachment(owner: .window(desktop.id), edge: .horizontalCrack, offset: 250, featureID: crack.id)
        let before = TerrainSupport.resolve(localAnchor, in: .init(windows: [desktop], viewport: viewport, features: first))
        canvas.scroll = 60; canvas.displayIfNeeded()
        let scrollDeadline = Date(timeIntervalSinceNow: 5)
        var afterFeatures: [WindowFeature] = []
        while Date() < scrollDeadline {
            afterFeatures = capture.currentFeatures()
            if let moved = afterFeatures.first(where: { $0.id == crack.id }), abs(moved.start.y - crack.start.y - 60) < 5 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let after = TerrainSupport.resolve(localAnchor, in: .init(windows: [desktop], viewport: viewport, features: afterFeatures))
        check(before != nil && after != nil && abs(after!.y - before!.y - 60) < 5, "scrolling preserves grip identity and carries its attachment by 60 points")
        try? await Task.sleep(for: .milliseconds(500))
        check(capture.currentFeatures().contains { $0.id == crack.id }, "unchanged window frames keep confirmed holds alive")
        var continuous = true
        for _ in 0..<16 {
            canvas.pulse.toggle(); canvas.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
            continuous = continuous && capture.currentFeatures().contains { $0.id == crack.id }
        }
        check(continuous, "stable holds remain published while unrelated window content repaints")
        capture.stop()
        check(capture.currentFeatures().isEmpty, "stopping capture removes stale holds")
        return passed
    }
}
#endif
