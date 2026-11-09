import Foundation

/// Reads complete, fsynced journal records. Networking never observes UI-only notes.
actor JOLSyncStore {
    struct Receipt: Codable, Sendable { let command: JOLCommand; let status: String; let result: String }
    struct Batch: Sendable { let expeditionID: UUID; let start: Int; let records: [JournalRecord] }
    struct Photo: Sendable { let expeditionID: UUID; let filename: String; let data: Data }
    struct DetailChange: Encodable, Sendable {
        let sequence: Int
        let id: UUID
        let date: Date
        let event: JournalRecord.Event
        let entryID: UUID
        let text: String
    }
    struct DetailBatch: Sendable {
        let expeditionID: UUID
        let through: Int
        let changes: [DetailChange]
    }
    private struct State: Codable {
        var cursors: [String: Int] = [:]
        var detailCursors: [String: Int]?
        var photos: Set<String> = []
        var commands: [String: String] = [:]
        var receipts: [String: Receipt] = [:]
    }
    private let journals: URL
    private let writer: ExpeditionJournalStore?
    private let stateURL: URL
    private let since: Date
    private var includeHistory: Bool
    private let details: Bool
    private var backfillDetails: Bool
    private let photos: Bool
    private var state: State
    private var eligible: [UUID: Bool] = [:]
    private struct Snapshot { let size: Int; let modified: Date?; let records: [JournalRecord] }
    private var snapshots: [UUID: Snapshot] = [:]
    init(journals: URL, directory: URL, since: Date, includeHistory: Bool, details: Bool, photos: Bool, writer: ExpeditionJournalStore? = nil, backfillDetails: Bool = false) throws {
        self.journals = journals; self.since = since; self.includeHistory = includeHistory; self.details = details; self.photos = photos
        self.writer = writer
        self.backfillDetails = backfillDetails
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        stateURL = directory.appendingPathComponent("sync.json")
        if FileManager.default.fileExists(atPath: stateURL.path) { state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) }
        else { state = State() }
    }
    private func save() throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
    func acknowledge(_ batch: Batch, cursor: Int) throws {
        guard cursor >= batch.start + batch.records.count - 1 else { throw JOLError(message: "JOL did not confirm the full journal batch.") }
        state.cursors[batch.expeditionID.uuidString] = cursor; try save()
    }
    func rememberCommand(_ id: UUID, status: String) throws { state.commands[id.uuidString] = status; try save() }
    func priorCommand(_ id: UUID) -> String? { state.commands[id.uuidString] }
    func complete(_ command: JOLCommand, status: String, result: String) throws {
        state.commands[command.id.uuidString] = status
        state.receipts[command.id.uuidString] = Receipt(command: command, status: status, result: result)
        try save()
    }
    func pendingReceipts() -> [Receipt] { Array(state.receipts.values) }
    func acknowledgeReceipt(_ id: UUID) throws { state.receipts[id.uuidString] = nil; try save() }
    func enableHistory() { includeHistory = true }
    func enableDetails() { backfillDetails = true }
    func nextBatches() async throws -> [Batch] {
        try await expeditions().compactMap { id, records in
            let cursor = state.cursors[id.uuidString] ?? 0
            guard cursor <= records.count else { throw JOLError(message: "A shared journal changed on disk. Reconnect to create a fresh sync connection.") }
            let pending = records.dropFirst(cursor).prefix(100).map { source in
                var record = source
                if !details {
                    if record.event == .detailsAppended {
                        return JournalRecord(id: record.id, date: record.date, event: .redacted)
                    }
                    if record.entry != nil { record.entry?.details = "" }
                }
                if !photos { record.entry?.photo = nil }
                return record
            }
            return pending.isEmpty ? nil : Batch(expeditionID: id, start: cursor + 1, records: pending)
        }
    }
    func nextDetails() async throws -> [DetailBatch] {
        guard backfillDetails, !details else { return [] }
        var result: [DetailBatch] = []
        for (id, records) in try await expeditions() {
            let cursor = state.detailCursors?[id.uuidString] ?? 0
            let accepted = min(state.cursors[id.uuidString] ?? 0, records.count)
            guard cursor < accepted else { continue }
            var through = cursor, bytes = 0
            var changes: [DetailChange] = []
            for index in cursor..<min(accepted, cursor + 100) {
                let record = records[index]
                let entryID = record.event == .detailsAppended ? record.entryID : record.entry?.id
                let text = record.event == .detailsAppended ? record.text : record.entry?.details
                if let entryID, let text, !text.isEmpty {
                    if !changes.isEmpty && bytes + text.utf8.count > 400_000 { break }
                    changes.append(.init(sequence: index + 1, id: record.id, date: record.date,
                                         event: record.event, entryID: entryID, text: text))
                    bytes += text.utf8.count
                }
                through = index + 1
            }
            result.append(.init(expeditionID: id, through: through, changes: changes))
            if result.count >= 5 { break }
        }
        return result
    }
    func acknowledgeDetails(_ batch: DetailBatch) throws {
        if state.detailCursors == nil { state.detailCursors = [:] }
        state.detailCursors?[batch.expeditionID.uuidString] = batch.through
        try save()
    }
    func nextPhotos() async throws -> [Photo] {
        guard photos else { return [] }
        var result: [Photo] = []
        for (id, records) in try await expeditions() {
            for record in records.prefix(state.cursors[id.uuidString] ?? 0) {
                guard let filename = record.entry?.photo, filename.hasSuffix(".jpg"), UUID(uuidString: String(filename.dropLast(4))) != nil,
                      !state.photos.contains(id.uuidString + "/" + filename) else { continue }
                let url = journals.appendingPathComponent(id.uuidString).appendingPathComponent(filename)
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? 0) <= 4_000_000, let data = try? Data(contentsOf: url) else { continue }
                result.append(Photo(expeditionID: id, filename: filename, data: data)); if result.count >= 3 { return result }
            }
        }
        return result
    }
    func acknowledgePhoto(_ photo: Photo) throws { state.photos.insert(photo.expeditionID.uuidString + "/" + photo.filename); try save() }
    private func expeditions() async throws -> [(UUID, [JournalRecord])] {
        guard FileManager.default.fileExists(atPath: journals.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let folders = try FileManager.default.contentsOfDirectory(at: journals, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var result: [(UUID, [JournalRecord])] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let id = UUID(uuidString: folder.lastPathComponent), try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
            let file = folder.appendingPathComponent("journal.jsonl")
            guard let attributes = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]), attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
            if !includeHistory {
                if eligible[id] == nil {
                    // Inspect just the immutable creation record before asking the
                    // writer for a full snapshot of an old, unshared journal.
                    let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                    let prefix = try handle.read(upToCount: 16_384) ?? Data()
                    if let end = prefix.firstIndex(of: 10), let header = try? decoder.decode(JournalRecord.self, from: prefix[..<end]),
                       header.event == .created, let created = header.expedition { eligible[id] = created.date >= since }
                }
                guard eligible[id] == true else { continue }
            }
            if let cached = snapshots[id], cached.size == attributes.fileSize, cached.modified == attributes.contentModificationDate {
                result.append((id, cached.records)); continue
            }
            let snapshot: Data?
            if let writer { snapshot = try await writer.committedData(for: id) }
            else { snapshot = try? Data(contentsOf: file) }
            guard let data = snapshot, let end = data.lastIndex(of: 10) else { continue }
            var seen: Set<UUID> = [], records: [JournalRecord] = []
            for line in data[..<end].split(separator: 10) {
                // Preserve the existing journal loader's tolerance of interrupted/malformed lines.
                guard let record = try? decoder.decode(JournalRecord.self, from: Data(line)), seen.insert(record.id).inserted else { continue }
                guard record.version == 1 else { throw JOLError(message: "This journal uses a newer format; update Jerry before syncing it.") }
                records.append(record)
            }
            guard let first = records.first, first.event == .created, first.expedition?.id == id,
                  includeHistory || (first.expedition?.date ?? .distantPast) >= since else { continue }
            snapshots[id] = Snapshot(size: attributes.fileSize ?? data.count, modified: attributes.contentModificationDate, records: records)
            result.append((id, records))
        }
        return result
    }
}
