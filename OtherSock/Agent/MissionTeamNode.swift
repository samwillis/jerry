import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class MissionTeamNode: SKNode {
    private struct Companion {
        let rig: ExplorerRig
        let label: SKLabelNode
        var body: ExplorerInteraction
        var reading = 0.0
        var leaving = false
        var exitTime = 0.0
    }
    private var team = TeamMission()
    private var companions: [ExpeditionMember: Companion] = [:]
    private let flags = SKNode()
    private let invitation = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
    private var leaderReading = 0.0
    private var invitationTime = 0.0
    private var lastStatus = ""
    private var usable = CGRect.zero
    private var terrain: TerrainSnapshot?
    var onStatus: ((String) -> Void)?
    var onHitAreas: (([String: CGRect]) -> Void)?
    var leaderUsesBinoculars = false
    #if DEBUG
    var debugVisibleMembers: Int { 1 + companions.count }
    var debugMissionComplete: Bool { team.isComplete }
    #endif
    var isInviting: Bool { invitationTime > 0 }
    override init() {
        super.init(); addChild(flags); addChild(invitation)
        invitation.fontSize = 12; invitation.fontColor = .labelColor; invitation.zPosition = 200; invitation.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func updateTerrain(_ terrain: TerrainSnapshot?, usable: CGRect) {
        self.terrain = terrain; self.usable = usable
        for member in companions.keys { companions[member]?.body.updateTerrain(terrain ?? fallbackTerrain()) }
    }
    private func fallbackTerrain() -> TerrainSnapshot { .init(windows: [], viewport: .init(x: usable.minX, y: usable.minY + 2, width: usable.width, height: usable.height - 2)) }
    func start(_ plan: SurveyPlan) throws {
        try team.start(plan); leaderReading = 0; leaderUsesBinoculars = false
        invitationTime = team.members.count > 1 ? 1.8 : 0
        rebuildFlags(plan)
        reconcile()
        report("Survey planned: \(plan.jobs.count) jobs, \(team.members.count) explorer\(team.members.count == 1 ? "" : "s"). Friends arrive only for independent work.")
    }
    func stop() {
        team.stop(); leaderReading = 0; leaderUsesBinoculars = false; invitationTime = 0
        flags.removeAllChildren(); reconcile(); report("Stopped. Friends are heading home; the explorer stays.")
    }
    private func rebuildFlags(_ plan: SurveyPlan) {
        flags.removeAllChildren()
        for job in plan.jobs {
            let x = targetX(job.marker)
            let flag = SKShapeNode(rect: .init(x: 0, y: 0, width: 18, height: 12), cornerRadius: 2)
            flag.fillColor = job.marker == "blue" ? .systemBlue : (job.marker == "amber" ? .systemOrange : .systemPurple)
            flag.strokeColor = .white; flag.lineWidth = 0.8
            let pole = SKShapeNode(rect: .init(x: -1, y: -15, width: 2, height: 28)); pole.fillColor = .darkGray; pole.strokeColor = .clear
            flag.addChild(pole); flag.position = .init(x: x, y: usable.minY + 17); flags.addChild(flag)
        }
    }
    private func targetX(_ marker: String) -> Double {
        let fraction = marker == "blue" ? 0.25 : (marker == "amber" ? 0.5 : 0.75)
        return usable.minX + usable.width * fraction
    }
    private func reconcile() {
        for member in [ExpeditionMember.scout, .rigger] {
            if team.assignments[member] != nil {
                if companions[member] != nil { companions[member]?.leaving = false; continue }
                let x = member == .scout ? usable.minX + 24 : usable.maxX - 24
                var body = ExplorerInteraction(position: .init(x: x, y: usable.minY + 2), bounds: .init(minimum: .init(x: usable.minX + 24, y: usable.minY + 2), maximum: .init(x: usable.maxX - 24, y: usable.maxY - 76)))
                body.autonomous = true; body.setIdleExploration(false); body.updateTerrain(terrain ?? fallbackTerrain()); body.setKeyboardControl(true)
                let rig = ExplorerRig(); addChild(rig)
                let label = SKLabelNode(fontNamed: "HelveticaNeue-Medium"); label.fontSize = 10; label.fontColor = .labelColor; addChild(label)
                companions[member] = .init(rig: rig, label: label, body: body)
            } else if companions[member] != nil { companions[member]?.leaving = true; companions[member]?.reading = 0 }
        }
    }
    func advance(by elapsed: Double, leader: WorldPoint, leaderReady: Bool) {
        let dt = min(0.1, max(0, elapsed))
        invitationTime = max(0, invitationTime - dt)
        invitation.isHidden = invitationTime <= 0
        invitation.text = "Could use a hand!"; invitation.position = .init(x: leader.x, y: leader.y + 92)
        leaderUsesBinoculars = team.assignments[.leader] != nil && leaderReady
        if let marker = team.assignments[.leader], leaderReady {
            leaderReading += dt
            if leaderReading >= 1.8 {
                try? team.complete(marker, by: .leader, generation: team.generation)
                leaderReading = 0; reconcile()
            }
        }
        var hits: [String: CGRect] = [:]
        for member in Array(companions.keys) {
            guard var actor = companions[member] else { continue }
            let target = actor.leaving ? (member == .scout ? usable.minX + 24 : usable.maxX - 24) : targetX(team.assignments[member] ?? "amber")
            let onFloor = actor.body.attachment?.edge == .floor
            if actor.body.state != .held {
                if onFloor && !actor.body.keyboardControlEnabled { actor.body.setKeyboardControl(true) }
                if actor.body.keyboardControlEnabled {
                    // An elevated drop finishes with the same physical launch and chute
                    // as the main explorer. No job completes while held or airborne.
                    actor.body.setControlDirection(horizontal: onFloor && abs(target - actor.body.position.x) > 3 ? (target > actor.body.position.x ? 1 : -1) : 0, vertical: onFloor ? 0 : -1)
                }
                actor.body.advance(by: dt)
            }
            let arrived = onFloor && abs(target - actor.body.position.x) <= 3 && actor.body.state != .held
            actor.rig.usingBinoculars = arrived && !actor.leaving
            if arrived && !actor.leaving, let marker = team.assignments[member] {
                actor.reading += dt
                if actor.reading >= 1.8 {
                    try? team.complete(marker, by: member, generation: team.generation)
                    actor.reading = 0
                }
            }
            if arrived && actor.leaving { actor.exitTime += dt }
            actor.rig.alpha = actor.leaving ? max(0, 1 - actor.exitTime / 0.6) : 1
            var point = actor.body.position
            if actor.leaving && arrived { point.x += (member == .scout ? -1 : 1) * actor.exitTime * 90 }
            actor.rig.position = .init(x: point.x, y: point.y); actor.rig.xScale = actor.body.facing
            let motion: ExplorerMotion = actor.body.state == .held ? .held : (actor.body.state == .recovering ? .parachuting : (actor.body.state == .dropping ? .launching : (actor.body.state == .walking ? .walking : .idle)))
            actor.rig.select(motion); actor.rig.jumpPose = actor.body.dropPose
            actor.rig.synchronizedTime = motion == .walking ? actor.body.walkingTime : (motion == .parachuting ? actor.body.recoveryElapsed : nil)
            actor.rig.render(delta: dt)
            actor.label.text = member.title + (actor.leaving ? " · heading home" : (actor.rig.usingBinoculars ? " · inspecting" : " · on my way"))
            actor.label.position = .init(x: point.x, y: point.y + 82); actor.label.alpha = actor.rig.alpha
            if actor.exitTime >= 0.6 {
                actor.rig.removeFromParent(); actor.label.removeFromParent(); companions[member] = nil
            } else {
                companions[member] = actor
                hits[member.rawValue] = .init(x: point.x - 24, y: point.y - 1, width: 48, height: 76)
            }
        }
        reconcile(); onHitAreas?(hits)
        if team.isComplete { report("Survey complete. Friends are heading home; the explorer stays.") }
        else if let plan = team.plan {
            let jobs = team.assignments.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.title): \($0.value)" }.joined(separator: " · ")
            report("\(team.completed.count)/\(plan.jobs.count) inspected · \(jobs)")
        }
    }
    private func report(_ value: String) { if lastStatus != value { lastStatus = value; onStatus?(value) } }
    func beginDrag(_ member: String, at point: CGPoint) {
        guard let id = ExpeditionMember(rawValue: member) else { return }
        if let position = companions[id]?.body.position {
            companions[id]?.rig.grabPoint = .init(x: point.x - position.x, y: point.y - position.y)
        }
        companions[id]?.body.setKeyboardControl(false)
        companions[id]?.body.beginDrag(at: .init(x: point.x, y: point.y), time: ProcessInfo.processInfo.systemUptime)
    }
    func drag(_ member: String, to point: CGPoint) {
        guard let id = ExpeditionMember(rawValue: member) else { return }
        companions[id]?.body.drag(to: .init(x: point.x, y: point.y), time: ProcessInfo.processInfo.systemUptime)
    }
    func endDrag(_ member: String) {
        guard let id = ExpeditionMember(rawValue: member) else { return }
        companions[id]?.body.endDrag(on: terrain)
    }
}
