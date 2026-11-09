import AppKit
import CryptoKit
import Network
import Security
import LocalAuthentication

@MainActor
final class JOLCredentials {
    struct Account: Codable {
        var manifest: JOLManifest
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var deviceID: UUID
        var deviceCredential: String
    }
    private var listener: NWListener?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Account, Error>?
    private var refresh: Task<String, Error>?
    private var attempt: UUID?
    private var completing = false
    private let service = "com.jerry.jol"
    func load() throws -> Account? {
        var query = keyQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?; let code = AgentCredentials.nonInteractiveKeychain { SecItemCopyMatching(query as CFDictionary, &result) }
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data else { throw JOLError(message: "Unlock Keychain to reconnect Jerry On Line.") }
        return try JSONDecoder().decode(Account.self, from: data)
    }
    private var keyQuery: [String: Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"connection"] }
    func save(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)
        let attributes: [String: Any] = [kSecValueData as String:data,kSecAttrLabel as String:"Jerry — Jerry On Line",kSecAttrDescription as String:"Jerry On Line sign-in and Mac enrollment"]
        let code = SecItemUpdate(keyQuery as CFDictionary, attributes as CFDictionary)
        if code == errSecItemNotFound {
            var insert = keyQuery.merging(attributes) { _, new in new }; insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw JOLError(message: "Couldn’t save the JOL connection in Keychain.") }; return
        }
        guard code == errSecSuccess else { throw JOLError(message: "Couldn’t update the JOL connection in Keychain.") }
    }
    func clear() { cancel(); refresh?.cancel(); refresh = nil; SecItemDelete(keyQuery as CFDictionary) }
    func token() async throws -> String {
        guard let account = try load() else { throw JOLError(message: "Connect Jerry On Line first.") }
        if account.expiresAt.timeIntervalSinceNow > 90 { return account.accessToken }
        if let refresh { return try await refresh.value }
        let pending = Task { @MainActor in
            let response = try await Self.exchange(account.manifest, fields:["grant_type":"refresh_token","refresh_token":account.refreshToken])
            var updated = account; updated.accessToken = response.access_token
            updated.refreshToken = response.refresh_token ?? account.refreshToken
            updated.expiresAt = Date().addingTimeInterval(response.expires_in)
            try Task.checkCancellation(); try self.save(updated); return updated.accessToken
        }
        refresh = pending; defer { refresh = nil }; return try await pending.value
    }
    private struct TokenResponse: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
    private static func exchange(_ manifest: JOLManifest, fields: [String: String]) async throws -> TokenResponse {
        var values = fields; values["client_id"] = manifest.auth.clientID; values["resource"] = manifest.auth.resource
        var request = URLRequest(url: URL(string: manifest.auth.issuer + "/oauth2/token")!); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents(); components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        return try JSONDecoder().decode(TokenResponse.self, from: await JOLHTTP.data(request))
    }
    func cancel() {
        attempt = nil; completing = false; listener?.cancel(); listener = nil; timeout?.cancel(); timeout = nil
        continuation?.resume(throwing: CancellationError()); continuation = nil
    }
    func signIn(_ manifest: JOLManifest) async throws -> Account {
        cancel()
        let state = try AgentCredentials.randomToken(), verifier = try AgentCredentials.randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let id = UUID(); attempt = id
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 49381)
        let listener = try NWListener(using: parameters); self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                continuation = completion
                listener.stateUpdateHandler = { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard let self, self.attempt == id else { return }
                        if case .failed = value { self.fail(JOLError(message: "Jerry’s sign-in port is busy. Close the other sign-in and try again.")); return }
                        guard case .ready = value else { return }
                        var url = URLComponents(string: manifest.origin + "/authorize")!
                        url.queryItems = ["response_type":"code","client_id":manifest.auth.clientID,"redirect_uri":manifest.auth.redirectURI,"scope":"openid offline_access","state":state,"code_challenge":challenge,"code_challenge_method":"S256","resource":manifest.auth.resource].map { URLQueryItem(name: $0.key, value: $0.value) }
                        if !NSWorkspace.shared.open(url.url!) { self.fail(JOLError(message: "Couldn’t open the browser. Try connecting again.")) }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    connection.start(queue: .main)
                    Self.receive(connection, accumulated: Data(), expectedState: state) { [weak self] result in
                        Task { @MainActor [weak self] in
                            guard let self, self.attempt == id, !self.completing else { return }
                            self.completing = true
                            self.listener?.cancel(); self.listener = nil
                            do {
                                let code = try result.get()
                                let response = try await Self.exchange(manifest, fields:["grant_type":"authorization_code","code":code,"code_verifier":verifier,"redirect_uri":manifest.auth.redirectURI])
                                guard let refresh = response.refresh_token, !refresh.isEmpty else { throw JOLError(message: "JOL did not grant background access. Check the server’s OAuth configuration.") }
                                guard self.attempt == id else { return }
                                let account = Account(manifest: manifest, accessToken: response.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(response.expires_in), deviceID: UUID(), deviceCredential: try AgentCredentials.randomToken())
                                let done = self.continuation; self.continuation = nil; self.attempt = nil; self.timeout?.cancel(); done?.resume(returning: account)
                            } catch { self.fail(error) }
                        }
                    }
                }
                listener.start(queue: .main)
                timeout = Task { [weak self] in try? await Task.sleep(for: .seconds(180)); guard !Task.isCancelled else { return }; self?.fail(JOLError(message: "Sign-in timed out. Connect again when you’re ready.")) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    private func fail(_ error: Error) {
        let done = continuation; continuation = nil; cancel(); done?.resume(throwing: error)
    }
    nonisolated private static func receive(_ connection: NWConnection, accumulated: Data, expectedState: String, completion: @escaping @Sendable (Result<String, JOLError>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, ended, error in
            let bytes = accumulated + (data ?? Data())
            guard bytes.count < 16_384, error == nil else { connection.cancel(); return }
            guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                if !ended { Self.receive(connection, accumulated: bytes, expectedState: expectedState, completion: completion) } else { connection.cancel() }; return
            }
            let parts = text.components(separatedBy: "\r\n").first?.components(separatedBy: " ") ?? []
            let url = parts.count > 1 ? URLComponents(string: "http://127.0.0.1" + parts[1]) : nil
            let values = url?.queryItems ?? []
            let code = values.first(where: { $0.name == "code" })?.value
            let expected = parts.first == "GET" && url?.path == "/jol/callback" && values.filter({ $0.name == "state" }).count == 1 && values.first(where: { $0.name == "state" })?.value == expectedState
            let declined = expected && values.contains(where: { $0.name == "error" })
            let valid = expected && !declined && values.filter({ $0.name == "code" }).count == 1 && code?.isEmpty == false
            let body = declined ? "Sign-in cancelled. Jerry is still working locally." : valid ? "Sign-in received. Return to Jerry to see the connection result." : "This sign-in callback did not match. Return to Jerry and try again."
            let response = "HTTP/1.1 \(valid || declined ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
                if declined { completion(.failure(JOLError(message: "Sign-in was declined. Jerry is still working locally."))) }
                else if valid, let code { completion(.success(code)) }
            })
        }
    }
}
