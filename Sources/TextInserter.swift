import Cocoa
import ApplicationServices

/// Ievieto tekstu aktīvajā lietotnē: vispirms mēģina caur Accessibility API,
/// pēc tam — starpliktuve + ⌘V simulācija.
/// Teksts VIENMĒR tiek iekopēts arī starpliktuvē (clipboard), lai tas nekad nepazustu.
final class TextInserter {

    enum InsertOutcome {
        case insertedDirectly   // Ievietots caur Accessibility API tieši kursorā
        case pastedViaShortcut  // Ielīmēts caur ⌘V simulāciju
        case copiedOnly         // Teksts tukšs vai nevarēja ievietot
    }

    /// Ievieto tekstu aktīvajā lietotnē un vienmēr saglabā to starpliktuvē.
    @discardableResult
    func insert(_ text: String) -> InsertOutcome {
        guard !text.isEmpty else { return .copiedOnly }

        // 1. Vienmēr iekopējam starpliktuvē, lai teksts nekad nepazustu
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. Mēģinām ievietot tieši kursorā caur Accessibility (lieliski darbojas Cocoa teksta laukos)
        if insertViaAccessibility(text) {
            AppLogger.info("TextInserter: ievietots tieši caur Accessibility API")
            return .insertedDirectly
        }

        // 3. Ja Accessibility tiešā ievietošana nav pieejama (piem., pārlūki, tīmekļa lapas,
        // Slack, Electron, redaktori), sūtām ⌘V simulāciju, kas acumirklī ielīmē tekstu
        AppLogger.info("TextInserter: sūta ⌘V uz aktīvo lietotni")
        sendPasteShortcut()
        return .pastedViaShortcut
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

        // Izlasi pašreizējo izvēlēto diapazonu un tekstu.
        var rangeRef: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success

        var valueRef: CFTypeRef?
        let hasValue = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success

        var newValue: String
        if hasRange, hasValue,
           let rangeValue = rangeRef,
           CFGetTypeID(rangeValue) == AXValueGetTypeID(),
           let current = valueRef as? String {
            var range = CFRange(location: 0, length: 0)
            guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return false }
            let nsRange = NSRange(location: range.location, length: range.length)
            guard nsRange.location != NSNotFound,
                  nsRange.location <= (current as NSString).length,
                  nsRange.location + nsRange.length <= (current as NSString).length else {
                return false
            }
            newValue = (current as NSString).replacingCharacters(in: nsRange, with: text)
        } else if hasValue, let current = valueRef as? String {
            // Nav zināms kursors — pievieno beigās.
            newValue = current + text
        } else {
            return false
        }

        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
        return result == .success
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
