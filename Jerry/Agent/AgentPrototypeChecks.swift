#if DEBUG
import AppKit
import FoundationModels
import ExpeditionCore
import Network
import CryptoKit

@MainActor
enum AgentPrototypeChecks {
    static func run() async -> Bool {
        var passed = true
        func check(_ condition: Bool, _ label: String) { print("AGENT \(condition ? "PASS" : "FAIL") \(label)"); fflush(stdout); passed = passed && condition }
        let viewport = WorldRect(x: 0, y: 0, width: 1000, height: 800)
        do {
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
            let history = ExpeditionJournal()
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
            let journal = AgentTaskController()
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
