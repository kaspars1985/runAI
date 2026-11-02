import Foundation
import CoreGraphics

// MARK: - Testu ietvars

final class TestContext {
    var passed = 0
    var failed = 0
    var failures: [String] = []
    var currentTestFailed = false
    var currentTestErrors: [String] = []
}

let ctx = TestContext()

// ANSI krāsas
let RESET = "\u{001B}[0m"
let GREEN = "\u{001B}[32m"
let RED = "\u{001B}[31m"
let YELLOW = "\u{001B}[33m"
let CYAN = "\u{001B}[36m"
let BOLD = "\u{001B}[1m"
let DIM = "\u{001B}[2m"

func test(_ name: String, _ block: () throws -> Void) {
    ctx.currentTestFailed = false
    ctx.currentTestErrors.removeAll()
    do {
        try block()
        if ctx.currentTestFailed {
            ctx.failed += 1
            print("  \(RED)✗\(RESET) \(name)")
            for err in ctx.currentTestErrors {
                print("    \(RED)\(err)\(RESET)")
                ctx.failures.append("\(name): \(err)")
            }
        } else {
            ctx.passed += 1
            print("  \(GREEN)✓\(RESET) \(name)")
        }
    } catch {
        ctx.failed += 1
        let msg = "\(name): \(error)"
        ctx.failures.append(msg)
        print("  \(RED)✗\(RESET) \(name)")
        print("    \(RED)\(error)\(RESET)")
    }
}

func expect(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        ctx.currentTestFailed = true
        let loc = "\((file as NSString).lastPathComponent):\(line)"
        ctx.currentTestErrors.append(message.isEmpty ? "Expectation failed at \(loc)" : "\(message) (\(loc))")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a != b {
        ctx.currentTestFailed = true
        let loc = "\((file as NSString).lastPathComponent):\(line)"
        let base = "Expected '\(b)', got '\(a)'"
        ctx.currentTestErrors.append(message.isEmpty ? "\(base) (\(loc))" : "\(message): \(base) (\(loc))")
    }
}

func suite(_ name: String, _ block: () -> Void) {
    print("\n\(BOLD)\(CYAN)▶ \(name)\(RESET)")
    block()
}

// MARK: - Hotkey testi

func runHotkeyTests() {
    suite("HotkeyTests") {
        test("default hotkey is right Option (0x3D, modifier-only)") {
            let hk = Hotkey.default
            expectEqual(hk.keyCode, 0x3D)
            expect(hk.isModifierOnly, "default should be modifier-only")
            expect(!hk.isMouse, "default should not be mouse")
            expectEqual(hk.modifiers, 0)
        }

        test("modifier flags for known key codes") {
            expectEqual(Hotkey.modifierFlag(for: 0x3D), .maskAlternate)
            expectEqual(Hotkey.modifierFlag(for: 0x3A), .maskAlternate)
            expectEqual(Hotkey.modifierFlag(for: 0x36), .maskCommand)
            expectEqual(Hotkey.modifierFlag(for: 0x37), .maskCommand)
            expectEqual(Hotkey.modifierFlag(for: 0x38), .maskShift)
            expectEqual(Hotkey.modifierFlag(for: 0x3C), .maskShift)
            expectEqual(Hotkey.modifierFlag(for: 0x3B), .maskControl)
            expectEqual(Hotkey.modifierFlag(for: 0x3E), .maskControl)
            expectEqual(Hotkey.modifierFlag(for: 0x3F), .maskSecondaryFn)
            expect(Hotkey.modifierFlag(for: 0x00) == nil, "key 'A' should not be modifier")
        }

        test("label generation for modifier-only Option") {
            let hk = Hotkey(keyCode: 0x3D, modifiers: 0, isMouse: false, mouseButton: 0, isModifierOnly: true)
            let label = hk.label
            expect(label.contains("⌥"), "label should contain ⌥, got: \(label)")
        }

        test("label generation for Command modifier") {
            let hk = Hotkey(keyCode: 0x36, modifiers: 0, isMouse: false, mouseButton: 0, isModifierOnly: true)
            let label = hk.label
            expect(label.contains("⌘"), "label should contain ⌘, got: \(label)")
        }

        test("label generation for middle mouse button") {
            let hk = Hotkey(keyCode: 0, modifiers: 0, isMouse: true, mouseButton: 2, isModifierOnly: false)
            expectEqual(hk.label, "Vidējā peles poga")
        }

        test("matches(keyCode:flags:) for regular key") {
            let hk = Hotkey(keyCode: 0x00, modifiers: CGEventFlags.maskCommand.rawValue,
                            isMouse: false, mouseButton: 0, isModifierOnly: false)
            expect(hk.matches(keyCode: 0x00, flags: .maskCommand), "should match with Command")
            expect(!hk.matches(keyCode: 0x00, flags: []), "should not match without Command")
            expect(!hk.matches(keyCode: 0x01, flags: .maskCommand), "should not match different key")
        }

        test("matches returns false for modifier-only hotkey") {
            let hk = Hotkey.default
            expect(!hk.matches(keyCode: 0x3D, flags: .maskAlternate), "modifier-only should not match via matches()")
        }

        test("matches returns false for mouse hotkey") {
            let hk = Hotkey(keyCode: 0, modifiers: 0, isMouse: true, mouseButton: 2, isModifierOnly: false)
            expect(!hk.matches(keyCode: 0, flags: []), "mouse hotkey should not match via matches()")
        }

        test("JSON Codable roundtrip") {
            let original = Hotkey(keyCode: 0x3D, modifiers: CGEventFlags.maskAlternate.rawValue,
                                  isMouse: false, mouseButton: 0, isModifierOnly: true)
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(Hotkey.self, from: data)
            expectEqual(decoded, original)
        }

        test("JSON Codable roundtrip for mouse hotkey") {
            let original = Hotkey(keyCode: 0, modifiers: 0, isMouse: true, mouseButton: 3, isModifierOnly: false)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
            expectEqual(decoded, original)
        }
    }
}

