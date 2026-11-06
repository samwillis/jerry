import AppKit
import SpriteKit

@MainActor
private final class WelcomeExplorerScene: SKScene {
    private let explorer = ExplorerRig()
    private var previousTime: TimeInterval?
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        let floor = SKShapeNode(rect: .init(x: 5, y: 20, width: 110, height: 12), cornerRadius: 2)
        floor.fillColor = NotebookTheme.leather.withAlphaComponent(0.045); floor.strokeColor = .clear; floor.zPosition = -20; addChild(floor)
        let edge = CGMutablePath(); edge.move(to: .init(x: 5, y: 32)); edge.addLine(to: .init(x: 115, y: 32))
        let floorEdge = SKShapeNode(path: edge); floorEdge.strokeColor = NotebookTheme.leather.withAlphaComponent(0.3); floorEdge.lineWidth = 1; floorEdge.zPosition = -19; addChild(floorEdge)
        explorer.position = .init(x: 60, y: 32)
        explorer.setScale(1.35)
        addChild(explorer)
        // The illustrated ledge occludes the drop shadow just like a real window.
        explorer.setShadowOcclusion(windows: [.init(x: -100, y: -100, width: 320, height: 132)], from: self)
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }
    override func update(_ currentTime: TimeInterval) {
        explorer.render(delta: previousTime.map { min(0.1, max(0, currentTime - $0)) } ?? 0)
        previousTime = currentTime
    }
}

enum ExplorerControls {
    static let rows = [
        ["⌃⌥ Return", "Ask Jerry, from any app"], ["⌃⌥ Space", "Take or release control"],
        ["Arrows / WASD", "Move, climb or swing; Up grabs a hold"],
        ["Shift", "Run or climb faster"], ["Space", "Jump"], ["↓", "Step off an edge and parachute"],
        ["Hold G + arrows", "Aim the grappling hook; release G to fire"],
        ["Hold C", "Crouch"], ["Option + C", "Crouch and reach lower"],
        ["E", "Click at Jerry’s hand, including on ropes"],
        ["Return", "Ask Jerry"], ["Esc", "Return to your previous app"]
    ]
    static let groups: [(String, [[String]])] = [
        ("From any app", [rows[1], rows[0]]),
        ("Movement", [rows[2], rows[4], rows[3], rows[5], rows[7], rows[11]]),
        ("Tools & tasks", [rows[6], rows[8], rows[9], rows[10]])
    ]
}

/// A short, permission-free introduction. The full reference lives in Settings.
@MainActor
final class WelcomeController: NSWindowController, NSWindowDelegate {
    var onIdleChanged: ((Bool) -> Void)?
    var onTakeControl: (() -> Void)?
    var onSetupAI: (() -> Void)?
    var onClose: (() -> Void)?
    private let illustration = SKView()
    init() {
        let window = NotebookWindow(contentRect: .init(x: 0, y: 0, width: 560, height: 450), styleMask: [.borderless, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to The Other Sock"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self; window.center()
        let root = NotebookTheme.install(on: window, title: "Welcome")
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32), content.topAnchor.constraint(equalTo: root.topAnchor, constant: 18)])
        let header = NSStackView(); header.spacing = 20; header.alignment = .centerY
        illustration.allowsTransparency = true; illustration.preferredFramesPerSecond = 30; illustration.setAccessibilityElement(false)
        illustration.presentScene(WelcomeExplorerScene(size: .init(width: 120, height: 148)))
        illustration.widthAnchor.constraint(equalToConstant: 120).isActive = true; illustration.heightAnchor.constraint(equalToConstant: 148).isActive = true
        let intro = NSStackView(); intro.orientation = .vertical; intro.alignment = .leading; intro.spacing = 9
        intro.addArrangedSubview(text("Meet Jerry.", size: 30, weight: .semibold, serif: true))
        intro.addArrangedSubview(text("One small adventurer.\nOne missing sock.", size: 15))
        header.addArrangedSubview(illustration); header.addArrangedSubview(intro); content.addArrangedSubview(header)
        content.addArrangedSubview(text("He climbs your windows, parachutes between ledges and looks for patterned socks. Drag him aside whenever he’s in the way.", size: 13))
        let shortcuts = NSStackView(); shortcuts.orientation = .vertical; shortcuts.alignment = .leading; shortcuts.spacing = 9
        shortcuts.addArrangedSubview(text("⌃⌥ Space    Take the lead", size: 12, weight: .medium))
        shortcuts.addArrangedSubview(text("⌃⌥ Return   Give Jerry a task", size: 12, weight: .medium))
        let playHint = text("In control: arrows move · Space jumps · Esc returns.", size: 11); playHint.textColor = NotebookTheme.faded
        shortcuts.addArrangedSubview(playHint)
        content.addArrangedSubview(shortcuts)
        let note = text("No account needed to explore. AI and desktop clicks are optional.", size: 11); note.textColor = NotebookTheme.faded; content.addArrangedSubview(note)
        let actions = NSStackView(); actions.spacing = 10
        let setup = NSButton(title: "Set up AI…", target: self, action: #selector(setupAI)); setup.isBordered = false; setup.contentTintColor = NotebookTheme.faded
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let control = NSButton(title: "Try Controls", target: self, action: #selector(takeControl)); control.bezelStyle = .rounded
        let start = NSButton(title: "Start Exploring", target: self, action: #selector(startExploring)); start.bezelStyle = .rounded; start.keyEquivalent = "\r"
        NotebookTheme.style(control); NotebookTheme.style(start, primary: true)
        [setup, spacer, control, start].forEach { actions.addArrangedSubview($0) }
        content.addArrangedSubview(actions)
        for view in [header, shortcuts, actions] { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, serif: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = NotebookTheme.font(size, weight: weight, italic: serif)
        label.textColor = NotebookTheme.ink
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.preferredMaxLayoutWidth = 476
        return label
    }
    func open(idleExploration: Bool) { illustration.isPaused = false; NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    @objc private func startExploring() { onIdleChanged?(true); close() }
    @objc private func takeControl() { close(); onTakeControl?() }
    @objc private func setupAI() { close(); onSetupAI?() }
    func windowWillClose(_ notification: Notification) { illustration.isPaused = true; onClose?() }
}
