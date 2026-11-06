import Foundation

/// All image coordinates are in window-local points, with y increasing upwards.
public struct WindowFeature: Equatable, Sendable {
    public let id: Int
    public let windowID: UInt32
    public let edge: TerrainEdge
    public var start: WorldPoint
    public var end: WorldPoint
    public var appearance: [Double]
    public init(id: Int, windowID: UInt32, edge: TerrainEdge, start: WorldPoint, end: WorldPoint, appearance: [Double] = []) {
        self.id = id; self.windowID = windowID; self.edge = edge
        self.start = start; self.end = end; self.appearance = appearance
    }
}

/// Reduced RGB pixels, top row first. Never retains a captured desktop image.
public struct TerrainPixels: Sendable {
    public let width: Int
    public let height: Int
    public let rgb: [UInt8]
    public let pointWidth: Double
    public let pointHeight: Double
    public let textRegions: [WorldRect]
    public init(width: Int, height: Int, rgb: [UInt8], pointWidth: Double, pointHeight: Double, textRegions: [WorldRect] = []) {
        self.width = width; self.height = height; self.rgb = rgb
        self.pointWidth = pointWidth; self.pointHeight = pointHeight; self.textRegions = textRegions
    }
    func color(_ x: Int, _ y: Int) -> SIMD3<Double> {
        let i = (min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))) * 3
        return SIMD3(Double(rgb[i]), Double(rgb[i + 1]), Double(rgb[i + 2])) / 255
    }
    var valid: Bool { width >= 24 && height >= 24 && rgb.count == width * height * 3 && pointWidth > 0 && pointHeight > 0 }
}

public enum WindowFeatureDetector {
    static func difference(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
    }
    static func difference(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }
    /// Long, coherent boundaries only. Text strokes and tiny controls are deliberately rejected.
    public static func detect(_ image: TerrainPixels, windowID: UInt32) -> [WindowFeature] {
        guard image.valid else { return [] }
        // Normalize each pixel once. The scan revisits neighbouring pixels many
        // times; repeated byte conversion/clamping was dominating debug captures.
        let colors = image.rgb.withUnsafeBufferPointer { bytes in
            [SIMD3<Double>](unsafeUninitializedCapacity: image.width * image.height) { output, initialized in
                for index in 0..<(image.width * image.height) {
                    let offset = index * 3
                    output[index] = SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
                }
                initialized = image.width * image.height
            }
        }
        var candidates: [WindowFeature] = []
        for horizontal in [true, false] {
            let across = horizontal ? image.height : image.width
            let along = horizontal ? image.width : image.height
            let alongScale = horizontal ? image.pointWidth / Double(image.width) : image.pointHeight / Double(image.height)
            let minimum = max(24, Int((horizontal ? 64.0 : 76.0) / alongScale))
            func color(_ a: Int, _ b: Int) -> SIMD3<Double> { colors[horizontal ? a * image.width + b : b * image.width + a] }
            for a in 8..<(across - 8) {
                var runStart = 0
                var runEdge: TerrainEdge?
                var runLow = SIMD3<Double>.zero, runHigh = SIMD3<Double>.zero, runCenter = SIMD3<Double>.zero
                func finish(_ b: Int) {
                    guard let edge = runEdge, b - runStart >= minimum else { return }
                    let s: WorldPoint, e: WorldPoint
                    if horizontal {
                        let y = image.pointHeight * (1 - Double(a) / Double(image.height))
                        s = .init(x: Double(runStart) * alongScale, y: y); e = .init(x: Double(b) * alongScale, y: y)
                    } else {
                        let x = image.pointWidth * Double(a) / Double(image.width)
                        s = .init(x: x, y: image.pointHeight - Double(b) * alongScale)
                        e = .init(x: x, y: image.pointHeight - Double(runStart) * alongScale)
                    }
                    // OCR boxes use the same bottom-left window-local coordinates.
                    // Reject the whole response rather than leaving text fragments as holds.
                    let band = WorldRect(x: min(s.x, e.x) - 1, y: min(s.y, e.y) - 1,
                                         width: abs(e.x - s.x) + 2, height: abs(e.y - s.y) + 2)
                    guard !image.textRegions.contains(where: { $0.intersects(band) }) else { return }
                    candidates.append(.init(id: 0, windowID: windowID, edge: edge, start: s, end: e, appearance: [runLow.x, runLow.y, runLow.z, runHigh.x, runHigh.y, runHigh.z, runCenter.x, runCenter.y, runCenter.z]))
                }
                for b in stride(from: 6, to: along - 6, by: 2) {
                    let center = color(a, b), nearLow = color(a - 1, b), nearHigh = color(a + 1, b)
                    if max(difference(center, nearLow), difference(center, nearHigh), difference(nearLow, nearHigh)) < 0.018 {
                        finish(b); runStart = b + 2; runEdge = nil
                        continue
                    }
                    let low = color(a - 5, b), high = color(a + 5, b)
                    let sustained = difference(low, high) >= 0.045
                        && difference(nearLow, nearHigh) >= 0.02
                        && difference(low, color(a - 8, b)) < 0.045
                        && difference(high, color(a + 8, b)) < 0.045
                    let thin = difference(low, high) < 0.035 && difference(center, (low + high) / 2) >= 0.03
                    let edge: TerrainEdge? = sustained ? (horizontal ? .ledge : .verticalEdge) : (thin ? (horizontal ? .horizontalCrack : .verticalCrack) : nil)
                    let nextCenter = thin ? center : SIMD3<Double>.zero
                    if edge != runEdge || (edge != nil && max(difference(runLow, low), difference(runHigh, high), difference(runCenter, nextCenter)) > 0.075) {
                        finish(b); runStart = b; runEdge = edge; runLow = low; runHigh = high; runCenter = nextCenter
                    }
                }
                finish(along - 6)
            }
        }
        // A thick boundary produces several nearby responses. Keep its centre response,
        // merging only collinear overlapping candidates of the same material/type.
        var merged: [WindowFeature] = []
        for candidate in candidates.sorted(by: { length($0) > length($1) }) {
            let fixed = candidate.edge.isHorizontal ? candidate.start.y : candidate.start.x
            if merged.contains(where: {
                guard $0.edge == candidate.edge, difference($0.appearance, candidate.appearance) < 0.12 else { return false }
                let other = candidate.edge.isHorizontal ? $0.start.y : $0.start.x
                let overlap = candidate.edge.isHorizontal
                    ? min($0.end.x, candidate.end.x) - max($0.start.x, candidate.start.x)
                    : min($0.end.y, candidate.end.y) - max($0.start.y, candidate.start.y)
                return abs(fixed - other) < 10 && overlap > min(length($0), length(candidate)) * 0.6
            }) { continue }
            merged.append(candidate)
            if merged.count >= 24 { break }
        }
        return merged
    }
    static func length(_ f: WindowFeature) -> Double { hypot(f.end.x - f.start.x, f.end.y - f.start.y) }
}

