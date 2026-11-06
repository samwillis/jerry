import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
private final class RigLimb: SKNode {
    private let upperNode = SKNode()
    let lowerNode = SKNode()
    private let endNode = SKNode()
    private let outline = SKShapeNode()
    private let mask = SKShapeNode()
    private let cloth = SKCropNode()
    private let isFoot: Bool
    private let baseColor: NSColor
    private let width: CGFloat
    let upperLength: Double
    let lowerLength: Double

    init(upper: Double, lower: Double, color: NSColor, foot: Bool) {
        upperLength = upper; lowerLength = lower; isFoot = foot
        baseColor = color
        width = foot ? 6 : 5
        super.init()
        // One rounded, continuous cloth silhouette covers both bones, with no internal cap borders.
        outline.lineCap = .round
        outline.lineJoin = .round
        outline.fillColor = .clear
        addChild(outline)
        mask.lineCap = .round
        mask.lineJoin = .round
        mask.lineWidth = width
        mask.strokeColor = .white
        mask.fillColor = .clear
        cloth.maskNode = mask
        cloth.addChild(PaintedPart(rect: CGRect(x: -32, y: -36, width: 64, height: 72), radius: 0, color: color, material: .limbCloth))
        addChild(cloth)
        // Keep the articulated hierarchy for the hand/boot attachments.
        addChild(upperNode)
        upperNode.addChild(lowerNode)
        lowerNode.position.y = -upper
        lowerNode.addChild(endNode)
        endNode.position.y = -lower
        let end = PaintedPart(rect: CGRect(x: -3, y: foot ? -3 : -2, width: foot ? 10 : 6, height: 5), radius: 2, color: foot ? ExplorerPalette.boots : ExplorerPalette.skin, material: foot ? .leather : .skin)
        endNode.addChild(end)
        setPainted(true)
    }
    required init?(coder: NSCoder) { fatalError("Use init(upper:lower:color:foot:)") }

    func setPainted(_ painted: Bool) {
        outline.strokeColor = painted
            ? (baseColor.blended(withFraction: 0.6, of: .black) ?? baseColor).withAlphaComponent(0.9)
            : NSColor(calibratedWhite: 0.15, alpha: 1)
        outline.lineWidth = width + (painted ? 1.4 : 2)
    }

