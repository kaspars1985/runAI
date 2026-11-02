import Foundation

/// Aizsardzība pret Whisper halucinācijām (3 slāņu aizsardzība):
/// 1. Audio līmeņa pārbaude — vai audio satur balsi (nevis klusumu).
/// 2. Transkripcijas tīrīšana — zināmu halucināciju frāžu noņemšana.
/// 3. Atkārtojumu sabrukšana — vārdu cilpu novēršana.
enum AudioGuard {

    // MARK: - 1. Audio līmeņa pārbaude

    /// Minimālais paraugu skaits, lai audio uzskatītu par pietiekami garu apstrādei.
    public static let minSamples: Int = 4800

    /// Pārbauda, vai audio paraugu skaits ir pietiekams (>= `minSamples`).
    public static func isLongEnough(_ samples: [Float]) -> Bool { samples.count >= minSamples }

    /// Nosaka, vai audio paraugos ir dzirdama balss.
    /// Sadala paraugus 100 ms gabalos (1600 paraugi pie 16 kHz), aprēķina RMS katram gabalam
    /// un atgriež `true`, ja vismaz `minActiveWindows` gabaliem RMS >= `voiceThreshold`.
    static func hasSpeech(_ samples: [Float],
                          sampleRate: Double = 16000,
                          windowMs: Double = 100,
                          voiceThreshold: Float = 0.007,
                          minActiveWindows: Int = 2) -> Bool {
        guard !samples.isEmpty, sampleRate > 0, windowMs > 0 else { return false }

        let windowSize = Int((sampleRate * windowMs / 1000.0).rounded())
        guard windowSize > 0, samples.count >= windowSize else { return false }

        var activeWindows = 0
        var index = 0
        while index + windowSize <= samples.count {
            var sum: Float = 0
            for i in index..<(index + windowSize) {
                let v = samples[i]
                sum += v * v
            }
            let rms = (sum / Float(windowSize)).squareRoot()
            if rms >= voiceThreshold {
                activeWindows += 1
                if activeWindows >= minActiveWindows {
                    return true
                }
            }
            index += windowSize
        }
        return false
    }

    // MARK: - 2. Transkripcijas tīrīšana

    /// Zināmās Whisper halucināciju frāzes (bez pieturzīmēm, mazajiem burtiem).
    private static let hallucinationPhrases: Set<String> = [
        // Latviešu
        "paldies par uzmanibu",
        "paldies ka skatijaties",
        "paldies par skatisanos",
        "paldies par uzmanibu un uz redzesanos",
        "abonejiet kanalu",
        "abonejiet kanalu un spiediet uz zvana pogu",
        "muzika",
        "muzika un efekti",
        "subtitri",
        "subtitrus veidoja",
        "subtitrus sagatavoja",
        "tulkojums",
        "tulkoja",
        // Angļu
        "thank you for watching",
        "thanks for watching",
        "thank you for watching and see you next time",
        "thanks for watching and see you next time",
        "please subscribe",
        "please subscribe to my channel",
        "subscribe to my channel",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara org community",
        "subtitled by",
        "transcribed by",
        "transcription by",
        "music",
        "applause",
        "laughter",
        "silence",
        "you"
    ]

    /// Notīra transkripcijas tekstu no zināmām halucinācijām un atkārtojumiem.
    /// Ja viss teksts ir halucinācija, atgriež tukšu virkni.
    static func cleanTranscription(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Normalizējam: mazie burti, noņemam pieturzīmes un iekavas.
        let normalized = normalizeForMatch(trimmed)
        if normalized.isEmpty {
            return ""
        }
        if hallucinationPhrases.contains(normalized) {
            return ""
        }

        // Sabrūkam atkārtojumu cilpas.
        let collapsed = removeRepetitions(trimmed)
        let collapsedTrimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsedTrimmed.isEmpty {
            return ""
        }
        // Ja pēc atkārtojumu sabrukšanas teksts kļuva par halucināciju, arī atgriežam tukšu.
        let collapsedNormalized = normalizeForMatch(collapsedTrimmed)
        if hallucinationPhrases.contains(collapsedNormalized) {
            return ""
        }
        return collapsedTrimmed
    }

    /// Normalizē tekstu salīdzināšanai ar halucināciju frāzēm:
    /// mazie burti, noņemtas pieturzīmes un iekavas, sakārtotas atstarpes.
    private static func normalizeForMatch(_ text: String) -> String {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "lv"))
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        let cleaned = String(scalars)
        let parts = cleaned.split(separator: " ", omittingEmptySubsequences: true)
        return parts.joined(separator: " ")
    }

    // MARK: - 3. Atkārtojumu sabrukšana

    /// Sabrūk secīgus identiskus vārdus (ignorējot reģistru un pieturzīmes),
    /// ja tie atkārtojas 3 vai vairāk reizes pēc kārtas.
    static func removeRepetitions(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Saglabājam oriģinālos tokenus (ar atstarpēm), lai varētu rekonstruēt tekstu.
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 3 else { return trimmed }

        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let currentKey = wordKey(tokens[i])
            var runLength = 1
            var j = i + 1
            while j < tokens.count, wordKey(tokens[j]) == currentKey {
                runLength += 1
                j += 1
            }
            if runLength >= 3 {
                // Patur vienu eksemplāru, pārējos nomet.
                result.append(tokens[i])
            } else {
                for k in i..<j {
                    result.append(tokens[k])
                }
            }
            i = j
        }
        return result.joined(separator: " ")
    }

    /// Atgriež vārda salīdzināšanas atslēgu: mazie burti, bez pieturzīmēm.
    private static func wordKey(_ word: String) -> String {
        let lowered = word.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            if CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) {
                continue
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }
}
