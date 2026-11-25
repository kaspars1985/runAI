import Cocoa
import ApplicationServices

/// Ievieto tekstu aktīvajā lietotnē: vispirms mēģina caur Accessibility API,
/// pēc tam — starpliktuve + ⌘V simulācija.
/// Ja tiešā ievietošana izdodas, lietotāja starpliktuve netiek aiztikta.
final class TextInserter {

    enum InsertOutcome {
        case insertedDirectly   // Ievietots caur Accessibility API tieši kursorā
        case pastedViaShortcut  // Ielīmēts caur ⌘V simulāciju
        case copiedOnly         // Teksts tukšs vai nevarēja ievietot
    }

    /// Lomas, kurām nav jēgas mēģināt ⌘V (tās nav teksta ievades lauki).
    private static let nonTextRoles: Set<String> = [
        "AXApplication", "AXWindow", "AXButton", "AXMenuBar", "AXMenuItem",
        "AXList", "AXOutline", "AXTable", "AXScrollArea", "AXImage",
        "AXToolbar", "AXTabGroup", "AXSplitGroup", "AXRadioButton",
        "AXCheckBox", "AXPopUpButton", "AXSlider", "AXDisclosureTriangle",
        "AXSheet", "AXDrawer", "AXIcon"
    ]

    /// Nosaka, vai, ņemot vērā fokusētā elementa lomu un "AXEditable" atribūtu,
    /// jāizmanto ⌘V (true) vai arī teksts jāatstāj tikai starpliktuvē (false).
    static func shouldFallbackToPaste(role: String?, isEditable: Bool?) -> Bool {
        if isEditable == true { return true }
        if role == nil { return true }
        if let role = role, nonTextRoles.contains(role) { return false }
        return true
    }

    /// Ievieto tekstu aktīvajā lietotnē.
    @discardableResult
    func insert(_ text: String) -> InsertOutcome {
        guard !text.isEmpty else { return .copiedOnly }

        let pb = NSPasteboard.general
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication

        // 1. Mēģinām ievietot tieši kursorā caur Accessibility.
        // Ja izdodas — starpliktuve netiek aiztikta (lietotāja starpliktuve saglabājas).
        if let front = front, front.processIdentifier != selfPID {
            if insertViaAccessibility(text, pid: front.processIdentifier) {
                AppLogger.info("TextInserter: ievietots tieši caur Accessibility API")
                return .insertedDirectly
            }
        }

        // 2. Ja nav aktīvas lietotnes, tā ir mēs paši, vai fokusētais elements nav
        // teksta ievades lauks — tekstu tikai ievietojam starpliktuvē.
        if front == nil || front!.processIdentifier == selfPID {
            pb.clearContents()
            pb.setString(text, forType: .string)
            AppLogger.info("TextInserter: nav aktīvas lietotnes — teksts paliek starpliktuvē")
            return .copiedOnly
        }

        // 3. Pārbaudām fokusētā elementa lomu / editējamību.
        let (role, isEditable) = focusedElementInfo(pid: front!.processIdentifier)
        if !Self.shouldFallbackToPaste(role: role, isEditable: isEditable) {
            pb.clearContents()
            pb.setString(text, forType: .string)
            AppLogger.info("TextInserter: fokusētais elements nav teksta lauks (role=\(role ?? "nil")) — teksts paliek starpliktuvē")
            return .copiedOnly
        }

        // 4. Ielīmējam caur ⌘V, saglabājot un atjaunojot lietotāja starpliktuvi.
        let savedItems = Self.snapshotPasteboard(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let expectedChangeCount = pb.changeCount

        AppLogger.info("TextInserter: sūta ⌘V uz aktīvo lietotni")
        sendPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
            if pb.changeCount == expectedChangeCount {
                Self.restorePasteboard(pb, items: savedItems)
            } else {
                AppLogger.info("TextInserter: starpliktuve mainīta pēc ⌘V — atjaunošana izlaista")
            }
        }
        return .pastedViaShortcut
    }

    // MARK: - Accessibility (tieša ievietošana)

    private func insertViaAccessibility(_ text: String, pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }
        let element = (focused as! AXUIElement)

        // Mēģinām iestatīt kAXSelectedTextAttribute tieši — tas saglabā undo vēsturi,
        // izvēli un formatējumu, atšķirībā no visa kAXValueAttribute pārrakstīšanas.
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable)
        if settableResult == .success, isSettable.boolValue {
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                return true
            }
        }

        return false
    }

    /// Nolasa fokusētā elementa lomu un "AXEditable" atribūtu.
    private func focusedElementInfo(pid: pid_t) -> (role: String?, isEditable: Bool?) {
        let axApp = AXUIElementCreateApplication(pid)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return (nil, nil)
        }
        let element = (focused as! AXUIElement)

        var roleValue: CFTypeRef?
        var role: String? = nil
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let r = roleValue as? String {
            role = r
        }

        var editableValue: CFTypeRef?
        var isEditable: Bool? = nil
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue) == .success,
           let e = editableValue as? Bool {
            isEditable = e
        }

        return (role, isEditable)
    }

    // MARK: - Starpliktuves momentuzņēmums

    static func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pb.pasteboardItems else { return [] }
        var copies: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            copies.append(copy)
        }
        return copies
    }

    static func restorePasteboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    // MARK: - ⌘V simulator
    private func sendPasteShortcut() {
        guard let src = CGEventSource(stateID: .privateState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // "V"
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cghidEventTap)
        }
    }
}
