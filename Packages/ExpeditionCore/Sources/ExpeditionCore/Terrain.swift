import Foundation

public typealias WorldPoint = ExplorerInteraction.Point

public struct WorldRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
    public init(x: Double, y: Double, width: Double, height: Double) {
        minX = x; minY = y; self.width = width; self.height = height
    }
    public func intersects(_ other: WorldRect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }
}

public enum DesktopCoordinates {
    public static func isFullScreen(window: WorldRect, display: WorldRect) -> Bool {
        window.minX <= display.minX + 1 && window.minY <= display.minY + 1
            && window.maxX >= display.maxX - 1 && window.maxY >= display.maxY - 1
    }

    /// Core Graphics uses a downward y axis from the primary display's top.
    public static func sceneRect(_ rect: WorldRect, primaryTop: Double, displayOrigin: WorldPoint) -> WorldRect {
        WorldRect(x: rect.minX - displayOrigin.x, y: primaryTop - rect.maxY - displayOrigin.y, width: rect.width, height: rect.height)
    }
}

public struct DesktopWindow: Equatable, Sendable {
    public let id: UInt32
    public let frame: WorldRect
    public let canClimb: Bool
    /// Rounded outline used by rope contact; ordinary ledges stay rectangular.
    public let cornerRadius: Double
    public init(id: UInt32, frame: WorldRect, canClimb: Bool = true, cornerRadius: Double = 10) {
        self.id = id; self.frame = frame; self.canClimb = canClimb
        self.cornerRadius = min(max(0, cornerRadius.isFinite ? cornerRadius : 10), max(0, min(frame.width, frame.height) / 2))
    }
}

public enum SurfaceOwner: Equatable, Sendable { case window(UInt32), screen }
public enum TerrainEdge: String, Equatable, Sendable { case top, left, right, floor, front, ledge, horizontalCrack, verticalEdge, verticalCrack
    public var isInternal: Bool { [.ledge, .horizontalCrack, .verticalEdge, .verticalCrack].contains(self) }
    public var isStandable: Bool { self == .top || self == .floor || self == .ledge }
    public var isHorizontal: Bool { isStandable || self == .horizontalCrack }
}

public struct TerrainSurface: Equatable, Sendable {
    public struct ID: Equatable, Sendable {
        public let owner: SurfaceOwner
        public let edge: TerrainEdge
        public let segment: Int
    }
    public let id: ID
    public let start: WorldPoint
    public let end: WorldPoint
}

public struct TerrainSnapshot: Equatable, Sendable {
    /// Front to back, including non-climbable occluders.
    public let windows: [DesktopWindow]
    public let viewport: WorldRect
    public let surfaces: [TerrainSurface]
    public let features: [WindowFeature]
    public init(windows: [DesktopWindow], viewport: WorldRect, features: [WindowFeature] = []) {
        self.windows = windows
        self.viewport = viewport
        self.features = features
        surfaces = TerrainBuilder.surfaces(windows: windows, viewport: viewport) + TerrainBuilder.featureSurfaces(features, windows: windows, viewport: viewport)
    }
}

