import Foundation

struct JOLError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
struct JOLManifest: Codable, Sendable {
    struct Auth: Codable, Sendable { let issuer: String; let clientID: String; let resource: String; let redirectURI: String }
    struct Capabilities: Codable, Sendable {
        let journal: Bool
        let commands: Bool
        let photos: Bool
        let realtime: Bool
        var detailsBackfill: Bool? = nil
        var photosBackfill: Bool? = nil
    }
    let version: Int
    let instanceID: String
    let name: String
    let origin: String
    let auth: Auth
    let capabilities: Capabilities
    func validate(for server: URL) throws {
        guard version == 1, UUID(uuidString: instanceID) != nil, origin == server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let issuer = URL(string: auth.issuer), issuer.scheme == "https", issuer.user == nil, issuer.password == nil,
              auth.resource == origin + "/api", !auth.clientID.isEmpty,
              auth.redirectURI == "http://127.0.0.1:49381/jol/callback" else {
            throw JOLError(message: "This server doesn’t offer a compatible Jerry On Line connection.")
        }
    }
    static func serverURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw JOLError(message: "Enter your JOL server’s HTTPS address, such as https://jol.example.com.")
        }
        return URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }
}
struct JOLCommand: Codable, Sendable {
    let id: UUID
    let kind: String
    let prompt: String
    let expedition_id: UUID?
    let fence: Int
}
struct JOLCommandResult: Sendable { let status: String; let message: String }

/// Reject redirects rather than allowing a chosen server to move bearer credentials.
private final class JOLRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
enum JOLHTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: JOLRedirectPolicy(), delegateQueue: nil)
    }()
    static func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JOLError(message: "JOL didn’t respond.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if message?["error"] as? String == "invalid_grant" { throw JOLError(message: "Your JOL sign-in expired. Disconnect and connect again.") }
            throw JOLError(message: String((message?["error"] as? String ?? "JOL connection failed (\(http.statusCode)).").prefix(250)))
        }
        guard data.count <= 8_000_000 else { throw JOLError(message: "The JOL response was too large.") }
        return data
    }
}
