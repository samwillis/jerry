import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
private final class RigLimb: SKNode {
    let lowerNode = SKNode()
    private let endNode = SKNode()
    private let isFoot: Bool
    let upperLength: Double
    let lowerLength: Double

    init(upper: Double, lower: Double, color: NSColor, foot: Bool) {
        upperLength = upper; lowerLength = lower; isFoot = foot
        super.init()
        let width: CGFloat = foot ? 6 : 5
        addChild(Self.segment(length: upper, width: width, color: color))
        lowerNode.position.y = -upper
        addChild(lowerNode)
        lowerNode.addChild(Self.segment(length: lower, width: width, color: color))
        endNode.position.y = -lower
        lowerNode.addChild(endNode)
        let end = SKShapeNode(rect: CGRect(x: -3, y: foot ? -3 : -2, width: foot ? 10 : 6, height: 5), cornerRadius: 2)
        end.fillColor = foot ? .brown : NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.54, alpha: 1)
        end.strokeColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        end.lineWidth = 1
        endNode.addChild(end)
    }
    required init?(coder: NSCoder) { fatalError("Use init(upper:lower:color:foot:)") }

    private static func segment(length: Double, width: CGFloat, color: NSColor) -> SKShapeNode {
        let shape = SKShapeNode(rect: CGRect(x: -width / 2, y: -length, width: width, height: length + 2), cornerRadius: width / 2)
        shape.fillColor = color
        shape.strokeColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        shape.lineWidth = 1
        return shape
    }

    func place(root: WorldPoint, solution: LimbSolution) {
        position = CGPoint(x: root.x, y: root.y)
        let a = atan2(solution.joint.y - root.y, solution.joint.x - root.x) + .pi / 2
        let b = atan2(solution.end.y - solution.joint.y, solution.end.x - solution.joint.x) + .pi / 2
        zRotation = a
        lowerNode.zRotation = b - a
        if isFoot { endNode.zRotation = -b }
    }
}

/// Shared by the desktop and playground. Visual offsets never change the simulation origin.
@MainActor
final class ExplorerRig: SKNode {
    private let pivot = SKNode()
    private let body = SKNode()
    private let torso = SKNode()
    private let head = SKNode()
    private let backpack = SKNode()
    private let joints = SKNode()
    private let canopy = SKNode()
    private let leftArm = RigLimb(upper: 12, lower: 12, color: .systemOrange, foot: false)
    private let rightArm = RigLimb(upper: 12, lower: 12, color: NSColor(calibratedRed: 0.78, green: 0.38, blue: 0.06, alpha: 1), foot: false)
    private let leftLeg = RigLimb(upper: 15, lower: 15, color: .darkGray, foot: true)
    private let rightLeg = RigLimb(upper: 15, lower: 15, color: .darkGray, foot: true)
    private var animator = RigAnimator()
    var handTargets: (WorldPoint, WorldPoint)?
    var grabPoint = CGPoint(x: 0, y: 64)
    var showsJoints = false
    var tuning: AnimationTuning {
        get { animator.tuning }
        set { animator.tuning = newValue }
    }
    var motion: ExplorerMotion { animator.motion }
    var animationTime: Double { animator.time }
    private(set) var clampedContacts = 0

