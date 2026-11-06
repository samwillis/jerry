import Foundation

/// URLSession.AsyncBytes.lines may omit empty lines. OpenAI sends one JSON object
/// per data line; dispatch complete JSON without relying on a blank separator.
/// Also accepts multi-line data records. Never includes raw payload in errors.
public struct ResponsesEventStream: Sendable {
    private var pending: [String] = []
    private var size = 0
    public init() {}
    public mutating func consume(_ line: String) throws -> Data? {
        size += line.utf8.count
        guard size < 4_000_000 else { throw StreamError.limit }
        guard line.hasPrefix("data:") else { return nil }
        let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if value == "[DONE]" { guard pending.isEmpty else { throw StreamError.invalid }; return nil }
        pending.append(value)
        let data = Data(pending.joined(separator: "\n").utf8)
        guard data.count < 2_000_000 else { throw StreamError.limit }
        if (try? JSONSerialization.jsonObject(with: data)) != nil { pending = []; return data }
        return nil
    }
    public func finish() throws { if !pending.isEmpty { throw StreamError.invalid } }
    public enum StreamError: Error, LocalizedError {
        case invalid, limit
        public var errorDescription: String? { self == .limit ? "The model stream exceeded the prototype's size limit." : "The model stream contained an incomplete event." }
    }
}
