import Cocoa
import CoreGraphics

/// Globāls karstā taustiņa monitors (CGEventTap).
/// Atbalsta: modifikatora taustiņu (turēšana), taustiņu kombinācijas un peles pogas.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Kad uzstādīts — monitors darbojas "tveršanas" režīmā un atgriež nospiesto taustiņu.
    var onCaptured: ((Hotkey?) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isDown = false
    private var hotkey: Hotkey
    private var captureModifierKey: UInt16?
    private var cancelledByCompoundKey = false

    /// Vai event tap šobrīd ir aktīvs (t.i., start() izdevās).
    var isRunning: Bool { tap != nil }

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func update(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
                ? nil
                : Unmanaged.passUnretained(event)
        }
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        if let t = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: mask,
                                     callback: callback,
                                     userInfo: selfPtr) {
            tap = t
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            if let source = source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            AppLogger.info("HotkeyMonitor: event tap started")
        } else {
            AppLogger.warn("HotkeyMonitor: event tap failed to start (tap == nil) — pārbaudīt Accessibility atļauju")
        }
    }

    func stop() {
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
    }

    // MARK: - Tveršana (jauna taustiņa iestatīšana)

    func beginCapture() {
        captureModifierKey = nil
    }

    func endCapture() {
        onCaptured = nil
        captureModifierKey = nil
    }

    // MARK: - Apstrāde

    /// Atgriež true, ja notikums ir "apēsts" (nav jāpārsūta tālāk).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            AppLogger.warn("HotkeyMonitor: event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput")) — re-enabled")
            return false
        }

        // Tveršanas režīms
        if onCaptured != nil {
            return handleCapture(type: type, event: event)
        }

        if hotkey.isMouse {
            return handleMouse(type: type, event: event)
        }
        return handleKeyboard(type: type, event: event)
    }

    private func handleCapture(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 0x35 { // Esc — atcelt
                finishCapture(nil)
                return true
            }
            if Hotkey.isModifierKeyCode(keyCode) {
                return false // modifikatorus apstrādā flagsChanged
            }
            // Parasts taustiņš — kombinācija ar pašreizējiem modifikatoriem
            let flags = event.flags.rawValue & Hotkey.modifierMask
            let h = Hotkey(keyCode: keyCode, modifiers: flags, isMouse: false, mouseButton: 0, isModifierOnly: false)
            finishCapture(h)
            return true

        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard Hotkey.isModifierKeyCode(keyCode), let flag = Hotkey.modifierFlag(for: keyCode) else {
                return false
            }
            if event.flags.contains(flag) {
                // Modifikators nospiests — atceramies un gaidām taustiņu/peli
                captureModifierKey = keyCode
                return false
            } else {
                // Modifikators atlaists — ja nekas cits netika nospiests, tad modifier-only
                if captureModifierKey == keyCode {
                    let h = Hotkey(keyCode: keyCode, modifiers: 0, isMouse: false, mouseButton: 0, isModifierOnly: true)
                    finishCapture(h)
                    return true
                }
                return false
            }

        case .otherMouseDown:
            let button = Int32(event.getIntegerValueField(.mouseEventButtonNumber))
            let h = Hotkey(keyCode: 0, modifiers: 0, isMouse: true, mouseButton: button, isModifierOnly: false)
            finishCapture(h)
            return true

        default:
            return false
        }
    }

    private func finishCapture(_ h: Hotkey?) {
        let cb = onCaptured
        onCaptured = nil
        cb?(h)
    }

    private func handleMouse(type: CGEventType, event: CGEvent) -> Bool {
        let button = Int32(event.getIntegerValueField(.mouseEventButtonNumber))
        guard button == hotkey.mouseButton else { return false }
        switch type {
        case .otherMouseDown:
            if !isDown {
                isDown = true
                AppLogger.info("HotkeyMonitor: hotkey press (mouse button \(button))")
                DispatchQueue.main.async { [weak self] in self?.onPress?() }
            }
        case .otherMouseUp:
            if isDown {
                isDown = false
                AppLogger.info("HotkeyMonitor: hotkey release (mouse button \(button))")
                DispatchQueue.main.async { [weak self] in self?.onRelease?() }
            }
        default:
            break
        }
        return false
    }

    private func handleKeyboard(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if hotkey.isModifierOnly {
            // A-05: Ja lietotājs, turot modifikatoru, nospiež kādu parastu taustiņu (piem., ⌥ + ←, ⌥ + ⌫),
            // atceļam diktēšanu, lai netraucētu sistēmas saīsnēm.
            if type == .keyDown && isDown {
                cancelledByCompoundKey = true
                isDown = false
                AppLogger.info("HotkeyMonitor: diktēšana atcelta (salikts taustiņš keyCode=\(keyCode))")
                DispatchQueue.main.async { [weak self] in self?.onCancel?() }
                return false
            }

            guard type == .flagsChanged else { return false }

            // A-05: Atšķiram kreiso un labo modifikatora taustiņu (precīzs keyCode)
            let matchesKey = (keyCode == hotkey.keyCode)
            guard matchesKey else { return false }

            guard let flag = hotkey.modifierFlag else { return false }
            let hasFlag = event.flags.contains(flag)
            if hasFlag && !isDown {
                cancelledByCompoundKey = false
                isDown = true
                AppLogger.info("HotkeyMonitor: hotkey press (modifier keyCode=\(keyCode))")
                DispatchQueue.main.async { [weak self] in self?.onPress?() }
            } else if !hasFlag {
                if isDown && !cancelledByCompoundKey {
                    isDown = false
                    AppLogger.info("HotkeyMonitor: hotkey release (modifier keyCode=\(keyCode))")
                    DispatchQueue.main.async { [weak self] in self?.onRelease?() }
                }
                isDown = false
                cancelledByCompoundKey = false
            }
            return false
        }

        switch type {
        case .keyDown:
            if keyCode == hotkey.keyCode && !autorepeat && hotkey.matches(keyCode: keyCode, flags: event.flags) {
                if !isDown {
                    isDown = true
                    AppLogger.info("HotkeyMonitor: hotkey press (keyCode=\(keyCode))")
                    DispatchQueue.main.async { [weak self] in self?.onPress?() }
                }
            }
        case .keyUp:
            if keyCode == hotkey.keyCode {
                if isDown {
                    isDown = false
                    AppLogger.info("HotkeyMonitor: hotkey release (keyCode=\(keyCode))")
                    DispatchQueue.main.async { [weak self] in self?.onRelease?() }
                }
            }
        default:
            break
        }
        return false
    }
}
