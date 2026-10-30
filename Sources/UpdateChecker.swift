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

                if self.isVersion(cleanTag, greaterThan: current) {
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

    /// Atver pārlūkprogrammā jaunākās relīzes lapu.
    func openReleasePage() {
        let target = releaseURL ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")!
        NSWorkspace.shared.open(target)
    }

    /// Semantiskā versiju salīdzināšana (piem., 1.10 > 1.2, 1.1 > 1.0).
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
