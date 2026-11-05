#if DEBUG
import AppKit
import SpriteKit
import ExpeditionCore

@MainActor
final class AnimationPlaygroundController: NSWindowController, NSWindowDelegate {
    private let scene = AnimationPlaygroundScene(size: CGSize(width: 1000, height: 530))
    private let view = SKView()
    private var picker: NSPopUpButton!
    private var pauseButton: NSButton!

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "The Other Sock — Animation Playground"
        window.minSize = CGSize(width: 980, height: 680)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        let content = NSView()
        window.contentView = content
        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controls)

        let row = NSStackView()
        row.spacing = 12
        picker = NSPopUpButton()
        for motion in ExplorerMotion.allCases { picker.addItem(withTitle: motion == .comic ? "Edge hesitation (comic)" : motion.rawValue.capitalized) }
        picker.target = self; picker.action = #selector(selectMotion)
        row.addArrangedSubview(picker)
        pauseButton = NSButton(title: "Pause", target: self, action: #selector(togglePause))
        row.addArrangedSubview(pauseButton)
        row.addArrangedSubview(NSButton(title: "Restart", target: self, action: #selector(restart)))
        row.addArrangedSubview(NSButton(checkboxWithTitle: "Face left", target: self, action: #selector(flip)))
        row.addArrangedSubview(NSButton(checkboxWithTitle: "Joints & contacts", target: self, action: #selector(toggleJoints)))
        row.addArrangedSubview(NSButton(checkboxWithTitle: "Light background", target: self, action: #selector(toggleBackground)))
        controls.addArrangedSubview(row)

        let sliders = NSStackView()
        sliders.spacing = 12
        addSlider("Playback", value: 1, min: 0.1, max: 1, action: #selector(rateChanged), to: sliders)
        addSlider("Zoom", value: 3, min: 1, max: 3, action: #selector(zoomChanged), to: sliders)
        addSlider("Cadence", value: 1, min: 0.3, max: 2, action: #selector(cadenceChanged), to: sliders)
        addSlider("Stride", value: 10, min: 2, max: 12, action: #selector(strideChanged), to: sliders)
        addSlider("Bounce", value: 1, min: 0, max: 2, action: #selector(bounceChanged), to: sliders)
        addSlider("Preview time (pauses)", value: 0, min: 0, max: 9, action: #selector(timeChanged), to: sliders)
        controls.addArrangedSubview(sliders)
        let hint = NSTextField(labelWithString: "Climbing: drag green handholds. Abseiling: drag the rope anchor. Held: move the pink grab point. Grab the body in any clip to interrupt it.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        controls.addArrangedSubview(hint)

        view.translatesAutoresizingMaskIntoConstraints = false
        view.preferredFramesPerSecond = 30
        content.addSubview(view)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        view.presentScene(scene)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func addSlider(_ title: String, value: Double, min: Double, max: Double, action: Selector, to row: NSStackView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        slider.widthAnchor.constraint(equalToConstant: 145).isActive = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(slider)
        row.addArrangedSubview(stack)
    }

    func open() {
        view.isPaused = false
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() { view.isPaused = true; super.close() }
    func windowWillClose(_ notification: Notification) { view.isPaused = true }
    @objc private func selectMotion() { scene.select(ExplorerMotion.allCases[picker.indexOfSelectedItem]) }
    @objc private func togglePause() {
        scene.playbackPaused.toggle()
        pauseButton.title = scene.playbackPaused ? "Resume" : "Pause"
    }
    @objc private func restart() { scene.restart() }
    @objc private func flip(_ sender: NSButton) { scene.facing = sender.state == .on ? -1 : 1 }
    @objc private func toggleJoints(_ sender: NSButton) { scene.showJoints = sender.state == .on }
    @objc private func toggleBackground(_ sender: NSButton) { scene.darkBackground = sender.state != .on }
    @objc private func rateChanged(_ sender: NSSlider) { scene.playbackRate = sender.doubleValue }
    @objc private func zoomChanged(_ sender: NSSlider) { scene.zoom = sender.doubleValue }
    @objc private func cadenceChanged(_ sender: NSSlider) { scene.tuning.cadence = sender.doubleValue }
    @objc private func strideChanged(_ sender: NSSlider) { scene.tuning.stride = sender.doubleValue }
    @objc private func bounceChanged(_ sender: NSSlider) { scene.tuning.bounce = sender.doubleValue }
    @objc private func timeChanged(_ sender: NSSlider) {
        scene.seek(to: sender.doubleValue)
        pauseButton.title = "Resume"
    }
}
#endif
