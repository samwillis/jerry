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

    public init(position: Point, bounds: Bounds) {
        self.position = position
        self.bounds = bounds
        clampPosition()
    }

    public mutating func beginDrag(at pointer: Point) {
        grabOffset = Point(x: pointer.x - position.x, y: pointer.y - position.y)
        settlingRemaining = 0
        attachment = nil
        state = .held
    }

    public mutating func drag(to pointer: Point) {
        guard state == .held else { return }
        position = Point(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        clampPosition()
    }

    public mutating func endDrag(on terrain: TerrainSnapshot? = nil) {
        guard state == .held else { return }
        state = .settling
        settlingRemaining = 0.8
        if let terrain { updateTerrain(terrain) }
    }

    /// Called only while the expedition is running. Pausing preserves the settling interval.
    public mutating func advance(by elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        if state == .recovering {
            // Temporary controlled descent. Full falling/parachute motion belongs to stage five.
            position.y = max(bounds.minimum.y, position.y - 180 * elapsed)
            if position.y <= bounds.minimum.y {
                state = .settling
                settlingRemaining = 0.8
            }
            return
        }
        guard state == .settling else { return }
        settlingRemaining -= elapsed
        if settlingRemaining <= 0 { state = .idle }
    }

    public mutating func updateBounds(_ bounds: Bounds) {
        self.bounds = bounds
        attachment = nil
        // A changed display invalidates the pointer's coordinate space and any active drag.
        if state == .held { endDrag() }
        clampPosition()
    }

    public mutating func updateTerrain(_ terrain: TerrainSnapshot) {
        guard state != .held else { return }
        if let attachment {
            if let supported = TerrainSupport.resolve(attachment, in: terrain) {
                position = supported
                clampPosition()
                return
            }
            self.attachment = nil
            state = .recovering
            return
        }
        guard state != .recovering else { return }
        if let (anchor, supported) = TerrainSupport.attach(at: position, in: terrain) {
            attachment = anchor
            position = supported
            clampPosition()
        } else {
            state = .recovering
        }
    }

    private mutating func clampPosition() {
        position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
        position.y = min(max(position.y, bounds.minimum.y), bounds.maximum.y)
    }
}