/// Matches appearance and image registration rather than assigning identity by row number.
public struct WindowFeatureTracker: Sendable {
    private struct Track: Sendable {
        var feature: WindowFeature
        var velocity = WorldPoint.zero
        var seen: Double
        var hits: Int
    }
    private var tracks: [Track] = []
    private var previous: TerrainPixels?
    private var lastTime = 0.0
    private var nextID = 1
    public init() {}
    public mutating func update(_ image: TerrainPixels, windowID: UInt32, at time: Double) {
        let dt = time - lastTime
        let compatible = previous.map { $0.width == image.width && $0.height == image.height && $0.pointWidth == image.pointWidth && $0.pointHeight == image.pointHeight } ?? false
        if !compatible || dt > 0.35 || dt <= 0 { tracks.removeAll() }
        let shift = compatible && dt > 0 && dt <= 0.35 ? Self.translation(from: previous!, to: image) : .zero
        var available = Set(tracks.indices)
        var next: [Track] = []
        for var feature in WindowFeatureDetector.detect(image, windowID: windowID) {
            let matches = available.compactMap { index -> (Int, Double)? in
                let old = tracks[index].feature
                guard old.edge == feature.edge, WindowFeatureDetector.difference(old.appearance, feature.appearance) < 0.15 else { return nil }
                let dx = feature.start.x - old.start.x, dy = feature.start.y - old.start.y
                let moved = hypot(dx - shift.x, dy - shift.y)
                let stationary = hypot(dx, dy)
                let score = min(moved, stationary + 6)
                guard score < 24 else { return nil }
                return (index, score)
            }
            if let (index, _) = matches.min(by: { $0.1 < $1.1 }) {
                let old = tracks[index]
                feature = WindowFeature(id: old.feature.id, windowID: windowID, edge: feature.edge, start: feature.start, end: feature.end, appearance: feature.appearance)
                let vx = (feature.start.x - old.feature.start.x) / max(0.01, dt)
                let vy = (feature.start.y - old.feature.start.y) / max(0.01, dt)
                // Never fling a body with an unconstrained prediction after a bad match.
                let velocity = WorldPoint(x: max(-1200, min(1200, vx)), y: max(-1200, min(1200, vy)))
                next.append(.init(feature: feature, velocity: velocity, seen: time, hits: old.hits + 1))
                available.remove(index)
            } else {
                feature = WindowFeature(id: nextID, windowID: windowID, edge: feature.edge, start: feature.start, end: feature.end, appearance: feature.appearance)
                nextID += 1; next.append(.init(feature: feature, seen: time, hits: 1))
            }
        }
        // A single missed sample is tolerated only for stationary holds. Moving misses
        // are dropped immediately: extrapolating invisible scrolling terrain is unsafe.
        for index in available where time - tracks[index].seen < 0.12 && hypot(tracks[index].velocity.x, tracks[index].velocity.y) < 5 {
            let f = tracks[index].feature
            let band = WorldRect(x: min(f.start.x, f.end.x) - 1, y: min(f.start.y, f.end.y) - 1,
                                 width: abs(f.end.x - f.start.x) + 2, height: abs(f.end.y - f.start.y) + 2)
            // Positive text evidence invalidates an old hold immediately; it is
            // not an ordinary missed-detection frame eligible for grace.
            if !image.textRegions.contains(where: { $0.intersects(band) }) { next.append(tracks[index]) }
        }
        tracks = next; previous = image; lastTime = time
    }
    /// ScreenCaptureKit idle frames (or byte-identical frames) are positive
    /// evidence that the image is unchanged, not missed detections.
    public mutating func confirmUnchanged(at time: Double) {
        guard previous != nil, time >= lastTime else { return }
        for index in tracks.indices {
            tracks[index].seen = time; tracks[index].hits += 1; tracks[index].velocity = .zero
        }
        lastTime = time
    }
    public func features(at time: Double) -> [WindowFeature] {
        tracks.filter { $0.hits >= 2 && time - $0.seen <= 0.25 }.map {
            var feature = $0.feature
            let t = min(0.05, max(0, time - $0.seen))
            feature.start.x += $0.velocity.x * t; feature.end.x += $0.velocity.x * t
            feature.start.y += $0.velocity.y * t; feature.end.y += $0.velocity.y * t
            return feature
        }
    }
    /// Coarse-to-fine RGB registration ignores the title bar. Choosing a shift must
    /// improve on a static frame substantially, so fixed app chrome stays fixed.
    static func translation(from old: TerrainPixels, to new: TerrainPixels) -> WorldPoint {
        guard old.valid && new.valid else { return .zero }
        func error(_ dx: Int, _ dy: Int) -> Double {
            var sum = 0.0, count = 0.0
            for y in stride(from: max(16, new.height / 5), to: new.height - 16, by: 13) {
                for x in stride(from: 16, to: new.width - 16, by: 23) where x - dx >= 0 && x - dx < old.width && y - dy >= 0 && y - dy < old.height {
                    let a = new.color(x, y), b = old.color(x - dx, y - dy)
                    sum += min(0.35, abs(a.x - b.x)) + min(0.35, abs(a.y - b.y)) + min(0.35, abs(a.z - b.z))
                    count += 3
                }
            }
            return count > 0 ? sum / count : 1
        }
        let baseline = error(0, 0)
        guard baseline > 0.003 else { return .zero }
        var best = (x: 0, y: 0, cost: baseline)
        for dy in stride(from: -min(120, new.height / 3), through: min(120, new.height / 3), by: 4) {
            for dx in stride(from: -24, through: 24, by: 8) {
                let cost = error(dx, dy)
                if cost < best.cost { best = (dx, dy, cost) }
            }
        }
        let coarse = best
        for dy in (coarse.y - 3)...(coarse.y + 3) {
            for dx in (coarse.x - 3)...(coarse.x + 3) {
                let cost = error(dx, dy)
                if cost < best.cost { best = (dx, dy, cost) }
            }
        }
        guard best.cost < baseline * 0.7 else { return .zero }
        return .init(x: Double(best.x) * new.pointWidth / Double(new.width), y: -Double(best.y) * new.pointHeight / Double(new.height))
    }
}
