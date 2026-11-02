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

    /// Ievieto tekstu aktīvajā lietotnē.
    @discardableResult
    func insert(_ text: String) -> InsertOutcome {
        guard !text.isEmpty else { return .copiedOnly }

        // 1. Mēģinām ievietot tieši kursorā caur Accessibility.
        // Ja izdodas — starpliktuve netiek aiztikta (lietotāja starpliktuve saglabājas).
        if insertViaAccessibility(text) {
            AppLogger.info("TextInserter: ievietots tieši caur Accessibility API")
            return .insertedDirectly
        }

        // 2. Saglabājam iepriekšējo starpliktuves saturu (visus tipus).
        let pb = NSPasteboard.general
        let savedItems = Self.snapshotPasteboard(pb)

        // 3. Ierakstām jauno tekstu starpliktuvē.
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 4. Ja ir aktīva lietotne (nevis mēs paši), sūtām ⌘V un pēc tam atjaunojam starpliktuvi.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            AppLogger.info("TextInserter: sūta ⌘V uz aktīvo lietotni")
            sendPasteShortcut()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Self.restorePasteboard(pb, items: savedItems)
            }
            return .pastedViaShortcut
        }

        // 5. Nav kur ielīmēt — teksts paliek starpliktuvē.
        AppLogger.info("TextInserter: nav aktīvas lietotnes — teksts paliek starpliktuvē")
        return .copiedOnly
    }

    // MARK: - Accessibility (tieša ievietošana)

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

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

    // MARK: - Starpliktuves momentuzņēmums

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
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

    private static func restorePasteboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    // MARK: - ⌘V simulator
    private func sendPasteShortcut() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // "V"
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        usleep(15000) // 15ms pauze starp nospiešanu un atlaišanu

        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
