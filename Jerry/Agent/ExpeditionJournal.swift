import AppKit
import SwiftUI
import CoreText

@MainActor
final class ExpeditionJournal: ObservableObject {
    enum Kind: String, Codable, Sendable { case request, response, activity }
    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let date: Date
        let kind: Kind
        var text: String
        var details: String
        var photo: String? = nil
    }
    struct Expedition: Identifiable {
        let id: UUID
        let date: Date
        var title: String
        var entries: [Entry] = []
        var status = "Ready for your next direction"
        var isRunning = false
        var isFinished = false
    }
    @Published private(set) var expeditions: [Expedition] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var activeID: UUID?
    @Published private(set) var storageIssue: String?
    @Published private(set) var saveFailed = false
    private var store: ExpeditionJournalStore?
    var committedStore: ExpeditionJournalStore? { store }
    private var restoreWarning: String?
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Jerry/Expeditions", isDirectory: true)
    }
    init(storageDirectory: URL? = ExpeditionJournal.defaultDirectory) {
        guard let storageDirectory else { return }
        let store = ExpeditionJournalStore(directory: storageDirectory) { [weak self] issue in
            Task { @MainActor [weak self] in self?.storageIssue = issue ?? self?.restoreWarning; self?.saveFailed = issue != nil }
        }
        self.store = store
        let restored = store.restore(); restoreWarning = restored.warning; storageIssue = restored.warning
        expeditions = restored.expeditions.map {
            Expedition(id: $0.header.id, date: $0.header.date, title: $0.header.title, entries: $0.entries,
                       status: $0.wasRunning ? "Paused after restarting — add a direction to continue" : $0.status,
                       isRunning: false, isFinished: $0.isFinished)
        }
        activeID = expeditions.last(where: { !$0.isFinished })?.id
        selectedID = activeID ?? expeditions.last?.id
        for saved in restored.expeditions where saved.wasRunning {
            if let expedition = expeditions.first(where: { $0.id == saved.header.id }) { recordState(expedition) }
        }
    }
    func flush() { store?.flush() }
    func retrySaving() { store?.retry() }
    private func recordState(_ expedition: Expedition) {
        store?.append(.init(event: .state, status: expedition.status, isRunning: expedition.isRunning, isFinished: expedition.isFinished), to: expedition.id)
    }
    @Published private(set) var revision = 0
    @Published var followsLatest = true
    @Published var sidebarVisible = true
    @Published var toolbarHeight: CGFloat = 52
    @Published var composerFocusRevision = 0
    var selected: Expedition? { expeditions.first { $0.id == selectedID } }
    var entries: [Entry] { selected?.entries ?? [] }
    var taskTitle: String { selected?.title ?? "Ready for an expedition" }
    var status: String {
        get { selected?.status ?? "Ask Jerry to start a new expedition." }
        set { changeActive { $0.status = newValue } }
    }
    var isRunning: Bool {
        get { expeditions.first { $0.id == activeID }?.isRunning ?? false }
        set { changeActive { $0.isRunning = newValue } }
    }
    private func changeActive(_ change: (inout Expedition) -> Void) {
        guard let index = expeditions.firstIndex(where: { $0.id == activeID }) else { return }
        let previous = expeditions[index]
        change(&expeditions[index]); revision += 1
        let current = expeditions[index]
        if previous.status != current.status || previous.isRunning != current.isRunning || previous.isFinished != current.isFinished { recordState(current) }
    }
    func select(_ id: UUID) { selectedID = id; followsLatest = true; revision += 1 }
    func finishActive() {
        changeActive { $0.isRunning = false; $0.isFinished = true; $0.status = "Expedition finished" }
        activeID = nil; revision += 1; flush()
    }
    func prepareNew() { finishActive(); selectedID = nil; revision += 1 }
    @discardableResult func continueExpedition(prompt: String, id: UUID? = nil) -> UUID {
        if let target = id ?? activeID, let index = expeditions.firstIndex(where: { $0.id == target }) {
            if activeID != target { finishActive() }
            activeID = target; selectedID = target; expeditions[index].isFinished = false
            followsLatest = true; revision += 1; recordState(expeditions[index]); return target
        }
        finishActive()
        let expedition = Expedition(id: UUID(), date: Date(), title: "An untitled adventure")
        expeditions.append(expedition); activeID = expedition.id; selectedID = expedition.id
        store?.append(.init(event: .created, expedition: .init(id: expedition.id, date: expedition.date, title: expedition.title)), to: expedition.id)
        followsLatest = true; revision += 1; flush(); return expedition.id
    }
    var needsTitle: Bool {
        guard let expedition = expeditions.first(where: { $0.id == activeID }) else { return false }
        return expedition.title == "An untitled adventure" || expedition.entries.first(where: { $0.kind == .request }).map { expedition.title == String($0.text.prefix(100)) } == true
    }
    func nameExpedition(_ text: String) -> Bool {
        let title = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").trimmingCharacters(in: .init(charactersIn: "\"“”"))
        guard needsTitle, !title.isEmpty, title.count <= 70, let id = activeID else { return false }
        let prompt = expeditions.first(where: { $0.id == id })?.entries.first(where: { $0.kind == .request })?.text
        if let prompt, prompt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").caseInsensitiveCompare(title) == .orderedSame { return false }
        changeActive { $0.title = title }
        store?.append(.init(event: .titleChanged, text: title), to: id)
        return true
    }
    @discardableResult func append(_ kind: Kind, _ text: String, details: String = "") -> UUID {
        if activeID == nil { continueExpedition(prompt: text) }
        let entry = Entry(id: UUID(), date: Date(), kind: kind, text: text, details: details)
        changeActive { $0.entries.append(entry) }
        if let activeID { store?.append(.init(event: .entry, entry: entry), to: activeID) }
        return entry.id
    }
    func savePhoto(_ data: Data, caption: String) async throws {
        guard let expedition = activeID, let store else { throw AgentConnectionError(message: "A saved expedition is needed for photos.") }
        let filename = try await store.savePhoto(data, to: expedition)
        // Capture may finish after an interruption. Keep the photo in its original expedition.
        guard let index = expeditions.firstIndex(where: { $0.id == expedition }) else { return }
        let entry = Entry(id: UUID(), date: Date(), kind: .activity, text: String(caption.prefix(300)), details: "Local photograph of Jerry and the task window. Not attached to the AI conversation.", photo: filename)
        expeditions[index].entries.append(entry); revision += 1
        store.append(.init(event: .entry, entry: entry), to: expedition)
    }
    func photoURL(for entry: Entry) -> URL? {
        guard let store, let filename = entry.photo, filename.hasSuffix(".jpg"), UUID(uuidString: String(filename.dropLast(4))) != nil,
              let expedition = expeditions.first(where: { $0.entries.contains(where: { $0.id == entry.id }) }) else { return nil }
        let folder = store.directory.appendingPathComponent(expedition.id.uuidString)
        let url = folder.appendingPathComponent(filename)
        guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]), values.isSymbolicLink == false, values.isRegularFile == true else { return nil }
        return url
    }
    func update(_ id: UUID, text: String) {
        for expedition in expeditions.indices {
            guard let row = expeditions[expedition].entries.firstIndex(where: { $0.id == id }) else { continue }
            let previous = expeditions[expedition].entries[row].text
            if previous != text {
                expeditions[expedition].entries[row].text = text; revision += 1
                let appending = text.hasPrefix(previous)
                store?.append(.init(event: appending ? .textAppended : .textReplaced, entryID: id, text: appending ? String(text.dropFirst(previous.count)) : text), to: expeditions[expedition].id)
            }
            return
        }
    }
    func addDetails(_ id: UUID, _ text: String) {
        for expedition in expeditions.indices {
            guard let row = expeditions[expedition].entries.firstIndex(where: { $0.id == id }) else { continue }
            let addition = (expeditions[expedition].entries[row].details.isEmpty ? "" : "\n\n") + text
            expeditions[expedition].entries[row].details += addition
            store?.append(.init(event: .detailsAppended, entryID: id, text: addition), to: expeditions[expedition].id)
            revision += 1; return
        }
    }
    func exportText() -> String {
        let clock = ISO8601DateFormatter()
        return expeditions.map { expedition in
            let entries = expedition.entries.map { entry in
                let role = entry.kind == .request ? "YOUR INSTRUCTION" : (entry.kind == .response ? "JERRY" : "JOURNAL")
                return "\(clock.string(from: entry.date))  \(role)\n\(entry.text)" + (entry.photo.map { "\n[Photograph: \(expedition.id.uuidString)/\($0)]" } ?? "") + (entry.details.isEmpty ? "" : "\n\nDETAILS\n\(entry.details)")
            }.joined(separator: "\n\n────────────────────\n\n")
            return "EXPEDITION: \(expedition.title)\n\(clock.string(from: expedition.date))\n\n" + entries
        }.joined(separator: "\n\n════════════════════\n\n")
    }
}

