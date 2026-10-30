import Foundation
import AVFoundation
import AudioToolbox

/// Tver mikrofonu, pārveido uz 16 kHz / mono / float32 un uzkrāj paraugus.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "lv.runai.audio")
    private let sampleRate: Double = 16000

    private(set) var samples: [Float] = []
    /// Mikrofona līmenis (0…1), tiek izsaukts galvenajā pavedienā.
    var onLevel: ((Float) -> Void)?

    var isRunning: Bool { engine.isRunning }

    init() {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: sampleRate,
                                     channels: 1,
                                     interleaved: false)!
    }

    func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
        guard let uid = uid, let deviceID = AudioDevices.deviceID(forUID: uid) else { return }
        var deviceIDValue = deviceID
        let audioUnit = engine.inputNode.audioUnit
        guard let audioUnit = audioUnit else { return }
        AudioUnitSetProperty(audioUnit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global,
                             0,
                             &deviceIDValue,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
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
