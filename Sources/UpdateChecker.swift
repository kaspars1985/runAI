import Foundation
import Combine
import AppKit

/// Versiju pārbaudītājs, kas sazinās ar GitHub Releases API,
/// lai noskaidrotu, vai ir pieejama jaunāka runAI versija.
final class UpdateChecker: ObservableObject {

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

    static let repoOwner = "kaspars1985"
    static let repoName = "runAI"

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

        var request = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("runAI-App", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .default,
                                 delegate: DownloadProgressDelegate(owner: self),
                                 delegateQueue: nil)
        let task = session.downloadTask(with: request) { [weak self] location, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.failUpdate(error.localizedDescription)
                }
                return
            }
            guard let location = location else {
                DispatchQueue.main.async {
                    self.failUpdate("Lejupielāde neizdevās.")
                }
                return
            }

            // Pārvietojam lejupielādēto failu uz temp DMG ceļu.
            do {
                if FileManager.default.fileExists(atPath: tempDMG.path) {
                    try FileManager.default.removeItem(at: tempDMG)
                }
                try FileManager.default.moveItem(at: location, to: tempDMG)
            } catch {
                DispatchQueue.main.async {
                    self.failUpdate("Neizdevās saglabāt lejupielādi: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.updateProgress = 1.0
                self.updateStage = "Instalē atjauninājumu…"
            }

            // Instalēšana fonā.
            DispatchQueue.global(qos: .userInitiated).async {
                self.installUpdate(from: tempDMG)
            }
        }
        task.resume()
    }

    /// Faila lejupielādes gaitas delegāts.
    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
        weak var owner: UpdateChecker?
        init(owner: UpdateChecker) { self.owner = owner }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async {
                self.owner?.updateProgress = min(max(progress, 0), 1.0)
            }
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // Apstrāde notiek downloadTask pabeigšanas blokā.
        }
    }

    /// Montē DMG, aizstāj lietotni, notīra karantīnu, atmontē un pārstartē.
    private func installUpdate(from tempDMG: URL) {
        do {
            // 1. Montējam DMG.
            let mountPoint = try mountDMG(tempDMG)

            // 2. Atrodam .app montētajā sējumā.
            let sourceApp = try findApp(in: mountPoint)

            // 3. Mērķa lietotnes ceļš.
            let targetApp = targetAppURL()

            // 4. Aizstājam lietotni.
            try replaceApp(source: sourceApp, target: targetApp)

            // 5. Notīrām karantīnu.
            runProcess("/usr/bin/xattr", ["-cr", targetApp.path])

            // 6. Atmontējam DMG.
            runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])

            // 7. Dzēšam temp DMG.
            try? FileManager.default.removeItem(at: tempDMG)

            DispatchQueue.main.async {
                self.updateStage = "Pārstartē…"
            }

            // 8. Pārstartējam lietotni un aizveram pašreizējo.
            let relaunch = "/bin/bash"
            let script = "(sleep 0.8 && open -n \"\(targetApp.path)\") &"
            runProcess(relaunch, ["-c", script])

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
    private func replaceApp(source: URL, target: URL) throws {
        let fm = FileManager.default

        // Ja mērķis ir pašreizējā lietotne, pārvietojam uz .old, lai varētu aizstāt.
        if fm.fileExists(atPath: target.path) {
            let backup = target.appendingPathExtension("old")
            try? fm.removeItem(at: backup)
            do {
                try fm.moveItem(at: target, to: backup)
            } catch {
                // Ja nevar pārvietot (piem., lietotne darbojas), mēģinām dzēst.
                try? fm.removeItem(at: target)
            }
        }

        try fm.copyItem(at: source, to: target)

        // Notīrām veco rezerves kopiju.
        let backup = target.appendingPathExtension("old")
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

    /// Semantiskā versiju salīdzināšana (piem., 1.10 > 1.2, 1.1 > 1.0).
    static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
