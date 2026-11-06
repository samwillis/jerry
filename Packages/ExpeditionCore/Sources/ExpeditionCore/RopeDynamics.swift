import Foundation

public enum RopeSupport {
    case point(WorldPoint)
    case corner(AbseilRope)
    func span(to point: WorldPoint) -> (contact: WorldPoint, length: Double) {
        switch self {
        case .point(let anchor): return (anchor, hypot(point.x - anchor.x, point.y - anchor.y))
        case .corner(let guide):
            let path = guide.taut(toward: point)
            return (path.sideTangent, path.wrappedLength + hypot(point.x - path.sideTangent.x, point.y - path.sideTangent.y))
        }
    }
}

/// A unilateral, inextensible line: it can pull under tension but never pushes a
/// slack climber. Position and velocity are in logical points and seconds.
public struct RopeDynamics {
    public static let gravity = 480.0
    public static let maximumLength = 2400.0
    public private(set) var position: WorldPoint
    public private(set) var velocity: WorldPoint
    public private(set) var length: Double
    public private(set) var isTaut = false
    public var damping = 0.08
    public var acceleration = WorldPoint(x: 0, y: -RopeDynamics.gravity)
    public init(position: WorldPoint, velocity: WorldPoint = .zero, length: Double) {
        self.position = position; self.velocity = velocity; self.length = max(24, length)
    }
    public mutating func advance(by elapsed: Double, guide: AbseilRope, payOut: Double = 0) {
        advance(by: elapsed, support: .corner(guide), payOut: payOut)
    }
    public mutating func advance(by elapsed: Double, support: RopeSupport, payOut: Double = 0) {
        guard elapsed.isFinite, elapsed > 0, payOut.isFinite else { return }
        let duration = min(elapsed, 0.25)
        let count = max(1, Int(ceil(duration * 240)))
        let dt = duration / Double(count)
        for _ in 0..<count {
            let previous = support.span(to: position)
            let oldFree = hypot(position.x - previous.contact.x, position.y - previous.contact.y)
            let change = payOut / Double(count)
            let oldLength = length
            length = min(Self.maximumLength, max(24, length + change))
            if change < 0, oldFree > 8, previous.length >= oldLength - 1 {
                let nx = (position.x - previous.contact.x) / oldFree, ny = (position.y - previous.contact.y) / oldFree
                let radial = velocity.x * nx + velocity.y * ny
                let ratio = oldFree / max(8, oldFree + length - oldLength)
                velocity = .init(x: radial * nx + (velocity.x - radial * nx) * ratio, y: radial * ny + (velocity.y - radial * ny) * ratio)
            }
            velocity.x += acceleration.x * dt
            velocity.y += acceleration.y * dt
            let decay = exp(-damping * dt)
            velocity.x *= decay; velocity.y *= decay
            position.x += velocity.x * dt; position.y += velocity.y * dt
            isTaut = false
            for _ in 0..<8 {
                let path = support.span(to: position)
                let dx = position.x - path.contact.x, dy = position.y - path.contact.y
                let free = hypot(dx, dy)
                let excess = path.length - length
                guard excess > 0.000001, free > 0.000001 else { break }
                position.x -= dx / free * excess; position.y -= dy / free * excess
                isTaut = true
            }
            if isTaut {
                let path = support.span(to: position)
                let dx = position.x - path.contact.x, dy = position.y - path.contact.y
                let distance = max(0.000001, hypot(dx, dy))
                let outward = (velocity.x * dx + velocity.y * dy) / distance
                if outward > 0 { velocity.x -= outward * dx / distance; velocity.y -= outward * dy / distance }
            }
        }
    }
    public mutating func addImpulse(_ impulse: WorldPoint) {
        velocity.x += impulse.x; velocity.y += impulse.y
    }
    public mutating func translate(by delta: WorldPoint) { position.x += delta.x; position.y += delta.y }
    /// Contact with a window, floor or usable display boundary removes only velocity
    /// into that contact. Tangential momentum remains available for the next rope mode.
    public mutating func contact(at point: WorldPoint, horizontal: Bool = false, vertical: Bool = false) {
        position = point
        if horizontal { velocity.x = 0 }
        if vertical { velocity.y = 0 }
    }
}

public struct RopeAnchor: Equatable, Sendable {
    public let windowID: UInt32
    public let edge: TerrainEdge
    public let offset: Double?
    public init(windowID: UInt32, edge: TerrainEdge, offset: Double? = nil) {
        self.windowID = windowID; self.edge = edge; self.offset = offset
    }
    public func resolve(in terrain: TerrainSnapshot) -> AbseilRope? {
        guard let window = terrain.windows.first(where: { $0.id == windowID }) else { return nil }
        if edge == .front, let offset {
            guard TerrainSupport.resolve(.init(owner: .window(windowID), edge: .front, offset: offset), in: terrain) != nil else { return nil }
            return .init(window: window.frame, frontOffset: offset)
        }
        guard edge == .left || edge == .right else { return nil }
        let pin = edge == .left ? AbseilRope.anchorInset : window.frame.width - AbseilRope.anchorInset
        guard TerrainSupport.resolve(.init(owner: .window(windowID), edge: .top, offset: pin), in: terrain) != nil,
              TerrainSupport.resolve(.init(owner: .window(windowID), edge: edge, offset: window.frame.height - EdgeTraversal.lipHeight), in: terrain) != nil else { return nil }
        return .init(window: window.frame, edge: edge)
    }
}

