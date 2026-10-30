import Foundation
import Carbon.HIToolbox

/// Pārvērš CGKeyCode par lasāmu nosaukumu (latviski, kur iespējams).
enum KeyLabel {
    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x31: return "Atstarpe"
        case 0x33: return "Backspace"
        case 0x35: return "Esc"
        case 0x73: return "Home"
        case 0x74: return "Page Up"
        case 0x75: return "Delete"
        case 0x77: return "End"
        case 0x79: return "Page Down"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x3A: return "Kreisais ⌥ Option"
        case 0x3D: return "Labais ⌥ Option"
        case 0x36: return "Labais ⌘ Command"
        case 0x37: return "Kreisais ⌘ Command"
        case 0x38: return "Kreisais ⇧ Shift"
        case 0x3C: return "Labais ⇧ Shift"
        case 0x3B: return "Kreisais ⌃ Control"
        case 0x3E: return "Labais ⌃ Control"
        case 0x3F: return "Fn"
        default: break
        }

        // Mēģinām iegūt simbolu no pašreizējā tastatūras izkārtojuma.
        if let translated = translate(keyCode: keyCode) {
            return translated
        }
        return "Taustiņš \(keyCode)"
    }

    private static func translate(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue()
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let osStatus = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,                     // modifikatori
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars)
        guard osStatus == noErr, length > 0 else { return nil }
        let str = String(utf16CodeUnits: chars, count: length)
        if str.isEmpty { return nil }
        return str.uppercased()
    }
}
