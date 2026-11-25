import Foundation
import Combine
import AppKit

/// Versiju pārbaudītājs, kas sazinās ar GitHub Releases API,
/// lai noskaidrotu, vai ir pieejama jaunāka runAI versija.
final class UpdateChecker: NSObject, ObservableObject, URLSessionDownloadDelegate {

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var lastCheckDate: Date?
    @Published var errorMessage: String?

    // MARK: - Automātiskās atjaunināšanas stāvoklis

    @Published var isUpdating = false
    @Published var updateProgress: Double = 0
    @Published var updateStage: String = ""
    @Published var downloadAssetURL: URL?
    var onRelaunch: (() -> Void)?

    private var activeDownloadSession: URLSession?
    private var activeTempDMG: URL?

    static let repoOwner = "kaspars1985"
    static let repoName = "runAI"

    override init() {
        super.init()
    }

    /// Pašreizējā lietotnes versija no Info.plist.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Pārbauda atjauninājumus GitHub Releases.
    /// - Parameter manual: Ja patiess, kļūdas paziņojums tiks parādīts lietotājam.
    func checkForUpdates(manual: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        let endpoint = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: endpoint) else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("runAI-App", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                self.lastCheckDate = Date()

                if let error = error {
                    if manual {
                        self.errorMessage = "Neizdevās pārbaudīt: \(error.localizedDescription)"
                    }
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if manual {
                        self.errorMessage = "Nav pieejama informācija par jaunāko versiju."
                    }
                    return
                }

                // Ja GitHub atgriež ziņojumu (piemēram, "Not Found", ja repozitorijā vēl nav relīžu)
                if let msg = json["message"] as? String, msg.lowercased().contains("not found") {
                    if manual {
                        self.errorMessage = "Pagaidām vēl nav publicētu publisku relīžu."
                    }
                    self.updateAvailable = false
                    return
                }

                guard let tagName = json["tag_name"] as? String else {
                    if manual {
                        self.errorMessage = "Nav atrasta versijas atzīme."
                    }
                    return
                }

                let cleanTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let current = self.currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

                // Atrodam DMG lejupielādes saiti starp relīzes failiem.
                self.downloadAssetURL = Self.extractDMGURL(from: json)

                if Self.isVersion(cleanTag, greaterThan: current) {
                    self.updateAvailable = true
                    self.latestVersion = cleanTag
                    if let htmlUrlStr = json["html_url"] as? String, let u = URL(string: htmlUrlStr) {
                        self.releaseURL = u
                    } else {
                        self.releaseURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")
                    }
                } else {
                    self.updateAvailable = false
                }
            }
        }.resume()
    }

    /// Izvelk no relīzes JSON `assets` masīva DMG faila `browser_download_url`.
    static func extractDMGURL(from json: [String: Any]) -> URL? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }

        // Prioritāte: precīzi "runAI.dmg", tad jebkurš ".dmg".
        var fallback: URL?
        for asset in assets {
            guard let name = asset["name"] as? String,
                  let urlStr = asset["browser_download_url"] as? String,
                  let url = URL(string: urlStr) else { continue }

            let lower = name.lowercased()
            if lower == "runai.dmg" {
                return url
            }
            if lower.hasSuffix(".dmg"), fallback == nil {
                fallback = url
            }
        }
        return fallback
    }

    /// Atver pārlūkprogrammā jaunākās relīzes lapu.
    func openReleasePage() {
        let target = releaseURL ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")!
        NSWorkspace.shared.open(target)
    }

    // MARK: - Automātiskā lejupielāde un instalēšana

    /// Lejupielādē jaunāko DMG un instalē to, aizstājot pašreizējo lietotni.
    func downloadAndInstallUpdate() {
        guard !isUpdating else { return }
        guard let assetURL = downloadAssetURL else {
            errorMessage = "Nav atrasta lejupielādes saite."
            return
        }

        isUpdating = true
        updateProgress = 0
        updateStage = "Lejupielādē atjauninājumu…"
        errorMessage = nil

        let tempDMG = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("runAI-update-\(UUID().uuidString).dmg")
        self.activeTempDMG = tempDMG

        var request = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("runAI-App", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.activeDownloadSession = session

        // Bez completion handler — progress un pabeigšana notiek delegāta metodēs.
        session.downloadTask(with: request).resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.updateProgress = min(max(progress, 0), 1.0)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tempDMG = self.activeTempDMG ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("runAI-update-\(UUID().uuidString).dmg")

        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            session.finishTasksAndInvalidate()
            self.activeDownloadSession = nil
            DispatchQueue.main.async {
                self.failUpdate("Servera kļūda (HTTP \(http.statusCode))")
            }
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: tempDMG.path) {
                try fm.removeItem(at: tempDMG)
            }
            try fm.moveItem(at: location, to: tempDMG)
        } catch {
            session.finishTasksAndInvalidate()
            self.activeDownloadSession = nil
            DispatchQueue.main.async {
                self.failUpdate("Neizdevās saglabāt lejupielādi: \(error.localizedDescription)")
            }
            return
        }

        DispatchQueue.main.async {
            self.updateProgress = 1.0
            self.updateStage = "Instalē atjauninājumu…"
            session.finishTasksAndInvalidate()
            self.activeDownloadSession = nil
            DispatchQueue.global(qos: .userInitiated).async {
                self.installUpdate(from: tempDMG)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        self.activeDownloadSession = nil

        if let error = error {
            if let tempDMG = self.activeTempDMG,
               FileManager.default.fileExists(atPath: tempDMG.path) {
                try? FileManager.default.removeItem(at: tempDMG)
            }
            DispatchQueue.main.async {
                self.failUpdate(error.localizedDescription)
            }
        }
    }

    /// Montē DMG, aizstāj lietotni, notīra karantīnu, atmontē un pārstartē.
    private func installUpdate(from tempDMG: URL) {
        defer { try? FileManager.default.removeItem(at: tempDMG) }

        var mountedPath: String?
        defer {
            if let mp = mountedPath {
                runProcess("/usr/bin/hdiutil", ["detach", mp, "-force"])
            }
        }

        do {
            // 1. Montējam DMG.
            let mountPoint = try mountDMG(tempDMG)
            mountedPath = mountPoint

            // 2. Atrodam .app montētajā sējumā.
            let sourceApp = try findApp(in: mountPoint)

            // 2a. Pārbaudām, vai avota lietotne ir derīga runAI lietotne pirms aizstāšanas.
            try validateSourceApp(sourceApp)

            // 3. Mērķa lietotnes ceļš.
            let targetApp = targetAppURL()

            // 4. Aizstājam lietotni.
            try replaceApp(source: sourceApp, target: targetApp)

            // 5. Notīrām karantīnu.
            runProcess("/usr/bin/xattr", ["-cr", targetApp.path])

            DispatchQueue.main.async {
                self.updateStage = "Pārstartē…"
            }

            // 6. Pārstartējam lietotni un aizveram pašreizējo.
            runProcess("/bin/bash", ["-c", "sleep 0.8 && open -n \"$1\" >/dev/null 2>&1 &", "_", targetApp.path])

            DispatchQueue.main.async {
                if let custom = self.onRelaunch {
                    custom()
                } else {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.failUpdate(error.localizedDescription)
            }
        }
    }

    private func failUpdate(_ message: String) {
        isUpdating = false
        updateProgress = 0
        updateStage = ""
        errorMessage = message
    }

    // MARK: - Instalēšanas palīgi

    private struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Montē DMG un atgriež montēšanas punktu (piem., /Volumes/runAI).
    private func mountDMG(_ dmg: URL) throws -> String {
        let output = try runProcessCapturing("/usr/bin/hdiutil",
                                             ["attach", "-nobrowse", "-readonly", dmg.path])
        // hdiutil izvada tabulatoru atdalītu tabulu; montēšanas punkts ir pēdējā kolonna.
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            if let last = cols.last {
                let path = String(last).trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("/Volumes/") {
                    return path
                }
            }
        }
        throw InstallError(message: "Neizdevās noteikt DMG montēšanas punktu.")
    }

    /// Pārbauda, vai avota .app satur derīgu Info.plist ar CFBundleIdentifier "lv.runai.app".
    func validateSourceApp(_ sourceApp: URL) throws {
        let infoPlist = sourceApp
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        guard FileManager.default.fileExists(atPath: infoPlist.path) else {
            throw InstallError(message: "Atjauninājuma pakotnē nav atrasts Info.plist — instalēšana pārtraukta drošības nolūkos.")
        }

        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let bundleId = plist["CFBundleIdentifier"] as? String else {
            throw InstallError(message: "Neizdevās nolasīt atjauninājuma Info.plist — instalēšana pārtraukta drošības nolūkos.")
        }

        guard bundleId == "lv.runai.app" else {
            throw InstallError(message: "Atjauninājuma pakotnes identifikators nav \"lv.runai.app\" (atrasts: \"\(bundleId)\") — instalēšana pārtraukta drošības nolūkos.")
        }
    }

    /// Atrod .app pakotni montētajā sējumā.
    private func findApp(in mountPoint: String) throws -> URL {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: mountPoint)
        for name in contents where name.hasSuffix(".app") {
            return URL(fileURLWithPath: mountPoint).appendingPathComponent(name)
        }
        throw InstallError(message: "DMG failā nav atrasta .app lietotne.")
    }

    /// Nosaka mērķa lietotnes ceļu (/Applications/runAI.app vai pašreizējais).
    private func targetAppURL() -> URL {
        let current = Bundle.main.bundleURL
        let applications = URL(fileURLWithPath: "/Applications")
        let preferred = applications.appendingPathComponent("runAI.app")

        // Ja pašreizējā lietotne jau atrodas /Applications, atjauninām to pašu.
        if current.deletingLastPathComponent().path == "/Applications" {
            return current
        }
        return preferred
    }

    /// Aizstāj mērķa lietotni ar jauno no DMG.
    func replaceApp(source: URL, target: URL) throws {
        let fm = FileManager.default
        let backup = target.appendingPathExtension("old")

        // Ja mērķis eksistē, pārvietojam uz .old, lai varētu aizstāt.
        if fm.fileExists(atPath: target.path) {
            if fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: backup)
            }
            try fm.moveItem(at: target, to: backup)
        }

        do {
            try fm.copyItem(at: source, to: target)
        } catch {
            // Atjaunojam iepriekšējo lietotni, ja kopēšana neizdevās.
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: target)
            }
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: target)
            }
            throw error
        }

        // Notīrām veco rezerves kopiju tikai pēc veiksmīgas kopēšanas.
        try? fm.removeItem(at: backup)
    }

    /// Palaidž procesu un atgriež izvadi (stdout).
    @discardableResult
    private func runProcessCapturing(_ path: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw InstallError(message: "Komanda \(path) beidzās ar kļūdu (kods \(process.terminationStatus)).")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Palaidž procesu, ignorējot izvadi.
    private func runProcess(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Semantiskā versiju salīdzināšana (piem., 1.10 > 1.2, 1.1 > 1.0, 1.0 > 1.0-beta).
    static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        func split(_ v: String) -> (core: [Int], prerelease: String?) {
            let parts = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let coreStr = String(parts.first ?? "")
            let pre = parts.count > 1 ? String(parts[1]) : nil
            let core = coreStr.split(separator: ".").map { Int($0) ?? 0 }
            return (core, pre)
        }

        let (core1, pre1) = split(v1)
        let (core2, pre2) = split(v2)

        let maxLen = max(core1.count, core2.count)
        let padded1 = core1 + Array(repeating: 0, count: maxLen - core1.count)
        let padded2 = core2 + Array(repeating: 0, count: maxLen - core2.count)

        for i in 0..<maxLen {
            if padded1[i] != padded2[i] {
                return padded1[i] > padded2[i]
            }
        }

        // Kodoli vienādi — salīdzinām pirmsizlaiduma atzīmes.
        if pre1 == nil && pre2 != nil { return true }
        if pre1 != nil && pre2 == nil { return false }
        if let p1 = pre1, let p2 = pre2 {
            return p1.compare(p2, options: .numeric) == .orderedDescending
        }
        return false
    }
}