/// Shared by the SwiftUI journal and the AppKit welcome/settings notebooks.
@MainActor
enum NotebookTheme {
    static let marginX: CGFloat = 25
    static let cornerRadius: CGFloat = 12
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
    private static let journalFontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func journalFont(_ size: CGFloat) -> NSFont {
        _ = journalFontRegistered
        return NSFont(name: "Caveat-Regular", size: size) ?? font(size)
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
            let origin = NSPoint(x: marginX + 12 + CGFloat(index) * 20, y: content.bounds.height - 16 - size.height / 2)
            let converted = content.convert(origin, to: parent)
            button.setFrameOrigin(.init(x: converted.x, y: window.toolbar == nil ? converted.y : button.frame.minY))
        }
    }
    static func install(on window: NSWindow, title: String, showsCaption: Bool = true, toolbar: NSToolbar? = nil) -> NSView {
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true; window.appearance = NSAppearance(named: .aqua)
        let root = NotebookPaperView(); root.wantsLayer = true; root.layer?.cornerRadius = cornerRadius; root.layer?.masksToBounds = true
        window.contentView = root
        if let toolbar {
            window.toolbarStyle = .unified; window.toolbar = toolbar
            let body = NSView(); body.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(body)
            NSLayoutConstraint.activate([
                body.topAnchor.constraint(equalTo: (window.contentLayoutGuide as! NSLayoutGuide).topAnchor),
                body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
                body.trailingAnchor.constraint(equalTo: root.trailingAnchor), body.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
            return body
        }
        let header = NotebookHeaderView(); header.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(header)
        let caption = NSTextField(labelWithString: "◉  JERRY / " + title.uppercased())
        caption.isHidden = !showsCaption
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
    override func update() {
        super.update()
        // AppKit lays out the toolbar after the content view. Apply the paper
        // inset last, so its native titlebar layout cannot reset the controls.
        if let contentView { NotebookTheme.alignWindowButtons(in: contentView) }
    }
}

private final class NotebookHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

class NotebookContentView: NSView {
    var onTitlebarLayout: ((CGFloat) -> Void)?
    private var previousTitlebarHeight: CGFloat = -1
    override func layout() {
        super.layout(); NotebookTheme.alignWindowButtons(in: self)
        DispatchQueue.main.async { [weak self] in
            if let self { NotebookTheme.alignWindowButtons(in: self) }
        }
        if let window, window.toolbar != nil {
            let height = max(0, bounds.maxY - convert(window.contentLayoutRect, from: nil).maxY)
            if abs(height - previousTitlebarHeight) > 0.5 {
                previousTitlebarHeight = height
                DispatchQueue.main.async { [weak self] in self?.onTitlebarLayout?(height) }
            }
        }
    }
}

private final class NotebookPaperView: NotebookContentView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NotebookTheme.paper.setFill(); bounds.fill()
        NotebookTheme.leather.withAlphaComponent(0.025).setStroke()
        let fibres = NSBezierPath(); fibres.lineWidth = 0.5
        for y in stride(from: CGFloat(2), to: bounds.height, by: 4) { fibres.move(to: .init(x: 10, y: y)); fibres.line(to: .init(x: bounds.width, y: y)) }; fibres.stroke()
        NotebookTheme.rust.withAlphaComponent(0.22).setStroke()
        let margin = NSBezierPath(); margin.lineWidth = 0.7; margin.move(to: .init(x: NotebookTheme.marginX, y: 0)); margin.line(to: .init(x: NotebookTheme.marginX, y: bounds.height)); margin.stroke()
        NotebookTheme.leather.setFill(); NSRect(x: 0, y: 0, width: 10, height: bounds.height).fill()
        NotebookTheme.paper.withAlphaComponent(0.5).setStroke()
        let stitches = NSBezierPath(); stitches.lineWidth = 1
        for y in stride(from: CGFloat(12), to: bounds.height, by: 10) { stitches.move(to: .init(x: 5, y: y)); stitches.line(to: .init(x: 5, y: y + 4)) }; stitches.stroke()
        NotebookTheme.leather.withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: NotebookTheme.cornerRadius, yRadius: NotebookTheme.cornerRadius).stroke()
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
    let send: (String, UUID?) -> Void
    @State private var instruction = ""
    @FocusState private var composing: Bool
    private var leadingInset: CGFloat { journal.sidebarVisible ? 20 : 36 }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: journal.toolbarHeight)
            HStack(spacing: 0) {
                if journal.sidebarVisible {
                    sidebar
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(JournalPalette.leather.opacity(0.15)).frame(width: 1)
                                .padding(.top, -journal.toolbarHeight).allowsHitTesting(false)
                        }
                        .transition(.move(edge: .leading))
                }
                VStack(spacing: 0) { pages; composer }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.2), value: journal.sidebarVisible)
        }
        .font(Font(NotebookTheme.journalFont(17)))
        .foregroundStyle(JournalPalette.ink)
        .background(notebookPaper)
        .clipShape(RoundedRectangle(cornerRadius: NotebookTheme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: NotebookTheme.cornerRadius).strokeBorder(JournalPalette.leather.opacity(0.22), lineWidth: 1).allowsHitTesting(false) }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: journal.sidebarVisible ? 560 : 360, minHeight: 380)
        .environment(\.colorScheme, .light)
        .tint(JournalPalette.ink)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Expeditions").font(Font(NotebookTheme.journalFont(14))).tracking(0.4)
                .foregroundStyle(JournalPalette.faded).padding(.horizontal, 9)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if journal.expeditions.isEmpty {
                        Text("No expeditions yet").font(Font(NotebookTheme.journalFont(17))).italic()
                            .foregroundStyle(JournalPalette.faded).padding(9)
                    }
                    ForEach(journal.expeditions.reversed()) { expedition in
                        Button { journal.select(expedition.id); instruction = "" } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(expedition.title).font(Font(NotebookTheme.journalFont(17)))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                HStack(spacing: 5) {
                                    if expedition.id == journal.activeID {
                                        Circle().fill(expedition.isRunning ? JournalPalette.rust : JournalPalette.ink).frame(width: 4, height: 4)
                                    }
                                    Text(expedition.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                                        .font(Font(NotebookTheme.journalFont(13)))
                                }.foregroundStyle(JournalPalette.faded)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(journal.selectedID == expedition.id ? JournalPalette.leather.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help(expedition.title)
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.leading, 28).padding(.trailing, 10).padding(.vertical, 14).frame(width: 176)
        .frame(maxHeight: .infinity).background(JournalPalette.leather.opacity(0.025))
    }
    private var pages: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let expedition = journal.selected {
                            Text(expedition.date, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(Font(NotebookTheme.journalFont(14))).foregroundStyle(JournalPalette.faded)
                            ForEach(expedition.entries) { entry in
                                JournalEntryView(entry: entry, photoURL: journal.photoURL(for: entry), pauseFollowing: { journal.followsLatest = false }).id(entry.id)
                            }
                            if expedition.isRunning {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Jerry is working…").font(Font(NotebookTheme.journalFont(17))).italic()
                                }.foregroundStyle(JournalPalette.faded)
                            } else if expedition.isFinished || expedition.status != "Ready for your next direction" {
                                Text(expedition.status).font(Font(NotebookTheme.journalFont(17))).italic().foregroundStyle(JournalPalette.faded)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("A new expedition").font(Font(NotebookTheme.journalFont(29))).italic()
                                Text("Where shall we go?").font(Font(NotebookTheme.journalFont(18))).foregroundStyle(JournalPalette.faded)
                            }.padding(.top, 14)
                        }
                        if let issue = journal.storageIssue {
                            HStack(alignment: .top, spacing: 10) {
                                Text(issue).font(Font(NotebookTheme.journalFont(17)))
                                if journal.saveFailed { Button("Retry saving") { journal.retrySaving() }.buttonStyle(.link) }
                            }.foregroundStyle(JournalPalette.rust)
                        }
                        Color.clear.frame(height: 1).id("journal-bottom")
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, leadingInset).padding(.trailing, 20).padding(.vertical, 18)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: JournalLegacyScrollKey.self, value: .init(bottom: geometry.frame(in: .named("journal-scroll")).maxY, height: geometry.size.height))
                        }
                    }
                }
                .coordinateSpace(name: "journal-scroll")
                .accessibilityValue(journal.followsLatest ? "Following latest" : "Reading earlier entries")
                .modifier(JournalScrollTracking(followsLatest: $journal.followsLatest, viewportHeight: viewport.size.height, pin: { proxy.scrollTo("journal-bottom", anchor: .bottom) }))
                .onChange(of: journal.revision) { _, _ in
                    if journal.followsLatest && journal.selectedID == journal.activeID { proxy.scrollTo("journal-bottom", anchor: .bottom) }
                }
                .onChange(of: journal.selectedID) { _, _ in proxy.scrollTo("journal-bottom", anchor: .bottom) }
            }
        }.clipped()
    }
    private var composer: some View {
        HStack(spacing: 9) {
            TextField(journal.selected == nil ? "Give Jerry a mission…" : (journal.selectedID == journal.activeID ? "Add a direction…" : "Resume this expedition…"), text: $instruction)
                .textFieldStyle(.plain).font(.custom("Courier", size: 12))
                .focused($composing).onSubmit(submitInstruction)
                .onChange(of: journal.composerFocusRevision) { _, _ in instruction = ""; composing = true }
                .onChange(of: instruction) { _, text in if !text.isEmpty && journal.isRunning { stop() } }
                .accessibilityLabel("Expedition instruction")
            Button(action: submitInstruction) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)) }
                .buttonStyle(.plain).disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send expedition instruction")
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(JournalPalette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(JournalPalette.ink.opacity(composing ? 0.32 : 0.13), lineWidth: 1) }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
        .padding(.leading, leadingInset).padding(.trailing, 20).padding(.top, 10).padding(.bottom, 14)
    }
    private var notebookPaper: some View {
        ZStack(alignment: .leading) {
            JournalPalette.paper
            Canvas { context, size in
                for y in stride(from: 2.0, to: size.height, by: 4) {
                    var fibre = Path(); fibre.move(to: .init(x: 12, y: y)); fibre.addLine(to: .init(x: size.width, y: y))
                    context.stroke(fibre, with: .color(JournalPalette.leather.opacity(0.025)), lineWidth: 0.5)
                }
                var margin = Path(); margin.move(to: .init(x: NotebookTheme.marginX, y: 0)); margin.addLine(to: .init(x: NotebookTheme.marginX, y: size.height))
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
    private func submitInstruction() {
        let value = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        composing = false; send(value, journal.selectedID); instruction = ""
    }
}

private struct JournalLegacyScrollPosition: Equatable {
    var bottom: CGFloat = 0
    var height: CGFloat = 0
}
private struct JournalLegacyScrollKey: PreferenceKey {
    static let defaultValue = JournalLegacyScrollPosition()
    static func reduce(value: inout JournalLegacyScrollPosition, nextValue: () -> JournalLegacyScrollPosition) { value = nextValue() }
}
private struct JournalScrollMetrics: Equatable {
    var nearBottom: Bool
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var viewportWidth: CGFloat
    var offset: CGFloat
}
private struct JournalScrollTracking: ViewModifier {
    @Binding var followsLatest: Bool
    let viewportHeight: CGFloat
    let pin: () -> Void
    @State private var userScrolling = false
    @State private var previousLegacyHeight: CGFloat = 0
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollPhaseChange { _, phase in userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating }
                .onScrollGeometryChange(for: JournalScrollMetrics.self) { geometry in
                    .init(nearBottom: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 80, contentHeight: geometry.contentSize.height, viewportHeight: geometry.containerSize.height, viewportWidth: geometry.containerSize.width, offset: geometry.contentOffset.y)
                } action: { old, new in
                    let movedUp = new.offset < old.offset - 0.5 && abs(new.contentHeight - old.contentHeight) < 0.5
                        && new.viewportHeight == old.viewportHeight && new.viewportWidth == old.viewportWidth
                    if new.nearBottom { followsLatest = true }
                    else if userScrolling || movedUp { followsLatest = false }
                    if followsLatest && (old.contentHeight != new.contentHeight || old.viewportHeight != new.viewportHeight) { pin() }
                }
        } else {
            content.onPreferenceChange(JournalLegacyScrollKey.self) { position in
                let nearBottom = position.bottom < viewportHeight + 80
                let contentChanged = abs(position.height - previousLegacyHeight) > 0.5
                if nearBottom || !contentChanged { followsLatest = nearBottom }
                previousLegacyHeight = position.height
                if followsLatest && contentChanged { pin() }
            }
        }
    }
}