    override init() {
        super.init()
        addChild(pivot)
        pivot.addChild(body)
        body.addChild(backpack)
        // Canonical left limbs are nearest the camera; mirror the entire stack when facing left.
        body.addChild(rightLeg)
        body.addChild(leftLeg)
        body.addChild(rightArm)
        body.addChild(torso)
        body.addChild(head)
        body.addChild(leftArm)
        body.addChild(canopy)
        body.addChild(joints)
        joints.zPosition = 10
        rectangle(CGRect(x: -4, y: 20, width: 8, height: 8), color: NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.54, alpha: 1), parent: torso)
        rectangle(CGRect(x: -12, y: -1, width: 24, height: 23), color: .systemOrange, parent: torso)
        rectangle(CGRect(x: -4, y: -10, width: 14, height: 26), color: .systemBrown, parent: backpack)
        let skin = NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.54, alpha: 1)
        rectangle(CGRect(x: -10, y: -7, width: 20, height: 17), color: skin, parent: head, radius: 6)
        rectangle(CGRect(x: 8, y: -5, width: 6, height: 5), color: skin, parent: head, radius: 2)
        rectangle(CGRect(x: -12, y: 7, width: 24, height: 8), color: .systemTeal, parent: head)
        rectangle(CGRect(x: -16, y: 6, width: 32, height: 3), color: .systemTeal, parent: head, radius: 1)
        rectangle(CGRect(x: -2, y: 2, width: 2, height: 3), color: .black, parent: head, radius: 0)
        rectangle(CGRect(x: 5, y: 2, width: 2, height: 3), color: .black, parent: head, radius: 0)
        buildParachute()
        render(delta: 0)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func rectangle(_ rect: CGRect, color: NSColor, parent: SKNode, radius: CGFloat = 3) {
        let shape = SKShapeNode(rect: rect, cornerRadius: radius)
        shape.fillColor = color
        shape.strokeColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        shape.lineWidth = 1
        parent.addChild(shape)
    }

    private func buildParachute() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -34, y: 105))
        path.addQuadCurve(to: CGPoint(x: 34, y: 105), control: CGPoint(x: 0, y: 155))
        path.addQuadCurve(to: CGPoint(x: -34, y: 105), control: CGPoint(x: 0, y: 98))
        let fabric = SKShapeNode(path: path)
        fabric.fillColor = .systemYellow
        fabric.strokeColor = .darkGray
        fabric.lineWidth = 1
        canopy.addChild(fabric)
        for x: CGFloat in [-34, 0, 34] {
            let cord = CGMutablePath()
            cord.move(to: CGPoint(x: x, y: 105))
            cord.addLine(to: CGPoint(x: x < 0 ? -17 : 17, y: 66))
            let line = SKShapeNode(path: cord)
            line.strokeColor = .lightGray
            line.lineWidth = 0.7
            canopy.addChild(line)
        }
    }

    func select(_ motion: ExplorerMotion, restart: Bool = false) { animator.select(motion, restart: restart) }

    func render(delta: Double) {
        var pose = animator.advance(by: delta)
        if let handTargets { pose.leftHand = handTargets.0; pose.rightHand = handTargets.1 }
        let held = motion == .held || (motion == .comic && animationTime.truncatingRemainder(dividingBy: 9) >= 5)
        let origin = held ? grabPoint : CGPoint(x: 0, y: 60)
        pivot.position = origin
        pivot.zRotation = pose.sway
        body.position = CGPoint(x: -origin.x, y: -origin.y)
        torso.position = CGPoint(x: pose.hips.x, y: pose.hips.y)
        head.position = CGPoint(x: pose.hips.x, y: pose.hips.y + 32)
        head.zRotation = pose.headTilt
        backpack.position = CGPoint(x: pose.hips.x - 18, y: pose.hips.y + 10)
        backpack.zRotation = pose.backpackTilt
        canopy.isHidden = motion != .parachuting || animationTime < 0.45
        canopy.alpha = min(max((animationTime - 0.45) * 3, 0), 1)
        joints.removeAllChildren()
        joints.isHidden = !showsJoints
        clampedContacts = 0
        place(leftArm, root: .init(x: pose.hips.x - 10, y: pose.hips.y + 20), target: pose.leftHand, knee: false)
        place(rightArm, root: .init(x: pose.hips.x + 10, y: pose.hips.y + 20), target: pose.rightHand, knee: false)
        place(leftLeg, root: .init(x: pose.hips.x - 7, y: pose.hips.y), target: pose.leftFoot, knee: true)
        place(rightLeg, root: .init(x: pose.hips.x + 7, y: pose.hips.y), target: pose.rightFoot, knee: true)
    }

    private func place(_ limb: RigLimb, root: WorldPoint, target: WorldPoint, knee: Bool) {
        // Toe direction is +x. Mirroring the whole rig flips feet and poles together.
        let pole = WorldPoint(x: root.x + (knee ? 24 : -24), y: root.y - 6)
        // Foot targets mark the sole; the shin ends at an ankle three points inside the boot.
        let jointTarget = WorldPoint(x: target.x, y: target.y + (knee ? 3 : 0))
        let solution = TwoBoneIK.solve(root: root, target: jointTarget, upper: limb.upperLength, lower: limb.lowerLength, pole: pole)
        limb.place(root: root, solution: solution)
        if solution.isClamped { clampedContacts += 1 }
        guard showsJoints else { return }
        for point in [root, solution.joint, solution.end] {
            let dot = SKShapeNode(circleOfRadius: 1.6)
            dot.fillColor = .systemCyan
            dot.strokeColor = .clear
            dot.position = CGPoint(x: point.x, y: point.y)
            joints.addChild(dot)
        }
        let contact = SKShapeNode(circleOfRadius: 2.5)
        contact.position = CGPoint(x: target.x, y: target.y)
        contact.strokeColor = solution.isClamped ? .systemRed : .systemGreen
        contact.lineWidth = 0.8
        joints.addChild(contact)
    }
}
