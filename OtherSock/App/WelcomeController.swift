import AppKit
import SpriteKit

@MainActor
private final class WelcomeExplorerScene: SKScene {
    private let explorer = ExplorerRig()
    private var previousTime: TimeInterval?
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        explorer.position = .init(x: 50, y: 9)
        explorer.setScale(1.35)
        addChild(explorer)
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
        ["Arrows / WASD", "Walk, climb and swing; Up grabs a hold"],
        ["Shift", "Run or climb faster"], ["Space", "Jump"], ["↓", "Step off an edge and parachute"],
        ["Hold G + arrows", "Aim the grappling hook; release G to fire"],
        ["Hold C", "Crouch"], ["Option + C", "Crouch and reach a little lower"],
        ["E", "Click at the hand marker, including on a rope"],
        ["Return", "Ask Jerry while in control"], ["Esc", "Return to your previous app"]
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
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 540, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to The Other Sock"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self; window.center()
        let root = NSView(); window.contentView = root
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32), content.topAnchor.constraint(equalTo: root.topAnchor, constant: 18)])
        let header = NSStackView(); header.spacing = 20; header.alignment = .centerY
        illustration.allowsTransparency = true; illustration.preferredFramesPerSecond = 30; illustration.setAccessibilityElement(false)
        illustration.presentScene(WelcomeExplorerScene(size: .init(width: 100, height: 112)))
        illustration.widthAnchor.constraint(equalToConstant: 100).isActive = true; illustration.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let intro = NSStackView(); intro.orientation = .vertical; intro.alignment = .leading; intro.spacing = 9
        intro.addArrangedSubview(text("Meet Jerry.", size: 30, weight: .semibold, serif: true))
        intro.addArrangedSubview(text("One small adventurer.\nOne missing sock.", size: 15))
        header.addArrangedSubview(illustration); header.addArrangedSubview(intro); content.addArrangedSubview(header)
        content.addArrangedSubview(text("He climbs your windows, parachutes between ledges and looks for patterned socks. Drag him aside whenever he’s in the way.", size: 13))
        let shortcuts = NSStackView(); shortcuts.orientation = .vertical; shortcuts.alignment = .leading; shortcuts.spacing = 9
        shortcuts.addArrangedSubview(text("⌃⌥ Space    Take the lead", size: 12, weight: .medium))
        shortcuts.addArrangedSubview(text("⌃⌥ Return   Give Jerry a task", size: 12, weight: .medium))
        let playHint = text("In control: arrows move · Space jumps · Esc returns.", size: 11); playHint.textColor = .secondaryLabelColor
        shortcuts.addArrangedSubview(playHint)
        content.addArrangedSubview(shortcuts)
        let note = text("No account needed to explore. AI and desktop clicks are optional.", size: 11); note.textColor = .secondaryLabelColor; content.addArrangedSubview(note)
        let actions = NSStackView(); actions.spacing = 10
        let setup = NSButton(title: "Set up AI…", target: self, action: #selector(setupAI)); setup.isBordered = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let control = NSButton(title: "Try Controls", target: self, action: #selector(takeControl)); control.bezelStyle = .rounded
        let start = NSButton(title: "Start Exploring", target: self, action: #selector(startExploring)); start.bezelStyle = .rounded; start.keyEquivalent = "\r"
        [setup, spacer, control, start].forEach { actions.addArrangedSubview($0) }
        content.addArrangedSubview(actions)
        for view in [header, shortcuts, actions] { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, serif: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = serif ? NSFont(descriptor: NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)!, size: size) ?? .systemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
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
