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

    public enum State: String { case idle, held, settling }
    public private(set) var position: Point
    public private(set) var state: State = .idle
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
        state = .held
    }

    public mutating func drag(to pointer: Point) {
        guard state == .held else { return }
        position = Point(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        clampPosition()
    }

    public mutating func endDrag() {
        guard state == .held else { return }
        state = .settling
        settlingRemaining = 0.8
    }

    /// Called only while the expedition is running. Pausing preserves the settling interval.
    public mutating func advance(by elapsed: Double) {
        guard state == .settling, elapsed.isFinite, elapsed > 0 else { return }
        settlingRemaining -= elapsed
        if settlingRemaining <= 0 { state = .idle }
    }

    public mutating func updateBounds(_ bounds: Bounds) {
        self.bounds = bounds
        // A changed display invalidates the pointer's coordinate space and any active drag.
        if state == .held { endDrag() }
        clampPosition()
    }

    private mutating func clampPosition() {
        position.x = min(max(position.x, bounds.minimum.x), bounds.maximum.x)
        position.y = min(max(position.y, bounds.minimum.y), bounds.maximum.y)
    }
}
