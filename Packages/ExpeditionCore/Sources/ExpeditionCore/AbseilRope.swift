import Foundation

/// A top pin and a circular corner guide. The free lead leaves the guide at its
/// mathematical tangent to the hand, rather than kinking at a fixed quarter-circle.
public struct AbseilRope {
    public static let cornerRadius = 10.0
    public static let anchorInset = 28.0
    public let anchor: WorldPoint
    public let topTangent: WorldPoint
    public let control1: WorldPoint
    public let control2: WorldPoint
    public let sideTangent: WorldPoint
    public let wrappedLength: Double
    private let window: WorldRect
    private let edge: TerrainEdge

    private let windowCornerRadius: Double
    private let frontOffset: Double?
    /// A hook over the front rim has one straight free span, without a side corner.
    public init(window: WorldRect, frontOffset: Double) {
        self.window = window; edge = .front; self.frontOffset = frontOffset; windowCornerRadius = 0
        let pin = WorldPoint(x: window.minX + frontOffset, y: window.maxY + 1)
        anchor = pin; topTangent = pin; sideTangent = pin
        control1 = pin; control2 = pin; wrappedLength = 0
    }

    public static func pinInset(window: WorldRect, cornerRadius: Double) -> Double {
        let radius = fittedRadius(window: window, radius: cornerRadius)
        return min(max(0, window.width / 2), max(anchorInset, radius + 8))
    }
    private static func fittedRadius(window: WorldRect, radius: Double) -> Double {
        min(max(0, radius.isFinite ? radius : Self.cornerRadius), max(0, min(window.width, window.height) / 2))
    }
    public init(window: WorldRect, edge: TerrainEdge, grip: WorldPoint? = nil, cornerRadius: Double = AbseilRope.cornerRadius) {
        self.window = window; self.edge = edge; frontOffset = nil
        let inward = edge == .left ? 1.0 : -1.0
        let cornerX = edge == .left ? window.minX : window.maxX
        let radius = Self.fittedRadius(window: window, radius: cornerRadius)
        windowCornerRadius = radius
        let pinInset = Self.pinInset(window: window, cornerRadius: radius)
        let arcRadius = radius + 1 // One point outside the rounded window border.
        let center = WorldPoint(x: cornerX + inward * radius, y: window.maxY - radius)
        var angle = Double.pi
        if let grip {
            let dx = (grip.x - center.x) * inward, dy = grip.y - center.y
            let distance = hypot(dx, dy)
            if distance > arcRadius {
                angle = (atan2(dy, dx) - acos(arcRadius / distance)).truncatingRemainder(dividingBy: 2 * .pi)
                if angle < 0 { angle += 2 * .pi }
                angle = min(.pi, max(.pi / 2, angle))
            }
        }
        wrappedLength = pinInset - radius + arcRadius * (angle - .pi / 2)
        let handle = 4.0 / 3 * tan((angle - .pi / 2) / 4)
        anchor = .init(x: cornerX + inward * pinInset, y: window.maxY + 1)
        topTangent = .init(x: center.x, y: window.maxY + 1)
        sideTangent = .init(x: center.x + inward * arcRadius * cos(angle), y: center.y + arcRadius * sin(angle))
        control1 = .init(x: topTangent.x - inward * arcRadius * handle, y: topTangent.y)
        control2 = .init(x: sideTangent.x + inward * arcRadius * sin(angle) * handle, y: sideTangent.y - arcRadius * cos(angle) * handle)
    }

    public func length(to grip: WorldPoint) -> Double {
        let path = taut(toward: grip)
        return path.wrappedLength + hypot(grip.x - path.sideTangent.x, grip.y - path.sideTangent.y)
    }
    public func taut(toward grip: WorldPoint) -> AbseilRope {
        if let frontOffset { return .init(window: window, frontOffset: frontOffset) }
        return .init(window: window, edge: edge, grip: grip, cornerRadius: windowCornerRadius)
    }
}
