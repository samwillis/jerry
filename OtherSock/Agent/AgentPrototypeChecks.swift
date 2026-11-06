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
            let journal = AgentTaskController()
            for (name, passed) in journal.debugCheckSettings() { check(passed, name) }
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
