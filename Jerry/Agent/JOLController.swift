import AppKit
import SwiftUI

@MainActor
final class JOLController: ObservableObject {
    @Published var address = UserDefaults.standard.string(forKey: "jolAddress") ?? ""
    @Published var sharePhotos = false
    @Published var shareDetails = false
    @Published var includeHistory = false
    @Published private(set) var backfillDetails = false
    @Published private(set) var manifest: JOLManifest?
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var status = "Optional. Jerry works without a JOL account."
    @Published private(set) var remoteArmed = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var sharingIssue: String?
    var execute: ((JOLCommand) async -> JOLCommandResult)?
    var isBusy: (() -> Bool)?
    var interruptRemote: (() -> Void)?
    private let credentials = JOLCredentials()
    private let journalDirectory: URL?
    private let journalStore: ExpeditionJournalStore?
    private var sync: JOLSyncStore?
    private var loop: Task<Void, Never>?
    private var signIn: Task<Void, Never>?
    private var presence: Task<Void, Never>?
    private var eventStream: Task<Void, Never>?
    private var commandCheck: Task<Void, Never>?
    private var execution: Task<Void, Never>?
    private var epoch = UUID()
    private var needsCommandCheck = true
    private var streamLive = false
    private var presenceReady = false
    private var presenceIssue: String?
    private var lastClaim = Date.distantPast
    init(journalDirectory: URL?, journalStore: ExpeditionJournalStore? = nil) { self.journalDirectory = journalDirectory; self.journalStore = journalStore }
    func start() {
        guard journalDirectory != nil, UserDefaults.standard.bool(forKey: "jolConnected") else { return }
        do {
            guard let account = try credentials.load() else { status = "Reconnect Jerry On Line to resume sharing."; return }
            manifest = account.manifest; address = account.manifest.origin; connected = true
            sharePhotos = UserDefaults.standard.bool(forKey: "jolSharePhotos"); shareDetails = UserDefaults.standard.bool(forKey: "jolShareDetails")
            includeHistory = UserDefaults.standard.bool(forKey: "jolHistory")
            backfillDetails = UserDefaults.standard.bool(forKey: "jolBackfillDetails")
            try makeSync(account); runLoop()
        } catch { status = error.localizedDescription }
    }
    func checkServer() {
        signIn?.cancel(); working = true; manifest = nil; status = "Finding your JOL server…"
        signIn = Task { [weak self] in
            guard let self else { return }; defer { self.working = false }
            do {
                let url = try JOLManifest.serverURL(self.address)
                let data = try await JOLHTTP.data(URLRequest(url: url.appendingPathComponent(".well-known/jerry-online")))
                let found = try JSONDecoder().decode(JOLManifest.self, from: data); try found.validate(for: url)
                try Task.checkCancellation(); self.manifest = found; self.status = "\(found.name) · \(url.host ?? found.origin)"
            } catch is CancellationError {} catch { self.status = error.localizedDescription }
        }
    }
    func connect() {
        guard let manifest, let journalDirectory else { return }
        working = true; status = "Finish signing in in your browser…"
        signIn = Task { [weak self] in
            guard let self else { return }; defer { self.working = false }
            do {
                let account = try await self.credentials.signIn(manifest)
                var request = URLRequest(url: URL(string: manifest.origin + "/api/devices")!); request.httpMethod = "POST"
                request.setValue("Bearer " + account.accessToken, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["id":account.deviceID.uuidString,"name":String((Host.current().localizedName ?? "My Mac").prefix(80)),"credential":account.deviceCredential])
                _ = try await JOLHTTP.data(request); try Task.checkCancellation(); try self.credentials.save(account)
                let defaults = UserDefaults.standard
                defaults.set(manifest.origin, forKey: "jolAddress"); defaults.set(Date(), forKey: "jolSince")
                defaults.set(self.sharePhotos, forKey: "jolSharePhotos"); defaults.set(self.shareDetails, forKey: "jolShareDetails"); defaults.set(self.includeHistory, forKey: "jolHistory")
                self.backfillDetails = false
                defaults.set(false, forKey: "jolBackfillDetails")
                defaults.set(true, forKey: "jolConnected"); self.connected = true
                try self.makeSync(account); self.runLoop()
            } catch is CancellationError {} catch { self.status = error.localizedDescription }
            _ = journalDirectory
        }
    }
    func cancelSignIn() { signIn?.cancel(); credentials.cancel(); working = false; status = "Connection cancelled. Jerry is still working locally." }
    func disconnect() {
        let saved = try? credentials.load()
        if execution != nil { interruptRemote?() }
        epoch = UUID(); remoteArmed = false; loop?.cancel(); presence?.cancel(); eventStream?.cancel(); commandCheck?.cancel(); execution?.cancel(); signIn?.cancel()
        loop = nil; presence = nil; eventStream = nil; commandCheck = nil; execution = nil; sync = nil
        connected = false; working = false; manifest = nil; lastSync = nil; sharingIssue = nil
        UserDefaults.standard.set(false, forKey: "jolConnected")
        // A local disconnect is immediate even if the server cannot be reached.
        if let saved {
            Task {
                var request = URLRequest(url: URL(string: saved.manifest.origin + "/api/devices/\(saved.deviceID.uuidString.lowercased())/revoke")!); request.httpMethod = "POST"
                request.setValue("Bearer " + saved.accessToken, forHTTPHeaderField: "Authorization"); _ = try? await JOLHTTP.data(request)
            }
        }
        credentials.clear(); status = "Disconnected. Local journals are unchanged; the shared copy remains on JOL."
    }
    func setRemoteArmed(_ value: Bool) {
        let armed = connected && value
        guard armed != remoteArmed else { return }
        remoteArmed = armed
        if !armed && execution != nil { interruptRemote?() }
        if !armed { eventStream?.cancel(); eventStream = nil; streamLive = false }
        startPresence(generation: epoch)
    }
    func wakeCommands() {
        guard remoteArmed else { return }
        needsCommandCheck = true
        scheduleCommandCheck(generation: epoch)
    }
    func serverAddressChanged() { if !connected { manifest = nil } }
    func localTakeover() { if remoteArmed { setRemoteArmed(false); status = "Remote missions paused for local control. Re-enable them when you’re ready." } }
    func openWebsite() { if let manifest, let url = URL(string: manifest.origin) { NSWorkspace.shared.open(url) } }
    func shareOlderExpeditions() {
        guard connected, let sync else { return }
        includeHistory = true
        UserDefaults.standard.set(true, forKey: "jolHistory")
        Task { await sync.enableHistory() }
    }
    func shareTechnicalDetails() {
        guard connected, let sync, !working else { return }
        let generation = epoch
        working = true
        sharingIssue = nil
        Task {
            defer { if epoch == generation { working = false } }
            do {
                guard let manifest, let url = URL(string: manifest.origin) else { return }
                let data = try await JOLHTTP.data(URLRequest(url: url.appendingPathComponent(".well-known/jerry-online")))
                let found = try JSONDecoder().decode(JOLManifest.self, from: data)
                try found.validate(for: url)
                guard connected, epoch == generation else { return }
                guard found.capabilities.detailsBackfill == true else {
                    sharingIssue = "Update your JOL server to share technical details on an existing connection."
                    return
                }
                backfillDetails = true
                UserDefaults.standard.set(true, forKey: "jolBackfillDetails")
                await sync.enableDetails()
            } catch {
                if epoch == generation { sharingIssue = error.localizedDescription }
            }
        }
    }
    private func makeSync(_ account: JOLCredentials.Account) throws {
        guard let journalDirectory else { return }
        let support = journalDirectory.deletingLastPathComponent().appendingPathComponent("JOL/\(account.manifest.instanceID)/\(account.deviceID.uuidString)")
        sync = try JOLSyncStore(journals: journalDirectory, directory: support, since: UserDefaults.standard.object(forKey: "jolSince") as? Date ?? Date(), includeHistory: includeHistory, details: shareDetails, photos: sharePhotos, writer: journalStore, backfillDetails: backfillDetails)
    }
    private func request(_ path: String, body: Data? = nil, method: String? = nil, contentType: String = "application/json", generation: UUID) async throws -> Data {
        guard connected, epoch == generation, !Task.isCancelled, let account = try credentials.load() else { throw CancellationError() }
        var request = URLRequest(url: URL(string: account.manifest.origin + "/api" + path)!)
        request.httpMethod = method ?? (body == nil ? "GET" : "POST"); request.httpBody = body
        let bearer = try await credentials.token()
        guard connected, epoch == generation else { throw CancellationError() }
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue(account.deviceCredential, forHTTPHeaderField: "X-JOL-Device")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return try await JOLHTTP.data(request)
    }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private var devicePath: String { get throws { guard let account = try credentials.load() else { throw CancellationError() }; return "/devices/" + account.deviceID.uuidString.lowercased() } }
    private func runLoop() {
        loop?.cancel(); eventStream?.cancel(); eventStream = nil; let generation = UUID(); epoch = generation
        status = "Connecting… Remote missions are off until you enable them."
        startPresence(generation: generation)
        loop = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.connected, self.epoch == generation, let sync = self.sync else { return }
                do {
                    let path = try self.devicePath
                    var uploaded = false
                    for receipt in await sync.pendingReceipts() {
                        try await self.ack(receipt.command, status: receipt.status, result: receipt.result, generation: generation)
                        try await sync.acknowledgeReceipt(receipt.command.id)
                    }
                    for batch in try await sync.nextBatches() {
                        struct Payload: Encodable { let start: Int; let records: [JournalRecord] }
                        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
                        let result = try await self.request(path + "/expeditions/\(batch.expeditionID.uuidString.lowercased())/batches", body: encoder.encode(Payload(start: batch.start, records: batch.records)), generation: generation)
                        struct Ack: Decodable { let cursor: Int }
                        try await sync.acknowledge(batch, cursor: JSONDecoder().decode(Ack.self, from: result).cursor)
                        uploaded = true
                    }
                    for batch in try await sync.nextDetails() {
                        if !batch.changes.isEmpty {
                            let encoder = JSONEncoder()
                            encoder.dateEncodingStrategy = .millisecondsSince1970
                            _ = try await self.request(path + "/expeditions/\(batch.expeditionID.uuidString.lowercased())/details",
                                                       body: encoder.encode(batch.changes), method: "PATCH", generation: generation)
                            uploaded = true
                        }
                        try await sync.acknowledgeDetails(batch)
                    }
                    if self.manifest?.capabilities.photos == true {
                        for photo in try await sync.nextPhotos() {
                            _ = try await self.request(path + "/expeditions/\(photo.expeditionID.uuidString.lowercased())/photos/\(photo.filename.lowercased())", body: photo.data, method: "PUT", contentType: "image/jpeg", generation: generation)
                            try await sync.acknowledgePhoto(photo)
                            uploaded = true
                        }
                    }
                    guard self.connected, self.epoch == generation, !Task.isCancelled else { return }
                    failures = 0
                    if uploaded { self.lastSync = Date() }
                    if let issue = self.presenceIssue { self.status = "JOL connection waiting: " + issue }
                    else if self.presenceReady {
                        self.status = self.remoteArmed ? "On line · remote missions enabled" : "On line · sharing journals. Remote missions are off."
                    }
                } catch is CancellationError { return }
                catch { guard self.epoch == generation else { return }; failures += 1; self.status = "Journal sync waiting: " + error.localizedDescription }
                try? await Task.sleep(for: .seconds(min(30, failures == 0 ? 2 : pow(2, Double(min(failures, 4))))))
            }
        }
    }
    private func startPresence(generation: UUID) {
        presence?.cancel()
        presenceReady = false
        presenceIssue = nil
        presence = Task { [weak self] in
            var nextHeartbeat = Date.distantPast
            while !Task.isCancelled {
                guard let self, self.connected, self.epoch == generation else { return }
                if Date() >= nextHeartbeat {
                    do {
                        let armed = self.remoteArmed
                        _ = try await self.request(try self.devicePath + "/heartbeat",
                                                   body: self.json(["remoteEnabled": armed]), generation: generation)
                        guard !Task.isCancelled, self.epoch == generation, self.remoteArmed == armed else { return }
                        if !self.presenceReady && armed { self.needsCommandCheck = true }
                        self.presenceReady = true
                        self.presenceIssue = nil
                        nextHeartbeat = Date().addingTimeInterval(20)
                    } catch {
                        if Task.isCancelled || self.epoch != generation { return }
                        self.presenceReady = false
                        self.presenceIssue = error.localizedDescription
                    }
                }
                if self.remoteArmed && self.presenceReady {
                    if self.manifest?.capabilities.realtime == true && self.eventStream == nil {
                        self.startEvents(generation: generation)
                    }
                    // Recover missed hints or expired leases. A healthy stream
                    // wakes the claim immediately, independently of journal uploads.
                    if Date().timeIntervalSince(self.lastClaim) >= (self.streamLive ? 90 : 10) {
                        self.needsCommandCheck = true
                    }
                    self.scheduleCommandCheck(generation: generation)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    private func startEvents(generation: UUID) {
        eventStream = Task { [weak self] in
            guard let self, self.epoch == generation, self.connected, self.remoteArmed, !Task.isCancelled else { return }
            defer {
                if self.epoch == generation && !Task.isCancelled {
                    self.eventStream = nil
                    self.streamLive = false
                }
            }
            do {
                guard let account = try self.credentials.load() else { return }
                var request = URLRequest(url: URL(string: account.manifest.origin + "/api" + (try self.devicePath) + "/events")!); request.timeoutInterval = 60
                request.setValue("Bearer " + (try await self.credentials.token()), forHTTPHeaderField: "Authorization"); request.setValue(account.deviceCredential, forHTTPHeaderField: "X-JOL-Device")
                guard self.connected, self.remoteArmed, self.epoch == generation, !Task.isCancelled else { return }
                let (bytes, response) = try await JOLHTTP.session.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                for try await line in bytes.lines {
                    guard !Task.isCancelled, self.epoch == generation else { return }
                    if line == "event: live" {
                        self.streamLive = true
                        self.wakeCommands()
                    } else if line == "event: commands_changed" {
                        self.wakeCommands()
                    }
                }
            } catch { /* The periodic durable queue read remains active. */ }
        }
    }
    private func scheduleCommandCheck(generation: UUID) {
        guard connected, remoteArmed, presenceReady, epoch == generation,
              needsCommandCheck, commandCheck == nil else { return }
        needsCommandCheck = false
        lastClaim = Date()
        commandCheck = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            defer {
                if self.epoch == generation {
                    self.commandCheck = nil
                    if succeeded { self.scheduleCommandCheck(generation: generation) }
                    else { self.needsCommandCheck = true }
                }
            }
            guard self.remoteArmed, self.epoch == generation, !Task.isCancelled else { return }
            do {
                try await self.checkCommands(generation: generation)
                succeeded = true
            } catch {
                // Presence maintenance retries without delaying journal uploads.
            }
        }
    }
    private func ack(_ command: JOLCommand, status: String, result: String = "", generation: UUID) async throws {
        guard epoch == generation else { throw CancellationError() }
        _ = try await request((try devicePath) + "/commands/\(command.id.uuidString.lowercased())/ack", body: json(["fence":command.fence,"status":status,"result":String(result.prefix(1000))]), generation: generation)
    }
    private func checkCommands(generation: UUID) async throws {
        guard epoch == generation, connected, !Task.isCancelled else { throw CancellationError() }
        guard let sync else { return }
        struct Claim: Decodable { let command: JOLCommand? }
        let data = try await request((try devicePath) + "/commands/claim", body: json(["busy":execution != nil || (isBusy?() ?? true)]), generation: generation)
        guard let command = try JSONDecoder().decode(Claim.self, from: data).command else { return }
        if await sync.priorCommand(command.id) != nil {
            try await ack(command, status: "uncertain", result: "Jerry already accepted this direction. Give a fresh direction to continue safely.", generation: generation); return
        }
        guard remoteArmed, epoch == generation else { return }
        try await sync.rememberCommand(command.id, status: "started")
        try await ack(command, status: "started", generation: generation)
        guard epoch == generation else { throw CancellationError() }
        guard remoteArmed else { try await ack(command, status: "failed", result: "Remote missions were paused locally before starting", generation: generation); return }
        if command.kind == "stop" {
            let result = await execute?(command) ?? .init(status: "failed", message: "Jerry is unavailable")
            try await sync.complete(command, status: result.status, result: result.message)
            try await ack(command, status: result.status, result: result.message, generation: generation); try await sync.acknowledgeReceipt(command.id); return
        }
        execution = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == generation { self.execution = nil; self.wakeCommands() } }
            guard self.epoch == generation, self.remoteArmed, !Task.isCancelled else { return }
            let renew = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20)); guard !Task.isCancelled, let self, self.epoch == generation else { return }
                    do { try await self.ack(command, status: "started", generation: generation) }
                    catch { guard self.epoch == generation else { return }; self.setRemoteArmed(false); self.interruptRemote?(); return }
                }
            }
            let result = await self.execute?(command) ?? .init(status: "failed", message: "Jerry is unavailable")
            renew.cancel()
            guard self.epoch == generation else { return }
            do {
                try await sync.complete(command, status: result.status, result: result.message)
                try await self.ack(command, status: result.status, result: result.message, generation: generation)
                try await sync.acknowledgeReceipt(command.id)
            }
            catch { if self.epoch == generation { self.status = "Direction completed locally; its acknowledgement is waiting for a connection." } }
        }
    }
}