public enum TerrainBuilder {
    public static func surfaces(windows: [DesktopWindow], viewport: WorldRect) -> [TerrainSurface] {
        var result: [TerrainSurface] = []
        for (index, window) in windows.enumerated() where window.canClimb {
            let frame = window.frame
            for edge in [TerrainEdge.top, .left, .right] {
                let horizontal = edge == .top
                let fixed = horizontal ? frame.maxY : (edge == .left ? frame.minX : frame.maxX)
                let fixedMin = horizontal ? viewport.minY : viewport.minX
                let fixedMax = horizontal ? viewport.maxY : viewport.maxX
                guard fixed >= fixedMin, fixed <= fixedMax else { continue }
                let low = max(horizontal ? frame.minX : frame.minY, horizontal ? viewport.minX : viewport.minY)
                let high = min(horizontal ? frame.maxX : frame.maxY, horizontal ? viewport.maxX : viewport.maxY)
                guard high > low else { continue }
                var intervals = [(low, high)]
                for occluder in windows[..<index] {
                    let cover = occluder.frame
                    let crosses = horizontal
                        ? cover.minY <= fixed && cover.maxY >= fixed
                        : cover.minX <= fixed && cover.maxX >= fixed
                    guard crosses else { continue }
                    intervals = subtract(intervals, low: horizontal ? cover.minX : cover.minY, high: horizontal ? cover.maxX : cover.maxY)
                }
                for (segment, interval) in intervals.enumerated() {
                    result.append(TerrainSurface(
                        id: .init(owner: .window(window.id), edge: edge, segment: segment),
                        start: horizontal ? .init(x: interval.0, y: fixed) : .init(x: fixed, y: interval.0),
                        end: horizontal ? .init(x: interval.1, y: fixed) : .init(x: fixed, y: interval.1)
                    ))
                }
            }
        }
        // These are guaranteed rescue boundaries, even when windows extend to the screen edge.
        result.append(.init(id: .init(owner: .screen, edge: .floor, segment: 0), start: .init(x: viewport.minX, y: viewport.minY), end: .init(x: viewport.maxX, y: viewport.minY)))
        for (edge, x) in [(TerrainEdge.left, viewport.minX), (.right, viewport.maxX)] {
            result.append(.init(id: .init(owner: .screen, edge: edge, segment: 0), start: .init(x: x, y: viewport.minY), end: .init(x: x, y: viewport.maxY)))
        }
        return result
    }

    static func featureSurfaces(_ features: [WindowFeature], windows: [DesktopWindow], viewport: WorldRect) -> [TerrainSurface] {
        var result: [TerrainSurface] = []
        for f in features {
            guard f.edge.isInternal, let index = windows.firstIndex(where: { $0.id == f.windowID && $0.canClimb }) else { continue }
            let frame = windows[index].frame
            let horizontal = f.edge.isHorizontal
            let fixed = horizontal ? frame.minY + f.start.y : frame.minX + f.start.x
            guard fixed >= (horizontal ? max(frame.minY + 4, viewport.minY) : max(frame.minX + 4, viewport.minX)),
                  fixed <= (horizontal ? min(frame.maxY - 4, viewport.maxY) : min(frame.maxX - 4, viewport.maxX)) else { continue }
            let low = horizontal ? max(frame.minX + f.start.x, frame.minX + 4, viewport.minX) : max(frame.minY + f.start.y, frame.minY + 4, viewport.minY)
            let high = horizontal ? min(frame.minX + f.end.x, frame.maxX - 4, viewport.maxX) : min(frame.minY + f.end.y, frame.maxY - 4, viewport.maxY)
            guard high > low else { continue }
            var intervals = [(low, high)]
            for cover in windows[..<index].map(\.frame) {
                if horizontal ? cover.minY <= fixed && cover.maxY >= fixed : cover.minX <= fixed && cover.maxX >= fixed {
                    intervals = subtract(intervals, low: horizontal ? cover.minX : cover.minY, high: horizontal ? cover.maxX : cover.maxY)
                }
            }
            for span in intervals {
                result.append(.init(id: .init(owner: .window(f.windowID), edge: f.edge, segment: f.id), start: horizontal ? .init(x: span.0, y: fixed) : .init(x: fixed, y: span.0), end: horizontal ? .init(x: span.1, y: fixed) : .init(x: fixed, y: span.1)))
            }
        }
        return result
    }

    private static func subtract(_ intervals: [(Double, Double)], low: Double, high: Double) -> [(Double, Double)] {
        intervals.flatMap { start, end -> [(Double, Double)] in
            guard high > start, low < end else { return [(start, end)] }
            var remaining: [(Double, Double)] = []
            if low > start { remaining.append((start, min(low, end))) }
            if high < end { remaining.append((max(high, start), end)) }
            return remaining
        }
    }
}

/// Window-relative anchors survive a visible edge splitting into different segments.
public struct TerrainAttachment: Equatable, Sendable {
    public let owner: SurfaceOwner
    public let edge: TerrainEdge
    public let offset: Double
    public let featureID: Int?
    public init(owner: SurfaceOwner, edge: TerrainEdge, offset: Double, featureID: Int? = nil) {
        self.owner = owner; self.edge = edge; self.offset = offset; self.featureID = featureID
    }
}

