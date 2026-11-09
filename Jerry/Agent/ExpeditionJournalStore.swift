import Foundation

/// Versioned append-only records. Streaming changes store deltas, not repeated
/// copies of the whole response. The directory is reserved for future assets.
struct JournalRecord: Codable, Sendable {
    enum Event: String, Codable, Sendable { case created, entry, textAppended, textReplaced, detailsAppended, state, titleChanged, redacted }
    struct Header: Codable, Sendable { let id: UUID; let date: Date; var title: String }
    var version = 1
    var id = UUID()
    var date = Date()
    let event: Event
    var expedition: Header?
    var entry: ExpeditionJournal.Entry?
    var entryID: UUID?
    var text: String?
    var status: String?
    var isRunning: Bool?
    var isFinished: Bool?
}

/// All mutable writer state is confined to queue. No credentials or provider
/// transcripts are written here; the journal contains its visible entries/details.
final class ExpeditionJournalStore: @unchecked Sendable {
    struct Loaded: Sendable {
        var header: JournalRecord.Header
        var entries: [ExpeditionJournal.Entry] = []
        var status = "Ready for your next direction"
        var wasRunning = false
        var isFinished = false
    }
    struct Restored { var expeditions: [Loaded] = []; var warning: String? }
    let directory: URL
    private let queue = DispatchQueue(label: "com.jerry.journal-storage", qos: .utility)
    private let report: @Sendable (String?) -> Void
    private var pending: [UUID: [JournalRecord]] = [:]
    private var scheduled: DispatchWorkItem?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder
    }()
    init(directory: URL, report: @escaping @Sendable (String?) -> Void) { self.directory = directory; self.report = report }
    func append(_ record: JournalRecord, to expedition: UUID) {
        queue.async { [self] in
            pending[expedition, default: []].append(record)
            guard scheduled == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.writePending() }
            scheduled = work; queue.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
    func savePhoto(_ data: Data, to expedition: UUID) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let folder = directory.appendingPathComponent(expedition.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
                    let filename = UUID().uuidString + ".jpg"
                    let url = folder.appendingPathComponent(filename)
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    continuation.resume(returning: filename)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func retry() { queue.async { [self] in writePending() } }
    /// Take the sync snapshot on the writer queue, after fsync. A failed local
    /// write must never be published remotely as a successfully saved note.
    func committedData(for expedition: UUID) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                writePending()
                guard pending[expedition] == nil else { continuation.resume(returning: nil); return }
                let url = directory.appendingPathComponent(expedition.uuidString).appendingPathComponent("journal.jsonl")
                do { continuation.resume(returning: try Data(contentsOf: url)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Used at task boundaries and shutdown; drains preceding queued records too.
    func flush() { queue.sync { writePending() } }
    private func writePending() {
        scheduled?.cancel(); scheduled = nil
        guard !pending.isEmpty else { return }
        var failed = false
        for (id, records) in pending {
            do {
                let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let folderValues = try folder.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard folderValues.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
                let url = folder.appendingPathComponent("journal.jsonl")
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                }
                let fileValues = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
                let handle = try FileHandle(forUpdating: url); defer { try? handle.close() }
                let end = try handle.seekToEnd()
                var data = Data()
                if end > 0 {
                    try handle.seek(toOffset: end - 1)
                    if try handle.read(upToCount: 1)?.first != 10 { data.append(10) }
                    try handle.seekToEnd()
                }
                for record in records { data.append(try encoder.encode(record)); data.append(10) }
                try handle.write(contentsOf: data); try handle.synchronize()
                pending[id] = nil
            } catch {
                failed = true
                // Keep unsaved records for Retry or the next update. Event IDs
                // make a retry safe even after a partially completed append.
                report("The journal couldn’t be saved. \(error.localizedDescription)")
            }
        }
        if !failed { report(nil) }
    }
    func restore() -> Restored {
        queue.sync {
            var result = Restored()
            guard FileManager.default.fileExists(atPath: directory.path) else { return result }
            do {
                let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for folder in children {
                    guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
                    let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    do {
                        if let loaded = try load(folder: folder, id: id, warning: &result.warning) { result.expeditions.append(loaded) }
                    } catch { result.warning = "Some saved expeditions couldn’t be read. Their files have been kept." }
                }
                result.expeditions.sort { $0.header.date == $1.header.date ? $0.header.id.uuidString < $1.header.id.uuidString : $0.header.date < $1.header.date }
            } catch { result.warning = "Saved expeditions couldn’t be opened. \(error.localizedDescription)" }
            return result
        }
    }
    private func load(folder: URL, id: UUID, warning: inout String?) throws -> Loaded? {
        let url = folder.appendingPathComponent("journal.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        var loaded: Loaded?, seen = Set<UUID>()
        for line in data.split(separator: 10) where !line.isEmpty {
            let record: JournalRecord
            do {
                struct Version: Decodable { let version: Int }
                guard try decoder.decode(Version.self, from: Data(line)).version == 1 else {
                    warning = "An expedition uses a newer journal format and was left untouched."; return nil
                }
                record = try decoder.decode(JournalRecord.self, from: Data(line))
            }
            catch { warning = "Some incomplete journal records were skipped. The original files have been kept."; continue }
            guard record.version == 1 else { warning = "An expedition uses a newer journal format and was left untouched."; return nil }
            guard seen.insert(record.id).inserted else { continue }
            if record.event == .created {
                guard let header = record.expedition, header.id == id else { throw CocoaError(.fileReadCorruptFile) }
                guard loaded == nil else { continue }
                loaded = Loaded(header: header); continue
            }
            guard var expedition = loaded else { continue }
            switch record.event {
            case .created, .redacted: break
            case .titleChanged:
                if let title = record.text, !title.isEmpty { expedition.header.title = title }
            case .entry:
                if let entry = record.entry, !expedition.entries.contains(where: { $0.id == entry.id }) { expedition.entries.append(entry) }
            case .textAppended, .textReplaced, .detailsAppended:
                if let id = record.entryID, let text = record.text, let index = expedition.entries.firstIndex(where: { $0.id == id }) {
                    switch record.event {
                    case .textAppended: expedition.entries[index].text += text
                    case .textReplaced: expedition.entries[index].text = text
                    default: expedition.entries[index].details += text
                    }
                }
            case .state:
                if let status = record.status { expedition.status = status }
                if let running = record.isRunning { expedition.wasRunning = running }
                if let finished = record.isFinished { expedition.isFinished = finished }
            }
            loaded = expedition
        }
        if loaded == nil && !data.isEmpty { warning = "An incomplete expedition could not be restored. Its file has been kept." }
        return loaded
    }
}