// MARK: - UpdateChecker testi

func runUpdateCheckerTests() {
    suite("UpdateCheckerTests") {
        test("isVersion: 2.4.4 > 2.4.3") {
            expect(UpdateChecker.isVersion("2.4.4", greaterThan: "2.4.3"))
        }

        test("isVersion: 2.10.0 > 2.9.0") {
            expect(UpdateChecker.isVersion("2.10.0", greaterThan: "2.9.0"))
        }

        test("isVersion: 1.0 > 1.0 is false") {
            expect(!UpdateChecker.isVersion("1.0", greaterThan: "1.0"))
        }

        test("isVersion: 1.0 > 1.1 is false") {
            expect(!UpdateChecker.isVersion("1.0", greaterThan: "1.1"))
        }

        test("extractDMGURL finds runAI.dmg") {
            let json: [String: Any] = [
                "assets": [
                    ["name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"],
                    ["name": "runAI.dmg", "browser_download_url": "https://example.com/runAI.dmg"]
                ]
            ]
            let url = UpdateChecker.extractDMGURL(from: json)
            expectEqual(url?.absoluteString, "https://example.com/runAI.dmg")
        }

        test("extractDMGURL falls back to any .dmg") {
            let json: [String: Any] = [
                "assets": [
                    ["name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"],
                    ["name": "runAI-1.2.3.dmg", "browser_download_url": "https://example.com/runAI-1.2.3.dmg"]
                ]
            ]
            let url = UpdateChecker.extractDMGURL(from: json)
            expectEqual(url?.absoluteString, "https://example.com/runAI-1.2.3.dmg")
        }

        test("extractDMGURL returns nil when no dmg present") {
            let json: [String: Any] = [
                "assets": [
                    ["name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"]
                ]
            ]
            expect(UpdateChecker.extractDMGURL(from: json) == nil)
        }

        test("extractDMGURL returns nil when assets missing") {
            let json: [String: Any] = [:]
            expect(UpdateChecker.extractDMGURL(from: json) == nil)
        }
    }
}

// MARK: - AudioGuard testi

