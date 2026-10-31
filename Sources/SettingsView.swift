import SwiftUI
import AppKit

// MARK: - Tēmas krāsas

struct ThemeColors {
    let isDark: Bool

    init(theme: AppTheme, colorScheme: ColorScheme) {
        switch theme {
        case .dark:
            self.isDark = true
        case .light:
            self.isDark = false
        case .system:
            self.isDark = (colorScheme == .dark)
        }
    }

    var canvasBg: Color {
        isDark ? Color(red: 0.078, green: 0.078, blue: 0.086)   // #141416
               : Color(red: 0.984, green: 0.984, blue: 0.980)   // #FBFBFA
    }
    var cardBg: Color {
        isDark ? Color(red: 0.110, green: 0.110, blue: 0.122)   // #1C1C1F
               : Color.white                                     // #FFFFFF
    }
    var cardBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    var keycapBg: Color {
        isDark ? Color(red: 0.149, green: 0.149, blue: 0.161)   // #262629
               : Color(red: 0.957, green: 0.957, blue: 0.949)   // #F4F4F2
    }
    var textPrimary: Color {
        isDark ? Color(red: 0.929, green: 0.929, blue: 0.929)   // #EDEDED
               : Color(red: 0.067, green: 0.067, blue: 0.067)   // #111111
    }
    var textSecondary: Color {
        isDark ? Color(red: 0.557, green: 0.557, blue: 0.576)   // #8E8E93
               : Color(red: 0.400, green: 0.400, blue: 0.408)   // #666668
    }
    var textMuted: Color {
        isDark ? Color(red: 0.388, green: 0.388, blue: 0.400)   // #636366
               : Color(red: 0.549, green: 0.549, blue: 0.565)   // #8C8C90
    }
    var badgeGreenBg: Color {
        isDark ? Color(red: 0.102, green: 0.149, blue: 0.110)   // #1A261C
               : Color(red: 0.929, green: 0.953, blue: 0.925)   // #EDF3EC
    }
    var badgeGreenText: Color {
        isDark ? Color(red: 0.361, green: 0.816, blue: 0.431)   // #5CD06E
               : Color(red: 0.180, green: 0.408, blue: 0.208)   // #2E6835
    }
    var badgeBlueBg: Color {
        isDark ? Color(red: 0.094, green: 0.145, blue: 0.208)   // #182535
               : Color(red: 0.910, green: 0.949, blue: 0.988)   // #E8F2FC
    }
    var badgeBlueText: Color {
        isDark ? Color(red: 0.353, green: 0.647, blue: 0.961)   // #5AA5F5
               : Color(red: 0.118, green: 0.361, blue: 0.600)   // #1E5C99
    }
    var statusGreen: Color {
        isDark ? Color(red: 0.361, green: 0.816, blue: 0.431) : Color(red: 0.180, green: 0.600, blue: 0.290)
    }
    var statusRed: Color {
        isDark ? Color(red: 0.937, green: 0.400, blue: 0.400) : Color(red: 0.780, green: 0.180, blue: 0.180)
    }
    var statusOrange: Color {
        isDark ? Color(red: 0.949, green: 0.686, blue: 0.290) : Color(red: 0.800, green: 0.500, blue: 0.100)
    }
}

