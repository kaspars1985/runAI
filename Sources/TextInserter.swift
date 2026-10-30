import Cocoa
import ApplicationServices

/// Ievieto tekstu aktīvajā lietotnē: vispirms mēģina caur Accessibility API,
/// pēc tam — starpliktuve + ⌘V.
/// Teksts VIENMĒR paliek starpliktuvē (clipboard), lai lietotājs jebkurā brīdī varētu nospiest ⌘V.
final class TextInserter {

    enum InsertOutcome {
        case insertedDirectly   // Ievietots caur Accessibility API tieši kursorā
        case pastedViaShortcut  // Ielīmēts caur ⌘V
        case copiedOnly         // Nav teksta lauka, atstāts starpliktuvē
    }

    /// Ievieto tekstu aktīvajā lietotnē un vienmēr saglabā to starpliktuvē.
    @discardableResult
    func insert(_ text: String) -> InsertOutcome {
        guard !text.isEmpty else { return .copiedOnly }

        // 1. Vienmēr iekopējam starpliktuvē, lai teksts nekad nepazustu
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. Mēģinām ievietot tieši kursorā caur Accessibility
        if insertViaAccessibility(text) {
            return .insertedDirectly
        }

        // 3. Pārbaudām, vai aktīvajā logā ir fokusēts elements pirms ⌘V sūtīšanas
        if hasFocusedUIElement() {
            sendPasteShortcut()
            return .pastedViaShortcut
        } else {
            AppLogger.info("TextInserter: nav fokusēta teksta lauka, teksts paliek starpliktuvē (gatavs ⌘V)")
            return .copiedOnly
        }
    }

    private func hasFocusedUIElement() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success && focusedValue != nil
    }

    // MARK: - Accessibility (tieša ievietošana)

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue else {
            return false
        }
        let element = focused as! AXUIElement

        // Izlasi pašreizējo izvēlēto diapazonu un tekstu.
        var rangeRef: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success

        var valueRef: CFTypeRef?
        let hasValue = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success

        var newValue: String
        if hasRange, hasValue,
           let rangeValue = rangeRef,
           let current = valueRef as? String {
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
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

        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
