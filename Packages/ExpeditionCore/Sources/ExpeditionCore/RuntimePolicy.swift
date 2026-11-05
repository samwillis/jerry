/// Platform notifications feed this policy; an explicit user pause always survives wake/Space changes.
public struct RuntimePolicy {
    public var manuallyPaused = false
    public var sleeping = false
    public var desktopSupported = true
    public init() {}
    public var shouldRun: Bool { !manuallyPaused && !sleeping && desktopSupported }
    public var shouldPollTerrain: Bool { !manuallyPaused && !sleeping && desktopSupported }
    public var shouldShow: Bool { !sleeping && desktopSupported }
}