private struct JournalEntryView: View {
    let entry: ExpeditionJournal.Entry
    let photoURL: URL?
    let pauseFollowing: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entryPaper
            if !entry.details.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView {
                        Text(entry.details).font(.custom("Courier", size: 11)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.frame(maxHeight: 180)
                        .background { JournalPaperCutout().fill(.white).shadow(color: .black.opacity(0.12), radius: 2, x: 1, y: 2) }
                        .overlay(alignment: .topTrailing) {
                            JournalTape().frame(width: 43, height: 15).rotationEffect(.degrees(11)).offset(x: -14, y: -6)
                        }
                        .padding(.vertical, 10)
                } label: { Text("Details").font(.custom("Courier", size: 11)).foregroundStyle(JournalPalette.faded) }
                .onChange(of: expanded) { _, opened in if opened { pauseFollowing() } }
            }
        }
    }
    private var entryPaper: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.photo != nil ? "A memento" : (entry.kind == .request ? "Your direction" : (entry.kind == .response ? "Jerry’s notes" : "On the trail")))
                    .font(Font(NotebookTheme.journalFont(14))).tracking(0.3)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute()).font(Font(NotebookTheme.journalFont(13)))
            }.foregroundStyle(JournalPalette.faded)
            if entry.photo != nil {
                VStack(spacing: 0) {
                    JournalPhotograph(url: photoURL, caption: entry.text)
                        .overlay(Rectangle().stroke(.black.opacity(0.12), lineWidth: 0.5))
                    Text(entry.text).font(Font(NotebookTheme.journalFont(19))).foregroundStyle(JournalPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                        .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 10).textSelection(.enabled)
                }
                .padding([.top, .horizontal], 12).frame(maxWidth: 320)
                .background(Color(red: 1, green: 0.995, blue: 0.975))
                .overlay(Rectangle().stroke(JournalPalette.leather.opacity(0.16), lineWidth: 0.5))
                // Flatten the opaque print before shadowing: otherwise SwiftUI
                // can shadow the photo and handwriting as separate descendants.
                .compositingGroup()
                .shadow(color: .black.opacity(0.15), radius: 4, x: 1, y: 3)
                .overlay(alignment: .top) {
                    JournalTape().frame(width: 54, height: 18).rotationEffect(.degrees(-5)).offset(y: -8)
                }
                .rotationEffect(.degrees(-1.7))
                .padding(.horizontal, 10).padding(.vertical, 14)
            } else { Group {
                if entry.kind == .response { Text(.init(entry.text)) }
                else { Text(entry.text) }
            }
            .font(entry.kind == .request ? .custom("Courier", size: 12) : Font(NotebookTheme.journalFont(18))).lineSpacing(4).textSelection(.enabled)
            .foregroundStyle(entry.kind == .activity ? JournalPalette.faded : JournalPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.kind == .response {
                Text("— Jerry").font(Font(NotebookTheme.journalFont(20))).foregroundStyle(JournalPalette.faded)
            }
            }

        }
        .padding(entry.kind == .request ? 14 : 0)
        .background {
            if entry.kind == .request {
                JournalPaperCutout().fill(Color(red: 1, green: 0.998, blue: 0.985))
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0.5, y: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if entry.kind == .request {
                JournalTape().frame(width: 46, height: 16).rotationEffect(.degrees(-13)).offset(x: 15, y: -7)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if entry.kind == .request {
                JournalTape().frame(width: 42, height: 16).rotationEffect(.degrees(-9)).offset(x: -13, y: 6)
            }
        }
        .padding(.vertical, entry.kind == .request ? 9 : 0)
    }
}

