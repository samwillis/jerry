import AppKit
import FoundationModels
import ExpeditionCore

@MainActor
private final class ExplorerPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns connection settings, the task composer and the non-activating task journal.
@MainActor
final class AgentTaskController: NSWindowController, NSWindowDelegate, NSComboBoxDelegate {
    private let credentials = AgentCredentials()
    private let provider = NSPopUpButton()
    private let preset = NSPopUpButton()
    private let model = NSComboBox()
    private let apiKey = NSSecureTextField()
    private let requestField = NSTextField()
    private let status = NSTextField(wrappingLabelWithString: "Choose a connection for your explorer.")
    private let connection = NSTextField(wrappingLabelWithString: "")
    private let promptHint = NSTextField(wrappingLabelWithString: "")
    private let taskStatus = NSTextField(wrappingLabelWithString: "Ready")
    private let taskRequest = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextView()
    private let run = NSButton(title: "Send explorer", target: nil, action: nil)
    private let signInButton = NSButton(title: "Continue with ChatGPT", target: nil, action: nil)
    private let cancelSignInButton = NSButton(title: "Cancel sign-in", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop task", target: nil, action: nil)
    private var chatGPTSection: NSView!
    private var keySection: NSView!
    private var modelsSection: NSView!
    private var demoSection: NSView!
    private var promptWindow: NSPanel!
    private var journal: NSPanel!
    private var catalogTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var acceptedPlan = false
    private var missionActive = false
    private var resumeControlOnCancel = false
    private var lastTeamStatus = ""
    var onPlan: ((SurveyPlan) -> Void)?
    var onStop: (() -> Void)?
    var onPromptCancelled: (() -> Void)?
    var onSubmitted: (() -> Void)?
    var onPromptOpened: (() -> Void)?
    var onPromptDismissed: (() -> Void)?
    var explorerFrame: (() -> CGRect)?

    override init(window: NSWindow?) { super.init(window: window) }
    convenience init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 580, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.init(window: window)
        window.title = "Explorer Settings"; window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        buildSettings(); buildPrompt(); buildJournal()
        credentials.onChange = { [weak self] in self?.updateConnection() }
        let savedProvider = UserDefaults.standard.object(forKey: "agentProvider") as? Int
        provider.selectItem(at: savedProvider.flatMap { (0...2).contains($0) ? $0 : nil } ?? (credentials.account == nil ? 0 : 1))
        providerChanged(); updateConnection()
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func open() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func openPrompt(resumeControl: Bool = false) {
        resumeControlOnCancel = resumeControl
        updatePromptHint(); onPromptOpened?(); updatePromptPosition(force: true)
        promptWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); promptWindow.makeFirstResponder(requestField)
    }
    func updateTeamStatus(_ message: String) {
        guard acceptedPlan, missionActive else { return }
        lastTeamStatus = message; taskStatus.stringValue = message
        if message.hasPrefix("Survey complete") { missionActive = false; stopButton.isEnabled = task != nil }
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); return field
    }
    private func button(_ title: String, _ selector: Selector) -> NSButton { NSButton(title: title, target: self, action: selector) }
    private func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.spacing = 10; row.alignment = .centerY; return row }
    private func stack(in content: NSView, inset: CGFloat = 24) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.distribution = .fill; stack.alignment = .leading; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset), stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -inset)])
        return stack
    }
    private func card(_ views: [NSView], width: CGFloat) -> NSView {
        let box = NSView(); box.wantsLayer = true; box.layer?.cornerRadius = 12; box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor
        let body = stack(in: box, inset: 16); body.spacing = 10
        for view in views { body.addArrangedSubview(view); view.widthAnchor.constraint(equalToConstant: width - 32).isActive = true }
        body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16).isActive = true
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }
    private func buildSettings() {
        guard let content = window?.contentView else { return }
        let body = stack(in: content)
        body.addArrangedSubview(label("A brain for the expedition", size: 24, weight: .bold))
        body.addArrangedSubview(label("Choose how your explorer plans a task. Connections stay on this Mac.", size: 13))
        provider.addItems(withTitles: ["Offline demo", "ChatGPT", "OpenAI API key"])
        provider.target = self; provider.action = #selector(providerChanged)
        body.addArrangedSubview(row([label("AI provider", weight: .semibold), provider]))
        connection.textColor = .secondaryLabelColor; connection.font = .systemFont(ofSize: 12)
        signInButton.target = self; signInButton.action = #selector(signIn)
        cancelSignInButton.target = self; cancelSignInButton.action = #selector(cancelSignIn)
        chatGPTSection = card([label("Use your ChatGPT account", size: 15, weight: .semibold), label("Continue in your browser to connect your plan. Your password never enters this app.", size: 12), row([signInButton, cancelSignInButton])], width: 532)
        keySection = card([label("Connect with an API key", size: 15, weight: .semibold), label("Paste a key below. It is stored securely in macOS Keychain.", size: 12), apiKey, row([button("Save API key", #selector(saveKey))])], width: 532)
        apiKey.placeholderString = "API key"; apiKey.setAccessibilityLabel("OpenAI API key")
        body.addArrangedSubview(chatGPTSection); body.addArrangedSubview(keySection)
        body.addArrangedSubview(connection)
        model.stringValue = UserDefaults.standard.string(forKey: "agentModelID") ?? ""
        model.placeholderString = "Choose a model with images and tools"; model.isEditable = true; model.delegate = self
        model.widthAnchor.constraint(equalToConstant: 350).isActive = true
        modelsSection = card([label("Model", size: 15, weight: .semibold), row([model, button("Load models", #selector(loadModels))]), label("Load your account’s catalog, then choose a model that supports vision and tools.", size: 12)], width: 532)
        body.addArrangedSubview(modelsSection)
        preset.addItems(withTitles: ["Three independent jobs", "One solo job", "Three jobs in order"])
        demoSection = card([label("Offline survey pattern", size: 15, weight: .semibold), preset], width: 532)
        body.addArrangedSubview(demoSection)
        let scope = label("This first version inspects illustrated blue, amber and purple flags. Only that illustration and your instruction go to AI. Other apps aren’t shared or controlled.", size: 12)
        scope.textColor = .secondaryLabelColor; scope.preferredMaxLayoutWidth = 532; scope.widthAnchor.constraint(equalToConstant: 532).isActive = true
        body.addArrangedSubview(scope)
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 12); status.widthAnchor.constraint(equalToConstant: 532).isActive = true
        body.addArrangedSubview(status)
        body.addArrangedSubview(row([button("Forget saved connections", #selector(forget)), button("Done", #selector(doneSettings))]))
    }
    private func buildPrompt() {
        promptWindow = ExplorerPromptPanel(contentRect: .init(x: 0, y: 0, width: 360, height: 52), styleMask: [.borderless], backing: .buffered, defer: false)
        promptWindow.title = "Ask explorer"; promptWindow.isReleasedWhenClosed = false; promptWindow.delegate = self; promptWindow.level = .floating
        promptWindow.isOpaque = false; promptWindow.backgroundColor = .clear; promptWindow.hasShadow = true
        promptWindow.hidesOnDeactivate = false; promptWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(); glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = 14; glass.layer?.masksToBounds = true; promptWindow.contentView = glass
        requestField.placeholderString = "Ask your explorer…"
        requestField.setAccessibilityLabel("Explorer task")
        requestField.font = .systemFont(ofSize: 14); requestField.isBordered = false; requestField.drawsBackground = false
        requestField.focusRingType = .none; requestField.delegate = self; requestField.target = self; requestField.action = #selector(plan)
        run.target = self; run.action = #selector(plan); run.isBordered = false
        run.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send task")
        run.imagePosition = .imageOnly; run.setAccessibilityLabel("Send task"); run.toolTip = "Send · Return"; run.contentTintColor = .controlAccentColor
        let input = row([requestField, run]); input.translatesAutoresizingMaskIntoConstraints = false; glass.addSubview(input)
        NSLayoutConstraint.activate([input.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 14), input.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -10), input.centerYAnchor.constraint(equalTo: glass.centerYAnchor), run.widthAnchor.constraint(equalToConstant: 28), run.heightAnchor.constraint(equalToConstant: 28)])
    }
    func updatePromptPosition(force: Bool = false) {
        guard force || promptWindow.isVisible else { return }
        guard let frame = explorerFrame?() else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let width = promptWindow.frame.width, height = promptWindow.frame.height
        let right = frame.maxX + 12
        let x = right + width <= visible.maxX - 10 ? right : frame.minX - width - 12
        let origin = CGPoint(x: min(max(x, visible.minX + 10), visible.maxX - width - 10), y: min(max(frame.maxY - height, visible.minY + 10), visible.maxY - height - 10))
        promptWindow.setFrameOrigin(origin)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === requestField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelPrompt(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { plan(); return true }
        return false
    }
    private func buildJournal() {
        journal = NSPanel(contentRect: .init(x: 0, y: 0, width: 340, height: 480), styleMask: [.titled, .nonactivatingPanel, .closable], backing: .buffered, defer: false)
        journal.title = "Expedition journal"; journal.isReleasedWhenClosed = false; journal.hidesOnDeactivate = false; journal.level = .floating
        journal.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(); glass.material = .sidebar; glass.blendingMode = .behindWindow; glass.state = .active; journal.contentView = glass
        let body = stack(in: glass, inset: 20); body.spacing = 12
        body.addArrangedSubview(label("EXPLORER · AI", size: 11, weight: .bold))
        taskRequest.font = .systemFont(ofSize: 16, weight: .semibold); taskRequest.maximumNumberOfLines = 3; taskRequest.preferredMaxLayoutWidth = 300; taskRequest.lineBreakMode = .byWordWrapping
        taskRequest.widthAnchor.constraint(equalToConstant: 300).isActive = true; body.addArrangedSubview(taskRequest)
        taskStatus.preferredMaxLayoutWidth = 300
        taskStatus.font = .systemFont(ofSize: 12, weight: .medium); taskStatus.textColor = .secondaryLabelColor; taskStatus.widthAnchor.constraint(equalToConstant: 300).isActive = true; body.addArrangedSubview(taskStatus)
        let divider = NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant: 300).isActive = true; body.addArrangedSubview(divider)
        result.isEditable = false; result.isSelectable = true; result.drawsBackground = false; result.font = .systemFont(ofSize: 13); result.textContainerInset = .init(width: 0, height: 4)
        result.isHorizontallyResizable = false; result.autoresizingMask = [.width]; result.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.documentView = result; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.widthAnchor.constraint(equalToConstant: 300).isActive = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        let preferredHeight = scroll.heightAnchor.constraint(equalToConstant: 220); preferredHeight.priority = .defaultLow; preferredHeight.isActive = true
        body.addArrangedSubview(scroll)
        body.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -20).isActive = true
        stopButton.target = self; stopButton.action = #selector(stop); stopButton.isEnabled = false
        body.addArrangedSubview(row([stopButton, button("New task…", #selector(newPrompt)), button("Hide", #selector(hideJournal))]))
    }
    private func showJournal() {
        if let frame = NSScreen.screens.first?.visibleFrame {
            journal.setFrameTopLeftPoint(.init(x: frame.maxX - journal.frame.width - 20, y: frame.maxY - 24))
        }
        journal.orderFrontRegardless()
    }
    func showActivity() {
        if taskRequest.stringValue.isEmpty { taskRequest.stringValue = "Ready for a mission"; taskStatus.stringValue = "Take control and press Return, or choose Ask Explorer." }
        showJournal()
    }
    func manualTakeover() { onPromptDismissed?(); resumeControlOnCancel = false; promptWindow.orderOut(nil); window?.orderOut(nil); stop() }
    @objc private func hideJournal() { journal.orderOut(nil) }
    @objc private func showSettings() { open() }
    @objc private func doneSettings() { persistModel(); window?.close(); if promptWindow.isVisible { promptWindow.makeKeyAndOrderFront(nil) } }
    @objc private func newPrompt() { openPrompt() }
    @objc private func cancelPrompt() { promptWindow.orderOut(nil); finishPromptCancellation() }
    private func finishPromptCancellation() {
        onPromptDismissed?()
        let resume = resumeControlOnCancel; resumeControlOnCancel = false
        if resume { onPromptCancelled?() }
    }
    private func persistModel() { UserDefaults.standard.set(model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "agentModelID") }
    func controlTextDidEndEditing(_ notification: Notification) { if notification.object as? NSComboBox === model { persistModel(); updatePromptHint() } }
    func comboBoxSelectionDidChange(_ notification: Notification) { DispatchQueue.main.async { [weak self] in self?.persistModel(); self?.updatePromptHint() } }
    private func updateConnection() {
        signInButton.title = credentials.account == nil ? "Continue with ChatGPT" : "Reconnect ChatGPT"
        signInButton.isEnabled = !credentials.isSigningIn
        cancelSignInButton.isHidden = !credentials.isSigningIn
        if let account = credentials.account { connection.stringValue = credentials.isSigningIn ? credentials.status : "Connected to ChatGPT · \(account.email)" }
        else { connection.stringValue = credentials.status + (credentials.hasAPIKey ? " · API key saved" : "") }
        updatePromptHint()
    }
    private func updatePromptHint() {
        let source = provider.indexOfSelectedItem
        promptHint.stringValue = source == 0 ? "Offline demo · uses the selected job pattern above." : "\(source == 1 ? "ChatGPT" : "OpenAI API") · \(model.stringValue.isEmpty ? "Choose a model in AI Settings" : model.stringValue)"
        requestField.toolTip = promptHint.stringValue + " · Return to send · Escape to cancel"
    }
    @objc private func providerChanged() {
        catalogTask?.cancel()
        let source = provider.indexOfSelectedItem
        UserDefaults.standard.set(source, forKey: "agentProvider")
        chatGPTSection.isHidden = source != 1; keySection.isHidden = source != 2; modelsSection.isHidden = source == 0; demoSection.isHidden = source != 0
        status.stringValue = source == 0 ? "The offline demo needs no account. It uses a scripted plan through the same native tool loop." : "Keys and sign-in tokens are stored in macOS Keychain."
        window?.setContentSize(.init(width: 580, height: source == 0 ? 500 : 640))
        updatePromptHint()
    }
    @objc private func signIn() { credentials.signIn() }
    @objc private func cancelSignIn() { credentials.cancelSignIn(); updateConnection(); status.stringValue = "Sign-in cancelled. You can connect again whenever you’re ready." }
    @objc private func forget() { stop(); catalogTask?.cancel(); credentials.disconnect(); model.removeAllItems(); model.stringValue = "" }
    @objc private func saveKey() {
        do { try credentials.saveAPIKey(apiKey.stringValue); apiKey.stringValue = ""; provider.selectItem(at: 2); providerChanged() }
        catch { connection.stringValue = error.localizedDescription }
    }
    @objc private func loadModels() {
        catalogTask?.cancel()
        let source = provider.indexOfSelectedItem
        guard source != 0 else { status.stringValue = "The offline model needs no credentials or model catalog."; return }
        catalogTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = source == 1 ? try await credentials.accessToken() : try credentials.apiKey()
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.timeoutInterval = 30; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentConnectionError(message: "Could not load models for this connection.") }
                let choices: [String]
                if let models = json["models"] as? [[String: Any]] { choices = models.filter { ($0["visibility"] as? String ?? "list") == "list" }.compactMap { $0["slug"] as? String } }
                else { choices = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted() }
                model.removeAllItems(); model.addItems(withObjectValues: choices)
                if model.stringValue.isEmpty, let first = choices.first { model.stringValue = first }
                status.stringValue = "Loaded \(choices.count) models. Choose one with images and tools."; persistModel(); updatePromptHint()
            } catch is CancellationError { } catch { status.stringValue = error.localizedDescription }
        }
    }
    private func scriptedPlan() -> SurveyPlan {
        switch preset.indexOfSelectedItem {
        case 1: return .init(jobs: [.init(marker: "blue", instruction: "Inspect the blue flag")])
        case 2: return .init(jobs: [.init(marker: "blue", instruction: "Inspect blue"), .init(marker: "amber", instruction: "Then amber", dependsOn: ["blue"]), .init(marker: "purple", instruction: "Then purple", dependsOn: ["amber"])])
        default: return .init(jobs: ["blue", "amber", "purple"].map { .init(marker: $0, instruction: "Inspect the \($0) flag") })
        }
    }
    @objc private func plan() {
        let source = provider.indexOfSelectedItem, selectedModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), prompt = requestField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { NSSound.beep(); return }
        guard source == 0 || (!selectedModel.isEmpty && (source == 1 ? credentials.account != nil : credentials.hasAPIKey)) else {
            promptHint.stringValue = "Connect an account and choose a model in AI Settings first."; open(); return
        }
        stop()
        let id = UUID(); runID = id; acceptedPlan = false; lastTeamStatus = ""
        resumeControlOnCancel = false; promptWindow.orderOut(nil); window?.orderOut(nil)
        let scripted = scriptedPlan()
        if !selectedModel.isEmpty { UserDefaults.standard.set(selectedModel, forKey: "agentModelID") }
        result.string = ""; taskRequest.stringValue = prompt; taskStatus.stringValue = "Planning the expedition…"; stopButton.isEnabled = true; showJournal(); onSubmitted?()
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.runID == id { self.task = nil; self.stopButton.isEnabled = self.missionActive } }
            do {
                guard #available(macOS 27.0, *) else { throw AgentConnectionError(message: "The Foundation Models provider prototype needs macOS 27 or later.") }
                guard !prompt.isEmpty else { throw AgentConnectionError(message: "Give the explorer a survey instruction.") }
                guard source == 0 || !selectedModel.isEmpty else { throw AgentConnectionError(message: "Load and select a model first.") }
                let token = source == 0 ? "" : (source == 1 ? try await credentials.accessToken() : try credentials.apiKey())
                let scriptJSON = source == 0 ? String(data: try JSONEncoder().encode(scripted), encoding: .utf8) : nil
                let languageModel = ExplorerLanguageModel(executorConfiguration: .init(model: selectedModel, bearer: token, scriptedPlan: scriptJSON, sessionID: UUID()))
                let tool = AssignSurveyJobsTool { [weak self] plan in
                    guard let self, self.runID == id, !self.acceptedPlan else { throw MissionError.staleRun }
                    self.acceptedPlan = true; self.missionActive = true; self.onPlan?(plan)
                }
                let session = LanguageModelSession(model: languageModel, tools: [tool], instructions: "You direct a little explorer team. The leader is permanent. There are at most two helpers, invited only for independent ready jobs. The picture is the app's synthetic survey card, not the user's desktop. Use assign_survey_jobs exactly once with 1–3 jobs for visible flag IDs blue, amber, purple, using dependsOn only where the user's request requires an ordering. Do not invent completed work. The tool queues work; physical arrival and inspection happen later. No external apps can be operated in this prototype.")
                let image = Self.surveyImage()
                for try await partial in session.streamResponse(to: Prompt { prompt; Attachment(image) }) {
                    try Task.checkCancellation()
                    guard self.runID == id else { return }
                    let visible = self.result.visibleRect
                    let following = visible.maxY >= self.result.bounds.maxY - 24
                    self.result.string = partial.content
                    if following { self.result.scrollToEndOfDocument(nil) }
                }
                try Task.checkCancellation()
                guard self.runID == id else { return }
                if !self.acceptedPlan { self.taskStatus.stringValue = "No survey assigned. Try another instruction." }
                else if !self.lastTeamStatus.isEmpty { self.taskStatus.stringValue = self.lastTeamStatus }
            } catch is CancellationError { }
            catch {
                if self.runID == id { self.missionActive = false; self.onStop?(); self.taskStatus.stringValue = "Couldn’t finish the task"; self.result.string += "\n\n" + error.localizedDescription }
            }
        }
    }
    @objc func stop() {
        runID = UUID(); task?.cancel(); task = nil; missionActive = false; acceptedPlan = false; stopButton.isEnabled = false; onStop?()
        taskStatus.stringValue = "Stopped · friends are heading home."
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === promptWindow { finishPromptCancellation() }
        if notification.object as? NSWindow === window { apiKey.stringValue = ""; credentials.cancelSignIn(); updateConnection() }
    }
    func closeAll() { stop(); catalogTask?.cancel(); credentials.cancelSignIn(); resumeControlOnCancel = false; promptWindow.close(); journal.close(); close() }
    static func surveyImage() -> CGImage {
        let image = NSImage(size: .init(width: 600, height: 110), flipped: false) { bounds in
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); bounds.fill()
            for (index, entry) in [("blue", NSColor.systemBlue), ("amber", NSColor.systemOrange), ("purple", NSColor.systemPurple)].enumerated() {
                let x = CGFloat(index) * 200 + 16
                entry.1.setFill(); NSBezierPath(roundedRect: .init(x: x, y: 16, width: 168, height: 78), xRadius: 10, yRadius: 10).fill()
                (entry.0 as NSString).draw(at: .init(x: x + 28, y: 42), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white])
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
