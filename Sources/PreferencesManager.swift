import Foundation
import AppKit

/// Centralizēti pārvalda lietotnes lietotāja iestatījumus (preferences),
/// to ielādi no `UserDefaults` un saglabāšanu tajos.
@MainActor
final class PreferencesManager: ObservableObject {

    // MARK: - Publicētās preferences

    @Published var language: String = "lv"
    @Published var hotkey: Hotkey = .default
    @Published var selectedInputID: String?
    @Published var selectedModel: String?
    @Published var menuBarIconStyle: MenuBarIconStyle = .waveform
    @Published var appTheme: AppTheme = .system
    @Published var autoCheckUpdates: Bool = true
    @Published var blurBackdrop: Bool = true
    @Published var hudPosition: HUDPosition = .center

    // MARK: - Init

    init() {
        loadDefaults()
    }

    private func loadDefaults() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: "hotkey"),
           let h = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = h
        }

        if let lang = defaults.string(forKey: "language"), !lang.isEmpty {
            language = lang
        }

        if let mid = defaults.string(forKey: "selectedInput"),
           !mid.isEmpty,
           !mid.contains("CADefaultDeviceAggregate"),
           mid != "0" {
            selectedInputID = mid
        }

        if let m = defaults.string(forKey: "selectedModel") {
            selectedModel = m
        }

        if let styleStr = defaults.string(forKey: "menuBarIconStyle"),
           let style = MenuBarIconStyle(rawValue: styleStr) {
            menuBarIconStyle = style
        } else {
            menuBarIconStyle = .waveform
            defaults.set(MenuBarIconStyle.waveform.rawValue, forKey: "menuBarIconStyle")
        }

        if let themeStr = defaults.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: themeStr) {
            appTheme = theme
        } else {
            appTheme = .system
        }

        if defaults.object(forKey: "autoCheckUpdates") != nil {
            autoCheckUpdates = defaults.bool(forKey: "autoCheckUpdates")
        } else {
            autoCheckUpdates = true
        }

        if defaults.object(forKey: "blurBackdrop") != nil {
            blurBackdrop = defaults.bool(forKey: "blurBackdrop")
        } else {
            blurBackdrop = true
        }

        if let rawPos = defaults.string(forKey: "hudPosition"),
           let pos = HUDPosition(rawValue: rawPos) {
            hudPosition = pos
        } else {
            hudPosition = .center
        }

        // Ja saglabātais UID ir AVAudioEngine virtuālais agregāts, atiestatām uz sistēmas noklusēto.
        if let sel = selectedInputID, sel.contains("CADefaultDeviceAggregate") {
            selectedInputID = AudioDevices.defaultInputUID()
        }
    }

    // MARK: - Setteri

    func setLanguage(_ code: String) {
        language = code
        UserDefaults.standard.set(code, forKey: "language")
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "menuBarIconStyle")
    }

    func setAppTheme(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        appTheme = theme
        NSApp.appearance = theme.nsAppearance
        SettingsWindowController.shared.updateAppearance(theme.nsAppearance)
    }

    func setAutoCheckUpdates(_ enabled: Bool) {
        autoCheckUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "autoCheckUpdates")
    }

    func setBlurBackdrop(_ enabled: Bool) {
        blurBackdrop = enabled
        UserDefaults.standard.set(enabled, forKey: "blurBackdrop")
    }

    func setHUDPosition(_ pos: HUDPosition) {
        hudPosition = pos
        UserDefaults.standard.set(pos.rawValue, forKey: "hudPosition")
    }

    func setHotkey(_ h: Hotkey) {
        AppLogger.info("setHotkey: \(h.label)")
        hotkey = h
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: "hotkey")
        }
    }

    func setSelectedModel(_ fileName: String?) {
        selectedModel = fileName
        if let fileName = fileName {
            UserDefaults.standard.set(fileName, forKey: "selectedModel")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedModel")
        }
    }

    func setSelectedInput(_ uid: String?) {
        selectedInputID = uid
        if let uid = uid, !uid.isEmpty {
            UserDefaults.standard.set(uid, forKey: "selectedInput")
        }
    }
}
