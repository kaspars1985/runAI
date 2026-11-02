import Foundation
import AppKit

/// Lejupielādē whisper modeļus no Hugging Face un glabā tos Models mapē.
final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var progress: [String: Double] = [:]   // fileName -> 0…1
    @Published private(set) var activeDownloads: Set<String> = []
    @Published var downloadError: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var completions: [String: (Result<URL, Error>) -> Void] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]

    func download(_ entry: ModelEntry, completion: @escaping (Result<URL, Error>) -> Void) {
        Paths.ensureDirs()
        let dest = Paths.modelsDir.appendingPathComponent(entry.fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            completion(.success(dest))
            return
        }
        let task = session.downloadTask(with: entry.url)
        task.taskDescription = entry.fileName
        DispatchQueue.main.async {
            self.downloadError = nil
            self.progress[entry.fileName] = 0
            self.activeDownloads.insert(entry.fileName)
            self.completions[entry.fileName] = completion
            self.tasks[entry.fileName] = task
        }
        task.resume()
    }

    /// Atceļ aktīvo lejupielādi un paziņo par kļūdu.
    func cancel(_ fileName: String) {
        DispatchQueue.main.async {
            let task = self.tasks[fileName]
            task?.cancel()
            let error = NSError(domain: "runAI.ModelManager", code: -999,
                                userInfo: [NSLocalizedDescriptionKey: "Lejupielāde atcelta"])
            if self.completions[fileName] != nil {
                self.finish(name: fileName, result: .failure(error))
            }
        }
    }

    func delete(_ fileName: String) {
        let url = Paths.modelsDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    func revealModelsFolder() {
        Paths.ensureDirs()
        NSWorkspace.shared.open(Paths.modelsDir)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let name = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            self.progress[name] = fraction
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let name = downloadTask.taskDescription else { return }
        let dest = Paths.modelsDir.appendingPathComponent(name)

        // Pārbaudām HTTP statusu — ja nav 2xx, failu NEpārvietojam.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let error = NSError(domain: "runAI.ModelManager", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "Servera kļūda (HTTP \(http.statusCode))"])
            DispatchQueue.main.async {
                self.finish(name: name, result: .failure(error))
            }
            return
        }

        // Pārbaudām, vai fails nav nepilnīgs (vismaz 1 MB).
        let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size < 1_000_000 {
            let error = NSError(domain: "runAI.ModelManager", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Lejupielādētais fails ir nepilnīgs vai bojāts"])
            DispatchQueue.main.async {
                self.finish(name: name, result: .failure(error))
            }
            return
        }

        // SVARĪGI: pagaidu fails tiek dzēsts, kad šī delegate metode atgriežas,
        // tāpēc faila pārvietošana jāveic SINHRONI (nevis DispatchQueue.main.async).
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.finish(name: name, result: .success(dest))
            }
        } catch {
            // Notīrām daļēji izveidoto failu, ja tāds palicis.
            try? FileManager.default.removeItem(at: dest)
            DispatchQueue.main.async {
                self.finish(name: name, result: .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let name = task.taskDescription, let error = error else { return }
        DispatchQueue.main.async {
            if self.completions[name] != nil {
                self.finish(name: name, result: .failure(error))
            }
        }
    }

    private func finish(name: String, result: Result<URL, Error>) {
        let cb = self.completions.removeValue(forKey: name)
        self.tasks.removeValue(forKey: name)
        self.activeDownloads.remove(name)
        self.progress[name] = nil
        if case .failure(let error) = result {
            self.downloadError = error.localizedDescription
        }
        cb?(result)
    }
}
