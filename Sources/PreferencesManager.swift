import Foundation

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

    // MARK: - Privātais stāvoklis

    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadDefaults()
    }

    private func loadDefaults() {
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
    }

    // MARK: - Setteri

    func setLanguage(_ code: String) {
        language = code
        defaults.set(code, forKey: "language")
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style
        defaults.set(style.rawValue, forKey: "menuBarIconStyle")
    }

    func setAppTheme(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: "appTheme")
        appTheme = theme
    }

    func setAutoCheckUpdates(_ enabled: Bool) {
        autoCheckUpdates = enabled
        defaults.set(enabled, forKey: "autoCheckUpdates")
    }

    func setBlurBackdrop(_ enabled: Bool) {
        blurBackdrop = enabled
        defaults.set(enabled, forKey: "blurBackdrop")
    }

    func setHUDPosition(_ pos: HUDPosition) {
        hudPosition = pos
        defaults.set(pos.rawValue, forKey: "hudPosition")
    }

    func setHotkey(_ h: Hotkey) {
        AppLogger.info("setHotkey: \(h.label)")
        hotkey = h
        if let data = try? JSONEncoder().encode(h) {
            defaults.set(data, forKey: "hotkey")
        }
    }

    func setSelectedModel(_ fileName: String?) {
        selectedModel = fileName
        if let fileName = fileName {
            defaults.set(fileName, forKey: "selectedModel")
        } else {
            defaults.removeObject(forKey: "selectedModel")
        }
    }

    func setSelectedInput(_ uid: String?) {
        selectedInputID = uid
        if let uid = uid, !uid.isEmpty {
            defaults.set(uid, forKey: "selectedInput")
        }
    }
}