/// Read photo bytes off the main thread, once per asset rather than on every streamed token.
private struct JournalPhotograph: View {
    let url: URL?
    let caption: String
    @State private var image: NSImage?
    @State private var loaded = false
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .accessibilityLabel("Expedition photograph: " + caption)
                } else {
                    Label(loaded ? "Photograph unavailable" : "Developing photograph…", systemImage: "photo")
                        .font(Font(NotebookTheme.journalFont(17))).foregroundStyle(JournalPalette.faded)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }.aspectRatio(1, contentMode: .fit)
        .background(JournalPalette.ink.opacity(0.025))
        .task(id: url) {
            let data = await Task.detached(priority: .utility) { url.flatMap { try? Data(contentsOf: $0) } }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { NSImage(data: $0) }; loaded = true
        }
    }
}

/// Translucent tape with uneven cut ends and a small reflected crease.
private struct JournalTape: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Path { path in
                path.move(to: .init(x: 1, y: 0)); path.addLine(to: .init(x: size.width - 1, y: 0.7))
                path.addLine(to: .init(x: size.width - 2, y: size.height * 0.3))
                path.addLine(to: .init(x: size.width, y: size.height * 0.55))
                path.addLine(to: .init(x: size.width - 1, y: size.height))
                path.addLine(to: .init(x: 0, y: size.height - 0.5))
                path.addLine(to: .init(x: 1.5, y: size.height * 0.6))
                path.addLine(to: .init(x: 0, y: size.height * 0.3)); path.closeSubpath()
            }.fill(LinearGradient(colors: [Color(red: 0.88, green: 0.83, blue: 0.62).opacity(0.48), Color.white.opacity(0.35), Color(red: 0.82, green: 0.76, blue: 0.55).opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(.white.opacity(0.3)).frame(height: 0.5).offset(y: 2)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct JournalPaperCutout: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .init(x: 0.5, y: 0.5))
            path.addLine(to: .init(x: rect.width * 0.4, y: 0)); path.addLine(to: .init(x: rect.maxX, y: 0.8))
            path.addLine(to: .init(x: rect.maxX - 0.5, y: rect.maxY)); path.addLine(to: .init(x: rect.width * 0.6, y: rect.maxY - 0.7))
            path.addLine(to: .init(x: 0, y: rect.maxY)); path.closeSubpath()
        }
    }
}
