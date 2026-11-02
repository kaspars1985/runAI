import Foundation
import AppKit
import ApplicationServices
import AVFoundation

/// Centralizēti pārvalda sistēmas atļaujas (Universālā piekļuve, mikrofons,
/// Ievades parraudzība) un to atsvaidzināšanu, kad lietotne kļūst aktīva.
@MainActor
final class PermissionsManager: ObservableObject {

    // MARK: - Publicētais stāvoklis

    @Published var hasAccessibility: Bool = AXIsProcessTrusted()
    @Published var micPermission: MicPermission = .notDetermined
    @Published var hasInputMonitoring: Bool = {
        if #available(macOS 15.0, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }()

    /// Izsaukts, kad Universālās piekļuves atļauja tikko tika piešķirta.
    var onAccessibilityGranted: (() -> Void)?

    // MARK: - Privātais stāvoklis

    private var didBecomeActiveObserver: NSObjectProtocol?

    // MARK: - Monitorings

    /// Sāk atļauju atsvaidzināšanu — reģistrē novērotāju, kas atsvaidzina
    /// atļaujas katru reizi, kad lietotne kļūst aktīva.
    func startMonitoring() {
        stopMonitoring()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.refreshAll()
            }
        }
    }

    func stopMonitoring() {
        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            didBecomeActiveObserver = nil
        }
    }

    /// Atsvaidzina visas atļaujas uzreiz.
    func refreshAll() {
        refreshAccessibility()
        refreshMicPermission()
        refreshInputMonitoring()
    }

    // MARK: - Mikrofons

    func refreshMicPermission() {
        let newStatus: MicPermission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: newStatus = .authorized
        case .denied, .restricted: newStatus = .denied
        case .notDetermined: newStatus = .notDetermined
        @unknown default: newStatus = .notDetermined
        }
        // SVARĪGI: piešķiram tikai ja stāvoklis mainījies, lai izvairītos no
        // bezgalīgas SwiftUI pārzīmēšanas.
        if micPermission != newStatus {
            micPermission = newStatus
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMicPermission()
            }
        }
    }

    func autoRequestMicrophoneIfNeeded() {
        refreshMicPermission()
        if micPermission == .notDetermined {
            requestMicrophonePermission()
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ievades parraudzība (macOS 15+)

    /// Vai šī macOS versija prasa atsevišķu Ievades parraudzības atļauju.
    var needsInputMonitoring: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    func refreshInputMonitoring() {
        guard #available(macOS 15.0, *) else { return }
        let granted = CGPreflightListenEventAccess()
        if granted != hasInputMonitoring {
            AppLogger.info("refreshInputMonitoring: stāvoklis mainījās uz \(granted)")
            hasInputMonitoring = granted
        }
    }

    func requestInputMonitoring() {
        guard #available(macOS 15.0, *) else { return }
        CGRequestListenEventAccess()
        refreshInputMonitoring()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Atiestata Ievades parraudzības atļauju lietotnei un pieprasa to no jauna.
    /// `tccutil` tiek izpildīts asinhroni, lai nebloķētu galveno pavedienu.
    func resetAndPromptInputMonitoring() {
        Task {
            await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = ["reset", "ListenEvent", "lv.runai.app"]
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    // Ja tccutil neizdodas, turpinām — vismaz pieprasīsim atļauju no jauna.
                }
            }.value
            self.requestInputMonitoring()
        }
    }

    // MARK: - Universālā piekļuve

    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        let wasTrusted = hasAccessibility
        if trusted != hasAccessibility {
            AppLogger.info("refreshAccessibility: stāvoklis mainījās uz \(trusted)")
            hasAccessibility = trusted
        }
        if !wasTrusted && trusted {
            onAccessibilityGranted?()
        }
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        if hasAccessibility {
            onAccessibilityGranted?()
        }
    }

    /// Atiestata Universālās piekļuves atļauju lietotnei un pieprasa to no jauna.
    /// `tccutil` tiek izpildīts asinhroni, lai nebloķētu galveno pavedienu.
    func resetAndPromptAccessibility() {
        Task {
            await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = ["reset", "Accessibility", "lv.runai.app"]
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    // Ja tccutil neizdodas, turpinām — vismaz pieprasīsim atļauju no jauna.
                }
            }.value
            self.hasAccessibility = AXIsProcessTrusted()
            self.promptAccessibility()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
