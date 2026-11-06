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

/// Shared by the SwiftUI journal and the AppKit welcome/settings notebooks.
@MainActor
enum NotebookTheme {
    static let paper = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.25, alpha: 1)
    static let faded = NSColor(calibratedRed: 0.45, green: 0.45, blue: 0.36, alpha: 1)
    static let leather = NSColor(calibratedRed: 0.38, green: 0.26, blue: 0.17, alpha: 1)
    static let rust = NSColor(calibratedRed: 0.64, green: 0.32, blue: 0.22, alpha: 1)
    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard var descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
    static func style(_ button: NSButton, primary: Bool = false) {
        button.bezelStyle = .rounded; button.bezelColor = primary ? ink : leather.withAlphaComponent(0.09)
        button.contentTintColor = primary ? paper : ink
        button.font = .systemFont(ofSize: 12, weight: primary ? .medium : .regular)
        let title = NSAttributedString(string: button.title, attributes: [.foregroundColor: primary ? paper : ink, .font: button.font!])
        button.attributedTitle = title; button.attributedAlternateTitle = title
    }
    /// Keep the native controls clear of the binding and level with the field-note title.
    static func alignWindowButtons(in content: NSView) {
        guard let window = content.window else { return }
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            let size = button.frame.size
            let origin = NSPoint(x: 36 + CGFloat(index) * 20, y: content.bounds.height - 16 - size.height / 2)
            button.setFrameOrigin(content.convert(origin, to: parent))
        }
    }
    static func install(on window: NSWindow, title: String) -> NSView {
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true; window.appearance = NSAppearance(named: .aqua)
        let root = NotebookPaperView(); root.wantsLayer = true; root.layer?.cornerRadius = 12; root.layer?.masksToBounds = true
        window.contentView = root
        let header = NotebookHeaderView(); header.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(header)
        let caption = NSTextField(labelWithString: "◉  THE OTHER SOCK / " + title.uppercased())
        caption.font = .monospacedSystemFont(ofSize: 10, weight: .medium); caption.textColor = faded
        caption.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(caption)
        let body = NSView(); body.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(body)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 44),
            caption.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 94), caption.centerYAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            body.topAnchor.constraint(equalTo: header.bottomAnchor), body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), body.trailingAnchor.constraint(equalTo: root.trailingAnchor), body.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        return body
    }
}

@MainActor
final class NotebookWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class NotebookHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class NotebookContentView: NSView {
    override func layout() { super.layout(); NotebookTheme.alignWindowButtons(in: self) }
}

private final class NotebookPaperView: NSView {
    override func layout() { super.layout(); NotebookTheme.alignWindowButtons(in: self) }
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NotebookTheme.paper.setFill(); bounds.fill()
        NotebookTheme.leather.withAlphaComponent(0.025).setStroke()
        let fibres = NSBezierPath(); fibres.lineWidth = 0.5
        for y in stride(from: CGFloat(2), to: bounds.height, by: 4) { fibres.move(to: .init(x: 10, y: y)); fibres.line(to: .init(x: bounds.width, y: y)) }; fibres.stroke()
        NotebookTheme.rust.withAlphaComponent(0.22).setStroke()
        let margin = NSBezierPath(); margin.lineWidth = 0.7; margin.move(to: .init(x: 25, y: 0)); margin.line(to: .init(x: 25, y: bounds.height)); margin.stroke()
        NotebookTheme.leather.setFill(); NSRect(x: 0, y: 0, width: 10, height: bounds.height).fill()
        NotebookTheme.paper.withAlphaComponent(0.5).setStroke()
        let stitches = NSBezierPath(); stitches.lineWidth = 1
        for y in stride(from: CGFloat(12), to: bounds.height, by: 10) { stitches.move(to: .init(x: 5, y: y)); stitches.line(to: .init(x: 5, y: y + 4)) }; stitches.stroke()
        NotebookTheme.leather.withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12).stroke()
    }
}

@MainActor
private enum JournalPalette {
    static let paper = Color(nsColor: NotebookTheme.paper)
    static let ink = Color(nsColor: NotebookTheme.ink)
    static let faded = Color(nsColor: NotebookTheme.faded)
    static let leather = Color(nsColor: NotebookTheme.leather)
    static let rust = Color(nsColor: NotebookTheme.rust)
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
        .ignoresSafeArea(.container, edges: .top)
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
            }.frame(height: 16).foregroundStyle(JournalPalette.faded).padding(.leading, 72)
            Text("Expedition journal").font(.system(size: 28, weight: .medium, design: .serif)).italic()
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(JournalPalette.faded)
            Text(journal.taskTitle.isEmpty ? "Ready for a mission" : journal.taskTitle)
                .font(.system(size: 16, weight: .semibold, design: .serif)).lineLimit(3).textSelection(.enabled)
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(journal.isRunning ? JournalPalette.rust : JournalPalette.faded.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
                Text(journal.status).font(.system(size: 11)).foregroundStyle(JournalPalette.faded).lineLimit(2)
            }
        }.padding(.leading, 36).padding(.trailing, 20).padding(.top, 8).padding(.bottom, 20)
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
