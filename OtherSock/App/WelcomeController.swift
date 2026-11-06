import AppKit
import SpriteKit

@MainActor
private final class WelcomeDocumentView: NSView {
    override var isFlipped: Bool { true }
}

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

/// The reusable first-run guide. Opening/closing it never grants permissions.
@MainActor
final class WelcomeController: NSWindowController, NSWindowDelegate {
    var onIdleChanged: ((Bool) -> Void)?
    var onTakeControl: (() -> Void)?
    var onAllowClicks: (() -> Void)?
    var onClose: (() -> Void)?
    private let illustration = SKView()
    private let idleCheckbox = NSButton(checkboxWithTitle: "Enable Idle Exploration", target: nil, action: nil)
    private let accessButton = NSButton(title: "Allow Clicks…", target: nil, action: nil)
    private let accessStatus = NSTextField(labelWithString: "")

    init() {
        let height = min(650.0, (NSScreen.screens.first?.visibleFrame.height ?? 900) - 70)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 680, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "The Other Sock — Welcome"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        let root = NSView(); window.contentView = root
        let footer = NSStackView(); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(footer)
        let footerRow = NSStackView(); footerRow.spacing = 10
        let note = text("Find this guide in the hiking menu → Controls & Tips.", size: 11, color: .secondaryLabelColor)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let takeControl = NSButton(title: "Take Control", target: self, action: #selector(takeControl))
        let done = NSButton(title: "Let’s Go", target: self, action: #selector(done))
        done.keyEquivalent = "\r"; done.bezelStyle = .rounded; takeControl.bezelStyle = .rounded
        [note, spacer, takeControl, done].forEach { footerRow.addArrangedSubview($0) }
        footer.addArrangedSubview(footerRow)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(scroll)
        let document = WelcomeDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.distribution = .fill
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            footerRow.widthAnchor.constraint(equalTo: footer.widthAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8)
        ])

        let header = NSStackView(); header.spacing = 20; header.alignment = .centerY
        header.heightAnchor.constraint(equalToConstant: 112).isActive = true
        illustration.allowsTransparency = true; illustration.preferredFramesPerSecond = 30
        illustration.setAccessibilityElement(false)
        illustration.presentScene(WelcomeExplorerScene(size: .init(width: 100, height: 112)))
        illustration.widthAnchor.constraint(equalToConstant: 100).isActive = true
        illustration.heightAnchor.constraint(equalToConstant: 112).isActive = true
        header.addArrangedSubview(illustration)
        let introduction = NSStackView(); introduction.orientation = .vertical; introduction.alignment = .leading; introduction.spacing = 8
        introduction.addArrangedSubview(text("Meet your explorer", size: 27, weight: .bold))
        introduction.addArrangedSubview(text("One small adventurer. One missing sock.", size: 14, weight: .medium))
        introduction.addArrangedSubview(text("Let him roam your windows, or take the lead.", size: 13, color: .secondaryLabelColor))
        header.addArrangedSubview(introduction); stack.addArrangedSubview(header)

        idleCheckbox.font = .systemFont(ofSize: 14, weight: .semibold)
        idleCheckbox.target = self; idleCheckbox.action = #selector(idleChanged)
        stack.addArrangedSubview(card([
            idleCheckbox,
            text("On: he explores and looks for the sock. Off: he rests and watches your mouse.\nYou can always drag him aside—he’ll land safely.", size: 12, color: .secondaryLabelColor)
        ]))
        let controls = NSStackView(); controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 8
        controls.addArrangedSubview(text("TAKE THE LEAD", size: 11, weight: .semibold, color: .secondaryLabelColor))
        let rows = [
            ["⌃ ⌥ Return", "Ask the explorer, from any app"],
            ["⌃ ⌥ Space", "Take or release control, from any app"],
            ["Arrows / WASD", "Walk, climb and swing; Up grabs a hold"],
            ["Shift / hold C", "Run or climb faster / crouch and click lower"],
            ["Space / ↓", "Jump / step off a ledge and parachute"],
            ["Hold G + arrows", "Aim the grappling hook"],
            ["Release G", "Fire at the highlighted window rim"],
            ["E", "Click the marker—even while on a rope"],
            ["Option + C", "Crouch with a lower pointer; the same pose"],
            ["Return", "Give the explorer an AI task"],
            ["Esc", "Give control back to your computer"]
        ]
        let grid = NSGridView(views: rows.map { [keycap($0[0]), text($0[1], size: 12)] })
        grid.rowSpacing = 4; grid.columnSpacing = 16
        grid.column(at: 0).width = 148
        grid.column(at: 1).xPlacement = .leading
        controls.addArrangedSubview(grid)
        stack.addArrangedSubview(card([controls]))

        let accessRow = NSStackView(); accessRow.spacing = 12; accessRow.alignment = .centerY
        let accessCopy = NSStackView(); accessCopy.orientation = .vertical; accessCopy.alignment = .leading; accessCopy.spacing = 5
        accessCopy.addArrangedSubview(text("Press real buttons through your explorer", size: 12, weight: .semibold))
        accessStatus.font = .systemFont(ofSize: 11); accessStatus.textColor = .secondaryLabelColor
        accessStatus.maximumNumberOfLines = 2
        accessCopy.addArrangedSubview(accessStatus); accessRow.addArrangedSubview(accessCopy)
        accessButton.target = self; accessButton.action = #selector(allowClicks); accessButton.bezelStyle = .rounded
        accessRow.addArrangedSubview(accessButton)
        stack.addArrangedSubview(card([accessRow]))
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        refreshAccess()
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }
    private func keycap(_ value: String) -> NSView {
        let label = NSTextField(labelWithString: value)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.alignment = .center; label.drawsBackground = true; label.backgroundColor = .controlBackgroundColor
        label.wantsLayer = true; label.layer?.cornerRadius = 5; label.layer?.masksToBounds = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }
    private func card(_ children: [NSView]) -> NSView {
        let card = NSView(); card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor
        card.layer?.cornerRadius = 12
        let content = NSStackView(views: children); content.orientation = .vertical; content.alignment = .leading; content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setContentHuggingPriority(.required, for: .vertical)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12), content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }
    func open(idleExploration: Bool) {
        idleCheckbox.state = idleExploration ? .on : .off
        refreshAccess(); illustration.isPaused = false
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    private func refreshAccess() {
        let allowed = ExplorerDesktopClick.hasAccess
        accessStatus.stringValue = allowed ? "Accessibility is enabled. E clicks without leaving control." : "Allow Accessibility for clicks in other apps.\nExploring and moving work without it."
        accessButton.title = allowed ? "Enabled ✓" : "Allow Clicks…"; accessButton.isEnabled = !allowed
    }
    @objc private func idleChanged() { onIdleChanged?(idleCheckbox.state == .on) }
    @objc private func allowClicks() { onAllowClicks?(); refreshAccess() }
    @objc private func done() { close() }
    @objc private func takeControl() { close(); onTakeControl?() }
    func windowDidBecomeKey(_ notification: Notification) { refreshAccess() }
    func windowWillClose(_ notification: Notification) { illustration.isPaused = true; onClose?() }
}
