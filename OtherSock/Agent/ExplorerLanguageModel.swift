import AppKit
import FoundationModels
import ImageIO
import UniformTypeIdentifiers
import ExpeditionCore

@available(macOS 27.0, *)
struct ExplorerLanguageModel: LanguageModel {
    struct Configuration: Hashable, Sendable {
        let model: String
        let bearer: String
        let scriptedPlan: String?
        let sessionID: UUID
    }
    let executorConfiguration: Configuration
    var capabilities: LanguageModelCapabilities { .init([.vision, .toolCalling]) }
    typealias Executor = ExplorerModelExecutor
}

@available(macOS 27.0, *)
private actor ExplorerReasoningCache {
    var turns = 0
    var reasoning: [String: Data] = [:]
    func nextTurn() throws -> Int { turns += 1; guard turns <= 160 else { throw AgentConnectionError(message: "The prototype stopped at its 160-turn limit.") }; return turns }
    func save(_ data: Data, for id: String) { reasoning[id] = data }
    func read(_ id: String) -> Data? { reasoning[id] }
}

/// Native Foundation Models provider. The executor runs model networking only;
/// only validated physical computer tools can operate the desktop.
@available(macOS 27.0, *)
struct ExplorerModelExecutor: LanguageModelExecutor {
    typealias Model = ExplorerLanguageModel
    typealias Configuration = ExplorerLanguageModel.Configuration
    private let configuration: Configuration
    private let cache = ExplorerReasoningCache()
    init(configuration: Configuration) throws { self.configuration = configuration }

    func respond(to request: LanguageModelExecutorGenerationRequest, model: Model, streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
        try Task.checkCancellation()
        let turn = try await cache.nextTurn()
        if let scripted = configuration.scriptedPlan {
            // Deterministic transport check, with no external model or task planning.
            if turn == 1 {
                await channel.send(.toolCalls(action: .toolCall(id: "offline-inspect", name: "computer_action", action: .appendArguments(scripted, tokenCount: 0))))
            } else {
                await channel.send(.response(action: .appendText("Offline connection test complete. Choose ChatGPT or an API key in Settings to plan computer tasks.", tokenCount: 0)))
            }
            return
        }
        guard request.schema == nil else { throw AgentConnectionError(message: "This prototype supports text and computer tools, not guided final-response schemas.") }
        var input: [[String: Any]] = []
        for entry in request.transcript {
            switch entry {
            case .instructions(let instructions):
                input.append(["role": "developer", "content": try contents(instructions.segments)])
            case .prompt(let prompt):
                input.append(["role": "user", "content": try contents(prompt.segments)])
            case .response(let response):
                input.append(["role": "assistant", "content": text(response.segments)])
            case .toolCalls(let calls):
                if let first = calls.first, let data = await cache.read(first.id), let reasoning = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] { input += reasoning }
                for call in calls {
                    input.append(["type": "function_call", "call_id": call.id, "name": call.toolName, "namespace": "explorer", "arguments": call.arguments.jsonString])
                }
            case .toolOutput(let output):
                input.append(["type": "function_call_output", "call_id": output.id, "output": try contents(output.segments)])
            case .reasoning: break // Opaque provider reasoning is preserved with its calls.
            default: throw AgentConnectionError(message: "The transcript contains an unsupported attachment or entry.")
            }
        }
        let tools: [[String: Any]] = try request.enabledToolDefinitions.map {
            ["type": "function", "name": $0.name, "description": $0.description, "parameters": try JSONSerialization.jsonObject(with: JSONEncoder().encode($0.parameters))]
        }
        let body: [String: Any] = ["model": configuration.model, "store": false, "stream": true,
                                  "input": input, "include": ["reasoning.encrypted_content"],
                                  "tools": [["type": "namespace", "name": "explorer", "description": "Physically embodied explorer computer tools", "tools": tools]]]
        var http = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        http.httpMethod = "POST"; http.timeoutInterval = 90
        http.setValue("Bearer \(configuration.bearer)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: http)
        guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            // Never echo remote response bodies: they can contain account details.
            throw AgentConnectionError(message: "The model request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check the selected model, connection and account eligibility.")
        }
        var completed = false
        var streamedItems: [[String: Any]] = []
        var events = ResponsesEventStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let data = try events.consume(line) {
                guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                switch event["type"] as? String {
                case "response.output_item.done":
                    if let item = event["item"] as? [String: Any] { streamedItems.append(item) }
                case "response.output_text.delta":
                    if let delta = event["delta"] as? String { await channel.send(.response(action: .appendText(delta, tokenCount: 0))) }
                case "response.completed":
                    guard let response = event["response"] as? [String: Any], let finalOutput = response["output"] as? [[String: Any]] else { throw AgentConnectionError(message: "The model returned an incomplete response.") }
                    // Some streaming hosts omit items from the terminal envelope.
                    // Preserve the completed items delivered earlier in the stream.
                    let output = finalOutput.isEmpty ? streamedItems : finalOutput
                    let calls = output.filter { $0["type"] as? String == "function_call" }
                    guard calls.count <= 1 else { throw AgentConnectionError(message: "The prototype accepts one computer tool call per turn; input actions must be sequential.") }
                    let reasoning = output.filter { $0["type"] as? String == "reasoning" }
                    for call in calls {
                        guard let id = call["call_id"] as? String, let name = call["name"] as? String,
                              request.enabledToolDefinitions.contains(where: { $0.name == name }), let arguments = call["arguments"] as? String else { throw AgentConnectionError(message: "The model requested a tool outside the prototype's scope.") }
                        await cache.save(try JSONSerialization.data(withJSONObject: reasoning), for: id)
                        await channel.send(.toolCalls(action: .toolCall(id: id, name: name, action: .appendArguments(arguments, tokenCount: 0))))
                    }
                    completed = true
                case "error", "response.failed", "response.incomplete":
                    throw AgentConnectionError(message: "The model could not complete this request. No desktop action was performed.")
                default: break
                }
            }
        }
        try events.finish()
        guard completed else { throw AgentConnectionError(message: "The model stream ended before completion.") }
    }
    private func text(_ segments: [Transcript.Segment]) -> String {
        segments.map { switch $0 { case .text(let t): t.content; case .structure(let s): s.content.jsonString; default: "" } }.joined(separator: "\n")
    }
    private func contents(_ segments: [Transcript.Segment]) throws -> [[String: Any]] {
        try segments.map {
            switch $0 {
            case .text(let text): return ["type": "input_text", "text": text.content]
            case .structure(let structure): return ["type": "input_text", "text": structure.content.jsonString]
            case .attachment(let attachment):
                guard case .image(let image) = attachment.content, image.orientation == .up else { throw AgentConnectionError(message: "Only upright image observations are supported in this prototype.") }
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw AgentConnectionError(message: "Could not encode the screen observation.") }
                CGImageDestinationAddImage(destination, image.cgImage, nil)
                guard CGImageDestinationFinalize(destination) else { throw AgentConnectionError(message: "Could not encode the screen observation.") }
                return ["type": "input_image", "image_url": "data:image/png;base64," + (data as Data).base64EncodedString()]
            @unknown default: throw AgentConnectionError(message: "Unsupported observation content.")
            }
        }
    }
}
