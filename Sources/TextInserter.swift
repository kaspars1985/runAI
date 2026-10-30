import Cocoa
import ApplicationServices

/// Ievieto tekstu aktīvajā lietotnē: vispirms mēģina caur Accessibility API,
/// pēc tam — starpliktuve + ⌘V (ar starpliktuves atjaunošanu).
final class TextInserter {

    /// Atgriež, kuru ceļu izmantoja (patiesība — Accessibility; nepatiesība — starpliktuve).
    @discardableResult
    func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        if insertViaAccessibility(text) {
            return true
        }
        insertViaPasteboard(text)
        return false
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

    // MARK: - Starpliktuve + ⌘V

    private func insertViaPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        let saved = snapshotPasteboard()

        pb.clearContents()
        pb.setString(text, forType: .string)

        sendPasteShortcut()

        // Atjauno iepriekšējo starpliktuves saturu pēc nelielas pauzes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let pb2 = NSPasteboard.general
            pb2.clearContents()
            pb2.writeObjects(saved)
        }
    }

    private func snapshotPasteboard() -> [NSPasteboardItem] {
        let pb = NSPasteboard.general
        return (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

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
