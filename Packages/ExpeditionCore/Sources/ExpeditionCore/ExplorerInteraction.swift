import Foundation

/// Input state in scene coordinates. The supplied bounds constrain the character's origin.
public struct ExplorerInteraction {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
        public static let zero = Point(x: 0, y: 0)
    }

    public struct Bounds {
        public let minimum: Point
        public let maximum: Point
        public init(minimum: Point, maximum: Point) {
            self.minimum = minimum
            self.maximum = Point(x: max(minimum.x, maximum.x), y: max(minimum.y, maximum.y))
        }
    }

    public enum State: String { case idle, held, settling, recovering }
    public private(set) var position: Point
    public private(set) var state: State = .idle
    public private(set) var attachment: TerrainAttachment?
    private var bounds: Bounds
    private var grabOffset = Point.zero
    private var settlingRemaining: Double = 0
    private var terrain: TerrainSnapshot?
    private var recoveryTime: Double = 0
    private var lastDragTime: Double?
    private var dragVelocity = Point.zero
    private var flightVelocity = Point.zero

    public init(position: Point, bounds: Bounds) {
        self.position = position
        self.bounds = bounds
        clampPosition()
    }

    public mutating func beginDrag(at pointer: Point, time: Double? = nil) {
        grabOffset = Point(x: pointer.x - position.x, y: pointer.y - position.y)
        settlingRemaining = 0
        attachment = nil
        lastDragTime = time
        dragVelocity = .zero
        flightVelocity = .zero
        state = .held
    }

    public mutating func drag(to pointer: Point, time: Double? = nil) {
        guard state == .held else { return }
        let previous = position
        position = Point(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        clampPosition()
        if let time, time.isFinite {
            if let last = lastDragTime, time > last {
                let dt = time - last
                if dt > 0.15 {
                    dragVelocity = .zero
                } else {
                    let weight = 1 - exp(-dt / 0.035)
                    dragVelocity.x += ((position.x - previous.x) / dt - dragVelocity.x) * weight
                    dragVelocity.y += ((position.y - previous.y) / dt - dragVelocity.y) * weight
                    let speed = hypot(dragVelocity.x, dragVelocity.y)
                    if speed > 900 { dragVelocity.x *= 900 / speed; dragVelocity.y *= 900 / speed }
                }
            }
            lastDragTime = time
        }
    }

    public mutating func endDrag(on terrain: TerrainSnapshot? = nil) {
        guard state == .held else { return }
        if hypot(dragVelocity.x, dragVelocity.y) > 60 {
            if let terrain { self.terrain = terrain }
            recoveryTime = 0
            flightVelocity = dragVelocity
            state = .recovering
            return
        }
        state = .settling
        settlingRemaining = 0.8
        if let terrain { updateTerrain(terrain) }
    }

    /// Called only while the expedition is running. Pausing preserves the settling interval.
    public mutating func advance(by elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        if state == .recovering {
            var remaining = min(elapsed, 10)
            while remaining > 0.000001, state == .recovering {
                let dt = min(remaining, 1.0 / 120)
                remaining -= dt
                let distance = RecoveryAnimation.distance(from: recoveryTime, to: recoveryTime + dt)
                let drag = 1.2 + 5 * RecoveryAnimation.deployment(at: recoveryTime + dt / 2)
                let decay = exp(-drag * dt)
                var next = Point(x: position.x + flightVelocity.x * (1 - decay) / drag, y: position.y - distance + flightVelocity.y * (1 - decay) / drag)
                flightVelocity.x *= decay
                flightVelocity.y *= decay
                recoveryTime += dt
                if next.x < bounds.minimum.x || next.x > bounds.maximum.x { flightVelocity.x = 0 }
                if next.y > bounds.maximum.y { flightVelocity.y = min(0, flightVelocity.y) }
                next.x = min(max(next.x, bounds.minimum.x), bounds.maximum.x)
                next.y = min(max(next.y, bounds.minimum.y), bounds.maximum.y)
                if let terrain, let (anchor, landed) = TerrainSupport.landing(from: position, to: next, in: terrain) {
                    attachment = anchor
                    position = landed
                    settle()
                } else {
                    position = next
                    if position.y <= bounds.minimum.y { settle() }
                }
            }
            return
        }
        guard state == .settling else { return }
        settlingRemaining -= elapsed
        if settlingRemaining <= 0 { state = .idle }
    }

    public mutating func updateBounds(_ bounds: Bounds) {
        self.bounds = bounds
        terrain = nil
        attachment = nil
        dragVelocity = .zero
        flightVelocity = .zero
        // A changed display invalidates the pointer's coordinate space and any active drag.
        if state == .held { endDrag() }
        clampPosition()
    }

    public mutating func updateTerrain(_ terrain: TerrainSnapshot) {
        self.terrain = terrain
        guard state != .held else { return }
        if let attachment {
            if let supported = TerrainSupport.resolve(attachment, in: terrain) {
                position = supported
                clampPosition()
                return
            }
            self.attachment = nil
            recoveryTime = 0
            flightVelocity = .zero
            state = .recovering
            return
        }
        guard state != .recovering else { return }
        if let (anchor, supported) = TerrainSupport.attach(at: position, in: terrain) {
            attachment = anchor
            position = supported
            clampPosition()
        } else {
            recoveryTime = 0
            flightVelocity = .zero
            state = .recovering
        }
    }

    private mutating func clampPosition() {
        position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
        position.y = min(max(position.y, bounds.minimum.y), bounds.maximum.y)
    }

    private mutating func settle() {
        flightVelocity = .zero
        state = .settling
        settlingRemaining = 0.8
    }
}
