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
    private let window: WorldRect
    private let edge: TerrainEdge

    public init(window: WorldRect, edge: TerrainEdge, grip: WorldPoint? = nil) {
        self.window = window; self.edge = edge
        let inward = edge == .left ? 1.0 : -1.0
        let cornerX = edge == .left ? window.minX : window.maxX
        let radius = Self.cornerRadius
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
        let handle = 4.0 / 3 * tan((angle - .pi / 2) / 4)
        anchor = .init(x: cornerX + inward * Self.anchorInset, y: window.maxY + 1)
        topTangent = .init(x: center.x, y: window.maxY + 1)
        sideTangent = .init(x: center.x + inward * arcRadius * cos(angle), y: center.y + arcRadius * sin(angle))
        control1 = .init(x: topTangent.x - inward * arcRadius * handle, y: topTangent.y)
        control2 = .init(x: sideTangent.x + inward * arcRadius * sin(angle) * handle, y: sideTangent.y - arcRadius * cos(angle) * handle)
    }

    public func taut(toward grip: WorldPoint) -> AbseilRope { .init(window: window, edge: edge, grip: grip) }
}
