import Foundation
import CoreAudio
import AudioToolbox

/// Uzskaita pieejamās audio ievades ierīces (mikrofonus).
enum AudioDevices {

    static func listInputDevices() -> [AudioDevice] {
        var result: [AudioDevice] = []
        let system = AudioObjectID(kAudioObjectSystemObject)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return result }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return result }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return result }

        for id in ids {
            guard hasInputChannels(id), let name = deviceName(id) else { continue }
            let uid = deviceUID(id) ?? String(id)
            // Izlaižam AVAudioEngine virtuālos/iekšējos apvienotos agregātus,
            // lai tie nekad neparādās mikrofona izvēlnē.
            if name.contains("CADefaultDeviceAggregate") || uid.contains("CADefaultDeviceAggregate") {
                continue
            }
            result.append(AudioDevice(id: uid, name: name))
        }
        return result
    }

    static func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var defaultID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultID) == noErr,
              defaultID != kAudioObjectUnknown,
              hasInputChannels(defaultID) else {
            return nil
        }
        return deviceUID(defaultID)
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return nil }
        for id in ids where deviceUID(id) == uid {
            return id
        }
        return nil
    }

    // MARK: - Privātie

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        // A-07: Droša mainīga izmēra alokācija, novēršot bufera pārpildi
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let bufferList = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}

/// Uzrauga CoreAudio sistēmas līmeņa notikumus (ierīču pievienošana/atvienošana
/// un noklusētās ievades ierīces maiņa) un paziņo par tiem uz galvenā pavediena.
final class AudioDeviceMonitor {

    /// Izsaukts uz `DispatchQueue.main`, kad mainās audio ierīču saraksts
    /// vai noklusētā ievades ierīce.
    private let onChange: () -> Void

    private var isRunning = false

    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Sāk uzraudzīt CoreAudio notikumus. Vairākkārtīgs izsaukums ir drošs.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let system = AudioObjectID(kAudioObjectSystemObject)

        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onChange()
            }
        }
        let defaultInputBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onChange()
            }
        }

        devicesListener = devicesBlock
        defaultInputListener = defaultInputBlock

        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, DispatchQueue.main, devicesBlock)
        AudioObjectAddPropertyListenerBlock(system, &defaultInputAddress, DispatchQueue.main, defaultInputBlock)
    }

    /// Pārtrauc uzraudzību un noņem CoreAudio listenerus.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        let system = AudioObjectID(kAudioObjectSystemObject)

        if let block = devicesListener {
            AudioObjectRemovePropertyListenerBlock(system, &devicesAddress, DispatchQueue.main, block)
            devicesListener = nil
        }
        if let block = defaultInputListener {
            AudioObjectRemovePropertyListenerBlock(system, &defaultInputAddress, DispatchQueue.main, block)
            defaultInputListener = nil
        }
    }
}
