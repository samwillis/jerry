import AppKit
import SwiftUI

@MainActor
final class ExpeditionJournal: ObservableObject {
    enum Kind { case request, response, activity }
    struct Entry: Identifiable {
        let id: UUID
        let date: Date
        let kind: Kind
        var text: String
        var details: String
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var revision = 0
    @Published var taskTitle = ""
    @Published var status = "Ready"
    @Published var isRunning = false
    @Published var followsLatest = true
    @discardableResult func append(_ kind: Kind, _ text: String, details: String = "") -> UUID {
        let id = UUID(); entries.append(.init(id: id, date: Date(), kind: kind, text: text, details: details)); revision += 1; return id
    }
    func update(_ id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].text != text else { return }
        entries[index].text = text; revision += 1
    }
    func addDetails(_ id: UUID, _ text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].details += (entries[index].details.isEmpty ? "" : "\n\n") + text; revision += 1
    }
    func exportText() -> String {
        let clock = ISO8601DateFormatter()
        return entries.map { entry in
            let role = entry.kind == .request ? "YOUR INSTRUCTION" : (entry.kind == .response ? "EXPLORER" : "JOURNAL")
            return "\(clock.string(from: entry.date))  \(role)\n\(entry.text)" + (entry.details.isEmpty ? "" : "\n\nDETAILS\n\(entry.details)")
        }.joined(separator: "\n\n────────────────────\n\n")
    }
}

struct ExpeditionJournalView: View {
    @ObservedObject var journal: ExpeditionJournal
    let stop: () -> Void
    let newTask: () -> Void
    let hide: () -> Void
    let save: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(.caption, design: .serif)).foregroundStyle(.secondary)
                Text(journal.taskTitle.isEmpty ? "A little desktop expedition" : journal.taskTitle)
                    .font(.system(size: 18, weight: .semibold, design: .serif)).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 8) {
                    if journal.isRunning { ProgressView().controlSize(.small) }
                    Text(journal.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(20)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if journal.entries.isEmpty {
                            Text("Every adventure starts with a small request.")
                                .font(.system(.body, design: .serif)).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                        ForEach(journal.entries) { entry in
                            JournalEntryView(entry: entry, pauseFollowing: { journal.followsLatest = false }).id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("journal-bottom")
                    }.padding(20)
                }
                .onChange(of: journal.revision) { _, _ in if journal.followsLatest { proxy.scrollTo("journal-bottom", anchor: .bottom) } }
                .onChange(of: journal.followsLatest) { _, following in if following { proxy.scrollTo("journal-bottom", anchor: .bottom) } }
            }
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Button("Stop", action: stop).disabled(!journal.isRunning)
                    Button("New task…", action: newTask)
                    Spacer()
                    Button("Hide", action: hide)
                }
                HStack {
                    Toggle("Follow latest", isOn: $journal.followsLatest).toggleStyle(.checkbox).font(.caption)
                    Spacer()
                    Button("Save log…", action: save).buttonStyle(.link).font(.caption)
                }
            }.padding(16)
        }.frame(minWidth: 300, minHeight: 300)
    }
}

private struct JournalEntryView: View {
    let entry: ExpeditionJournal.Entry
    let pauseFollowing: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if entry.kind != .activity {
                    Text(entry.kind == .request ? "Your instruction" : "Explorer").font(.caption.weight(.semibold))
                }
                Text(entry.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.tertiary)
            }
            Group {
                if entry.kind == .response { Text(.init(entry.text)) }
                else { Text(entry.text) }
            }
            .font(.system(size: 14, design: .serif)).lineSpacing(4).textSelection(.enabled)
            .foregroundStyle(entry.kind == .activity ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.details.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView {
                        Text(entry.details).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.frame(maxHeight: 220).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                } label: { Text("Details").font(.caption).foregroundStyle(.secondary) }
                .onChange(of: expanded) { _, opened in if opened { pauseFollowing() } }
            }
        }
        .padding(.leading, entry.kind == .request ? 12 : 0)
        .overlay(alignment: .leading) { if entry.kind == .request { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.4)).frame(width: 2) } }
    }
}