public enum TerrainSupport {
    /// Sweep the feet across the entire descent step so thin platforms cannot be skipped.
    public static func landing(from start: WorldPoint, to end: WorldPoint, in terrain: TerrainSnapshot) -> (TerrainAttachment, WorldPoint)? {
        guard end.y <= start.y else { return nil }
        let crossed = terrain.surfaces.filter {
            $0.id.edge.isStandable
                && $0.start.y <= start.y && $0.start.y >= end.y
        }.sorted { $0.start.y > $1.start.y }
        for surface in crossed {
            let fraction = start.y > end.y ? (start.y - surface.start.y) / (start.y - end.y) : 0
            let feet = WorldPoint(x: start.x + (end.x - start.x) * fraction, y: surface.start.y)
            if let support = attach(at: feet, in: terrain, tolerance: 0) { return support }
        }
        return nil
    }

    public static func attach(at position: WorldPoint, in terrain: TerrainSnapshot, tolerance: Double = 16) -> (TerrainAttachment, WorldPoint)? {
        let candidates = terrain.surfaces.filter {
            $0.id.edge.isStandable
                && position.x - 24 >= $0.start.x && position.x + 24 <= $0.end.x
                && abs(position.y - $0.start.y) <= tolerance
        }.sorted { abs(position.y - $0.start.y) < abs(position.y - $1.start.y) }
        for surface in candidates {
            if surface.id.edge == .ledge, let feature = terrain.features.first(where: { $0.id == surface.id.segment && .window($0.windowID) == surface.id.owner }),
               let window = terrain.windows.first(where: { $0.id == feature.windowID }) {
                let anchor = TerrainAttachment(owner: surface.id.owner, edge: .ledge, offset: position.x - window.frame.minX - feature.start.x, featureID: feature.id)
                if let point = resolve(anchor, in: terrain) { return (anchor, point) }
                continue
            }
            let base = terrain.windows.first { .window($0.id) == surface.id.owner }?.frame.minX ?? terrain.viewport.minX
            let anchor = TerrainAttachment(owner: surface.id.owner, edge: surface.id.edge, offset: position.x - base)
            if let point = resolve(anchor, in: terrain) { return (anchor, point) }
        }
        return nil
    }

    /// Reach is measured from feet to the matching body pose, not just to a line.
    public static func grip(at position: WorldPoint, in terrain: TerrainSnapshot, reach: Double = 18, excluding: TerrainAttachment? = nil, direction: WorldPoint = .zero) -> (TerrainAttachment, WorldPoint)? {
        var best: (TerrainAttachment, WorldPoint, Double)?
        for feature in terrain.features {
            guard let window = terrain.windows.first(where: { $0.id == feature.windowID }) else { continue }
            if excluding?.featureID == feature.id && excluding?.owner == .window(feature.windowID) { continue }
            let length = WindowFeatureDetector.length(feature)
            let horizontal = feature.edge.isHorizontal
            let offset = horizontal ? min(max(20, position.x - window.frame.minX - feature.start.x), length - 20)
                : min(max(0, position.y - window.frame.minY - feature.start.y), length - 62)
            let anchor = TerrainAttachment(owner: .window(feature.windowID), edge: feature.edge, offset: offset, featureID: feature.id)
            guard let point = resolve(anchor, in: terrain) else { continue }
            let dx = point.x - position.x, dy = point.y - position.y
            guard dx * direction.x + dy * direction.y >= -2 else { continue }
            let distance = hypot(dx, dy)
            if distance <= reach && distance < (best?.2 ?? .infinity) { best = (anchor, point, distance) }
        }
        return best.map { ($0.0, $0.1) }
    }