public struct RopeSession {
    public enum Mode: String, Sendable { case firing, swinging, climbing, descending, supported }
    public static let harnessHeight = 34.0
    public let anchor: RopeAnchor
    public private(set) var mode: Mode
    public private(set) var body: RopeDynamics
    public private(set) var age = 0.0
    public private(set) var pullTime = 0.0
    public let shotOrigin: WorldPoint
    private var previousAnchor: WorldPoint
    private var supportVelocity = WorldPoint.zero
    private var supportMotionAge = 1.0
    public var releaseVelocity: WorldPoint { .init(x: body.velocity.x + supportVelocity.x, y: body.velocity.y + supportVelocity.y) }
    private var takeUp = 0.0
    public var climbsAfterSwing = true
    public var modeAfterLatch: Mode?
    public var isTakingUp: Bool { takeUp > 0 }

    public init(anchor: RopeAnchor, guide: AbseilRope, feet: WorldPoint, mode: Mode, velocity: WorldPoint = .zero) {
        self.anchor = anchor; self.mode = mode
        let harness = WorldPoint(x: feet.x, y: feet.y + Self.harnessHeight)
        body = .init(position: harness, velocity: velocity, length: guide.length(to: harness))
        previousAnchor = guide.anchor
        shotOrigin = Self.muzzle(feet: feet, target: guide.anchor)
    }
    public static func muzzle(feet: WorldPoint, target: WorldPoint) -> WorldPoint {
        let facing = target.x >= feet.x ? 1.0 : -1.0
        let angle = atan2(target.y - feet.y - 46, abs(target.x - feet.x) - 8)
        return .init(x: feet.x + facing * (8 + 17 * cos(angle)), y: feet.y + 46 + 17 * sin(angle))
    }
    public var feet: WorldPoint { .init(x: body.position.x, y: body.position.y - Self.harnessHeight) }
    public var shotDuration: Double { min(0.65, max(0.25, hypot(previousAnchor.x - shotOrigin.x, previousAnchor.y - shotOrigin.y) / 850)) }
    public func hookPosition(guide: AbseilRope) -> WorldPoint {
        Self.hook(from: shotOrigin, to: guide.anchor, fraction: min(1, age / shotDuration))
    }
    public static func hook(from: WorldPoint, to: WorldPoint, fraction: Double) -> WorldPoint {
        let t = min(max(fraction, 0), 1), u = 1 - t
        let control = WorldPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 80)
        return .init(x: u*u*from.x + 2*u*t*control.x + t*t*to.x, y: u*u*from.y + 2*u*t*control.y + t*t*to.y)
    }
    public mutating func switchMode(_ mode: Mode) { self.mode = mode; age = 0; if mode != .swinging { takeUp = 0 } }
    public mutating func followSupport(_ guide: AbseilRope, sampleElapsed: Double = 0.1) {
        let shift = WorldPoint(x: guide.anchor.x - previousAnchor.x, y: guide.anchor.y - previousAnchor.y)
        if mode != .firing && mode != .supported {
            body.translate(by: shift)
            if hypot(shift.x, shift.y) > 0.00001 {
                let dt = max(1.0 / 120, sampleElapsed)
                supportVelocity = .init(x: shift.x / dt, y: shift.y / dt)
                let speed = hypot(supportVelocity.x, supportVelocity.y)
                if speed > 900 { supportVelocity.x *= 900 / speed; supportVelocity.y *= 900 / speed }
                supportMotionAge = 0
            }
        }
        previousAnchor = guide.anchor
    }
    public mutating func advance(by dt: Double, guide: AbseilRope, minimumLength: Double) {
        followSupport(guide)
        supportMotionAge += dt
        if supportMotionAge > 0.15 { supportVelocity = .zero }
        age += dt
        if mode == .firing {
            if age >= shotDuration {
                let feet = self.feet
                body = .init(position: .init(x: feet.x, y: feet.y + Self.harnessHeight), velocity: .init(x: 0, y: 140), length: guide.length(to: body.position))
                switchMode(modeAfterLatch ?? .swinging)
                let safeLength = max(minimumLength, guide.wrappedLength + guide.anchor.y - feet.y - Self.harnessHeight - 40)
                takeUp = mode == .descending ? 0 : max(24, body.length - safeLength)
            }
            return
        }
        guard mode != .supported else { return }
        var payOut = 0.0
        if takeUp > 0 {
            let part = min(dt * 120, takeUp); payOut -= part; takeUp -= part
            if takeUp <= 0 { age = 0 }
        } else if mode == .climbing {
            payOut -= ClimbingGait.distance(from: pullTime, to: pullTime + dt)
            pullTime += dt
        } else if mode == .descending { payOut += 48 * dt }
        payOut = max(minimumLength - body.length, payOut)
        body.advance(by: dt, guide: guide, payOut: payOut)
        if mode == .swinging && climbsAfterSwing && age > 3.0 && takeUp <= 0 { switchMode(.climbing) }
    }
    public mutating func pushOff(guide: AbseilRope) {
        let contact = guide.taut(toward: body.position).sideTangent
        let dx = body.position.x - contact.x, dy = body.position.y - contact.y
        let length = max(1, hypot(dx, dy))
        var tangent = WorldPoint(x: -dy / length, y: dx / length)
        let outward = anchor.edge == .left ? -1.0 : 1.0
        if tangent.x * outward < 0 { tangent.x *= -1; tangent.y *= -1 }
        let speed = body.velocity.x * tangent.x + body.velocity.y * tangent.y
        if abs(speed) < 40 { body.addImpulse(.init(x: tangent.x * 130, y: tangent.y * 130)) }
    }
    public mutating func addImpulse(_ impulse: WorldPoint) { body.addImpulse(impulse) }
    public mutating func contact(feet: WorldPoint, horizontal: Bool = false, vertical: Bool = false) {
        body.contact(at: .init(x: feet.x, y: feet.y + Self.harnessHeight), horizontal: horizontal, vertical: vertical)
    }
}
