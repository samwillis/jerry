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
    @MainActor static var rows: [[String]] { [
        [GlobalShortcutAction.ask.display, "Ask Jerry, from any app"], [GlobalShortcutAction.control.display, "Take or release control"],
        ["Arrows / WASD", "Move, climb or swing; Up grabs a hold"],
        ["Shift", "Run or climb faster"], ["Space", "Jump"], ["↓", "Step off an edge and parachute"],
        ["Hold G + arrows", "Aim the grappling hook; release G to fire"],
        ["Hold C", "Crouch"], ["Option + C", "Crouch and reach lower"],
        ["E", "Click at Jerry’s hand, including on ropes"],
        ["Return", "Ask Jerry"], ["Esc", "Return to your previous app"]
    ] }
    @MainActor static var groups: [(String, [[String]])] { [
        ("From any app", [rows[1], rows[0]]),
        ("Movement", [rows[2], rows[4], rows[3], rows[5], rows[7], rows[11]]),
        ("Tools & tasks", [rows[6], rows[8], rows[9], rows[10]])
    ] }
}

/// A short, permission-free introduction. The full reference lives in Settings.
@MainActor
final class WelcomeController: NSWindowController, NSWindowDelegate {
    var onIdleChanged: ((Bool) -> Void)?
    var onTakeControl: (() -> Void)?
    var onSetupAI: (() -> Void)?
    var onClose: (() -> Void)?
    private let illustration = SKView()
    private var controlShortcutLabel: NSTextField!
    private var askShortcutLabel: NSTextField!
    init() {
        let window = NotebookWindow(contentRect: .init(x: 0, y: 0, width: 560, height: 450), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Welcome to Jerry"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self; window.center()
        let root = NotebookTheme.install(on: window, title: "Welcome", showsCaption: false)
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32), content.topAnchor.constraint(equalTo: root.topAnchor, constant: 18)])
        let header = NSStackView(); header.spacing = 20; header.alignment = .centerY
        illustration.allowsTransparency = true; illustration.preferredFramesPerSecond = 30; illustration.setAccessibilityElement(false)
        illustration.presentScene(WelcomeExplorerScene(size: .init(width: 120, height: 148)))
        illustration.widthAnchor.constraint(equalToConstant: 120).isActive = true; illustration.heightAnchor.constraint(equalToConstant: 148).isActive = true
        let intro = NSStackView(); intro.orientation = .vertical; intro.alignment = .leading; intro.spacing = 9
        intro.addArrangedSubview(text("Meet Jerry.", size: 30, weight: .semibold, serif: true))
        intro.addArrangedSubview(text("Your personal\ndesktop explorer.", size: 15))
        header.addArrangedSubview(illustration); header.addArrangedSubview(intro); content.addArrangedSubview(header)
        content.addArrangedSubview(text("Take control and turn your desktop into an adventure, or give Jerry a mission. He keeps a journal along the way.", size: 13))
        let shortcuts = NSStackView(); shortcuts.orientation = .vertical; shortcuts.alignment = .leading; shortcuts.spacing = 9
        controlShortcutLabel = text("", size: 12, weight: .medium); askShortcutLabel = text("", size: 12, weight: .medium)
        shortcuts.addArrangedSubview(controlShortcutLabel); shortcuts.addArrangedSubview(askShortcutLabel)
        let playHint = text("In control: arrows move · Space jumps · Esc returns.", size: 11); playHint.textColor = NotebookTheme.faded
        shortcuts.addArrangedSubview(playHint)
        content.addArrangedSubview(shortcuts)
        let note = text("Between expeditions, he explores your windows looking for patterned socks. Drag him aside whenever he’s in the way.", size: 12); note.textColor = NotebookTheme.faded; content.addArrangedSubview(note)
        let actions = NSStackView(); actions.spacing = 10
        let setup = NSButton(title: "Set up AI…", target: self, action: #selector(setupAI)); setup.isBordered = false; setup.contentTintColor = NotebookTheme.faded
        let github = NSButton(title: "GitHub ↗", target: self, action: #selector(openGitHub)); github.isBordered = false; github.contentTintColor = NotebookTheme.faded
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let control = NSButton(title: "Try Controls", target: self, action: #selector(takeControl)); control.bezelStyle = .rounded
        let start = NSButton(title: "Let’s Go", target: self, action: #selector(startExploring)); start.bezelStyle = .rounded; start.keyEquivalent = "\r"
        NotebookTheme.style(control); NotebookTheme.style(start, primary: true)
        [setup, github, spacer, control, start].forEach { actions.addArrangedSubview($0) }
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
    func open(idleExploration: Bool) {
        controlShortcutLabel.stringValue = GlobalShortcutAction.control.display + "    Take control"
        askShortcutLabel.stringValue = GlobalShortcutAction.ask.display + "    Give Jerry a mission"
        illustration.isPaused = false; NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/samwillis/jerry")!) }
    @objc private func startExploring() { onIdleChanged?(true); close() }
    @objc private func takeControl() { close(); onTakeControl?() }
    @objc private func setupAI() { close(); onSetupAI?() }
    func windowWillClose(_ notification: Notification) { illustration.isPaused = true; onClose?() }
}
