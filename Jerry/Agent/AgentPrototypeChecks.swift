#if DEBUG
import AppKit
import SpriteKit
import FoundationModels
import ExpeditionCore
import Network
import CryptoKit
import Security

@MainActor
enum AgentPrototypeChecks {
    private static var previewOverlay: OverlayController?
    private static var previewController: AgentTaskController?
    static func showJOLPreview() {
        let controller = AgentTaskController(journalDirectory: nil); previewController = controller
        controller.openSettings(section: "Jerry On Line")
    }
    static func showJournalPreview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jerry-journal-preview-" + UUID().uuidString)
        let journal = ExpeditionJournal(storageDirectory: folder)
        journal.continueExpedition(prompt: "Write a greeting in TextEdit")
        _ = journal.nameExpedition("The Curious Case of Five Little Letters")
        journal.append(.request, "Open TextEdit and write hello.", details: "Request · 13:13\nProvider: preview fixture\n\nThis is a disposable visual sample.\nNo screen content was read.")
        journal.append(.response, "I found TextEdit in Applications. Next, I’ll climb down to a fresh page and leave your greeting there.")
        // A drawn fixture, never a capture of the user's screen.
        let image = NSImage(size: .init(width: 640, height: 300))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 300).fill()
        NSColor(white: 0.94, alpha: 1).setFill(); NSRect(x: 0, y: 260, width: 640, height: 40).fill()
        ("Untitled — TextEdit" as NSString).draw(at: .init(x: 240, y: 273), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.darkGray])
        ("hello" as NSString).draw(at: .init(x: 28, y: 206), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
        let rig = ExplorerRig(); rig.handTargets = (.init(x: -18, y: 75), .init(x: 20, y: 78)); rig.seek(to: 1)
        let scene = SKScene(size: .init(width: 180, height: 160)); scene.backgroundColor = .clear; scene.addChild(rig)
        let view = SKView(frame: .init(x: 0, y: 0, width: 180, height: 160)); view.presentScene(scene)
        if let texture = view.texture(from: rig) {
            NSImage(cgImage: texture.cgImage(), size: texture.size()).draw(in: .init(x: 270, y: 65, width: 100, height: 145))
        }
        image.unlockFocus()
        let jpeg = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
        try await journal.savePhoto(jpeg, caption: "A small greeting, safely on the page.")
        journal.append(.response, "Five letters, one little expedition. I checked the page: “hello” is there in a new document. I’ve left it open for you.")
        journal.append(.request, "Please keep this document open. Next, add a second line saying: Thanks, Jerry!\nThen check both lines before finishing.", details: "Tool request · inspect\n{\"action\": \"inspect\", \"targetID\": \"\"}\n\nTool response\nA disposable visual fixture with a deliberately longer line to check wrapping in the typed details insert, followed by another paragraph.\n\nNo real computer action was performed.")
        journal.flush()
        let controller = AgentTaskController(journalDirectory: folder)
        previewController = controller; controller.showActivity()
        if ProcessInfo.processInfo.arguments.contains("--compact") { controller.debugResizeJournal(width: 360, height: 420, sidebar: false) }
        if ProcessInfo.processInfo.arguments.contains("--wide") { controller.debugResizeJournal(width: 900, height: 650, sidebar: true) }
    }

    static func showLivePhotoPreview() async throws {
        guard #available(macOS 27.0, *), CGPreflightScreenCaptureAccess() else { throw AgentConnectionError(message: "Existing Screen Recording access is required for the live photo fixture. No permission requested.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jerry-live-photo-" + UUID().uuidString)
        let journal = ExpeditionJournal(storageDirectory: folder)
        journal.continueExpedition(prompt: "Photograph Jerry at the fixture window")
        _ = journal.nameExpedition("A Small Summit, A Grand Portrait")
        let overlay = OverlayController(); previewOverlay = overlay
        overlay.setIdleExploration(false); overlay.show(); overlay.beginAgent()
        let computer = ExplorerComputer(); computer.start()
        computer.photoStage = { overlay.setPhotoMoment($0) }; computer.photoSubject = { overlay.photoSubject }
        computer.photograph = { data, caption in try await journal.savePhoto(data, caption: caption) }
        try await Task.sleep(for: .milliseconds(500))
        _ = try await computer.execute(action: "take_photo", targetID: "", text: "One for the journal — Jerry at the fixture window.", x: 0, y: 0, amount: 0)
        journal.flush()
        guard let photo = journal.entries.first(where: { $0.photo != nil }), let url = journal.photoURL(for: photo) else { throw AgentConnectionError(message: "The live photo fixture did not produce a photograph.") }
        print("LIVE PHOTO", url.path); fflush(stdout)
        let controller = AgentTaskController(journalDirectory: folder); previewController = controller; controller.showActivity()
    }

    private static func checkJOL() async throws -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Jerry-JOL-Checks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let journals = temporary.appendingPathComponent("Expeditions")
        let id = UUID(), row = UUID(), header = JournalRecord.Header(id: id, date: Date(), title: "The Paper Mountain")
        let store = ExpeditionJournalStore(directory: journals) { _ in }
        store.append(.init(event: .created, expedition: header), to: id)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 240, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let photograph = bitmap.representation(using: .jpeg, properties: [:])!
        let filename = try await store.savePhoto(photograph, to: id)
        let entry = ExpeditionJournal.Entry(id: row, date: Date(), kind: .response, text: "I reached the ridge.", details: "Private screen text", photo: filename)
        store.append(.init(event: .entry, entry: entry), to: id)
        store.append(.init(event: .detailsAppended, entryID: row, text: "More screen text"), to: id)
        store.flush()
        let sync = try JOLSyncStore(journals: journals, directory: temporary.appendingPathComponent("Sync"), since: Date.distantPast, includeHistory: false, details: false, photos: false)
        let batch = try await sync.nextBatches().first!
        checks.append(("JOL reads committed journal records in order", batch.start == 1 && batch.records.count == 3 && batch.records.first?.event == .created))
        checks.append(("JOL removes nested technical details and photograph references before upload", batch.records[1].entry?.details == "" && batch.records[1].entry?.photo == nil && batch.records[2].event == .redacted))
        checks.append(("JOL retry preserves transport event IDs", try await sync.nextBatches().first?.records.map(\.id) == batch.records.map(\.id)))
        try await sync.acknowledge(batch, cursor: 3)
        let restored = try JOLSyncStore(journals: journals, directory: temporary.appendingPathComponent("Sync"), since: .distantPast, includeHistory: false, details: false, photos: false)
        checks.append(("JOL accepted cursor survives restarting without replay", try await restored.nextBatches().isEmpty))
        checks.append(("JOL keeps saved photographs local until explicitly shared", try await restored.nextPhotos().isEmpty))
        await restored.enablePhotos()
        let photos = try await restored.nextPhotos()
        checks.append(("JOL finds an existing photograph and the acknowledged entry it belongs to",
                       photos.count == 1 && photos.first?.entryID == row && photos.first?.data == photograph))
        if let photo = photos.first { try await restored.acknowledgePhoto(photo) }
        let future = try JOLSyncStore(journals: journals, directory: temporary.appendingPathComponent("Future"), since: Date().addingTimeInterval(10), includeHistory: false, details: false, photos: false)
        checks.append(("JOL does not upload old journals without history opt-in", try await future.nextBatches().isEmpty))
        await future.enableHistory()
        checks.append(("JOL can add older expeditions on the same connection", try await future.nextBatches().first?.expeditionID == id))
        await restored.enableDetails()
        let details = try await restored.nextDetails()
        checks.append(("JOL backfills only previously acknowledged details after opt-in",
                       details.first?.changes.map(\.sequence) == [2, 3] && details.first?.through == 3))
        if let first = details.first { try await restored.acknowledgeDetails(first) }
        let enriched = try JOLSyncStore(journals: journals, directory: temporary.appendingPathComponent("Sync"),
                                        since: .distantPast, includeHistory: false, details: false, photos: false, backfillDetails: true, backfillPhotos: true)
        checks.append(("JOL preserves the details cursor across restart", try await enriched.nextDetails().isEmpty))
        checks.append(("JOL does not re-upload an acknowledged photograph after restart", try await enriched.nextPhotos().isEmpty))
        let file = journals.appendingPathComponent(id.uuidString).appendingPathComponent("journal.jsonl")
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"incomplete\":".utf8)); try handle.close()
        checks.append(("JOL never uploads an uncommitted partial last line", try await restored.nextBatches().isEmpty))
        try await restored.rememberCommand(id, status: "started")
        let receipts = try JOLSyncStore(journals: journals, directory: temporary.appendingPathComponent("Sync"), since: .distantPast, includeHistory: false, details: false, photos: false)
        checks.append(("JOL persists accepted command IDs to prevent action replay", await receipts.priorCommand(id) == "started"))
        checks.append(("JOL accepts an HTTPS origin", (try? JOLManifest.serverURL("https://jol.example.com/"))?.absoluteString == "https://jol.example.com"))
        checks.append(("JOL rejects credentials, paths and insecure server addresses", ["http://jol.example.com", "https://a:b@jol.example.com", "https://jol.example.com/other", "https://jol.example.com?token=secret"].allSatisfy { (try? JOLManifest.serverURL($0)) == nil }))
        let offline = JOLController(journalDirectory: nil)
        checks.append(("JOL is disconnected and remote missions disabled by default", !offline.connected && !offline.remoteArmed))
        return checks
    }
    private static func checkCredentialLabels() throws -> [(String, Bool)] {
        // Exercise actual Keychain metadata with disposable, non-secret records.
        // The production namespace and real account credentials are never used.
        let service = "com.jerry.tests.credentials.\(UUID().uuidString)"
        func query(_ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        }
        defer { for name in ["api-key", "chatgpt"] { SecItemDelete(query(name) as CFDictionary) } }
        let account = AgentCredentials.Account(clientID: "test-client", subject: "test-subject", email: "test@example.invalid", accessToken: "not-a-real-token", refreshToken: "not-a-real-refresh-token", idToken: "", expiresAt: .distantFuture, scopes: [])
        for (name, data) in [("api-key", Data("not-a-real-api-key".utf8)), ("chatgpt", try JSONEncoder().encode(account))] {
            var item = query(name)
            item[kSecValueData as String] = data; item[kSecAttrLabel as String] = "The Other Sock"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AgentConnectionError(message: "Could not create disposable Keychain check item.") }
        }
        func label(_ name: String) -> String? {
            var q = query(name); q[kSecReturnAttributes as String] = true
            q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
            return (item as? [String: Any])?[kSecAttrLabel as String] as? String
        }
        let credentials = AgentCredentials(service: service)
        let preserved = try credentials.apiKey() == "not-a-real-api-key" && credentials.account?.clientID == account.clientID
        var checks = [("legacy Keychain labels become Jerry without changing saved API keys or ChatGPT accounts", preserved && label("api-key") == "Jerry — API key" && label("chatgpt") == "Jerry — ChatGPT")]
        credentials.removeAPIKey(); try credentials.saveAPIKey("new-test-key")
        checks.append(("new Keychain entries use Jerry labels", label("api-key") == "Jerry — API key"))
        try credentials.saveAPIKey("updated-test-key")
        checks.append(("updating a saved key preserves Jerry labels and the other connection", try credentials.apiKey() == "updated-test-key" && label("api-key") == "Jerry — API key" && credentials.account?.clientID == account.clientID))
        return checks
    }
    private static func checkJournalPersistence() async throws -> [(String, Bool)] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jerry-journal-check-\(UUID().uuidString)", isDirectory: true)
        var journals: [ExpeditionJournal] = []
        defer { journals.forEach { $0.flush() }; try? FileManager.default.removeItem(at: root) }
        func journal(_ directory: URL) -> ExpeditionJournal {
            let model = ExpeditionJournal(storageDirectory: directory); journals.append(model); return model
        }
        func appendBytes(_ data: Data, to url: URL) throws {
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data); try file.synchronize()
        }
        let original = journal(root)
        let first = original.continueExpedition(prompt: "Find a patterned sock")
        let request = original.append(.request, "Find a patterned sock")
        let response = original.append(.response, "")
        var streamed = ""
        for chunk in ["Hello", " 👩🏽‍🚀", " — café", "\nOne small discovery."] { streamed += chunk; original.update(response, text: streamed) }
        let corrected = "A corrected note 👩🏽‍🚀\nThe sock has stripes."
        original.update(response, text: corrected)
        original.addDetails(response, "Tool metadata"); original.addDetails(response, "A later result")
        original.status = "Inspecting the window…"; original.isRunning = true; original.flush()
        let file = root.appendingPathComponent(first.uuidString).appendingPathComponent("journal.jsonl")
        let lines = try Data(contentsOf: file).split(separator: 10)
        let objects = try lines.map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
        var checks = [("an expedition gets its own folder containing only a versioned JSONL journal", try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["journal.jsonl"] && objects.allSatisfy { $0["version"] as? Int == 1 } && objects.contains { $0["event"] as? String == "textAppended" })]
        checks.append(("new expeditions wait for an AI name instead of copying the prompt", original.selected?.title == "An untitled adventure"))
        let rejectsCopiedPrompt = !original.nameExpedition("Find a patterned sock")
        let named = original.nameExpedition("The Striped Sock Summit")
        original.flush()
        checks.append(("an AI expedition name persists and follow-up prompts do not rename it", named && rejectsCopiedPrompt && !original.nameExpedition("A second name") && journal(root).selected?.title == "The Striped Sock Summit"))
        let restored = journal(root)
        checks.append(("journal restart restores IDs, Unicode messages and expandable details", restored.activeID == first && restored.entries.first?.id == request && restored.entries.first { $0.id == response }?.text == corrected && restored.entries.first { $0.id == response }?.details == "Tool metadata\n\nA later result"))
        checks.append(("a running expedition restores paused without restarting computer actions", !restored.isRunning && restored.selected?.status.contains("Paused after restarting") == true && restored.selected?.isFinished == false))
        restored.flush()
        let duplicate = lines.first { line in (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])?["event"] as? String == "textAppended" }!
        try appendBytes(Data(duplicate) + Data([10]), to: file)
        let deduplicated = journal(root)
        checks.append(("retrying a previously appended event cannot duplicate streamed text", deduplicated.entries.first { $0.id == response }?.text == corrected))
        try appendBytes(Data("{\"version\":1,\"event\":\"entry\"".utf8), to: file)
        let recovered = journal(root)
        checks.append(("a truncated final record preserves complete notes and reports recovery", recovered.entries.first { $0.id == response }?.text == corrected && recovered.storageIssue != nil))
        recovered.append(.activity, "Recovered after an interrupted write"); recovered.flush()
        let continued = journal(root)
        checks.append(("new notes remain readable after an interrupted JSONL tail", continued.entries.contains { $0.text == "Recovered after an interrupted write" }))
        continued.finishActive()
        let second = continued.continueExpedition(prompt: "A second expedition")
        continued.append(.request, "Keep this mission separate"); continued.finishActive()
        let separate = journal(root)
        checks.append(("finished expeditions restore separately with their completion state", separate.expeditions.count == 2 && separate.activeID == nil && separate.expeditions.allSatisfy(\.isFinished) && separate.exportText().contains("Keep this mission separate")))
        separate.continueExpedition(prompt: "A follow-up direction", id: first)
        separate.append(.request, "A follow-up direction"); separate.flush()
        let resumed = journal(root)
        checks.append(("an earlier expedition remains open and resumable after another restart", resumed.activeID == first && resumed.selectedID == first && resumed.entries.last?.text == "A follow-up direction" && resumed.expeditions.first { $0.id == second }?.isFinished == true))
        // Photos share the expedition directory; old entries without photo metadata still decode.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 240, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        try await resumed.savePhoto(jpeg, caption: "I found the result.")
        resumed.flush()
        let album = journal(root)
        let photo = album.entries.first { $0.photo != nil }!
        let photoURL = album.photoURL(for: photo)!
        checks.append(("local photographs round-trip as assets beside their expedition notes", try Data(contentsOf: photoURL) == jpeg && NSImage(contentsOf: photoURL) != nil && photo.text == "I found the result." && album.exportText().contains(photo.photo!)))
        var invalidPhoto = photo; invalidPhoto.photo = "../../outside.jpg"
        checks.append(("journal photograph paths reject traversal", album.photoURL(for: invalidPhoto) == nil))
        try FileManager.default.removeItem(at: photoURL)
        checks.append(("a missing photograph preserves its caption and journal history", album.photoURL(for: photo) == nil && journal(root).entries.contains { $0.id == photo.id && $0.text == photo.text }))
        let controller = AgentTaskController(journalDirectory: root)
        checks.append(("the journal window restores an open expedition with Finish available and no running task", controller.debugCheckRestoredJournal(id: first, text: "A follow-up direction")))
        resumed.append(.activity, "Saved automatically")
        var automatic = false
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            let snapshot = ExpeditionJournalStore(directory: root, report: { _ in }).restore()
            automatic = snapshot.expeditions.contains { $0.entries.contains { $0.text == "Saved automatically" } }
            if automatic { break }
        }
        checks.append(("batched journal records save automatically without an explicit flush", automatic))
        let futureID = UUID(), futureFolder = root.appendingPathComponent(futureID.uuidString)
        try FileManager.default.createDirectory(at: futureFolder, withIntermediateDirectories: true)
        var future = JournalRecord(event: .created, expedition: .init(id: futureID, date: Date(), title: "Newer format")); future.version = 2
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let futureBytes = try encoder.encode(future) + Data([10])
        let futureFile = futureFolder.appendingPathComponent("journal.jsonl"); try futureBytes.write(to: futureFile)
        let unsupported = journal(root); unsupported.flush()
        checks.append(("newer journal formats stay untouched and do not hide readable expeditions", try unsupported.expeditions.count == 2 && unsupported.storageIssue != nil && Data(contentsOf: futureFile) == futureBytes))
        let asset = file.deletingLastPathComponent().appendingPathComponent("future-asset.txt")
        try Data("Future asset fixture".utf8).write(to: asset)
        let withAssets = journal(root)
        checks.append(("unrelated future assets in an expedition folder are preserved", try withAssets.expeditions.count == 2 && String(contentsOf: asset, encoding: .utf8) == "Future asset fixture"))
        let blocked = root.appendingPathComponent("blocked-storage")
        let failed = journal(blocked) // Create the obstruction after a clean initial read.
        try Data("obstruction".utf8).write(to: blocked)
        failed.continueExpedition(prompt: "Survive a save failure"); failed.append(.request, "Keep this unsaved note"); failed.flush()
        try await Task.sleep(for: .milliseconds(20))
        checks.append(("save failures are visible while retaining the journal in memory", failed.saveFailed && failed.storageIssue != nil && failed.entries.first?.text == "Keep this unsaved note"))
        try FileManager.default.removeItem(at: blocked)
        failed.retrySaving(); failed.flush()
        try await Task.sleep(for: .milliseconds(20))
        let retried = journal(blocked)
        checks.append(("retry saves retained records after a filesystem failure is fixed", !failed.saveFailed && failed.storageIssue == nil && retried.entries.first?.text == "Keep this unsaved note"))
        return checks
    }

    static func run() async -> Bool {
        var passed = true
        func check(_ condition: Bool, _ label: String) { print("AGENT \(condition ? "PASS" : "FAIL") \(label)"); fflush(stdout); passed = passed && condition }
        let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
        do {
            for (name, result) in try await checkJOL() { check(result, name) }
            for (name, result) in try await checkJournalPersistence() { check(result, name) }
            for (name, result) in try checkCredentialLabels() { check(result, name) }
            if #available(macOS 27.0, *) {
                var calls = 0
                let scripted = #"{"action":"inspect","targetID":"","text":"","x":0,"y":0,"amount":0}"#
                let model = ExplorerLanguageModel(executorConfiguration: .init(model: "scripted", bearer: "", scriptedPlan: scripted, sessionID: UUID()))
                let tool = ExplorerComputerTool { args in calls += 1; return Prompt("Computer tool received \(args.action). No input is injected by this test.") }
                let session = LanguageModelSession(model: model, tools: [tool], instructions: "Test the native computer tool loop.")
                var response = "", hasSnapshotResponse = false
                for try await partial in session.streamResponse(to: "Inspect the active app.") {
                    response = partial.content
                    hasSnapshotResponse = hasSnapshotResponse || partial.transcriptEntries.contains { if case .response = $0 { return true }; return false }
                }
                check(hasSnapshotResponse, "stream snapshots expose response entries for the full journal")
                check(calls == 1 && response.contains("Offline"), "Foundation Models invokes the computer tool and streams its final response")
                let outputCount = session.transcript.filter { if case .toolOutput = $0 { return true }; return false }.count
                check(outputCount == 1, "native computer tool output is included exactly once")
                let continued = LanguageModelSession(model: model, tools: [tool], transcript: AgentTaskController.continuableTranscript(session.transcript))
                for try await _ in continued.streamResponse(to: "Continue the same expedition with a second direction.") { }
                let prompts = continued.transcript.compactMap { entry -> String? in
                    if case .prompt(let prompt) = entry { return prompt.segments.compactMap { if case .text(let text) = $0 { return text.content }; return nil }.joined() }
                    return nil
                }
                check(prompts.count == 2 && prompts.first?.contains("Inspect the active app.") == true && prompts.last?.contains("second direction") == true, "continuing a native model session retains the first request and the new direction")
                let interrupted = Transcript(entries: session.transcript.filter { if case .toolOutput = $0 { return false }; return true })
                let repaired = AgentTaskController.continuableTranscript(interrupted)
                check(!repaired.contains { if case .toolCalls = $0 { return true }; return false }, "interrupted transcript repair removes tool calls without results before continuing")
                let image = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
                var pictured = session.transcript
                for index in pictured.indices {
                    if case .toolOutput(var output) = pictured[index] {
                        output.segments.append(.attachment(.init(content: .image(.init(image)))))
                        pictured[index] = .toolOutput(output)
                    }
                }
                func hasImages(_ transcript: Transcript) -> Bool {
                    transcript.contains { entry in
                        if case .toolOutput(let output) = entry { return output.segments.contains { if case .attachment = $0 { return true }; return false } }
                        return false
                    }
                }
                check(!hasImages(AgentTaskController.continuableTranscript(pictured, includeImages: false)), "continuation removes previous screen images when sharing is off")
                check(hasImages(AgentTaskController.continuableTranscript(pictured, includeImages: true)), "continuation retains screen context only with image sharing enabled")
                let definition = Transcript.ToolDefinition(tool: tool)
                let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.parameters)) as? [String: Any]
                check(schema?["type"] as? String == "object", "computer tool schemas encode to JSON Schema")
            } else { check(false, "macOS 27 Foundation Models provider availability") }
            let scene = ExplorerScene(size: .init(width: 1000, height: 800))
            check(scene.children.filter { $0 is ExplorerRig }.count == 1, "the scene contains one explorer and no recruitment system")
            scene.layout(in: .init(x: 0, y: 90, width: 1000, height: 710))
            scene.updateTerrain(.init(windows: [], viewport: viewport))
            scene.setAgentMode(true); scene.agentTarget = .init(x: 500, y: 1)
            for frame in 0..<900 {
                if frame == 600 {
                    scene.layout(in: .init(x: 0, y: 110, width: 1000, height: 690))
                    scene.updateTerrain(.init(windows: [], viewport: viewport))
                }
                scene.update(Double(frame) / 30)
            }
            check(scene.agentAtTarget, "the rendered hand reaches the Dock reveal edge after visible-frame changes")
            scene.setAgentMode(false)
            let spottingScene = ExplorerScene(size: .init(width: 1000, height: 800))
            spottingScene.layout(in: .init(x: 0, y: 0, width: 1000, height: 800))
            spottingScene.updateTerrain(.init(windows: [], viewport: viewport)); spottingScene.setIdleExploration(true)
            let spottingRig = spottingScene.children.compactMap { $0 as? ExplorerRig }.first!
            var tick = 0
            while tick < 900 && !spottingRig.usingBinoculars { spottingScene.update(Double(tick) / 60); tick += 1 }
            let sharedBinoculars = spottingRig.childNode(withName: "//binoculars")
            check(spottingRig.usingBinoculars && sharedBinoculars?.isHidden == false, "idle sock spotting uses the explorer's head-mounted binoculars")
            spottingScene.setAgentMode(true); spottingScene.agentReading = true; spottingScene.update(Double(tick + 1) / 60)
            check(spottingRig.childNode(withName: "//binoculars") === sharedBinoculars && sharedBinoculars?.isHidden == false && spottingRig.clampedContacts == 0, "AI reading uses the same binoculars and reachable two-hand grip")
            spottingScene.agentReading = false; spottingScene.update(Double(tick + 2) / 60)
            check(sharedBinoculars?.isHidden == true, "finishing screen reading puts the binoculars away")
            let keyboardFrame = CGRect(x: 100, y: 400, width: 600, height: 200)
            let keyboard = ExplorerComputer.VisibleWindow(pid: 101, frame: keyboardFrame, alpha: 1)
            check(ExplorerComputer.visibleWindow(keyboardFrame, pid: 101, in: [keyboard]), "a visible keyboard window matches its AX geometry")
            check(!ExplorerComputer.visibleWindow(keyboardFrame, pid: 101, in: []), "remembered AX keyboard geometry is rejected when its window is hidden")
            check(!ExplorerComputer.visibleWindow(keyboardFrame, pid: 102, in: [keyboard]), "another running keyboard process cannot borrow a visible window")
            check(!ExplorerComputer.visibleWindow(keyboardFrame, pid: 101, in: [.init(pid: 101, frame: keyboardFrame, alpha: 0)]), "a transparent keyboard window is not visible")
            check(!ExplorerComputer.visibleWindow(keyboardFrame.offsetBy(dx: 800, dy: 0), pid: 101, in: [keyboard]), "stale key-window positions do not match a moved keyboard")
            let keyPoint = CGPoint(x: 300, y: 450)
            let covering = ExplorerComputer.VisibleWindow(pid: 202, frame: keyboardFrame, alpha: 1)
            check(!ExplorerComputer.windowIsFrontmost(at: keyPoint, pid: 101, ignoring: 303, in: [covering, keyboard]), "covered keyboard keys cannot receive physical presses")
            check(ExplorerComputer.windowIsFrontmost(at: keyPoint, pid: 101, ignoring: 202, in: [covering, keyboard]), "only the explorer's own withdrawn overlay is ignored")
            let suite = "JerryPermissionChecks." + UUID().uuidString
            let permissionDefaults = UserDefaults(suiteName: suite)!
            defer { permissionDefaults.removePersistentDomain(forName: suite) }
            let denied = DesktopAccess.Snapshot(accessibility: false, screenRecording: false)
            check(DesktopAccess.needed(for: denied, defaults: permissionDefaults).isEmpty, "a fresh install does not demand optional desktop permissions")
            permissionDefaults.set(true, forKey: "exploreInsideWindows")
            check(DesktopAccess.needed(for: denied, defaults: permissionDefaults) == [.screenRecording], "enabled internal ledges identify missing Screen Recording at startup")
            permissionDefaults.set("configured-model", forKey: "agentModelID")
            check(DesktopAccess.needed(for: denied, defaults: permissionDefaults) == [.accessibility, .screenRecording], "configured desktop tasks and terrain identify both missing grants")
            check(DesktopAccess.needed(for: .init(accessibility: true, screenRecording: true), defaults: permissionDefaults).isEmpty, "valid macOS grants do not trigger startup repair")
            permissionDefaults.removeObject(forKey: "agentModelID"); permissionDefaults.set(false, forKey: "exploreInsideWindows")
            permissionDefaults.set(true, forKey: "desktopAccessibilityGranted")
            check(DesktopAccess.needed(for: denied, defaults: permissionDefaults) == [.accessibility], "a lost previous Accessibility grant is detected after an app change")
            let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
            let helperSize = CGSize(width: 380, height: 510)
            let settingsFrame = CGRect(x: 200, y: 80, width: 700, height: 760)
            let right = DesktopAccess.setupFrame(size: helperSize, beside: settingsFrame, in: screen)
            check(right != nil && !right!.intersects(settingsFrame) && screen.contains(right!), "access helper fits beside Settings without covering its controls")
            let shifted = settingsFrame.offsetBy(dx: 400, dy: 0)
            let left = DesktopAccess.setupFrame(size: helperSize, beside: shifted, in: screen)
            check(left != nil && left!.maxX < shifted.minX, "access helper can use the left side without clamping onto Settings")
            check(DesktopAccess.setupFrame(size: helperSize, beside: .init(x: 100, y: 40, width: 1240, height: 820), in: screen) == nil, "no side space leaves the helper in place instead of overlapping Settings")
            let drag = JerryApplicationDragView()
            let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
            board.writeObjects([drag.applicationURL as NSURL])
            let dragged = (board.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
            check(dragged == Bundle.main.bundleURL && dragged?.pathExtension == "app", "permission drag exports the exact running app as a file URL")
            let history = ExpeditionJournal(storageDirectory: nil)
            let first = history.continueExpedition(prompt: "First expedition")
            history.append(.request, "First expedition")
            let response = history.append(.response, "First reply")
            history.isRunning = false
            check(history.continueExpedition(prompt: "A follow-up") == first && history.expeditions.count == 1, "an expedition stays open between replies and follow-ups reuse it")
            history.append(.request, "A follow-up")
            history.prepareNew()
            check(history.activeID == nil && history.selectedID == nil, "finishing or preparing a new expedition leaves no active conversation")
            let second = history.continueExpedition(prompt: "Second expedition")
            history.append(.request, "Second expedition"); history.select(first)
            history.append(.activity, "Second expedition progress")
            history.update(response, text: "Updated first reply")
            check(history.entries.contains { $0.text == "Updated first reply" } && !history.entries.contains { $0.text == "Second expedition progress" }, "browsing an older expedition cannot redirect live progress or response updates")
            check(history.expeditions.first { $0.id == second }?.entries.contains { $0.text == "Second expedition progress" } == true, "live entries remain attached to the active expedition")
            check(history.continueExpedition(prompt: "Resume the first", id: first) == first && history.activeID == first && history.expeditions.count == 2, "a selected earlier expedition can be resumed without merging histories")
            history.finishActive()
            let third = history.continueExpedition(prompt: "Third expedition")
            check(third != first && third != second && history.expeditions.count == 3 && history.exportText().contains("Second expedition"), "a prompt after finishing creates a new expedition and export retains all histories")
            let journal = AgentTaskController(journalDirectory: nil)
            for (name, passed) in journal.debugCheckSettings() { check(passed, name) }
            check(await journal.debugCheckJournalFocus(), "showing and automatically focusing the journal cannot pause an expedition")
            check(await journal.debugCheckTrafficLights(), "native traffic lights stay inside the paper margin after toolbar layout and resizing")
            check(journal.debugCheckLogIsolation(), "late progress from a cancelled execution cannot create or change an expedition")
            let journalChecks = journal.debugCheckJournal()
            check(journalChecks.0, "streaming Unicode response updates preserve subsequent tool log entries")
            check(journalChecks.1, "the journal preserves requests across tasks")
            check(journalChecks.2, "human journal entries keep tool output and metadata inside details")
            journal.closeAll()
            let verifier = try AgentCredentials.randomToken()
            let otherVerifier = try AgentCredentials.randomToken()
            check(verifier.count == 43 && verifier != otherVerifier, "OAuth attempts use independent random PKCE values")
            let challenge = Data(SHA256.hash(data: Data("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk".utf8))).base64URL
            check(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE matches the RFC S256 test vector")
        } catch { check(false, "prototype round trip: \(error.localizedDescription)") }
        return passed
    }
}
#endif
