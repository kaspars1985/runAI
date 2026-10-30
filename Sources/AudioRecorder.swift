import Foundation
import AVFoundation
import AudioToolbox

/// Tver mikrofonu, pārveido uz 16 kHz / mono / float32 un uzkrāj paraugus.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "lv.runai.audio")
    private let sampleRate: Double = 16000
    private var isTapped = false
    private var currentDeviceUID: String?
    private var configObserver: NSObjectProtocol?

    private(set) var samples: [Float] = []
    /// Mikrofona līmenis (0…1), tiek izsaukts galvenajā pavedienā.
    var onLevel: ((Float) -> Void)?

    /// Seko līdzi, vai ieraksts ir aktīvs. Tiek uzturēts atsevišķi no engine.isRunning,
    /// jo CoreAudio var īslaicīgi atiestatīt engine Bluetooth frekvenču maiņas laikā.
    private(set) var isRunning: Bool = false

    init() {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: sampleRate,
                                     channels: 1,
                                     interleaved: false)!
    }

    func start() throws {
        guard !isRunning else { return }
        queue.sync {
            samples.removeAll(keepingCapacity: true)
        }
        converter = nil
        isRunning = true

        do {
            try startEngine(applyDeviceUID: true)
        } catch {
            AppLogger.warn("AudioRecorder.start: pirmais mēģinājums neizdevās (\(error.localizedDescription)); mēģina ar sistēmas noklusēto ievadi")
            do {
                try startEngine(applyDeviceUID: false)
            } catch {
                isRunning = false
                throw error
            }
        }
        AppLogger.info("AudioRecorder.start: AVAudioEngine veiksmīgi palaists")
    }

    private func startEngine(applyDeviceUID: Bool) throws {
        // Vispirms sakopjam iepriekšējo engine, ja tāds bija aktīvs
        if let oldEng = self.engine {
            if isTapped {
                oldEng.inputNode.removeTap(onBus: 0)
                isTapped = false
            }
            if oldEng.isRunning {
                oldEng.stop()
            }
            self.engine = nil
        }

        // Jauna AVAudioEngine instance katrā palaišanā — novērš novecojušu
        // kešoto outputFormat (piem., 48000 Hz, kamēr Bluetooth pārslēdzas uz 24000 Hz).
        let eng = AVAudioEngine()
        self.engine = eng

        if applyDeviceUID, let uid = currentDeviceUID {
            let defaultUID = AudioDevices.defaultInputUID()
            if uid != defaultUID, let deviceID = AudioDevices.deviceID(forUID: uid) {
                var deviceIDValue = deviceID
                if let audioUnit = eng.inputNode.audioUnit {
                    let status = AudioUnitSetProperty(audioUnit,
                                                      kAudioOutputUnitProperty_CurrentDevice,
                                                      kAudioUnitScope_Global,
                                                      0,
                                                      &deviceIDValue,
                                                      UInt32(MemoryLayout<AudioDeviceID>.size))
                    if status != noErr {
                        AppLogger.warn("AudioRecorder.startEngine: AudioUnitSetProperty neizdevās (status=\(status))")
                    } else {
                        eng.reset()
                    }
                }
            }
        }

        let input = eng.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        let outFormat = input.outputFormat(forBus: 0)
        AppLogger.info("AudioRecorder.startEngine: hwFormat sampleRate=\(hwFormat.sampleRate) channels=\(hwFormat.channelCount); outFormat sampleRate=\(outFormat.sampleRate) channels=\(outFormat.channelCount)")

        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        isTapped = true

        eng.prepare()
        try eng.start()

        // Uzklausām konfigurācijas izmaiņas (piem., AirPods pārslēdzas 48kHz → 24kHz ieraksta laikā).
        if let existing = configObserver {
            NotificationCenter.default.removeObserver(existing)
            configObserver = nil
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: eng,
            queue: nil) { [weak self] _ in
                self?.handleConfigurationChange()
            }
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        AppLogger.info("AudioRecorder: AVAudioEngineConfigurationChange — pārstartē engine")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            do {
                try self.startEngine(applyDeviceUID: true)
                AppLogger.info("AudioRecorder: engine veiksmīgi pārstartēts pēc konfigurācijas maiņas")
            } catch {
                AppLogger.warn("AudioRecorder: pārstartēšana ar izvēlēto ierīci neizdevās (\(error.localizedDescription)); mēģina ar noklusēto")
                do {
                    try self.startEngine(applyDeviceUID: false)
                    AppLogger.info("AudioRecorder: engine veiksmīgi pārstartēts ar noklusēto ierīci")
                } catch {
                    AppLogger.error("AudioRecorder: engine pārstartēšana neizdevās: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        if let eng = engine {
            if isTapped {
                eng.inputNode.removeTap(onBus: 0)
                isTapped = false
            }
            if eng.isRunning {
                eng.stop()
            }
        }
        engine = nil
        isRunning = false
        AppLogger.info("AudioRecorder.stop: apturēts")
    }

    /// Atgriež un notīra uzkrātos paraugus (pavediendroši).
    func takeSamples() -> [Float] {
        queue.sync {
            let s = samples
            samples.removeAll(keepingCapacity: true)
            return s
        }
    }

    /// Izvēlas konkrētu ievades ierīci pēc UID (pirms start()). Ja neizdodas — izmanto sistēmas noklusēto.
    func setInputDeviceUID(_ uid: String?) {
        currentDeviceUID = uid
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter = converter, buffer.format.sampleRate > 0 else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var fed = false
        var convError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: out, error: &convError, withInputFrom: inputBlock)

        guard let channelData = out.floatChannelData else { return }
        let n = Int(out.frameLength)
        guard n > 0 else { return }

        let ptr = channelData[0]
        var sum: Float = 0
        for i in 0..<n {
            let v = ptr[i]
            sum += v * v
        }
        let rms = (sum / Float(n)).squareRoot()
        let level = min(1.0, max(0.0, rms * 12.0))

        let copy = Array(UnsafeBufferPointer(start: ptr, count: n))
        queue.async { [weak self] in
            self?.samples.append(contentsOf: copy)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }
}
