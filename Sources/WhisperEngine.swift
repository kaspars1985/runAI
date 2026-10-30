import Foundation
import whisper

enum WhisperError: Error, LocalizedError {
    case notLoaded
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .notLoaded:  return "Modelis nav ielādēts"
        case .loadFailed: return "Neizdevās ielādēt modeli"
        }
    }
}

/// Plāns aptinums ap whisper.cpp — ielādē modeli un atšifrē audio.
/// Pavediendrošs: visu piekļuvi aizsargā iekšējā serial rinda.
final class WhisperEngine: @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "lv.runai.whisper", qos: .userInitiated)
    private(set) var loadedPath: String?

    var isLoaded: Bool {
        queue.sync { ctx != nil }
    }

    func load(path: String) throws {
        try queue.sync {
            if let old = ctx {
                whisper_free(old)
                ctx = nil
            }
            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            guard let c = whisper_init_from_file_with_params(path, cparams) else {
                loadedPath = nil
                throw WhisperError.loadFailed
            }
            ctx = c
            loadedPath = path
        }
    }

    func unload() {
        queue.sync {
            if let old = ctx {
                whisper_free(old)
                ctx = nil
            }
            loadedPath = nil
        }
    }

    /// Atšifrē audio paraugus (16 kHz, mono, float32). Atgriež rezultātu galvenajā pavedienā.
    func transcribe(_ samples: [Float], language: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard let ctx = self.ctx else {
                DispatchQueue.main.async { completion(.failure(WhisperError.notLoaded)) }
                return
            }
            guard !samples.isEmpty else {
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
            params.single_segment = true
            params.translate = false

            let forced = language != "auto"
            var resultText = ""

            if forced {
                language.withCString { langPtr in
                    params.language = langPtr
                    params.detect_language = false
                    samples.withUnsafeBufferPointer { buf in
                        _ = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                }
            } else {
                params.language = nil
                params.detect_language = true
                samples.withUnsafeBufferPointer { buf in
                    _ = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }

            let n = whisper_full_n_segments(ctx)
            var parts: [String] = []
            for i in 0..<n {
                if let seg = whisper_full_get_segment_text(ctx, i) {
                    parts.append(String(cString: seg))
                }
            }
            resultText = parts.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async { completion(.success(resultText)) }
        }
    }
}
