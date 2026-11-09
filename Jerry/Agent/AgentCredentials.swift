import AppKit
import CryptoKit
import Network
import Security
import LocalAuthentication

struct AgentConnectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// App-owned credentials only. Never reads Codex/OpenCode/browser credential stores.
@MainActor
final class AgentCredentials {
    struct Account: Codable {
        var clientID: String
        var subject: String
        var email: String
        var accessToken: String
        var refreshToken: String
        var idToken: String
        var expiresAt: Date
        var scopes: [String]
    }
    // Persistent Keychain namespace: preserve saved connections across app renames.
    private let service: String
    private var labelledAccounts: Set<String> = []
    init(service: String = "com.othersock.desktop.agent") { self.service = service }
    private var listener: NWListener?
    private var loginTimeout: Task<Void, Never>?
    private var attempt: UUID?
    private var refreshTask: Task<String, Error>?
    var onChange: (() -> Void)?
    private(set) var status = "Not connected"
    var account: Account? { guard let data = try? read("chatgpt") else { return nil }; return try? JSONDecoder().decode(Account.self, from: data) }
    var hasAPIKey: Bool { ((try? read("api-key"))?.isEmpty == false) }
    var isSigningIn: Bool { attempt != nil }

    func saveAPIKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentConnectionError(message: "Enter an API key first.") }
        try save(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8), as: "api-key")
        status = "API key saved in Keychain"; onChange?()
    }
    func apiKey() throws -> String {
        guard let data = try read("api-key"), let key = String(data: data, encoding: .utf8) else { throw AgentConnectionError(message: "Add an API key or continue with ChatGPT.") }
        return key
    }
    func disconnectChatGPT() {
        cancelSignIn(); refreshTask?.cancel(); refreshTask = nil
        SecItemDelete(query("chatgpt") as CFDictionary)
        status = "ChatGPT disconnected"; onChange?()
    }
    func removeAPIKey() { SecItemDelete(query("api-key") as CFDictionary); status = "API key removed"; onChange?() }
    func disconnect() {
        cancelSignIn(); refreshTask?.cancel(); refreshTask = nil
        for name in ["chatgpt", "api-key"] { SecItemDelete(query(name) as CFDictionary) }
        status = "Disconnected"; onChange?()
    }
    private func query(_ name: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name] }
    private func displayAttributes(_ name: String) -> [String: Any] {
        [kSecAttrLabel as String: name == "chatgpt" ? "Jerry — ChatGPT" : "Jerry — API key",
         kSecAttrDescription as String: name == "chatgpt" ? "Jerry ChatGPT connection" : "Jerry API key"]
    }
    private func updateDisplayAttributes(_ name: String) {
        guard !labelledAccounts.contains(name) else { return }
        var q = query(name)
        // Relabel old items without reading or replacing their secret, and never
        // interrupt an automatic status check with an authorisation dialog.
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var lookup = q; lookup[kSecReturnAttributes as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let code = Self.nonInteractiveKeychain { SecItemCopyMatching(lookup as CFDictionary, &found) }
        let expected = displayAttributes(name)
        if code == errSecSuccess, let attributes = found as? [String: Any],
           attributes[kSecAttrLabel as String] as? String == expected[kSecAttrLabel as String] as? String,
           attributes[kSecAttrDescription as String] as? String == expected[kSecAttrDescription as String] as? String {
            labelledAccounts.insert(name); return
        }
        guard code == errSecSuccess else { return }
        if Self.nonInteractiveKeychain({ SecItemUpdate(q as CFDictionary, expected as CFDictionary) }) == errSecSuccess {
            labelledAccounts.insert(name)
        }
    }
    /// Legacy login-keychain ACL changes can ignore the modern no-UI query key.
    /// This synchronous MainActor scope restores the previous process setting
    /// before any other app-owned credential operation can run.
    static func nonInteractiveKeychain<T>(_ body: () throws -> T) rethrows -> T {
        var prior: DarwinBoolean = true
        let known = SecKeychainGetUserInteractionAllowed(&prior) == errSecSuccess
        if known { SecKeychainSetUserInteractionAllowed(false) }
        defer { if known { SecKeychainSetUserInteractionAllowed(prior.boolValue) } }
        return try body()
    }
    private func read(_ name: String) throws -> Data? {
        updateDisplayAttributes(name)
        var q = query(name); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Automatic status checks must not block startup behind a Keychain prompt.
        // Unsigned Debug/Release binaries can have different access identities.
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let code = Self.nonInteractiveKeychain { SecItemCopyMatching(q as CFDictionary, &result) }
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess else { throw AgentConnectionError(message: "Keychain could not be read (\(code)).") }
        return result as? Data
    }
    private func save(_ data: Data, as name: String) throws {
        let q = query(name)
        var attributes = displayAttributes(name); attributes[kSecValueData as String] = data
        let code = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if code == errSecItemNotFound {
            var insert = q.merging(attributes) { _, new in new }; insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AgentConnectionError(message: "Could not save credentials to Keychain.") }; labelledAccounts.insert(name); return
        }
        guard code == errSecSuccess else { throw AgentConnectionError(message: "Could not update credentials in Keychain.") }
        labelledAccounts.insert(name)
    }
    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AgentConnectionError(message: "Could not generate sign-in randomness.") }
        return Data(bytes).base64URL
    }
    func cancelSignIn() {
        if attempt != nil { status = "Sign-in cancelled" }
        attempt = nil; listener?.cancel(); listener = nil; loginTimeout?.cancel(); loginTimeout = nil
    }
    func signIn() {
        cancelSignIn()
        do {
            let id = UUID(); attempt = id
            let state = try Self.randomToken(), nonce = try Self.randomToken(), verifier = try Self.randomToken()
            let saved = account
            let host = UserDefaults.standard.string(forKey: "agentHostID") ?? "urn:uuid:\(UUID().uuidString.lowercased())"
            UserDefaults.standard.set(host, forKey: "agentHostID")
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener; status = "Preparing browser sign-in…"; onChange?()
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let port = listener?.port else { connection.cancel(); return }
                let redirect = "http://127.0.0.1:\(port.rawValue)/auth/callback"
                connection.start(queue: .main)
                Self.receiveCallback(connection, pending: "", expectedState: state) { [weak self] values in
                    Task { @MainActor [weak self] in
                        guard let self, self.attempt == id else { return }
                        self.listener?.cancel(); self.listener = nil
                        do {
                            guard values["error"] == nil else { throw AgentConnectionError(message: "ChatGPT sign-in was declined. You can try again.") }
                            guard let code = values["code"], let client = values["client_id"] ?? saved?.clientID,
                                  client != "dynamic_agent_client", saved == nil || saved?.clientID == client else { throw AgentConnectionError(message: "The sign-in callback did not match this registration.") }
                            self.status = "Validating ChatGPT connection…"; self.onChange?()
                            let response = try await Self.tokenRequest(["grant_type": "authorization_code", "client_id": client, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "resource": "https://api.openai.com/v1"])
                            guard let jwt = response["id_token"] as? String else { throw AgentConnectionError(message: "The sign-in response has no identity token.") }
                            let identity = try await Self.validateIdentity(jwt, clientID: client, nonce: nonce)
                            if let saved, saved.subject != identity.subject { throw AgentConnectionError(message: "The signed-in account differs from the selected account. Disconnect to change account.") }
                            let record = try Self.record(response, clientID: client, identity: identity, previous: nil)
                            guard self.attempt == id else { return }
                            try self.save(JSONEncoder().encode(record), as: "chatgpt")
                            self.cancelSignIn(); self.status = "Connected to ChatGPT: \(record.email)"; self.onChange?()
                        } catch { self.fail(error, attempt: id) }
                    }
                }
            }

            listener.stateUpdateHandler = { [weak self, weak listener] listenerState in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.attempt == id else { return }
                    if case .ready = listenerState, let port = listener.port {
                        let redirect = "http://127.0.0.1:\(port.rawValue)/auth/callback"
                        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
                        var items = ["client_id": saved?.clientID ?? "dynamic_agent_client", "ext_agent_host_id": host,
                                     "response_type": "code", "redirect_uri": redirect,
                                     "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                                     "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce,
                                     "code_challenge_method": "S256", "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL]
                        if saved == nil { items["agent_name_hint"] = "Jerry" }
                        else { items["id_token_hint"] = saved?.idToken }
                        url.queryItems = items.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
                        if let address = url.url, NSWorkspace.shared.open(address) { self.status = "Finish sign-in in your browser"; self.onChange?() }
                        else { self.fail(AgentConnectionError(message: "Could not open the sign-in browser."), attempt: id) }
                    } else if case .failed(let error) = listenerState { self.fail(AgentConnectionError(message: "Could not start the local sign-in callback: \(error.localizedDescription)"), attempt: id) }
                }
            }
            listener.start(queue: .main)
            loginTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.fail(AgentConnectionError(message: "Sign-in timed out. Please try again."), attempt: id)
            }
        } catch { cancelSignIn(); status = error.localizedDescription; onChange?() }
    }
    private func fail(_ error: Error, attempt id: UUID) {
        guard attempt == id else { return }
        cancelSignIn(); status = error.localizedDescription; onChange?()
    }
    nonisolated private static func receiveCallback(_ connection: NWConnection, pending: String, expectedState: String, complete: @escaping @Sendable ([String: String]) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, ended, error in
            let request = pending + (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            guard request.utf8.count <= 16384 else { connection.cancel(); return }
            if !request.contains("\r\n\r\n"), !ended, error == nil { receiveCallback(connection, pending: request, expectedState: expectedState, complete: complete); return }
            let path = request.components(separatedBy: "\r\n").first?.split(separator: " ")
            let url = path.flatMap { $0.count >= 2 && $0[0] == "GET" ? URLComponents(string: "http://127.0.0.1" + String($0[1])) : nil }
            let pairs = url?.queryItems ?? []
            var values: [String: String] = [:]
            var duplicate = false
            for item in pairs { if values[item.name] != nil { duplicate = true }; values[item.name] = item.value ?? "" }
            let valid = url?.path == "/auth/callback" && values["state"] == expectedState && !duplicate
            let body = valid ? "Sign-in received. Return to Jerry to see the result. You can close this tab." : "Invalid sign-in callback. Return to Jerry and retry."
            let response = "HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel(); if valid { complete(values) } })
        }
    }
    func accessToken() async throws -> String {
        guard let record = account else { throw AgentConnectionError(message: "Continue with ChatGPT first.") }
        if record.expiresAt.timeIntervalSinceNow > 60 { return record.accessToken }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { @MainActor [weak self] () throws -> String in
            guard let self else { throw CancellationError() }
            let response = try await Self.tokenRequest(["grant_type": "refresh_token", "client_id": record.clientID, "refresh_token": record.refreshToken, "resource": "https://api.openai.com/v1"])
            var identity = (subject: record.subject, email: record.email)
            if let jwt = response["id_token"] as? String {
                identity = try await Self.validateIdentity(jwt, clientID: record.clientID, nonce: nil)
                guard identity.subject == record.subject else { throw AgentConnectionError(message: "The refreshed account identity changed. Please reconnect.") }
            }
            let renewed = try Self.record(response, clientID: record.clientID, identity: identity, previous: record)
            try Task.checkCancellation()
            try self.save(JSONEncoder().encode(renewed), as: "chatgpt")
            return renewed.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    private static func record(_ data: [String: Any], clientID: String, identity: (subject: String, email: String), previous: Account?) throws -> Account {
        let scopes = (data["scope"] as? String)?.split(separator: " ").map(String.init) ?? previous?.scopes ?? []
        guard let access = data["access_token"] as? String, !access.isEmpty,
              let refresh = data["refresh_token"] as? String ?? previous?.refreshToken,
              scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke"),
              (data["token_type"] as? String)?.lowercased() == "bearer" else { throw AgentConnectionError(message: "ChatGPT did not grant plan usage. Reconnect and enable plan usage in the browser.") }
        return .init(clientID: clientID, subject: identity.subject, email: identity.email, accessToken: access, refreshToken: refresh,
                     idToken: data["id_token"] as? String ?? previous?.idToken ?? "", expiresAt: Date(timeIntervalSinceNow: (data["expires_in"] as? Double) ?? 3600), scopes: scopes)
    }
    private static func tokenRequest(_ values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentConnectionError(message: "ChatGPT token exchange failed. Start a fresh sign-in; the account or local-app flow may not be enabled.")
        }
        return result
    }
    /// OIDC signature, issuer, audience, nonce and expiry are checked before saving.
    private static func validateIdentity(_ token: String, clientID: String, nonce: String?) async throws -> (subject: String, email: String) {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]), let claimsData = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let kid = header["kid"] as? String, let alg = header["alg"] as? String,
              claims["iss"] as? String == "https://auth.openai.com", (nonce == nil || claims["nonce"] as? String == nonce),
              (claims["azp"] == nil || claims["azp"] as? String == clientID),
              ((claims["aud"] as? [String])?.count ?? 1 <= 1 || claims["azp"] as? String == clientID),
              (claims["aud"] as? String == clientID || (claims["aud"] as? [String])?.contains(clientID) == true),
              let expires = claims["exp"] as? Double, expires > Date().timeIntervalSince1970,
              let subject = claims["sub"] as? String, !subject.isEmpty else { throw AgentConnectionError(message: "ChatGPT identity validation failed.") }
        let (discoveryData, discoveryResponse) = try await URLSession.shared.data(from: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        guard (discoveryResponse as? HTTPURLResponse)?.statusCode == 200,
              let discovery = try JSONSerialization.jsonObject(with: discoveryData) as? [String: Any], discovery["issuer"] as? String == "https://auth.openai.com",
              let jwks = discovery["jwks_uri"] as? String, let jwksURL = URL(string: jwks), jwksURL.scheme == "https", jwksURL.host == "auth.openai.com" else { throw AgentConnectionError(message: "Could not verify the ChatGPT identity issuer.") }
        let (keyData, keyResponse) = try await URLSession.shared.data(from: jwksURL)
        guard (keyResponse as? HTTPURLResponse)?.statusCode == 200,
              let keys = try JSONSerialization.jsonObject(with: keyData) as? [String: Any], let list = keys["keys"] as? [[String: Any]],
              let key = list.first(where: { $0["kid"] as? String == kid && ($0["alg"] == nil || $0["alg"] as? String == alg) }) else { throw AgentConnectionError(message: "Could not find the ChatGPT identity signing key.") }
        let message = Data((parts[0] + "." + parts[1]).utf8)
        let valid: Bool
        if alg == "RS256", key["kty"] as? String == "RSA", let n = key["n"] as? String, let e = key["e"] as? String, let modulus = Data(base64URL: n), let exponent = Data(base64URL: e) {
            func der(_ tag: UInt8, _ value: Data) -> Data {
                let length: [UInt8] = value.count < 128 ? [UInt8(value.count)] : (value.count < 256 ? [0x81, UInt8(value.count)] : [0x82, UInt8(value.count >> 8), UInt8(value.count & 255)])
                return Data([tag] + length) + value
            }
            func integer(_ value: Data) -> Data { der(2, value.first.map { $0 >= 128 } == true ? Data([0]) + value : value) }
            let encoded = der(0x30, integer(modulus) + integer(exponent))
            let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
            if let publicKey = SecKeyCreateWithData(encoded as CFData, attributes as CFDictionary, nil) { valid = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, signature as CFData, nil) } else { valid = false }
        } else if alg == "ES256", key["kty"] as? String == "EC", key["crv"] as? String == "P-256", let x = key["x"] as? String, let y = key["y"] as? String,
                  let dx = Data(base64URL: x), let dy = Data(base64URL: y) {
            valid = try P256.Signing.PublicKey(x963Representation: Data([4]) + dx + dy).isValidSignature(P256.Signing.ECDSASignature(rawRepresentation: signature), for: message)
        } else { valid = false }
        guard valid else { throw AgentConnectionError(message: "The ChatGPT identity signature is invalid.") }
        return (subject, claims["email"] as? String ?? "ChatGPT account")
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}