// MARK: - Iestatījumu skats

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var models: ModelManager
    @ObservedObject var updates: UpdateChecker

    init(state: AppState) {
        self.state = state
        self.models = state.modelManager
        self.updates = state.updateChecker
    }

    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(theme: state.appTheme, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    inputCard
                    configCard
                }
                .frame(width: 350, alignment: .top)

                VStack(alignment: .leading, spacing: 14) {
                    modelsCard
                    permissionsCard
                }
                .frame(width: 370, alignment: .top)
            }
        }
        .padding(18)
        .frame(width: 760, alignment: .topLeading)
        .background(colors.canvasBg)
        .onAppear {
            state.refreshModels()
            state.refreshInputDevices()
        }
        .alert("Lejupielādes kļūda", isPresented: Binding(
            get: { models.downloadError != nil },
            set: { if !$0 { models.downloadError = nil } }
        )) {
            Button("Labi", role: .cancel) {}
        } message: {
            Text(models.downloadError ?? "")
        }
    }

    // MARK: - Galvene

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            if let appIcon = AppIconImageHelper.loadIcon() {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 30))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("runAI")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(updates.currentVersion)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(colors.keycapBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("Lokāla balss diktēšana ar mākslīgo intelektu")
                    .font(.system(size: 11.5))
                    .foregroundColor(colors.textSecondary)
                HStack(spacing: 5) {
                    Label("100% lokāli", systemImage: "shield.lefthalf.filled")
                    Text("·")
                    Label("Bez interneta", systemImage: "wifi.slash")
                }
                .font(.system(size: 10))
                .foregroundColor(colors.textMuted)
            }

            Spacer(minLength: 8)

            updateStatusView
        }
    }

    private var updateStatusView: some View {
        HStack(spacing: 8) {
            if updates.updateAvailable {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Pieejama v\(updates.latestVersion ?? "")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text("Pašreizējā v\(updates.currentVersion)")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textMuted)
                }
                Button("Lejupielādēt") { updates.openReleasePage() }
                    .buttonStyle(FlatButtonStyle(colors: colors, prominent: true))
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("v\(updates.currentVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    if let last = updates.lastCheckDate {
                        Text("Pārbaudīts \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textMuted)
                    } else {
                        Text("Jaunākā versija")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textMuted)
                    }
                }
                if updates.isChecking {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 60, height: 22)
                } else {
                    Button("Pārbaudīt") { updates.checkForUpdates(manual: true) }
                        .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                }
            }
        }
    }

    // MARK: - Kartīte: Ierakstīšana un ievade

    private var inputCard: some View {
        SettingsCard(title: "Ierakstīšana un ievade", colors: colors) {
            VStack(alignment: .leading, spacing: 12) {
                // Karstais taustiņš
                VStack(alignment: .leading, spacing: 6) {
                    Text("Karstais taustiņš")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    if state.isCapturingHotkey {
                        HStack(spacing: 8) {
                            Text("Nospiediet taustiņu…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                            Spacer()
                            Button("Atcelt") { state.cancelHotkeyCapture() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                        }
                    } else {
                        HStack(spacing: 8) {
                            KeycapView(text: state.hotkey.label, colors: colors)
                            Spacer()
                            Button("Mainīt…") { state.beginHotkeyCapture() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                        }
                    }

                    Text("Turiet taustiņu nospiestu un runājiet. Atlaižot — teksts tiks ievietots tur, kur atrodas kursors. Darbojas gan kreisais, gan labais ⌥ Option.")
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.5)

                // Mikrofons
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mikrofons")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    Picker("", selection: Binding(
                        get: { state.selectedInputID ?? "" },
                        set: { state.setInputDevice($0) }
                    )) {
                        if state.inputDevices.isEmpty {
                            Text("Nav pievienots neviens mikrofons").tag("")
                        } else if state.selectedInputID == nil || !state.inputDevices.contains(where: { $0.id == state.selectedInputID }) {
                            Text("Sistēmas noklusētais").tag("")
                        }
                        ForEach(state.inputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Ja izvēlētais mikrofons ir atvienots, ieraksts notiek no sistēmas noklusētā mikrofona.")
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Kartīte: Konfigurācija

    private var configCard: some View {
        SettingsCard(title: "Konfigurācija", colors: colors) {
            VStack(alignment: .leading, spacing: 12) {
                // Valoda
                VStack(alignment: .leading, spacing: 6) {
                    Text("Valoda")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    Picker("", selection: Binding(
                        get: { state.language },
                        set: { state.setLanguage($0) }
                    )) {
                        ForEach(LanguageOption.all) { option in
                            Text(option.title).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Latviešu valodai ieteicams AiLab LV, latgaliešu — AiLab Latgalian, angļu — Large v3 Turbo.")
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.5)

                // Izskata tēma
                VStack(alignment: .leading, spacing: 6) {
                    Text("Izskata tēma")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    ThemeSegmentedControl(
                        selection: Binding(
                            get: { state.appTheme },
                            set: { state.setAppTheme($0) }
                        ),
                        colors: colors
                    )
                }

                Divider().opacity(0.5)

                // Izvēlnes josla
                VStack(alignment: .leading, spacing: 6) {
                    Text("Izvēlnes josla")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    Picker("", selection: Binding(
                        get: { state.menuBarIconStyle },
                        set: { state.setMenuBarIconStyle($0) }
                    )) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            HStack {
                                Image(systemName: style.rawValue)
                                Text(style.title)
                            }
                            .tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().opacity(0.5)

                // A-10: Automātiska atjauninājumu pārbaude
                Toggle(isOn: Binding(
                    get: { state.autoCheckUpdates },
                    set: { state.setAutoCheckUpdates($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pārbaudīt atjauninājumus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        Text("Automātiski noskaidrot jaunākās versijas esamību.")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textMuted)
                    }
                }
                .toggleStyle(.checkbox)

                Divider().opacity(0.5)

                // Gaussian Blur fokusa fons
                Toggle(isOn: Binding(
                    get: { state.blurBackdrop },
                    set: { state.setBlurBackdrop($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aizmiglot ekrāna fonu (Gaussian Blur fokuss)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        Text("Diktēšanas laikā fons aiz HUD tiek maigi izpludināts kinemātiskam fokusam.")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textMuted)
                    }
                }
                .toggleStyle(.checkbox)

                Divider().opacity(0.5)

                // HUD novietojums ekrānā
                VStack(alignment: .leading, spacing: 6) {
                    Text("HUD novietojums ekrānā")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    HUDPositionSegmentedControl(
                        selection: Binding(
                            get: { state.hudPosition },
                            set: { state.setHUDPosition($0) }
                        ),
                        colors: colors
                    )
                }
            }
        }
    }

    // MARK: - Kartīte: Modeļi

    private var modelsCard: some View {
        SettingsCard(title: "Mākslīgā intelekta modeļi", colors: colors) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ModelEntry.catalog) { entry in
                    ModelRow(
                        entry: entry,
                        state: state,
                        models: models,
                        colors: colors,
                        isDownloaded: state.downloadedFiles.contains(entry.fileName),
                        isActive: state.selectedModel == entry.fileName,
                        progress: models.progress[entry.fileName],
                        isDownloading: models.activeDownloads.contains(entry.fileName)
                    )
                }

                Divider().opacity(0.5).padding(.vertical, 2)

                HStack(spacing: 8) {
                    Button("Pievienot savu .bin failu…") { state.addCustomModel() }
                        .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                    Button("Atvērt mapi") { state.revealModelsFolder() }
                        .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                    Spacer()
                }
            }
        }
    }

    // MARK: - Kartīte: Atļaujas

    private var permissionsCard: some View {
        SettingsCard(title: "Sistēmas atļaujas", colors: colors) {
            VStack(alignment: .leading, spacing: 12) {
                // Universālā piekļuve
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(state.hasAccessibility ? colors.statusGreen : colors.statusRed)
                            .frame(width: 7, height: 7)
                        Text("Universālā piekļuve")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                    }
                    Text("Nepieciešama, lai lietotne dzirdētu karsto taustiņu un ievietotu tekstu citās programmās.")
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !state.hasAccessibility {
                        HStack(spacing: 8) {
                            Button("Atiestatīt atļauju") { state.resetAndPromptAccessibility() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                            Button("Atvērt iestatījumus") { state.openAccessibilitySettings() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                            Spacer()
                        }
                    }
                }

                Divider().opacity(0.5)

                // Mikrofons
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(micStatusColor)
                            .frame(width: 7, height: 7)
                        Text("Mikrofons")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                        if state.micPermission == .notDetermined {
                            Button("Pieprasīt") { state.requestMicrophonePermission() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                        } else if state.micPermission == .denied {
                            Button("Atvērt iestatījumus") { state.openMicrophoneSettings() }
                                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                        }
                    }
                    Text(micText)
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Ievades pārraudzība (nepieciešama macOS 15+)
                if state.needsInputMonitoring {
                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(state.hasInputMonitoring ? colors.statusGreen : colors.statusRed)
                                .frame(width: 7, height: 7)
                            Text("Ievades pārraudzība")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                            Spacer()
                            if !state.hasInputMonitoring {
                                Button("Pieprasīt") { state.requestInputMonitoring() }
                                    .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                                Button("Atvērt iestatījumus") { state.openInputMonitoringSettings() }
                                    .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                            }
                        }
                        Text(inputMonitoringText)
                            .font(.system(size: 10.5))
                            .foregroundColor(colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var inputMonitoringText: String {
        if state.hasInputMonitoring {
            return "Atļauja piešķirta. Lietotne var droši uztvert karstos taustiņus fona režīmā."
        } else {
            return "Nepieciešama macOS 15 un jaunākās versijās, lai uztvertu karstos taustiņus, kamēr strādājat citās programmās."
        }
    }

    private var micStatusColor: Color {
        switch state.micPermission {
        case .authorized: return colors.statusGreen
        case .denied: return colors.statusRed
        case .notDetermined: return colors.statusOrange
        }
    }

    private var micText: String {
        switch state.micPermission {
        case .authorized: return "Atļauja piešķirta. Mikrofons tiks izmantots ierakstam."
        case .denied: return "Atļauja nav piešķirta. Atveriet iestatījumus un atļaujiet runAI piekļuvi mikrofonam."
        case .notDetermined: return "Atļauja vēl nav pieprasīta."
        }
    }
}

// MARK: - Kartītes konteiners

private struct SettingsCard<Content: View>: View {
    let title: String
    let colors: ThemeColors
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Taustiņa atslēga

private struct KeycapView: View {
    let text: String
    let colors: ThemeColors

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.keycapBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(colors.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Plakana poga

private struct FlatButtonStyle: ButtonStyle {
    let colors: ThemeColors
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(prominent ? colors.cardBg : colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? colors.textPrimary : colors.keycapBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(prominent ? Color.clear : colors.cardBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Tēmas segmentētais slēdzis

private struct ThemeSegmentedControl: View {
    @Binding var selection: AppTheme
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: theme.iconName)
                            .font(.system(size: 10))
                        Text(theme.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selection == theme ? colors.textPrimary : colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selection == theme ? colors.cardBg : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(colors.keycapBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - HUD pozīcijas izvēle

private struct HUDPositionSegmentedControl: View {
    @Binding var selection: HUDPosition
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HUDPosition.allCases) { pos in
                Button {
                    selection = pos
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: pos.iconName)
                            .font(.system(size: 10))
                        Text(pos.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selection == pos ? colors.textPrimary : colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selection == pos ? colors.cardBg : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(colors.keycapBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Modeļa rinda

private struct ModelRow: View {
    let entry: ModelEntry
    @ObservedObject var state: AppState
    @ObservedObject var models: ModelManager
    let colors: ThemeColors
    let isDownloaded: Bool
    let isActive: Bool
    let progress: Double?
    let isDownloading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    if let rec = entry.recommendation {
                        Text(rec)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.badgeGreenText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(colors.badgeGreenBg)
                            .clipShape(Capsule())
                    }
                    if isActive {
                        Text("Aktīvs")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.badgeBlueText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(colors.badgeBlueBg)
                            .clipShape(Capsule())
                    }
                }
                Text("\(entry.languageSupport) · \(entry.sizeMB) MB")
                    .font(.system(size: 10))
                    .foregroundColor(colors.textMuted)
            }

            Spacer(minLength: 4)

            if isDownloading {
                ProgressView(value: progress ?? 0)
                    .frame(width: 90)
            } else if isDownloaded {
                if isActive {
                    Button("Dzēst") { state.deleteModel(entry.fileName) }
                        .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
                } else {
                    Button("Izmantot") { state.selectModel(entry.fileName) }
                        .buttonStyle(FlatButtonStyle(colors: colors, prominent: true))
                }
            } else {
                Button("Lejupielādēt") {
                    models.download(entry) { result in
                        if case .success = result {
                            state.refreshModels()
                            if state.selectedModel == nil {
                                state.selectModel(entry.fileName)
                            }
                        }
                    }
                }
                .buttonStyle(FlatButtonStyle(colors: colors, prominent: false))
            }
        }
        .padding(.vertical, 2)
    }
}
