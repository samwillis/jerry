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

private enum JournalPalette {
    static let paper = Color(red: 0.98, green: 0.95, blue: 0.86)
    static let ink = Color(red: 0.24, green: 0.29, blue: 0.25)
    static let faded = Color(red: 0.45, green: 0.45, blue: 0.36)
    static let leather = Color(red: 0.38, green: 0.26, blue: 0.17)
    static let rust = Color(red: 0.64, green: 0.32, blue: 0.22)
}

struct ExpeditionJournalView: View {
    @ObservedObject var journal: ExpeditionJournal
    let stop: () -> Void
    let newTask: () -> Void
    let hide: () -> Void
    let save: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rule
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if journal.entries.isEmpty { emptyPage }
                        ForEach(journal.entries) { entry in
                            JournalEntryView(entry: entry, pauseFollowing: { journal.followsLatest = false }).id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("journal-bottom")
                    }.padding(.vertical, 24).padding(.leading, 36).padding(.trailing, 24)
                }
                .onChange(of: journal.revision) { _, _ in if journal.followsLatest { proxy.scrollTo("journal-bottom", anchor: .bottom) } }
                .onChange(of: journal.followsLatest) { _, following in if following { proxy.scrollTo("journal-bottom", anchor: .bottom) } }
            }
            rule
            footer
        }
        .foregroundStyle(JournalPalette.ink)
        .background {
            ZStack(alignment: .leading) {
                JournalPalette.paper
                // Fine paper fibres and a red notebook margin stay fixed behind the writing.
                Canvas { context, size in
                    for y in stride(from: 2.0, to: size.height, by: 4) {
                        var fibre = Path(); fibre.move(to: .init(x: 12, y: y)); fibre.addLine(to: .init(x: size.width, y: y))
                        context.stroke(fibre, with: .color(JournalPalette.leather.opacity(0.025)), lineWidth: 0.5)
                    }
                    var margin = Path(); margin.move(to: .init(x: 25, y: 0)); margin.addLine(to: .init(x: 25, y: size.height))
                    context.stroke(margin, with: .color(JournalPalette.rust.opacity(0.22)), lineWidth: 0.7)
                }.allowsHitTesting(false)
                Rectangle().fill(JournalPalette.leather.gradient).frame(width: 10)
                Canvas { context, size in
                    for y in stride(from: 12.0, to: size.height, by: 10) {
                        var stitch = Path(); stitch.move(to: .init(x: 5, y: y)); stitch.addLine(to: .init(x: 5, y: y + 4))
                        context.stroke(stitch, with: .color(JournalPalette.paper.opacity(0.5)), lineWidth: 1)
                    }
                }.frame(width: 10).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(JournalPalette.leather.opacity(0.25), lineWidth: 1).allowsHitTesting(false) }
        .frame(minWidth: 340, minHeight: 400)
        .environment(\.colorScheme, .light)
        .tint(JournalPalette.ink)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "safari").font(.system(size: 16, weight: .light))
                Text("THE OTHER SOCK / FIELD NOTES").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1)
                Spacer(minLength: 0)
                Button(action: hide) { Image(systemName: "xmark").font(.system(size: 12)).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help("Close journal").accessibilityLabel("Close journal")
            }.foregroundStyle(JournalPalette.faded)
            Text("Expedition journal").font(.system(size: 28, weight: .medium, design: .serif)).italic()
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(JournalPalette.faded)
            Text(journal.taskTitle.isEmpty ? "Ready for a mission" : journal.taskTitle)
                .font(.system(size: 16, weight: .semibold, design: .serif)).lineLimit(3).textSelection(.enabled)
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(journal.isRunning ? JournalPalette.rust : JournalPalette.faded.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
                Text(journal.status).font(.system(size: 11)).foregroundStyle(JournalPalette.faded).lineLimit(2)
            }
        }.padding(.leading, 36).padding(.trailing, 20).padding(.top, 16).padding(.bottom, 20)
    }
    private var emptyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "map").font(.system(size: 34, weight: .ultraLight)).rotationEffect(.degrees(-8)).foregroundStyle(JournalPalette.faded.opacity(0.6))
            Text("No tracks yet.").font(.system(size: 21, design: .serif)).italic()
            Text("Every adventure starts with a small request. What shall we try today?")
                .font(.system(size: 14, design: .serif)).lineSpacing(5).foregroundStyle(JournalPalette.faded)
        }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var rule: some View {
        Rectangle().fill(JournalPalette.leather.opacity(0.18)).frame(height: 1).padding(.leading, 36).padding(.trailing, 24)
    }
    private var footer: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: newTask) { Label("New task", systemImage: "square.and.pencil").font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8) }
                    .buttonStyle(.plain).background(JournalPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                Button("Stop", action: stop).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(JournalPalette.rust).disabled(!journal.isRunning).opacity(journal.isRunning ? 1 : 0.35)
            }
            HStack {
                Button { journal.followsLatest.toggle() } label: {
                    Label("Follow latest", systemImage: journal.followsLatest ? "checkmark.circle.fill" : "circle").font(.system(size: 10))
                }.buttonStyle(.plain).accessibilityValue(journal.followsLatest ? "On" : "Off")
                Spacer()
                Button("Save log…", action: save).buttonStyle(.plain).font(.system(size: 10))
            }.foregroundStyle(JournalPalette.faded)
        }.padding(.leading, 36).padding(.trailing, 24).padding(.vertical, 16)
    }
}

private struct JournalEntryView: View {
    let entry: ExpeditionJournal.Entry
    let pauseFollowing: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.kind == .request ? "THE MISSION" : (entry.kind == .response ? "EXPLORER’S NOTES" : "ON THE TRAIL"))
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute()).font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(JournalPalette.faded)
            Group {
                if entry.kind == .response { Text(.init(entry.text)) }
                else { Text(entry.text) }
            }
            .font(.system(size: 15, design: .serif)).lineSpacing(5).textSelection(.enabled)
            .foregroundStyle(entry.kind == .activity ? JournalPalette.faded : JournalPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.details.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView {
                        Text(entry.details).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.frame(maxHeight: 220).background(JournalPalette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                } label: { Text("Details").font(.system(size: 10)).foregroundStyle(JournalPalette.faded) }
                .onChange(of: expanded) { _, opened in if opened { pauseFollowing() } }
            }
        }
        .padding(entry.kind == .request ? 12 : 0)
        .background { if entry.kind == .request { RoundedRectangle(cornerRadius: 3).fill(JournalPalette.leather.opacity(0.055)) } }
    }
}