    public static func resolve(_ anchor: TerrainAttachment, in terrain: TerrainSnapshot) -> WorldPoint? {
        if anchor.owner == .screen, anchor.edge == .top {
            return .init(x: min(max(terrain.viewport.minX + anchor.offset, terrain.viewport.minX + 24), terrain.viewport.maxX - 24), y: terrain.viewport.maxY - 76)
        }
        if anchor.owner == .screen, anchor.edge == .floor {
            let point = WorldPoint(x: min(max(terrain.viewport.minX + anchor.offset, terrain.viewport.minX + 24), terrain.viewport.maxX - 24), y: terrain.viewport.minY)
            return point
        }
        guard case .window(let id) = anchor.owner,
              let index = terrain.windows.firstIndex(where: { $0.id == id }) else { return nil }
        let frame = terrain.windows[index].frame
        if anchor.edge.isInternal {
            guard let featureID = anchor.featureID,
                  let feature = terrain.features.first(where: { $0.windowID == id && $0.id == featureID && $0.edge == anchor.edge }) else { return nil }
            let horizontal = anchor.edge.isHorizontal
            let point = WorldPoint(x: frame.minX + feature.start.x + (horizontal ? anchor.offset : -12),
                                   y: frame.minY + feature.start.y + (horizontal ? (anchor.edge == .horizontalCrack ? -58 : 0) : anchor.offset))
            let contact = WorldPoint(x: horizontal ? point.x : point.x + 12, y: anchor.edge == .horizontalCrack ? point.y + 58 : point.y)
            guard point.x - 24 >= terrain.viewport.minX, point.x + 24 <= terrain.viewport.maxX,
                  point.y >= terrain.viewport.minY, point.y + 76 <= terrain.viewport.maxY,
                  terrain.surfaces.contains(where: {
                      $0.id.owner == anchor.owner && $0.id.edge == anchor.edge && $0.id.segment == featureID
                      && (horizontal ? contact.x - 20 >= $0.start.x && contact.x + 20 <= $0.end.x : contact.y >= $0.start.y && contact.y + 62 <= $0.end.y)
                  }) else { return nil }
            let body = WorldRect(x: point.x - 23, y: point.y + 1, width: 46, height: 74)
            guard !terrain.windows[..<index].contains(where: { $0.frame.intersects(body) }) else { return nil }
            return point
        }
        if anchor.edge == .front {
            // A visible hook pin does not need standing room above the roof.
            // Keep the hanging body on screen when a window touches the menu bar.
            let x = frame.minX + anchor.offset
            guard terrain.surfaces.contains(where: {
                $0.id.owner == anchor.owner && $0.id.edge == .top
                    && x - 24 >= $0.start.x && x + 24 <= $0.end.x
            }) else { return nil }
            let point = WorldPoint(x: x, y: min(frame.maxY - 58, terrain.viewport.maxY - 76))
            let body = WorldRect(x: point.x - 23, y: point.y + 1, width: 46, height: 74)
            guard point.x - 24 >= terrain.viewport.minX, point.x + 24 <= terrain.viewport.maxX,
                  point.y >= terrain.viewport.minY,
                  !terrain.windows[..<index].contains(where: { $0.frame.intersects(body) }) else { return nil }
            return point
        }
        if anchor.edge == .left || anchor.edge == .right {
            let y = frame.minY + anchor.offset
            let x = anchor.edge == .left ? frame.minX - 24 : frame.maxX + 24
            guard x >= terrain.viewport.minX + 24, x <= terrain.viewport.maxX - 24,
                  y >= terrain.viewport.minY, y + 76 <= terrain.viewport.maxY,
                  terrain.surfaces.contains(where: {
                      $0.id.owner == anchor.owner && $0.id.edge == anchor.edge
                          && y >= $0.start.y - 64 && y <= $0.end.y
                          && min(y + 60, frame.maxY) <= $0.end.y
                  }) else { return nil }
            let body = WorldRect(x: x - 23, y: y + 1, width: 46, height: 74)
            guard !terrain.windows[..<index].contains(where: { $0.frame.intersects(body) }) else { return nil }
            return .init(x: x, y: y)
        }
        guard anchor.edge == .top else { return nil }
        let point = WorldPoint(x: frame.minX + anchor.offset, y: frame.maxY)
        guard point.y + 76 <= terrain.viewport.maxY,
              terrain.surfaces.contains(where: {
                  $0.id.owner == anchor.owner && $0.id.edge == anchor.edge
                      && point.x - 24 >= $0.start.x && point.x + 24 <= $0.end.x
              }) else { return nil }
        let body = WorldRect(x: point.x - 24, y: point.y, width: 48, height: 76)
        guard !terrain.windows[..<index].contains(where: { $0.frame.intersects(body) }) else { return nil }
        return point
    }
}
