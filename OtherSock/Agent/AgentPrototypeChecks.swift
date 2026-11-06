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
        let team = MissionTeamNode()
        team.updateTerrain(.init(windows: [], viewport: viewport), usable: .init(x: 0, y: -2, width: 1000, height: 802))
        let parallel = SurveyPlan(jobs: ["blue", "amber", "purple"].map { .init(marker: $0, instruction: "Inspect") })
        do {
            try team.start(.init(jobs: [.init(marker: "blue", instruction: "Inspect")]))
            check(team.debugVisibleMembers == 1, "a single job keeps only the original explorer")
            try team.start(parallel)
            check(team.debugVisibleMembers == 3, "independent jobs invite two rendered companions")
            var minimumMembers = 3
            for _ in 0..<250 { team.advance(by: 0.1, leader: .init(x: 500, y: 0), leaderReady: true); minimumMembers = min(minimumMembers, team.debugVisibleMembers) }
            check(team.debugMissionComplete && team.debugVisibleMembers == 1 && minimumMembers >= 1, "helpers arrive, inspect with binoculars and leave; leader remains")
            try team.start(.init(jobs: [.init(marker: "blue", instruction: "First"), .init(marker: "amber", instruction: "Next", dependsOn: ["blue"])]))
            var remainedSolo = true
            for _ in 0..<50 { team.advance(by: 0.1, leader: .init(x: 500, y: 0), leaderReady: true); remainedSolo = remainedSolo && team.debugVisibleMembers == 1 }
            check(remainedSolo && team.debugMissionComplete, "dependent jobs never invite spare helpers")
            try team.start(parallel); team.stop()
            for _ in 0..<100 { team.advance(by: 0.1, leader: .init(x: 500, y: 0), leaderReady: true) }
            check(team.debugVisibleMembers == 1, "stop retires helpers without removing the leader")
            if #available(macOS 27.0, *) {
                var accepted: SurveyPlan?
                let model = ExplorerLanguageModel(executorConfiguration: .init(model: "scripted", bearer: "", scriptedPlan: String(data: try JSONEncoder().encode(parallel), encoding: .utf8), sessionID: UUID()))
                let tool = AssignSurveyJobsTool { accepted = $0 }
                let session = LanguageModelSession(model: model, tools: [tool], instructions: "Inspect the synthetic image and queue survey jobs.")
                var response = ""
                for try await partial in session.streamResponse(to: Prompt { "Inspect all three flags."; Attachment(AgentTaskController.surveyImage()) }) { response = partial.content }
                check(accepted == parallel && response.contains("queued"), "Foundation Models image, custom provider, tool call, result and streamed final response round trip")
                let outputCount = session.transcript.filter { if case .toolOutput = $0 { return true }; return false }.count
                check(outputCount == 1, "native tool output is included exactly once")
                let definition = Transcript.ToolDefinition(tool: tool)
                let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.parameters)) as? [String: Any]
                check(schema?["type"] as? String == "object", "native tool schemas encode to JSON Schema for Responses")
            } else { check(false, "macOS 27 Foundation Models provider availability") }
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
