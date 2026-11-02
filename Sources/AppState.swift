import Foundation
import AppKit
import Combine
import ApplicationServices
import AVFoundation
import UniformTypeIdentifiers

enum MicPermission: Equatable {
    case notDetermined, authorized, denied
}

/// Galvenais lietotnes stāvokļa koordinators (@MainActor).
/// Savieno lietotāja saskarni (SwiftUI) ar audio dzinēju, whisper.cpp,
/// globālo taustiņu monitoru, atļaujām un iestatījumiem.
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - Pārvaldnieki

    let prefs = PreferencesManager()
    let perms = PermissionsManager()
    let modelManager = ModelManager()
    let updateChecker = UpdateChecker()

    // MARK: - Publiskais stāvoklis

    @Published var status: AppStatus = .needsModel
    @Published var inputDevices: [AudioDevice] = []
    @Published var downloadedFiles: [String] = []
    @Published var isCapturingHotkey: Bool = false

    // MARK: - Fasādes īpašības (Preferences)

    var language: String { prefs.language }
    var hotkey: Hotkey { prefs.hotkey }
    var selectedInputID: String? { prefs.selectedInputID }
    var selectedModel: String? { prefs.selectedModel }
    var menuBarIconStyle: MenuBarIconStyle { prefs.menuBarIconStyle }
    var appTheme: AppTheme { prefs.appTheme }
    var autoCheckUpdates: Bool { prefs.autoCheckUpdates }
    var blurBackdrop: Bool { prefs.blurBackdrop }
    var hudPosition: HUDPosition { prefs.hudPosition }

    // MARK: - Fasādes īpašības (Atļaujas)

    var hasAccessibility: Bool { perms.hasAccessibility }
    var micPermission: MicPermission { perms.micPermission }
    var hasInputMonitoring: Bool { perms.hasInputMonitoring }
    var needsInputMonitoring: Bool { perms.needsInputMonitoring }

    // MARK: - Iekšējās komponentes

    private let recorder = AudioRecorder()
    private let engine = WhisperEngine()
    private let inserter = TextInserter()
    private let hud = HUDController()
    private var monitor: HotkeyMonitor!
    private var hudHideWork: DispatchWorkItem?
    private var deviceMonitor: AudioDeviceMonitor?
    private var didSetup = false

    private init() {}

    // MARK: - Inicializācija un iestatīšana

    func setup() {
        guard !didSetup else { return }
        didSetup = true

        AppLogger.installCrashHandlers()
        AppLogger.info("=== runAI palaists ===")

        Paths.ensureDirs()
        monitor = HotkeyMonitor(hotkey: prefs.hotkey)

        monitor.onPress = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        monitor.onRelease = { [weak self] in
            Task { @MainActor in self?.stopRecordingAndTranscribe() }
        }
        monitor.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        recorder.onLevel = { [weak self] level in
            self?.hud.updateLevel(level)
        }

        // Tēma un HUD iestatījumi
        NSApp.appearance = prefs.appTheme.nsAppearance
        hud.blurBackdropEnabled = prefs.blurBackdrop
        hud.positionPreference = prefs.hudPosition

        refreshInputDevices()
        refreshModels()
        perms.refreshMicPermission()
        monitor.start()

        // Kad Accessibility tikko piešķirts, pārstartējam HotkeyMonitor
        perms.onAccessibilityGranted = { [weak self] in
            guard let self = self, let monitor = self.monitor, !monitor.isRunning else { return }
            AppLogger.info("AppState: Accessibility piešķirta — pārstartē HotkeyMonitor")
            monitor.start()
        }
        perms.startMonitoring()

        // Audio ierīču CoreAudio notikumu monitors (0% CPU dīkstāvē)
        let devMon = AudioDeviceMonitor { [weak self] in
            self?.refreshInputDevices()
        }
        devMon.start()
        self.deviceMonitor = devMon

        // 10 minūšu limita sasniegšana — automātiska transkripcija
        recorder.onMaxDurationReached = { [weak self] in
            guard let self = self, self.status == .recording else { return }
            AppLogger.warn("AudioRecorder: sasniegts 10 minūšu limits — automātiski aptur un transkribē")
            self.stopRecordingAndTranscribe()
        }

        // Auto pieprasījums mikrofonam pirmajā reizē
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.perms.autoRequestMicrophoneIfNeeded()
        }

        // Auto atjauninājumu pārbaude
        updateChecker.onRelaunch = { [weak self] in
            self?.quitApp()
        }
        if prefs.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.updateChecker.checkForUpdates(manual: false)
            }
        }

        // Ielādē modeli fonā
        if let sel = prefs.selectedModel, downloadedFiles.contains(sel) {
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
        if perms.micPermission == .denied {
            AppLogger.warn("startRecording: mikrofona atļauja nav piešķirta")
            status = .error("Mikrofona atļauja nav piešķirta. Atveriet iestatījumus → Mikrofons.")
            hudHideWork?.cancel()
            hud.showError("Mikrofona atļauja nav piešķirta")
            scheduleHUDHide(after: 2.5)
            return
        }
        do {
            AppLogger.info("startRecording: sāk ierakstu (device=\(prefs.selectedInputID ?? "default"))")
            recorder.setInputDeviceUID(prefs.selectedInputID)
            try recorder.start()
            status = .recording
            hudHideWork?.cancel()
            hud.showRecording(hotkeyText: prefs.hotkey.label)
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

        if samples.isEmpty {
            AppLogger.error("stopRecordingAndTranscribe: mikrofons nenodeva datus (samples=0)")
            finishTranscription(text: nil, error: "Mikrofons nenodeva skaņu (0 paraugi)")
            return
        }

        guard AudioGuard.isLongEnough(samples) else {
            AppLogger.warn("stopRecordingAndTranscribe: audio pārāk īss (<300ms, samples=\(samples.count))")
            finishTranscription(text: nil, error: "Pārāk īss ieraksts")
            return
        }

        // Anti-halucinācijas (1. slānis): pārbaudām, vai audio satur runu, nevis tikai fona klusumu
        if !AudioGuard.hasSpeech(samples) {
            AppLogger.info("stopRecordingAndTranscribe: audio ir klusums (nav konstatēta balss)")
            finishTranscription(text: nil, error: "Netika konstatēta balss")
            return
        }

        status = .transcribing
        hudHideWork?.cancel()
        hud.showTranscribing()

        engine.transcribe(samples, language: prefs.language) { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .success(let rawText):
                    // Anti-halucinācijas (3. slānis): tīrām subtitru klišejas un vārdu atkārtošanās cilpas
                    let text = AudioGuard.cleanTranscription(rawText)
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
    }

    func cancelRecording() {
        guard recorder.isRunning else { return }
        AppLogger.info("cancelRecording: ieraksts atcelts")
        recorder.stop()
        _ = recorder.takeSamples()
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
                message = "Teksts gatavs"
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

    private func scheduleHUDHide(after delay: TimeInterval) {
        hudHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hud.hide()
                if let self = self, self.status != .recording && self.status != .transcribing {
                    self.status = self.engine.isLoaded ? .ready : .needsModel
                }
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try engine.load(path: path)
                Task { @MainActor in
                    guard let self = self else { return }
                    AppLogger.info("loadModel: ielādēts \(fileName)")
                    self.prefs.setSelectedModel(fileName)
                    self.status = .ready
                }
            } catch {
                Task { @MainActor in
                    guard let self = self else { return }
                    AppLogger.error("loadModel neizdevās \(fileName): \(error.localizedDescription)")
                    self.status = .error("Neizdevās ielādēt modeli")
                }
            }
        }
    }

    func selectModel(_ fileName: String) {
        prefs.setSelectedModel(fileName)
        loadModel(fileName)
    }

    func deleteModel(_ fileName: String) {
        modelManager.delete(fileName)
        refreshModels()
        if prefs.selectedModel == fileName {
            prefs.setSelectedModel(nil)
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

    // MARK: - Preferences fasādes

    func setLanguage(_ code: String) { prefs.setLanguage(code) }
    func setMenuBarIconStyle(_ style: MenuBarIconStyle) { prefs.setMenuBarIconStyle(style) }
    func setAppTheme(_ theme: AppTheme) { prefs.setAppTheme(theme) }
    func setAutoCheckUpdates(_ enabled: Bool) { prefs.setAutoCheckUpdates(enabled) }
    func setBlurBackdrop(_ enabled: Bool) {
        prefs.setBlurBackdrop(enabled)
        hud.blurBackdropEnabled = enabled
    }
    func setHUDPosition(_ pos: HUDPosition) {
        prefs.setHUDPosition(pos)
        hud.positionPreference = pos
    }
    func setHotkey(_ h: Hotkey) {
        prefs.setHotkey(h)
        monitor.update(hotkey: h)
    }

    func beginHotkeyCapture() {
        isCapturingHotkey = true
        monitor.onCaptured = { [weak self] h in
            Task { @MainActor in
                guard let self = self else { return }
                self.isCapturingHotkey = false
                if let h = h {
                    self.setHotkey(h)
                }
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
        prefs.setSelectedInput(uid)
    }

    func refreshInputDevices() {
        let newDevices = AudioDevices.listInputDevices()
        if inputDevices != newDevices {
            inputDevices = newDevices
        }

        let defaultUID = AudioDevices.defaultInputUID()
        let savedUID = UserDefaults.standard.string(forKey: "selectedInput")

        let targetUID: String?
        if let sel = prefs.selectedInputID, !sel.isEmpty, newDevices.contains(where: { $0.id == sel }) {
            targetUID = sel
        } else if let saved = savedUID, !saved.isEmpty, newDevices.contains(where: { $0.id == saved }) {
            targetUID = saved
        } else if let def = defaultUID, newDevices.contains(where: { $0.id == def }) {
            targetUID = def
        } else {
            targetUID = newDevices.first?.id
        }

        if prefs.selectedInputID != targetUID {
            prefs.setSelectedInput(targetUID)
        }
    }

    // MARK: - Permissions fasādes

    func refreshMicPermission() { perms.refreshMicPermission() }
    func requestMicrophonePermission() { perms.requestMicrophonePermission() }
    func openMicrophoneSettings() { perms.openMicrophoneSettings() }

    func refreshInputMonitoring() { perms.refreshInputMonitoring() }
    func requestInputMonitoring() { perms.requestInputMonitoring() }
    func openInputMonitoringSettings() { perms.openInputMonitoringSettings() }
    func resetAndPromptInputMonitoring() { perms.resetAndPromptInputMonitoring() }

    func refreshAccessibility() { perms.refreshAccessibility() }
    func promptAccessibility() { perms.promptAccessibility() }
    func resetAndPromptAccessibility() { perms.resetAndPromptAccessibility() }
    func openAccessibilitySettings() { perms.openAccessibilitySettings() }

    // MARK: - Iziet

    func quitApp() {
        AppLogger.info("Lietotne tiek aizvērta (Quit)")
        perms.stopMonitoring()
        deviceMonitor?.stop()
        deviceMonitor = nil
        monitor?.stop()
        recorder.tearDown()
        engine.unload()
        UserDefaults.standard.synchronize()
        AppLogger.flush()
        _exit(0)
    }

    // MARK: - Palīgi

    var selectedModelTitle: String {
        if let m = prefs.selectedModel {
            if let entry = ModelEntry.catalog.first(where: { $0.fileName == m }) {
                return entry.title
            }
            return m
        }
        return "—"
    }

    var selectedInputTitle: String {
        if inputDevices.isEmpty {
            return "Nav mikrofona"
        }
        if let id = prefs.selectedInputID, let dev = inputDevices.first(where: { $0.id == id }) {
            return dev.name
        }
        if let def = AudioDevices.defaultInputUID(), let dev = inputDevices.first(where: { $0.id == def }) {
            return dev.name
        }
        return inputDevices.first?.name ?? "Sistēmas noklusētais"
    }
}
