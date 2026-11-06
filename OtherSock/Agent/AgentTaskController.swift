import AppKit
import FoundationModels
import ExpeditionCore

@MainActor
final class AgentTaskController: NSWindowController, NSWindowDelegate {
    private let credentials = AgentCredentials()
    private let provider = NSPopUpButton()
    private let preset = NSPopUpButton()
    private let model = NSComboBox()
    private let apiKey = NSSecureTextField()
    private let requestField = NSTextField(string: "Inspect all three survey flags independently. Invite friends only if there are independent jobs for them.")
    private let status = NSTextField(wrappingLabelWithString: "Ready for an offline survey. The original explorer stays on screen.")
    private let connection = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextView()
    private let run = NSButton(title: "Plan Survey", target: nil, action: nil)
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var acceptedPlan = false
    var onPlan: ((SurveyPlan) -> Void)?
    var onStop: (() -> Void)?
    override init(window: NSWindow?) { super.init(window: window) }
    convenience init() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 680, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        self.init(window: window)
        window.title = "The Other Sock — Tasks"; window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        build()
        credentials.onChange = { [weak self] in self?.updateConnection() }
        updateConnection()
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func open() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func updateTeamStatus(_ message: String) { status.stringValue = message }
    private func label(_ text: String, size: CGFloat = 13) -> NSTextField { let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: size); return field }
    private func button(_ title: String, _ selector: Selector) -> NSButton { let button = NSButton(title: title, target: self, action: selector); return button }
    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)])
        let heading = label("A little help from his friends", size: 23); heading.font = .boldSystemFont(ofSize: 23); stack.addArrangedSubview(heading)
        stack.addArrangedSubview(label("The explorer invites helpers when the plan has independent work. When the work is done, his friends head home."))
        let preview = NSImageView(image: NSImage(cgImage: Self.surveyImage(), size: .init(width: 560, height: 100)))
        preview.imageScaling = .scaleProportionallyUpOrDown; preview.setAccessibilityLabel("Survey image: blue, amber and purple flags")
        preview.heightAnchor.constraint(equalToConstant: 90).isActive = true; preview.widthAnchor.constraint(equalToConstant: 620).isActive = true
        stack.addArrangedSubview(preview)
        let scope = label("Prototype: the team inspects these survey flags. Only this illustrated card and your request are sent to a live model. No screenshots of other apps or desktop input are used.", size: 12)
        scope.textColor = .secondaryLabelColor; stack.addArrangedSubview(scope)
        provider.addItems(withTitles: ["Scripted Foundation Models test (offline)", "ChatGPT plan", "OpenAI API key"])
        provider.target = self; provider.action = #selector(providerChanged); stack.addArrangedSubview(provider)
        let auth = NSStackView(views: [button("Continue with ChatGPT", #selector(signIn)), button("Cancel Sign-in", #selector(cancelSignIn)), button("Forget Connection", #selector(forget))]); auth.spacing = 8
        stack.addArrangedSubview(auth); stack.addArrangedSubview(connection)
        apiKey.placeholderString = "OpenAI API key (saved to Keychain)"; apiKey.widthAnchor.constraint(equalToConstant: 370).isActive = true
        let keyRow = NSStackView(views: [apiKey, button("Save Key", #selector(saveKey))]); keyRow.spacing = 8; stack.addArrangedSubview(keyRow)
        model.stringValue = UserDefaults.standard.string(forKey: "agentModelID") ?? ""
        model.placeholderString = "Choose a model after loading your account's catalog"; model.isEditable = true; model.widthAnchor.constraint(equalToConstant: 400).isActive = true
        let models = NSStackView(views: [model, button("Load Models", #selector(loadModels))]); models.spacing = 8; stack.addArrangedSubview(models)
        preset.addItems(withTitles: ["Parallel: three independent flags", "Solo: one flag", "Sequential: three dependent flags"]); stack.addArrangedSubview(preset)
        requestField.widthAnchor.constraint(equalToConstant: 620).isActive = true; stack.addArrangedSubview(requestField)
        run.target = self; run.action = #selector(plan)
        let actions = NSStackView(views: [run, button("Stop & Send Friends Home", #selector(stop))]); actions.spacing = 12; stack.addArrangedSubview(actions)
        status.font = .systemFont(ofSize: 12, weight: .medium); status.widthAnchor.constraint(equalToConstant: 620).isActive = true; stack.addArrangedSubview(status)
        result.isEditable = false; result.font = .systemFont(ofSize: 12); result.textContainerInset = .init(width: 6, height: 6)
        let scroll = NSScrollView(); scroll.documentView = result; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 620).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true; stack.addArrangedSubview(scroll)
        window?.setContentSize(.init(width: 680, height: 720))
        providerChanged()
    }
    private func updateConnection() {
        if let account = credentials.account {
            connection.stringValue = credentials.isSigningIn ? credentials.status : "ChatGPT connected: \(account.email)"
            if provider.indexOfSelectedItem == 0 && status.stringValue.hasPrefix("Ready for an offline") {
                provider.selectItem(at: 1); providerChanged()
                status.stringValue = "ChatGPT is connected. Load Models, choose a vision/tool model, then Plan Survey."
            }
        }
        else { connection.stringValue = credentials.status + (credentials.hasAPIKey ? " · API key saved" : "") }
        connection.textColor = .secondaryLabelColor
    }
    @objc private func providerChanged() { preset.isEnabled = provider.indexOfSelectedItem == 0; model.isEnabled = provider.indexOfSelectedItem != 0 }
    @objc private func signIn() { credentials.signIn() }
    @objc private func cancelSignIn() { credentials.cancelSignIn(); connection.stringValue = "Sign-in cancelled" }
    @objc private func forget() { stop(); credentials.disconnect(); model.removeAllItems(); model.stringValue = "" }
    @objc private func saveKey() {
        do { try credentials.saveAPIKey(apiKey.stringValue); apiKey.stringValue = ""; provider.selectItem(at: 2); providerChanged() }
        catch { connection.stringValue = error.localizedDescription }
    }
    @objc private func loadModels() {
        guard task == nil else { return }
        let source = provider.indexOfSelectedItem
        guard source != 0 else { status.stringValue = "The offline model needs no credentials or model catalog."; return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
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
                status.stringValue = "Loaded \(choices.count) models. Choose one supporting images and tools; Plan Survey verifies access."
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
        stop()
        let id = UUID(); runID = id; acceptedPlan = false
        let source = provider.indexOfSelectedItem, selectedModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), prompt = requestField.stringValue
        let scripted = scriptedPlan()
        if !selectedModel.isEmpty { UserDefaults.standard.set(selectedModel, forKey: "agentModelID") }
        run.isEnabled = false; result.string = ""; status.stringValue = "Planning survey…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.runID == id { self.run.isEnabled = true; self.task = nil } }
            do {
                guard #available(macOS 27.0, *) else { throw AgentConnectionError(message: "The Foundation Models provider prototype needs macOS 27 or later.") }
                guard !prompt.isEmpty else { throw AgentConnectionError(message: "Give the explorer a survey instruction.") }
                guard source == 0 || !selectedModel.isEmpty else { throw AgentConnectionError(message: "Load and select a model first.") }
                let token = source == 0 ? "" : (source == 1 ? try await credentials.accessToken() : try credentials.apiKey())
                let scriptJSON = source == 0 ? String(data: try JSONEncoder().encode(scripted), encoding: .utf8) : nil
                let languageModel = ExplorerLanguageModel(executorConfiguration: .init(model: selectedModel, bearer: token, scriptedPlan: scriptJSON, sessionID: UUID()))
                let tool = AssignSurveyJobsTool { [weak self] plan in
                    guard let self, self.runID == id, !self.acceptedPlan else { throw MissionError.staleRun }
                    self.acceptedPlan = true; self.onPlan?(plan)
                }
                let session = LanguageModelSession(model: languageModel, tools: [tool], instructions: "You direct a little explorer team. The leader is permanent. There are at most two helpers, invited only for independent ready jobs. The picture is the app's synthetic survey card, not the user's desktop. Use assign_survey_jobs exactly once with 1–3 jobs for visible flag IDs blue, amber, purple, using dependsOn only where the user's request requires an ordering. Do not invent completed work. The tool queues work; physical arrival and inspection happen later. No external apps can be operated in this prototype.")
                let image = Self.surveyImage()
                let response = try await session.respond(to: Prompt {
                    prompt
                    Attachment(image)
                })
                try Task.checkCancellation()
                guard self.runID == id else { return }
                self.result.string = response.content
                if !self.acceptedPlan { self.status.stringValue = "The model replied without assigning a survey. No helpers were invited." }
            } catch is CancellationError { }
            catch {
                if self.runID == id { self.status.stringValue = error.localizedDescription }
            }
        }
    }
    @objc func stop() {
        runID = UUID(); task?.cancel(); task = nil; run.isEnabled = true; onStop?()
        status.stringValue = "Stopped. Friends are heading home; the explorer stays."
    }
    func windowWillClose(_ notification: Notification) { stop(); credentials.cancelSignIn() }
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
