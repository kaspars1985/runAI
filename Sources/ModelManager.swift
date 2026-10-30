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

    func download(_ entry: ModelEntry, completion: @escaping (Result<URL, Error>) -> Void) {
        Paths.ensureDirs()
        let dest = Paths.modelsDir.appendingPathComponent(entry.fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            completion(.success(dest))
            return
        }
        DispatchQueue.main.async {
            self.downloadError = nil
            self.progress[entry.fileName] = 0
            self.activeDownloads.insert(entry.fileName)
            self.completions[entry.fileName] = completion
        }
        let task = session.downloadTask(with: entry.url)
        task.taskDescription = entry.fileName
        task.resume()
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
        self.activeDownloads.remove(name)
        self.progress[name] = nil
        if case .failure(let error) = result {
            self.downloadError = error.localizedDescription
        }
        cb?(result)
    }
}
