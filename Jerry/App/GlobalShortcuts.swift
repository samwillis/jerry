import AppKit
@preconcurrency import Carbon

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    var isValid: Bool {
        keyCode < 128 && !(54...63).contains(keyCode) && modifiers & ~Self.allowedModifiers == 0 && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var value: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { value |= UInt32(carbon) }
        }
        modifiers = value
    }
    var modifierFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        for (carbon, flag) in [(cmdKey, NSEvent.ModifierFlags.command), (controlKey, .control), (optionKey, .option), (shiftKey, .shift)] {
            if modifiers & UInt32(carbon) != 0 { result.insert(flag) }
        }
        return result
    }
    @MainActor var keyEquivalent: String {
        let special: [UInt32: String] = [36: "\r", 49: " ", 48: "\t", 51: "\u{8}", 117: "\u{7f}", 53: "\u{1b}", 123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}", 115: "\u{f729}", 119: "\u{f72b}", 116: "\u{f72c}", 121: "\u{f72d}"]
        if let key = special[keyCode] { return key }
        let functionKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        if let index = functionKeys.firstIndex(of: keyCode) { return String(UnicodeScalar(0xf704 + index)!) }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0, count = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &dead, characters.count, &count, &characters)
        return status == noErr ? String(utf16CodeUnits: characters, count: count).lowercased() : ""
    }
    @MainActor var display: String {
        var prefix = ""
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { prefix += symbol }
        }
        let names: [UInt32: String] = [36: "Return", 49: "Space", 48: "Tab", 51: "Delete", 117: "Forward Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        if let name = names[keyCode] { return prefix + " " + name }
        let key = keyEquivalent
        if let scalar = key.unicodeScalars.first, (0xf704...0xf717).contains(scalar.value) { return prefix + " F\(scalar.value - 0xf704 + 1)" }
        return prefix + " " + (key.isEmpty ? "Key \(keyCode)" : key.uppercased())
    }
}

enum GlobalShortcutAction: String, CaseIterable {
    case control, ask
    var title: String { self == .control ? "Take or release control" : "Ask Jerry" }
    var preferenceKey: String { "globalShortcut." + rawValue }
    var defaultShortcut: GlobalShortcut { .init(keyCode: self == .control ? 49 : 36, modifiers: UInt32(controlKey | optionKey)) }
    private struct Saved: Codable { let shortcut: GlobalShortcut? }
    func load(from defaults: UserDefaults = .standard) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: preferenceKey), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return defaultShortcut }
        guard let shortcut = saved.shortcut else { return nil }
        return shortcut.isValid ? shortcut : defaultShortcut
    }
    func save(_ shortcut: GlobalShortcut?, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Saved(shortcut: shortcut)) else { return }
        defaults.set(data, forKey: preferenceKey)
    }
    @MainActor var display: String { load()?.display ?? "Not set" }
}

/// Captures keys only inside its own key window while recording. No global
/// monitor or Accessibility permission is needed to edit a shortcut.
@MainActor
final class ShortcutRecorder: NSButton {
    var shortcut: GlobalShortcut? { didSet { updateTitle() } }
    var onChange: ((GlobalShortcut?) -> String?)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onError: ((String?) -> Void)?
    private(set) var isRecording = false
    private var pendingShortcut: GlobalShortcut?
    private var releaseKey: UInt16?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    init(action: GlobalShortcutAction) {
        shortcut = action.load()
        super.init(frame: .zero)
        bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self; self.action = #selector(toggleRecording)
        setAccessibilityLabel(action.title + " shortcut")
        toolTip = "Click, then press a shortcut. Delete clears it; Esc cancels."
        NotebookTheme.style(self); updateTitle()
    }
    required init?(coder: NSCoder) { fatalError("Use init(action:)") }
    override var acceptsFirstResponder: Bool { true }
    private func updateTitle() {
        let text = isRecording ? (releaseKey == nil ? "Press shortcut…" : "Release keys…") : (shortcut?.display ?? "Not set")
        title = text
        attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NotebookTheme.ink])
    }
    @objc private func toggleRecording() {
        if isRecording { cancelRecording(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true; updateTitle(); onError?(nil); onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isRecording else { return false }
                guard self.window?.isKeyWindow == true, self.window?.firstResponder === self else { self.cancelRecording(); return false }
                self.capture(event); return true
            }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }
    private func capture(_ event: NSEvent) {
        if let releaseKey {
            if event.type == .keyUp && event.keyCode == releaseKey {
                let candidate = pendingShortcut
                self.releaseKey = nil; pendingShortcut = nil
                if let error = onChange?(candidate) { updateTitle(); onError?(error) }
                else { shortcut = candidate; cancelRecording(); onError?(nil) }
            }
            return
        }
        guard event.type == .keyDown, !event.isARepeat else { return }
        if event.keyCode == 53 { cancelRecording(); return }
        let candidate = GlobalShortcut(event: event)
        let plain = candidate.modifiers == 0
        if plain && event.keyCode == 48 { cancelRecording(); return }
        let clear = plain && [51, 117].contains(event.keyCode)
        guard clear || candidate.isValid else { onError?("Include Command, Option or Control in your shortcut."); return }
        // Do not even probe registration until key-up. Registering a held
        // combination could steal its release event or trigger the action.
        releaseKey = event.keyCode; pendingShortcut = clear ? nil : candidate
        updateTitle(); onError?(nil)
    }
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false; releaseKey = nil; pendingShortcut = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        updateTitle(); onRecordingChanged?(false); onError?(nil)
    }
    override func resignFirstResponder() -> Bool { cancelRecording(); return super.resignFirstResponder() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { cancelRecording() } }
}

/// A registered system hotkey, rather than a global keyboard event monitor.
@MainActor
final class ExplorerControlHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    private var binding: GlobalShortcut?
    private let id: UInt32
    init(keyCode: UInt32 = 49, id: UInt32 = 1) { binding = .init(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey)); self.id = id }
    var onTrigger: (() -> Void)?
    var isRegistered: Bool { reference != nil }
    func register() { _ = configure(binding) }
    /// Acquire the replacement first: a conflict must leave the old binding alive.
    @discardableResult func configure(_ shortcut: GlobalShortcut?) -> Bool {
        guard let shortcut else { close(); binding = nil; return true }
        guard shortcut.isValid else { return false }
        if binding == shortcut, reference != nil { return true }
        if handler == nil, !installHandler() { return false }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x536f636b, id: id), GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr, let replacement else { if reference == nil { close() }; return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement; binding = shortcut; pressed = false
        return true
    }
    private func installHandler() -> Bool {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ExplorerControlHotKey>.fromOpaque(pointer).takeUnretainedValue()
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                      identifier.signature == 0x536f636b, identifier.id == owner.id else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed = false }
                else if !owner.pressed { owner.pressed = true; owner.onTrigger?() }
                return noErr
            }
        }, 2, &specs, pointer, &handler)
        return installed == noErr
    }
    #if DEBUG
    func dispatchNativeCheck() -> OSStatus {
        var event: EventRef?
        let result = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event)
        guard result == noErr, let event else { return result }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x536f636b, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
        let first = SendEventToEventTarget(event, GetApplicationEventTarget())
        _ = SendEventToEventTarget(event, GetApplicationEventTarget()) // Holding must not toggle twice.
        var released: EventRef?
        if CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyReleased), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &released) == noErr, let released {
            SetEventParameter(released, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
            SendEventToEventTarget(released, GetApplicationEventTarget()); ReleaseEvent(released)
        }
        return first
    }
    #endif
    func close() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        pressed = false
    }
}