    func place(root: WorldPoint, solution: LimbSolution) {
        position = CGPoint(x: root.x, y: root.y)
        let a = atan2(solution.joint.y - root.y, solution.joint.x - root.x) + .pi / 2
        let b = atan2(solution.end.y - solution.joint.y, solution.end.x - solution.joint.x) + .pi / 2
        upperNode.zRotation = a
        lowerNode.zRotation = b - a
        if isFoot { endNode.zRotation = -b }
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: solution.joint.x - root.x, y: solution.joint.y - root.y))
        // Leave the rounded shin cap inside the boot rather than below its sole.
        path.addLine(to: CGPoint(x: solution.end.x - root.x, y: solution.end.y - root.y + (isFoot ? 1 : 0)))
        outline.path = path
        mask.path = path
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
    private let grappleGun = SKNode()
    private let canopyFabric = SKNode()
    private var cords: [(SKShapeNode, CGFloat)] = []
    private let leftEye = SKShapeNode(rect: CGRect(x: -1, y: -1.5, width: 2, height: 3))
    private let rightEye = SKShapeNode(rect: CGRect(x: -1, y: -1.5, width: 2, height: 3))
    private let leftArm = RigLimb(upper: 12, lower: 12, color: ExplorerPalette.jacket, foot: false)
    private let rightArm = RigLimb(upper: 12, lower: 12, color: ExplorerPalette.farSleeve, foot: false)
    private let leftLeg = RigLimb(upper: ExpeditionConfiguration.legSegmentLength, lower: ExpeditionConfiguration.legSegmentLength, color: ExplorerPalette.trousers, foot: true)
    private let rightLeg = RigLimb(upper: ExpeditionConfiguration.legSegmentLength, lower: ExpeditionConfiguration.legSegmentLength, color: ExplorerPalette.trousers, foot: true)
    private var animator = RigAnimator()
    private var expressionTime: Double = 0
    private var pointerEyeOffset = CGPoint.zero
    private var pointerHeadTurn = 0.0
    private var landingTime: Double?
    private var landingStrength: Double = 1
    private var presentedPose = ExplorerPose()
    private var ropeBlendFrom = ExplorerPose()
    private var ropeBlendTime: Double = 1
    private var harnessWasUsed = false
    var synchronizedTime: Double?
    var ropePose: ExplorerPose?
    var jumpPose: ExplorerPose?
    var grappleAim: WorldPoint?
    var usesHarnessPivot = false
    var handTargets: (WorldPoint, WorldPoint)?
    var footTargets: (WorldPoint, WorldPoint)?
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
        body.addChild(grappleGun)
        buildGrappleGun()
        body.addChild(canopy)
        canopy.zPosition = -4
        body.addChild(joints)
        joints.zPosition = 10
        rectangle(CGRect(x: -4, y: 20, width: 8, height: 8), color: ExplorerPalette.skin, parent: torso, material: .skin)
        rectangle(CGRect(x: -12, y: -1, width: 24, height: 23), color: ExplorerPalette.jacket, parent: torso)
        rectangle(CGRect(x: -4, y: -10, width: 14, height: 26), color: ExplorerPalette.bag, parent: backpack, material: .canvas)
        rectangle(CGRect(x: -10, y: -7, width: 20, height: 17), color: ExplorerPalette.skin, parent: head, radius: 6, material: .skin)
        rectangle(CGRect(x: -12, y: 7, width: 24, height: 8), color: ExplorerPalette.hat, parent: head, material: .felt)
        rectangle(CGRect(x: -16, y: 6, width: 32, height: 3), color: ExplorerPalette.hat, parent: head, radius: 1, material: .felt)
        for (eye, x) in [(leftEye, -1.0), (rightEye, 6.0)] {
            eye.position = CGPoint(x: x, y: 3.5)
            eye.fillColor = .black
            eye.strokeColor = NSColor(calibratedWhite: 0.15, alpha: 1)
            eye.lineWidth = 1
            head.addChild(eye)
        }
        buildParachute()
        setPainted(true)
        render(delta: 0)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func rectangle(_ rect: CGRect, color: NSColor, parent: SKNode, radius: CGFloat = 3, material: ExplorerMaterial = .cloth) {
        parent.addChild(PaintedPart(rect: rect, radius: radius, color: color, material: material))
    }

    func setPainted(_ painted: Bool) {
        func update(_ node: SKNode) {
            (node as? PaintedPart)?.setPainted(painted)
            (node as? RigLimb)?.setPainted(painted)
            for child in node.children { update(child) }
        }
        update(body)
        for eye in [leftEye, rightEye] {
            eye.fillColor = painted ? NSColor(calibratedRed: 0.19, green: 0.13, blue: 0.1, alpha: 1) : .black
            eye.strokeColor = eye.fillColor
            eye.lineWidth = painted ? 0.4 : 1
        }
    }

    private func buildGrappleGun() {
        func part(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 1) {
            let shape = SKShapeNode(rect: rect, cornerRadius: radius)
            shape.fillColor = color; shape.strokeColor = NSColor(calibratedWhite: 0.12, alpha: 1); shape.lineWidth = 0.7
            grappleGun.addChild(shape)
        }
        part(.init(x: -4, y: -4, width: 13, height: 8), NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.37, alpha: 1), radius: 2)
        part(.init(x: 7, y: -2, width: 10, height: 4), .lightGray)
        part(.init(x: -2, y: -9, width: 4, height: 6), ExplorerPalette.bag)
        let spool = SKShapeNode(circleOfRadius: 3)
        spool.fillColor = ExplorerPalette.jacket; spool.strokeColor = .darkGray; spool.lineWidth = 0.7
        spool.position = .init(x: 2, y: 0); grappleGun.addChild(spool)
        grappleGun.zPosition = 4
    }

    func grappleMuzzle(in node: SKNode) -> CGPoint { grappleGun.convert(.init(x: 17, y: 0), to: node) }

    private func buildParachute() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -34, y: 105))
        path.addQuadCurve(to: CGPoint(x: 34, y: 105), control: CGPoint(x: 0, y: 155))
        path.addQuadCurve(to: CGPoint(x: -34, y: 105), control: CGPoint(x: 0, y: 98))
        let fabric = PaintedPart(path: path, color: NSColor(calibratedRed: 0.93, green: 0.72, blue: 0.22, alpha: 1), material: .canopy, tag: "parachute")
        canopy.addChild(canopyFabric)
        canopyFabric.addChild(fabric)
        for x: CGFloat in [-34, -12, 12, 34] {
            let line = SKShapeNode()
            line.strokeColor = .lightGray
            line.lineWidth = 0.7
            line.zPosition = -1
            canopy.addChild(line)
            cords.append((line, x))
        }
    }

    private func renderParachute(pose: ExplorerPose) {
        canopy.isHidden = motion != .parachuting || animationTime < RecoveryAnimation.deploymentStart
        guard !canopy.isHidden else { return }
        let opening = RecoveryAnimation.deployment(at: animationTime)
        canopyFabric.xScale = 0.05 + 0.95 * opening
        canopyFabric.yScale = 0.025 + 0.975 * opening
        canopyFabric.zRotation = -0.3 * (1 - opening)
        canopyFabric.position = CGPoint(
            x: backpack.position.x * (1 - opening) - sin(.pi * opening) * 5,
            y: backpack.position.y * (1 - opening) + 105 * opening - 105 * canopyFabric.yScale
        )
        for (line, x) in cords {
            let edgeY = 101.5 + 14 * x * x / (68 * 68)
            let path = CGMutablePath()
            path.move(to: canopyFabric.convert(CGPoint(x: x, y: edgeY), to: canopy))
            let hand = x < 0 ? pose.leftHand : pose.rightHand
            path.addLine(to: CGPoint(x: hand.x, y: hand.y))
            line.path = path
            line.alpha = max(0, (opening - 0.2) / 0.8)
        }
    }

    func select(_ motion: ExplorerMotion, restart: Bool = false) {
        if restart { expressionTime = 0 }
        if restart || ![ExplorerMotion.idle, .investigating, .landing].contains(motion) { landingTime = nil }
        if motion != animator.motion { ropeBlendFrom = presentedPose; ropeBlendTime = 0 }
        animator.select(motion, restart: restart, from: presentedPose)
    }

    func land(strength: Double = 1) {
        landingTime = 0
        landingStrength = strength
    }

    func seek(to time: Double) {
        animator.seek(to: time)
        expressionTime = animator.time
        landingTime = nil
        render(delta: 0)
    }

    func render(delta: Double) {
        var pose = animator.advance(by: delta, synchronizedTime: synchronizedTime)
        ropeBlendTime += delta.isFinite ? min(max(delta, 0), 0.1) : 0
        if let ropePose {
            let t = min(1, ropeBlendTime / 0.15)
            pose = ropePose.blended(from: ropeBlendFrom, fraction: t * t * (3 - 2 * t))
        }
        if let jumpPose {
            let t = min(1, ropeBlendTime / 0.04)
            pose = jumpPose.blended(from: ropeBlendFrom, fraction: t * t * (3 - 2 * t))
        }
        grappleGun.isHidden = motion != .grappling && grappleAim == nil
        if motion == .grappling || grappleAim != nil {
            let aim = grappleAim ?? .init(x: 80, y: 130)
            let angle = atan2(aim.y - 46, aim.x - 8)
            grappleGun.position = .init(x: 8, y: 46); grappleGun.zRotation = angle
            func hand(_ x: Double, _ y: Double) -> WorldPoint {
                .init(x: 8 + cos(angle) * x - sin(angle) * y, y: 46 + sin(angle) * x + cos(angle) * y)
            }
            pose.leftHand = hand(4, -3); pose.rightHand = hand(-3, -4)
            pose.headTilt = min(0.15, max(-0.15, angle * 0.12))
        }
        let elapsed = delta.isFinite ? min(max(delta, 0), 0.1) : 0
        expressionTime += elapsed
        if let time = landingTime {
            let next = time + elapsed
            landingTime = next < LandingAnimation.duration ? next : nil
            pose = LandingAnimation.apply(to: pose, elapsed: next, strength: landingStrength)
        }
        if let handTargets { pose.leftHand = handTargets.0; pose.rightHand = handTargets.1 }
        if let footTargets { pose.leftFoot = footTargets.0; pose.rightFoot = footTargets.1 }
        let held = motion == .held || (motion == .comic && animationTime.truncatingRemainder(dividingBy: 9) >= 5)
        harnessWasUsed = usesHarnessPivot || (harnessWasUsed && abs(pose.sway) > 0.001 && !held)
        let origin = held ? grabPoint : CGPoint(x: 0, y: harnessWasUsed ? RopeSession.harnessHeight : 60)
        presentedPose = pose
        pivot.position = origin
        pivot.zRotation = pose.sway
        body.position = CGPoint(x: -origin.x, y: -origin.y)
        torso.position = CGPoint(x: pose.hips.x, y: pose.hips.y)
        head.position = CGPoint(x: pose.hips.x, y: pose.hips.y + ExpeditionConfiguration.headOffset)
        head.zRotation = pose.headTilt
        updatePointerAttention(elapsed: elapsed)
        backpack.position = CGPoint(x: pose.hips.x - 18, y: pose.hips.y + 10)
        backpack.zRotation = pose.backpackTilt
        renderParachute(pose: pose)
        joints.removeAllChildren()
        joints.isHidden = !showsJoints
        clampedContacts = 0
        place(leftArm, root: .init(x: pose.hips.x - 10, y: pose.hips.y + 20), target: pose.leftHand, knee: false, elbowPole: pose.elbowPole, elbowBend: pose.leftElbowBend)
        place(rightArm, root: .init(x: pose.hips.x + 10, y: pose.hips.y + 20), target: pose.rightHand, knee: false, elbowPole: pose.elbowPole, elbowBend: pose.rightElbowBend)
        place(leftLeg, root: .init(x: pose.hips.x - 7, y: pose.hips.y), target: pose.leftFoot, knee: true)
        place(rightLeg, root: .init(x: pose.hips.x + 7, y: pose.hips.y), target: pose.rightFoot, knee: true)
    }

    /// Sample the current pointer, without capturing mouse events or keyboard focus.
    /// Convert through the actual node transforms so mirroring, rope sway, and the
    /// playground's enlarged rig all keep the eyes aimed in the right direction.
    private func updatePointerAttention(elapsed: Double) {
        var desiredEyes = CGPoint.zero
        var desiredTurn = 0.0
        let pointer = NSEvent.mouseLocation
        if let scene, let view = scene.view, let window = view.window,
           window.isVisible, window.screen?.frame.contains(pointer) == true {
            let inWindow = window.convertPoint(fromScreen: pointer)
            let inView = view.convert(inWindow, from: nil)
            let inScene = scene.convertPoint(fromView: inView)
            let relative = head.convert(inScene, from: scene)
            let dx = relative.x - 2.5, dy = relative.y - 3.5
            let distance = hypot(dx, dy)
            // Fully engaged close by, with a soft boundary instead of a sudden snap.
            let fade = min(1, max(0, (220 - distance) / 100))
            let attention = fade * fade * (3 - 2 * fade)
            let taskWeight = motion == .grappling ? 0.3 : 1.0
            let weight = attention * taskWeight
            desiredEyes = .init(x: min(1, max(-1, dx / 55)) * 2.2 * weight,
                                y: min(1, max(-1, dy / 55)) * 1.3 * weight)
            desiredTurn = min(1, max(-1, dy / (abs(dx) + 30))) * (dx < 0 ? -1 : 1) * 0.12 * weight
        }
        // Eyes lead the head slightly; both ease back to their animated neutral pose.
        let eyeResponse = 1 - exp(-elapsed / 0.09)
        let headResponse = 1 - exp(-elapsed / 0.22)
        pointerEyeOffset.x += (desiredEyes.x - pointerEyeOffset.x) * eyeResponse
        pointerEyeOffset.y += (desiredEyes.y - pointerEyeOffset.y) * eyeResponse
        pointerHeadTurn += (desiredTurn - pointerHeadTurn) * headResponse
        head.zRotation += pointerHeadTurn
        head.position.x += pointerEyeOffset.x * 0.35
        for (index, eye) in [leftEye, rightEye].enumerated() {
            let openness = BlinkAnimation.openness(time: expressionTime, eye: index)
            eye.yScale = openness
            eye.position = .init(x: (index == 0 ? -1.0 : 6.0) + pointerEyeOffset.x,
                                 y: 2 + (1.5 + pointerEyeOffset.y) * openness)
        }
    }

    private func place(_ limb: RigLimb, root: WorldPoint, target: WorldPoint, knee: Bool, elbowPole: WorldPoint = .init(x: -24, y: -6), elbowBend: Double? = nil) {
        // Toe direction is +x. Mirroring the whole rig flips feet and poles together.
        let pole = WorldPoint(x: root.x + (knee ? 24 : elbowPole.x), y: root.y + (knee ? -6 : elbowPole.y))
        // Foot targets mark the sole; the shin ends at an ankle three points inside the boot.
        let jointTarget = WorldPoint(x: target.x, y: target.y + (knee ? ExpeditionConfiguration.ankleHeight : 0))
        let solution = TwoBoneIK.solve(root: root, target: jointTarget, upper: limb.upperLength, lower: limb.lowerLength, bend: elbowBend ?? 1, pole: knee || elbowBend != nil ? nil : pole)
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
