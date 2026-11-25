import Foundation
import whisper
import os

enum WhisperError: Error, LocalizedError {
    case notLoaded
    case loadFailed
    case transcribeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .notLoaded:  return "Modelis nav ielādēts"
        case .loadFailed: return "Neizdevās ielādēt modeli"
        case .transcribeFailed(let code): return "Atšifrēšana neizdevās (kods \(code))"
        }
    }
}

/// Plāns aptinums ap whisper.cpp — ielādē modeli un atšifrē audio.
/// Pavediendrošs: visu piekļuvi aizsargā iekšējā serial rinda.
final class WhisperEngine: @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "lv.runai.whisper", qos: .userInitiated)

    /// Aizsargā ielādes stāvokli, lai isLoaded varētu atgriezties acumirklī bez bloķēšanas.
    private let loadedLock = OSAllocatedUnfairLock(initialState: false)

    var isLoaded: Bool {
        loadedLock.withLock { $0 }
    }

    func load(path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            self.loadedLock.withLock { $0 = false }
            if let old = self.ctx {
                whisper_free(old)
                self.ctx = nil
            }
            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            guard let c = whisper_init_from_file_with_params(path, cparams) else {
                self.loadedLock.withLock { $0 = false }
                DispatchQueue.main.async { completion(.failure(WhisperError.loadFailed)) }
                return
            }
            self.ctx = c
            self.loadedLock.withLock { $0 = true }
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    func unload() {
        queue.async {
            if let old = self.ctx {
                whisper_free(old)
                self.ctx = nil
            }
            self.loadedLock.withLock { $0 = false }
        }
    }

    func unloadSync() {
        queue.sync {
            if let old = self.ctx {
                whisper_free(old)
                self.ctx = nil
            }
            self.loadedLock.withLock { $0 = false }
        }
    }

    /// Atšifrē audio paraugus (16 kHz, mono, float32). Atgriež rezultātu galvenajā pavedienā.
    func transcribe(_ samples: [Float], language: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard let ctx = self.ctx else {
                DispatchQueue.main.async { completion(.failure(WhisperError.notLoaded)) }
                return
            }
            // A-08: Nometam audio, kas ir īsāks par 300 ms (4800 paraugi pie 16 kHz),
            // lai novērstu Whisper halucinācijas pie nejaušiem īsiem taustiņa klikšķiem.
            guard AudioGuard.isLongEnough(samples) else {
                DispatchQueue.main.async { completion(.success("")) }
                return
            }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.print_special = false
            params.no_context = true
            params.no_timestamps = true
            // A-02: Atļaujam vairāku teikumu diktēšanu bez apraušanas pie pauzēm.
            params.single_segment = false
            params.translate = false
            // Anti-halucināciju parametri (2. slānis):
            // - suppress_blank: nepieļauj tukšus segmentus
            // - suppress_nst: nepieļauj "non-speech tokens" (troksni, mūziku)
            // - no_speech_thold: augstāks slieksnis klusuma atzīšanai
            // - entropy_thold: ierobežo haotiskus/zema pārliecības segmentus
            params.suppress_blank = true
            params.suppress_nst = true
            params.no_speech_thold = 0.6
            params.entropy_thold = 2.4

            let forced = language != "auto"
            var resultText = ""
            var fullResult: Int32 = 0

            if forced {
                // Latgaliešu modelis izmanto "lv" valodas marķieri Whisper modelī
                let effectiveLang = (language == "ltg") ? "lv" : language
                effectiveLang.withCString { langPtr in
                    params.language = langPtr
                    params.detect_language = false
                    samples.withUnsafeBufferPointer { buf in
                        fullResult = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                }
            } else {
                params.language = nil
                params.detect_language = true
                samples.withUnsafeBufferPointer { buf in
                    fullResult = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }

            if fullResult != 0 {
                AppLogger.warn("WhisperEngine: whisper_full atgrieza kodu \(fullResult)")
                DispatchQueue.main.async { completion(.failure(WhisperError.transcribeFailed(fullResult))) }
                return
            }

            let n = whisper_full_n_segments(ctx)
            var parts: [String] = []
            for i in 0..<n {
                if let seg = whisper_full_get_segment_text(ctx, i) {
                    parts.append(String(cString: seg))
                }
            }
            // A-09: Unicode NFC normalizācija latviešu diakritiskajām zīmēm
            resultText = parts.joined()
                .precomposedStringWithCanonicalMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async { completion(.success(resultText)) }
        }
    }
}
