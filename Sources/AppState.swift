import Foundation
import AppKit
import Combine
import ApplicationServices
import AVFoundation
import UniformTypeIdentifiers

enum MicPermission: Equatable {
    case notDetermined, authorized, denied
}

final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - Publicētais stāvoklis

    @Published var status: AppStatus = .needsModel
    @Published var inputDevices: [AudioDevice] = []
    @Published var selectedInputID: String?
    @Published var language: String = "lv"
    @Published var hotkey: Hotkey = .default
    @Published var hasAccessibility: Bool = AXIsProcessTrusted()
    @Published var micPermission: MicPermission = .notDetermined
    @Published var hasInputMonitoring: Bool = {
        if #available(macOS 15.0, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }()
    @Published var downloadedFiles: [String] = []
    @Published var selectedModel: String?
    @Published var isCapturingHotkey: Bool = false
    @Published var menuBarIconStyle: MenuBarIconStyle = .waveform
    @Published var appTheme: AppTheme = .system
    @Published var autoCheckUpdates: Bool = true

    let modelManager = ModelManager()
    let updateChecker = UpdateChecker()

    // MARK: - Komponentes

    private let recorder = AudioRecorder()
    private let engine = WhisperEngine()
    private let inserter = TextInserter()
    private let hud = HUDController()
    private var monitor: HotkeyMonitor!
    private var hudHideWork: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var didSetup = false

    private init() {
        // Ielādē saglabātos iestatījumus
        if let data = UserDefaults.standard.data(forKey: "hotkey"),
           let h = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = h
        }
        if let lang = UserDefaults.standard.string(forKey: "language"), !lang.isEmpty {
            language = lang
        }
        if let mid = UserDefaults.standard.string(forKey: "selectedInput"),
           !mid.isEmpty,
           !mid.contains("CADefaultDeviceAggregate"),
           mid != "0" {
            selectedInputID = mid
        }
        if let m = UserDefaults.standard.string(forKey: "selectedModel") {
            selectedModel = m
        }
        if let styleStr = UserDefaults.standard.string(forKey: "menuBarIconStyle"),
           let style = MenuBarIconStyle(rawValue: styleStr) {
            menuBarIconStyle = style
        } else {
            menuBarIconStyle = .waveform
            UserDefaults.standard.set(MenuBarIconStyle.waveform.rawValue, forKey: "menuBarIconStyle")
        }
        if let themeStr = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: themeStr) {
            appTheme = theme
        } else {
            appTheme = .system
        }
        if UserDefaults.standard.object(forKey: "autoCheckUpdates") != nil {
            autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        } else {
            autoCheckUpdates = true
        }

        // Ja saglabātais UID ir AVAudioEngine virtuālais agregāts, atiestatām uz sistēmas noklusēto.
        if let sel = selectedInputID, sel.contains("CADefaultDeviceAggregate") {
            selectedInputID = AudioDevices.defaultInputUID()
        }
    }

    func setup() {
        guard !didSetup else { return }
        didSetup = true

        AppLogger.installCrashHandlers()
        AppLogger.info("=== runAI palaists ===")

        Paths.ensureDirs()
        monitor = HotkeyMonitor(hotkey: hotkey)

        monitor.onPress = { [weak self] in self?.startRecording() }
        monitor.onRelease = { [weak self] in self?.stopRecordingAndTranscribe() }
        monitor.onCancel = { [weak self] in self?.cancelRecording() }
        recorder.onLevel = { [weak self] level in self?.hud.updateLevel(level) }

        // Piemēro izvēlēto izskata tēmu
        NSApp.appearance = appTheme.nsAppearance

        refreshInputDevices()
        refreshModels()
        refreshMicPermission()
        monitor.start()

        // Atļauju un audio ierīču stāvokļa atsvaidzināšana
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
            self?.refreshMicPermission()
            self?.refreshInputDevices()
            self?.refreshInputMonitoring()
        }

        // Pirmajā palaišanā pieprasām mikrofona atļauju, lai lietotne parādītos
        // «Mikrofons» sarakstā sistēmas iestatījumos.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.autoRequestMicrophoneIfNeeded()
        }

        // A-10: Pārbauda atjauninājumus fonā tikai tad, ja tas ir iespējots
        if autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.updateChecker.checkForUpdates(manual: false)
            }
        }

        // Ielādē izvēlēto modeli fonā
        if let sel = selectedModel, downloadedFiles.contains(sel) {
            loadModel(sel)
        } else {
            status = .needsModel
        }
    }

    // MARK: - Ierakstīšana

    func toggleRecording() {
        if status == .recording {
            stopRecordingAndTranscribe()
        } else if status != .transcribing {
            startRecording()
        }
    }

    func startRecording() {
        guard !isCapturingHotkey else { return }
        guard status != .transcribing else {
            AppLogger.warn("startRecording: transkripcija jau notiek, ignorējam jaunu sākumu")
            return
        }

        if !engine.isLoaded {
            AppLogger.warn("startRecording: modelis vēl nav ielādēts")
            hudHideWork?.cancel()
            hud.showError("Modelis tiek ielādēts…")
            scheduleHUDHide(after: 1.5)
            return
        }
        if micPermission == .denied {
            AppLogger.warn("startRecording: mikrofona atļauja nav piešķirta")
            status = .error("Mikrofona atļauja nav piešķirta. Atveriet iestatījumus → Mikrofons.")
            hudHideWork?.cancel()
            hud.showError("Mikrofona atļauja nav piešķirta")
            scheduleHUDHide(after: 2.5)
            return
        }
        do {
            AppLogger.info("startRecording: sāk ierakstu (device=\(selectedInputID ?? "default"))")
            recorder.setInputDeviceUID(selectedInputID)
            try recorder.start()
            status = .recording
            hudHideWork?.cancel()
            hud.showRecording(hotkeyText: hotkey.label)
        } catch let error as AudioRecorderError where error == .noInputDevice {
            AppLogger.error("startRecording neizdevās: nav pievienots neviens mikrofons")
            status = .error("Nav pievienots neviens mikrofons")
            hudHideWork?.cancel()
            hud.showError("Nav pievienots neviens mikrofons")
            scheduleHUDHide(after: 2.5)
        } catch {
            AppLogger.error("startRecording neizdevās: \(error.localizedDescription)")
            status = .error("Mikrofons nav pieejams. Pārbaudiet savienojumu vai iestatījumus.")
            hudHideWork?.cancel()
            hud.showError("Mikrofons nav pieejams")
            scheduleHUDHide(after: 2.5)
        }
    }

    func stopRecordingAndTranscribe() {
        guard recorder.isRunning else { return }
        AppLogger.info("stopRecordingAndTranscribe: aptur ierakstu, sāk atšifrēšanu")
        recorder.stop()
        let samples = recorder.takeSamples()
        AppLogger.info("stopRecordingAndTranscribe: samples=\(samples.count)")
        status = .transcribing
        hudHideWork?.cancel()
        hud.showTranscribing()

        engine.transcribe(samples, language: language) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let text):
                if text.isEmpty {
                    self.finishTranscription(text: nil, error: "Nekas netika atpazīts")
                } else {
                    let outcome = self.inserter.insert(text)
                    self.finishTranscription(text: text, outcome: outcome, error: nil)
                }
            case .failure(let err):
                self.finishTranscription(text: nil, error: err.localizedDescription)
            }
        }
    }

    /// A-05: Atceļ aktīvo ierakstu (piemēram, ja lietotājs turot Option nospieda citu taustiņu)
    func cancelRecording() {
        guard recorder.isRunning else { return }
        AppLogger.info("cancelRecording: ieraksts atcelts")
        recorder.stop()
        _ = recorder.takeSamples() // Nometam paraugus
        hudHideWork?.cancel()
        hud.hide()
        status = engine.isLoaded ? .ready : .needsModel
    }

    private func finishTranscription(text: String?, outcome: TextInserter.InsertOutcome = .insertedDirectly, error: String?) {
        hudHideWork?.cancel()
        if let error = error {
            AppLogger.error("finishTranscription kļūda: \(error)")
            status = .error(error)
            hud.showError(error)
        } else if let text = text, !text.isEmpty {
            AppLogger.info("finishTranscription: \(text.count) simbolu, iznākums: \(outcome)")
            status = .copied
            let message: String
            switch outcome {
            case .insertedDirectly, .pastedViaShortcut:
                message = "Teksts ievietots kursorā"
            case .copiedOnly:
                message = "Nokopēts (⌘V)"
            }
            hud.showSuccess(message: message, isCopiedOnly: outcome == .copiedOnly)
        } else {
            AppLogger.info("finishTranscription: tukšs rezultāts")
            status = .ready
            hud.showSuccess(message: "Gatavs", isCopiedOnly: false)
        }
        scheduleHUDHide(after: 1.5)
    }

    // MARK: - HUD

    private func showHUD(text: String, showLevel: Bool = false) {
        hudHideWork?.cancel()
        hud.show(text: text, showLevel: showLevel)
    }

    private func scheduleHUDHide(after delay: TimeInterval) {
        hudHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hud.hide()
            if let self = self, self.status != .recording && self.status != .transcribing {
                self.status = self.engine.isLoaded ? .ready : .needsModel
            }
        }
        hudHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Modeļi

    func refreshModels() {
        Paths.ensureDirs()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.modelsDir, includingPropertiesForKeys: nil)) ?? []
        downloadedFiles = files
            .filter { $0.pathExtension == "bin" }
            .map { $0.lastPathComponent }
            .sorted()
    }

    func loadModel(_ fileName: String) {
        let path = Paths.modelsDir.appendingPathComponent(fileName).path
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.warn("loadModel: fails nav atrasts \(fileName)")
            status = .needsModel
            return
        }
        AppLogger.info("loadModel: sāk ielādēt \(fileName)")
        status = .loading
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try engine.load(path: path)
                DispatchQueue.main.async {
                    AppLogger.info("loadModel: ielādēts \(fileName)")
                    self.selectedModel = fileName
                    UserDefaults.standard.set(fileName, forKey: "selectedModel")
                    self.status = .ready
                }
            } catch {
                DispatchQueue.main.async {
                    AppLogger.error("loadModel neizdevās \(fileName): \(error.localizedDescription)")
                    self.status = .error("Neizdevās ielādēt modeli")
                }
            }
        }
    }

    func selectModel(_ fileName: String) {
        selectedModel = fileName
        UserDefaults.standard.set(fileName, forKey: "selectedModel")
        loadModel(fileName)
    }

    func deleteModel(_ fileName: String) {
        modelManager.delete(fileName)
        refreshModels()
        if selectedModel == fileName {
            selectedModel = nil
            UserDefaults.standard.removeObject(forKey: "selectedModel")
            engine.unload()
            status = .needsModel
        }
    }

    func addCustomModel() {
        let panel = NSOpenPanel()
        panel.title = "Izvēlieties whisper.cpp modeļa failu (.bin)"
        panel.allowedContentTypes = [.init(filenameExtension: "bin") ?? .data]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importCustomModel(url)
        }
    }

    private func importCustomModel(_ url: URL) {
        Paths.ensureDirs()
        let dest = Paths.modelsDir.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            refreshModels()
            selectModel(url.lastPathComponent)
        } catch {
            status = .error("Neizdevās pievienot modeli")
        }
    }

    func revealModelsFolder() {
        modelManager.revealModelsFolder()
    }

    func revealLogFile() {
        AppLogger.revealLogFile()
    }

    // MARK: - Iestatījumi

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

    func setHotkey(_ h: Hotkey) {
        AppLogger.info("setHotkey: \(h.label)")
        hotkey = h
        monitor.update(hotkey: h)
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: "hotkey")
        }
    }

    func beginHotkeyCapture() {
        isCapturingHotkey = true
        monitor.onCaptured = { [weak self] h in
            guard let self = self else { return }
            self.isCapturingHotkey = false
            if let h = h {
                self.setHotkey(h)
            }
        }
        monitor.beginCapture()
    }

    func cancelHotkeyCapture() {
        isCapturingHotkey = false
        monitor.endCapture()
    }

    func setInputDevice(_ uid: String) {
        guard !uid.isEmpty else { return }
        if selectedInputID != uid {
            selectedInputID = uid
        }
        UserDefaults.standard.set(uid, forKey: "selectedInput")
    }

    func refreshInputDevices() {
        let newDevices = AudioDevices.listInputDevices()
        if inputDevices != newDevices {
            inputDevices = newDevices
        }

        let defaultUID = AudioDevices.defaultInputUID()
        let savedUID = UserDefaults.standard.string(forKey: "selectedInput")

        let targetUID: String?
        if let sel = selectedInputID, !sel.isEmpty, newDevices.contains(where: { $0.id == sel }) {
            // Pašreiz izvēlētā ierīce joprojām ir pieslēgta
            targetUID = sel
        } else if let saved = savedUID, !saved.isEmpty, newDevices.contains(where: { $0.id == saved }) {
            // Iepriekš saglabātā ierīce (piem., AirPods) tikko atkal pieslēdzās
            targetUID = saved
        } else if let def = defaultUID, newDevices.contains(where: { $0.id == def }) {
            // Izmantojam sistēmas noklusēto ievades ierīci (piem., tikko ielikti AirPods)
            targetUID = def
        } else {
            // Pirmā pieejamā ierīce vai nil, ja nav neviena mikrofona
            targetUID = newDevices.first?.id
        }

        if selectedInputID != targetUID {
            selectedInputID = targetUID
            if let valid = targetUID, !valid.isEmpty {
                UserDefaults.standard.set(valid, forKey: "selectedInput")
            }
        }
    }

    // MARK: - Atļaujas

    /// Vai šī macOS versija prasa atsevišķu Ievades parraudzības atļauju.
    /// macOS 15 (Sequoia) un jaunākas prasa to, lai fona lietotne varētu
    /// uztvert globālos karstos taustiņus citās programmās.
    var needsInputMonitoring: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    func refreshMicPermission() {
        let newStatus: MicPermission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: newStatus = .authorized
        case .denied, .restricted: newStatus = .denied
        case .notDetermined: newStatus = .notDetermined
        @unknown default: newStatus = .notDetermined
        }
        // SVARĪGI: piešķiram tikai ja stāvoklis mainījies. Iepriekš @Published tika
        // piešķirts katras 2 sekundes, izraisot objectWillChange un bezgalīgu
        // SwiftUI pārzīmēšanu.
        if micPermission != newStatus {
            micPermission = newStatus
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshMicPermission()
            }
        }
    }

    private func autoRequestMicrophoneIfNeeded() {
        refreshMicPermission()
        if micPermission == .notDetermined {
            requestMicrophonePermission()
        }
    }

    /// Atsvaidzina Ievades parraudzības atļaujas stāvokli (tikai macOS 15+).
    /// Piešķiram @Published tikai ja stāvoklis mainījies, lai izvairītos no
    /// bezgalīgas SwiftUI pārzīmēšanas.
    func refreshInputMonitoring() {
        guard #available(macOS 15.0, *) else { return }
        let granted = CGPreflightListenEventAccess()
        if granted != hasInputMonitoring {
            AppLogger.info("refreshInputMonitoring: stāvoklis mainījās uz \(granted)")
            hasInputMonitoring = granted
        }
    }

    /// Pieprasa Ievades parraudzības atļauju (tikai macOS 15+).
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
    /// Noderīgi, ja Sistēmas iestatījumos slēdzis jau ir ieslēgts, bet lietotne
    /// joprojām rāda sarkanu (TCC ieraksts neatbilst pašreizējam binaram).
    func resetAndPromptInputMonitoring() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "ListenEvent", "lv.runai.app"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Ja tccutil neizdodas, turpinām — vismaz pieprasīsim atļauju no jauna.
        }
        requestInputMonitoring()
    }

    /// Atsvaidzina Universālās piekļuves stāvokli un, ja atļauja tikko parādījās,
    /// pārstartē HotkeyMonitor (jo sākotnējais start() varēja neizdoties, ja atļauja
    /// vēl nebija piešķirta — CGEvent.tapCreate atgriež nil).
    private func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility {
            AppLogger.info("refreshAccessibility: stāvoklis mainījās uz \(trusted)")
            hasAccessibility = trusted
        }
        if trusted, let monitor = monitor, !monitor.isRunning {
            AppLogger.info("refreshAccessibility: atļauja piešķirta, pārstartē HotkeyMonitor")
            monitor.start()
        }
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        if hasAccessibility, let monitor = monitor, !monitor.isRunning {
            monitor.start()
        }
    }

    /// Atiestata Universālās piekļuves atļauju lietotnei un pieprasa to no jauna.
    /// Noderīgi, ja Sistēmas iestatījumos slēdzis jau ir ieslēgts, bet lietotne
    /// joprojām rāda sarkanu (TCC ieraksts neatbilst pašreizējam binaram).
    func resetAndPromptAccessibility() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", "lv.runai.app"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Ja tccutil neizdodas, turpinām — vismaz pieprasīsim atļauju no jauna.
        }
        hasAccessibility = AXIsProcessTrusted()
        promptAccessibility()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Iziet

    /// Kārtīgi aptur visas komponentes un iziet no lietotnes.
    /// Izsaucam exit(0) tieši, lai ggml_metal_device_free neabortētu uz neatbrīvotiem
    /// Metal resursiem NSApplicationWillTerminate laikā.
    func quitApp() {
        AppLogger.info("Lietotne tiek aizvērta (Quit)")
        permissionTimer?.invalidate()
        permissionTimer = nil
        monitor?.stop()
        recorder.tearDown()
        engine.unload()
        UserDefaults.standard.synchronize()
        AppLogger.flush()
        _exit(0)
    }

    // MARK: - Palīgi

    var selectedModelTitle: String {
        if let m = selectedModel {
            if let entry = ModelEntry.catalog.first(where: { $0.fileName == m }) {
                return entry.title
            }
            return m
        }
        return "—"
    }
}