func runAudioGuardTests() {
    suite("AudioGuardTests") {
        test("hasSpeech returns false for silence") {
            let samples = [Float](repeating: 0.0005, count: 16000)
            expect(!AudioGuard.hasSpeech(samples), "silence should not be speech")
        }

        test("hasSpeech returns true for active burst") {
            var samples = [Float](repeating: 0.0005, count: 16000)
            // Ievietojam skaļu signālu vairākos logos.
            for i in 0..<8000 {
                samples[i] = 0.5 * sin(Float(i) * 0.1)
            }
            expect(AudioGuard.hasSpeech(samples), "active burst should be speech")
        }

        test("hasSpeech returns false for empty samples") {
            expect(!AudioGuard.hasSpeech([]))
        }

        test("cleanTranscription removes Latvian cliche 'Paldies par skatīšanos!'") {
            expectEqual(AudioGuard.cleanTranscription("Paldies par skatīšanos!"), "")
        }

        test("cleanTranscription removes Latvian cliche 'Paldies par uzmanību!'") {
            expectEqual(AudioGuard.cleanTranscription("Paldies par uzmanību!"), "")
        }

        test("cleanTranscription removes Latvian cliche 'Abonējiet kanālu'") {
            expectEqual(AudioGuard.cleanTranscription("Abonējiet kanālu"), "")
        }

        test("cleanTranscription removes English cliche 'Subtitles by the Amara.org community'") {
            expectEqual(AudioGuard.cleanTranscription("Subtitles by the Amara.org community"), "")
        }

        test("cleanTranscription collapses repetition loop 'Jā jā jā jā labi'") {
            expectEqual(AudioGuard.cleanTranscription("Jā jā jā jā labi"), "Jā labi")
        }

        test("cleanTranscription preserves normal text 'Labdien!'") {
            expectEqual(AudioGuard.cleanTranscription("Labdien!"), "Labdien!")
        }

        test("cleanTranscription returns empty for empty input") {
            expectEqual(AudioGuard.cleanTranscription(""), "")
        }

        test("isLongEnough verifies minSamples threshold") {
            expectEqual(AudioGuard.minSamples, 4800)
            let short = [Float](repeating: 0.1, count: 4799)
            let exact = [Float](repeating: 0.1, count: 4800)
            let longer = [Float](repeating: 0.1, count: 4801)
            expect(!AudioGuard.isLongEnough(short), "short buffer should not be long enough")
            expect(AudioGuard.isLongEnough(exact), "exact 4800 should be long enough")
            expect(AudioGuard.isLongEnough(longer), "longer buffer should be long enough")
        }
    }
}

// MARK: - ModelCatalog testi

func runModelCatalogTests() {
    suite("ModelCatalogTests") {
        test("catalog is not empty") {
            expect(!ModelEntry.catalog.isEmpty, "catalog should not be empty")
        }

        test("each entry has valid sizeMB > 0") {
            for entry in ModelEntry.catalog {
                expect(entry.sizeMB > 0, "entry \(entry.fileName) has invalid sizeMB \(entry.sizeMB)")
            }
        }

        test("each entry fileName ends with .bin") {
            for entry in ModelEntry.catalog {
                expect(entry.fileName.hasSuffix(".bin"),
                       "entry \(entry.fileName) does not end with .bin")
            }
        }

        test("each entry has valid URL") {
            for entry in ModelEntry.catalog {
                let url = entry.url
                expect(url.scheme == "https" || url.scheme == "http",
                       "entry \(entry.fileName) has invalid URL scheme: \(url.scheme ?? "nil")")
                expect(!url.absoluteString.isEmpty,
                       "entry \(entry.fileName) has empty URL")
            }
        }

        test("each entry has non-empty title and note") {
            for entry in ModelEntry.catalog {
                expect(!entry.title.isEmpty, "entry \(entry.fileName) has empty title")
                expect(!entry.note.isEmpty, "entry \(entry.fileName) has empty note")
            }
        }
    }
}

// MARK: - Galvenā funkcija

@main
struct TestMain {
    static func main() {
        let start = Date()

        print("\(BOLD)runAI testu komplekts\(RESET)")
        print("\(DIM)\(Date())\(RESET)")

        runHotkeyTests()
        runUpdateCheckerTests()
        runAudioGuardTests()
        runModelCatalogTests()

        let elapsed = Date().timeIntervalSince(start)
        let total = ctx.passed + ctx.failed

        print("")
        print("\(BOLD)─────────────────────────────────────\(RESET)")
        if ctx.failed == 0 {
            print("\(GREEN)\(BOLD)✓ Visi testi izturēti\(RESET) \(DIM)(\(ctx.passed)/\(total))\(RESET)")
        } else {
            print("\(RED)\(BOLD)✗ \(ctx.failed) no \(total) testiem neizturēja\(RESET)")
            print("\(GREEN)  Izturēti: \(ctx.passed)\(RESET)")
            print("\(RED)  Neizturēti: \(ctx.failed)\(RESET)")
            print("")
            print("\(RED)\(BOLD)Neizdevušies testi:\(RESET)")
            for f in ctx.failures {
                print("  \(RED)• \(f)\(RESET)")
            }
        }
        print("\(DIM)Laiks: \(String(format: "%.3f", elapsed))s\(RESET)")
        print("\(BOLD)─────────────────────────────────────\(RESET)")

        exit(ctx.failed == 0 ? 0 : 1)
    }
}
