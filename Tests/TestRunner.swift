import Foundation
import CoreGraphics
import AppKit

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

// MARK: - Testu palīgi

/// Izveido pagaidu direktoriju un atgriež tā URL. Izsaucējam jāiztīra ar `try? FileManager.default.removeItem(at:)`.
func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("runAI-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Izveido viltus .app pakotni ar Info.plist saturošu CFBundleIdentifier.
func makeFakeApp(at url: URL, bundleId: String?, marker: String? = nil) throws {
    let fm = FileManager.default
    let contents = url.appendingPathComponent("Contents", isDirectory: true)
    try fm.createDirectory(at: contents, withIntermediateDirectories: true)

    if let bundleId = bundleId {
        let plist: [String: Any] = ["CFBundleIdentifier": bundleId]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    if let marker = marker {
        try marker.data(using: .utf8)?.write(to: contents.appendingPathComponent("marker.txt"))
    }
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

// MARK: - HotkeyMonitor testi

func runHotkeyMonitorTests() {
    suite("HotkeyMonitorTests") {
        test("modifier-only press and release") {
            let monitor = HotkeyMonitor(hotkey: .default) // right Option 0x3D
            let press = monitor.processKeyboardEvent(type: .flagsChanged, keyCode: 0x3D, flags: .maskAlternate, autorepeat: false)
            expectEqual(press.action, .press)
            expect(!press.consume, "modifier-only press should not consume")

            let release = monitor.processKeyboardEvent(type: .flagsChanged, keyCode: 0x3D, flags: [], autorepeat: false)
            expectEqual(release.action, .release)
            expect(!release.consume, "modifier-only release should not consume")
        }

        test("modifier-only compound-key cancel then release -> none") {
            let monitor = HotkeyMonitor(hotkey: .default)
            let press = monitor.processKeyboardEvent(type: .flagsChanged, keyCode: 0x3D, flags: .maskAlternate, autorepeat: false)
            expectEqual(press.action, .press)

            // Nospiežam citu taustiņu, turot modifikatoru — atcelšana.
            let cancel = monitor.processKeyboardEvent(type: .keyDown, keyCode: 0x7B, flags: .maskAlternate, autorepeat: false)
            expectEqual(cancel.action, .cancel)
            expect(!cancel.consume, "compound-key cancel should not consume")

            // Atlaidam modifikatoru — pēc atcelšanas nekāda darbība.
            let release = monitor.processKeyboardEvent(type: .flagsChanged, keyCode: 0x3D, flags: [], autorepeat: false)
            expectEqual(release.action, .none)
        }

        test("combo hotkey Cmd+A press and release consumes both") {
            let hk = Hotkey(keyCode: 0x00, modifiers: CGEventFlags.maskCommand.rawValue,
                            isMouse: false, mouseButton: 0, isModifierOnly: false)
            let monitor = HotkeyMonitor(hotkey: hk)

            let press = monitor.processKeyboardEvent(type: .keyDown, keyCode: 0x00, flags: .maskCommand, autorepeat: false)
            expectEqual(press.action, .press)
            expect(press.consume, "combo press should consume")

            let release = monitor.processKeyboardEvent(type: .keyUp, keyCode: 0x00, flags: .maskCommand, autorepeat: false)
            expectEqual(release.action, .release)
            expect(release.consume, "combo release should consume")
        }

        test("regression bug #5: plain keyUp of non-modifier hotkey when !isDown is not consumed") {
            // Cmd+Space hotkey (Space = 0x31)
            let hk = Hotkey(keyCode: 0x31, modifiers: CGEventFlags.maskCommand.rawValue,
                            isMouse: false, mouseButton: 0, isModifierOnly: false)
            let monitor = HotkeyMonitor(hotkey: hk)

            // Nospiežam Space bez Cmd — nav mūsu hotkey, neapēdam.
            let down = monitor.processKeyboardEvent(type: .keyDown, keyCode: 0x31, flags: [], autorepeat: false)
            expectEqual(down.action, .none)
            expect(!down.consume, "plain keyDown should not consume")

            // Atlaidam Space — isDown == false, tāpēc neapēdam un darbība .none.
            let up = monitor.processKeyboardEvent(type: .keyUp, keyCode: 0x31, flags: [], autorepeat: false)
            expectEqual(up.action, .none)
            expect(!up.consume, "plain keyUp when !isDown must not be consumed (bug #5)")
        }

        test("mouse button press and release consumes and returns press/release") {
            let hk = Hotkey(keyCode: 0, modifiers: 0, isMouse: true, mouseButton: 2, isModifierOnly: false)
            let monitor = HotkeyMonitor(hotkey: hk)

            let press = monitor.processMouseEvent(type: .otherMouseDown, button: 2)
            expectEqual(press.action, .press)
            expect(press.consume, "mouse press should consume")

            let release = monitor.processMouseEvent(type: .otherMouseUp, button: 2)
            expectEqual(release.action, .release)
            expect(release.consume, "mouse release should consume")
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

        test("isVersion: 3.0.0 vs 3.0 are equal (not greater)") {
            expect(!UpdateChecker.isVersion("3.0.0", greaterThan: "3.0"))
            expect(!UpdateChecker.isVersion("3.0", greaterThan: "3.0.0"))
        }

        test("isVersion: prerelease is less than release") {
            expect(!UpdateChecker.isVersion("3.0.1-beta.1", greaterThan: "3.0.1"))
            expect(UpdateChecker.isVersion("3.0.1", greaterThan: "3.0.1-beta.1"))
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

        test("validateSourceApp succeeds for valid bundle") {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let app = dir.appendingPathComponent("runAI.app")
            try makeFakeApp(at: app, bundleId: "lv.runai.app")

            let checker = UpdateChecker()
            var threw = false
            do { try checker.validateSourceApp(app) } catch { threw = true }
            expect(!threw, "valid bundle should not throw")
        }

        test("validateSourceApp throws for wrong bundle ID") {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let app = dir.appendingPathComponent("runAI.app")
            try makeFakeApp(at: app, bundleId: "com.example.evil")

            let checker = UpdateChecker()
            var threw = false
            do { try checker.validateSourceApp(app) } catch { threw = true }
            expect(threw, "wrong bundle ID should throw")
        }

        test("validateSourceApp throws when Info.plist missing") {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let app = dir.appendingPathComponent("runAI.app")
            try makeFakeApp(at: app, bundleId: nil)

            let checker = UpdateChecker()
            var threw = false
            do { try checker.validateSourceApp(app) } catch { threw = true }
            expect(threw, "missing Info.plist should throw")
        }

        test("replaceApp successfully replaces target bundle") {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            let source = dir.appendingPathComponent("source.app")
            let target = dir.appendingPathComponent("target.app")
            try makeFakeApp(at: source, bundleId: "lv.runai.app", marker: "NEW")
            try makeFakeApp(at: target, bundleId: "lv.runai.app", marker: "OLD")

            let checker = UpdateChecker()
            try checker.replaceApp(source: source, target: target)

            let markerURL = target.appendingPathComponent("Contents/marker.txt")
            let content = try String(contentsOf: markerURL, encoding: .utf8)
            expectEqual(content, "NEW", "target should contain new bundle content")

            let backup = target.appendingPathExtension("old")
            expect(!FileManager.default.fileExists(atPath: backup.path), ".old backup should be removed")
        }

        test("replaceApp restores original target when copy fails") {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            let missingSource = dir.appendingPathComponent("missing.app")
            let target = dir.appendingPathComponent("target.app")
            try makeFakeApp(at: target, bundleId: "lv.runai.app", marker: "ORIGINAL")

            let checker = UpdateChecker()
            var threw = false
            do { try checker.replaceApp(source: missingSource, target: target) } catch { threw = true }
            expect(threw, "replaceApp should throw when source missing")

            // Mērķis atjaunots neskarts.
            let markerURL = target.appendingPathComponent("Contents/marker.txt")
            let content = try String(contentsOf: markerURL, encoding: .utf8)
            expectEqual(content, "ORIGINAL", "original target should be restored intact")

            let backup = target.appendingPathExtension("old")
            expect(!FileManager.default.fileExists(atPath: backup.path), ".old backup should not be left behind")
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

// MARK: - TextInserter testi

func runTextInserterTests() {
    suite("TextInserterTests") {
        test("shouldFallbackToPaste returns true for text roles") {
            expect(TextInserter.shouldFallbackToPaste(role: "AXTextField", isEditable: nil))
            expect(TextInserter.shouldFallbackToPaste(role: "AXTextArea", isEditable: nil))
            expect(TextInserter.shouldFallbackToPaste(role: "AXWebArea", isEditable: nil))
            expect(TextInserter.shouldFallbackToPaste(role: nil, isEditable: nil))
        }

        test("shouldFallbackToPaste returns false for non-text roles") {
            expect(!TextInserter.shouldFallbackToPaste(role: "AXButton", isEditable: false))
            expect(!TextInserter.shouldFallbackToPaste(role: "AXScrollArea", isEditable: false))
            expect(!TextInserter.shouldFallbackToPaste(role: "AXOutline", isEditable: false))
        }

        test("shouldFallbackToPaste returns true for editable group") {
            expect(TextInserter.shouldFallbackToPaste(role: "AXGroup", isEditable: true))
        }

        test("snapshotPasteboard/restorePasteboard roundtrip") {
            let pb = NSPasteboard.withUniqueName()
            defer { pb.releaseGlobally() }

            pb.clearContents()
            pb.setString("hello", forType: .string)
            pb.addTypes([NSPasteboard.PasteboardType("lv.runai.test.custom")], owner: nil)
            if let item = pb.pasteboardItems?.first {
                item.setData(Data([0x01, 0x02, 0x03]), forType: NSPasteboard.PasteboardType("lv.runai.test.custom"))
            }

            let snapshot = TextInserter.snapshotPasteboard(pb)
            expect(!snapshot.isEmpty, "snapshot should not be empty")

            // Aizstājam saturu.
            pb.clearContents()
            pb.setString("replaced", forType: .string)
            expectEqual(pb.string(forType: .string), "replaced")

            // Atjaunojam.
            TextInserter.restorePasteboard(pb, items: snapshot)
            expectEqual(pb.string(forType: .string), "hello", "restored string should match original")
            let customData = pb.pasteboardItems?.first?.data(forType: NSPasteboard.PasteboardType("lv.runai.test.custom"))
            expectEqual(customData, Data([0x01, 0x02, 0x03]), "restored custom data should match original")
        }
    }
}

// MARK: - PreferencesManager testi

func runPreferencesManagerTests() {
    suite("PreferencesManagerTests") {
        test("ignores CADefaultDeviceAggregate and 0 in selectedInput") {
            MainActor.assumeIsolated {
                let suiteName = "lv.runai.tests." + UUID().uuidString
                guard let defaults = UserDefaults(suiteName: suiteName) else {
                    expect(false, "failed to create isolated UserDefaults")
                    return
                }
                defer { defaults.removePersistentDomain(forName: suiteName) }

                defaults.set("CADefaultDeviceAggregate", forKey: "selectedInput")
                let pm1 = PreferencesManager(defaults: defaults)
                expect(pm1.selectedInputID == nil, "CADefaultDeviceAggregate should be ignored")

                defaults.set("0", forKey: "selectedInput")
                let pm2 = PreferencesManager(defaults: defaults)
                expect(pm2.selectedInputID == nil, "\"0\" should be ignored")
            }
        }

        test("persists language, hudPosition, blurBackdrop, hotkey across instances") {
            MainActor.assumeIsolated {
                let suiteName = "lv.runai.tests." + UUID().uuidString
                guard let defaults = UserDefaults(suiteName: suiteName) else {
                    expect(false, "failed to create isolated UserDefaults")
                    return
                }
                defer { defaults.removePersistentDomain(forName: suiteName) }

                let pm1 = PreferencesManager(defaults: defaults)
                pm1.setLanguage("en")
                pm1.setHUDPosition(.top)
                pm1.setBlurBackdrop(false)
                let customHotkey = Hotkey(keyCode: 0x00, modifiers: CGEventFlags.maskCommand.rawValue,
                                          isMouse: false, mouseButton: 0, isModifierOnly: false)
                pm1.setHotkey(customHotkey)

                let pm2 = PreferencesManager(defaults: defaults)
                expectEqual(pm2.language, "en")
                expectEqual(pm2.hudPosition, .top)
                expectEqual(pm2.blurBackdrop, false)
                expectEqual(pm2.hotkey, customHotkey)
            }
        }
    }
}

// MARK: - Galvenā funkcija

@main
struct TestMain {
    @MainActor
    static func main() {
        let start = Date()

        print("\(BOLD)runAI testu komplekts\(RESET)")
        print("\(DIM)\(Date())\(RESET)")

        runHotkeyTests()
        runHotkeyMonitorTests()
        runUpdateCheckerTests()
        runAudioGuardTests()
        runModelCatalogTests()
        runTextInserterTests()
        runPreferencesManagerTests()

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
