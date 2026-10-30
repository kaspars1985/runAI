import Foundation
import CoreGraphics
import AppKit
import SwiftUI

// MARK: - Lietotnes stāvoklis

enum AppStatus: Equatable {
    case needsModel            // modelis nav lejupielādēts
    case loading               // ielādē modeli
    case ready                 // gatavs ierakstam
    case recording             // tur taustiņu — ieraksta
    case transcribing          // atšifrē audio
    case copied                // teksts ievietots
    case error(String)         // kļūda

    var hudText: String {
        switch self {
        case .needsModel:  return "Modelis nav lejupielādēts"
        case .loading:     return "Ielādē modeli…"
        case .ready:       return "Gatavs"
        case .recording:   return "Ieraksta…"
        case .transcribing: return "Atšifrē…"
        case .copied:      return "Ievietots"
        case .error(let m): return m
        }
    }
}

// MARK: - Modeļa ieraksts

struct ModelEntry: Identifiable, Equatable, Hashable {
    let fileName: String
    let title: String
    let note: String
    let sizeMB: Int
    let languageSupport: String
    let customURL: String?
    let recommendation: String?

    var id: String { fileName }

    init(fileName: String, title: String, note: String, sizeMB: Int, languageSupport: String, customURL: String? = nil, recommendation: String? = nil) {
        self.fileName = fileName
        self.title = title
        self.note = note
        self.sizeMB = sizeMB
        self.languageSupport = languageSupport
        self.customURL = customURL
        self.recommendation = recommendation
    }

    var url: URL {
        if let custom = customURL, let u = URL(string: custom) {
            return u
        }
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + fileName)!
    }

    static let catalog: [ModelEntry] = [
        ModelEntry(fileName: "whisper-large-v3-lv-cv19-q8_0.bin",
                   title: "AiLab Large v3 LV (q8)",
                   note: "Ieteicamais latviešu valodai. Latvijas Universitātes MII modelis (CV19 + LATE). Izcila precizitāte un izpratne.",
                   sizeMB: 1579,
                   languageSupport: "Latviešu: izcili (ieteicams)",
                   customURL: "https://huggingface.co/AiLab-IMCS-UL/whisper-large-v3-lv-late-cv19/resolve/main/ggml-model-q8_0.bin",
                   recommendation: "Ieteicams latviešu valodai"),
        ModelEntry(fileName: "whisper-large-v3-lv-cv19-q5_0.bin",
                   title: "AiLab Large v3 LV (q5)",
                   note: "AiLab modelis kompaktākā izmērā (~1 GB). Ātrāka darbība ar minimālu kvalitātes atšķirību.",
                   sizeMB: 1031,
                   languageSupport: "Latviešu: izcili (kompakts)",
                   customURL: "https://huggingface.co/AiLab-IMCS-UL/whisper-large-v3-lv-late-cv19/resolve/main/ggml-model-q5_0.bin",
                   recommendation: nil),
        ModelEntry(fileName: "ggml-large-v3-turbo-q8_0.bin",
                   title: "Large v3 Turbo (q8)",
                   note: "Ieteicamais angļu un citām valodām. OpenAI oficiālais turbo modelis — zibenīgs ātrums un augsta precizitāte.",
                   sizeMB: 874,
                   languageSupport: "Angļu / visas valodas: izcili (ieteicams)",
                   customURL: nil,
                   recommendation: "Ieteicams angļu valodai"),
        ModelEntry(fileName: "ggml-large-v3-turbo-q5_0.bin",
                   title: "Large v3 Turbo (q5)",
                   note: "Kompakta OpenAI turbo versija (~550 MB), ātra ikdienas lietošanai ar minimālu kvalitātes zudumu.",
                   sizeMB: 547,
                   languageSupport: "Angļu / visas valodas: labi",
                   customURL: nil,
                   recommendation: nil),
    ]
}

// MARK: - Audio iekārta

struct AudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

// MARK: - Karstais taustiņš

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64      // CGEventFlags rawValue (tikai modifikatoru biti)
    var isMouse: Bool
    var mouseButton: Int32     // 2 = vidējā, 3 = sānu "atpakaļ", 4 = sānu "uz priekšu"
    var isModifierOnly: Bool

    static let modifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    var modifierFlags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    static var `default`: Hotkey {
        Hotkey(keyCode: 0x3D, modifiers: 0, isMouse: false, mouseButton: 0, isModifierOnly: true) // labais ⌥ Option
    }

    /// Modifikatora bits, ko ieslēdz/izslēdz šis taustiņš (tikai modifier-only gadījumā).
    var modifierFlag: CGEventFlags? {
        Hotkey.modifierFlag(for: keyCode)
    }

    static func isModifierKeyCode(_ code: UInt16) -> Bool {
        modifierFlag(for: code) != nil
    }

    static func modifierFlag(for code: UInt16) -> CGEventFlags? {
        switch code {
        case 0x36, 0x37: return .maskCommand
        case 0x38, 0x3C: return .maskShift
        case 0x3A, 0x3D: return .maskAlternate
        case 0x3B, 0x3E: return .maskControl
        case 0x3F:       return .maskSecondaryFn
        default:         return nil
        }
    }

    var label: String {
        if isMouse {
            switch mouseButton {
            case 2:  return "Vidējā peles poga"
            case 3:  return "Sānu poga (atpakaļ)"
            case 4:  return "Sānu poga (uz priekšu)"
            default: return "Peles poga \(mouseButton)"
            }
        }
        let key = KeyLabel.keyName(for: keyCode)
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        parts.append(key)
        return parts.joined()
    }

    func matches(keyCode code: UInt16, flags: CGEventFlags) -> Bool {
        guard !isMouse && !isModifierOnly else { return false }
        guard code == keyCode else { return false }
        return (flags.rawValue & Hotkey.modifierMask) == modifiers
    }
}

// MARK: - Valoda

struct LanguageOption: Identifiable, Equatable {
    let code: String
    let title: String
    var id: String { code }

    static let all: [LanguageOption] = [
        LanguageOption(code: "lv", title: "Latviešu"),
        LanguageOption(code: "en", title: "Angļu"),
        LanguageOption(code: "auto", title: "Automātiski (noteikt pēc balss)"),
    ]
}

// MARK: - Ceļi

enum Paths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("runAI", isDirectory: true)
    }
    static var modelsDir: URL {
        appSupport.appendingPathComponent("Models", isDirectory: true)
    }
    static func ensureDirs() {
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }
}

// MARK: - Izvēlnes joslas ikonas stils

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case waveform = "waveform"
    case waveformBadgeMic = "waveform.badge.mic"
    case mic = "mic.fill"
    case sparkles = "sparkles"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waveform: return "Skaņas vilnis (noklusējums)"
        case .waveformBadgeMic: return "Vilnis ar mikrofonu"
        case .mic: return "Mikrofons"
        case .sparkles: return "AI dzirkstis"
        }
    }
}

// MARK: - Izskata tēma

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistēmas (automātiski)"
        case .light:  return "Gaišā"
        case .dark:   return "Tumšā"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Ikonas palīgs

enum AppIconImageHelper {
    /// Ikonu ielādē TIKAI VIENU reizi. Iepriekš `NSImage(contentsOf:)` tika izsaukts
    /// katrā SwiftUI body novērtēšanā, radot jaunu NSImage instanci katrā kadrā un
    /// izraisot bezgalīgu NSHostingView izkārtojuma atgriezenisko saiti.
    private static let cached: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let img = NSImage(named: "AppIcon") {
            return img
        }
        return NSApp.applicationIconImage
    }()

    static func loadIcon() -> NSImage? {
        return cached
    }
}
