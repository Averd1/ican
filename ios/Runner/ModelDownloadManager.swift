import Foundation

/// Downloads SmolVLM GGUF model files from HuggingFace CDN.
/// Supports progress reporting, cancellation, and resume on interruption.
final class ModelDownloadManager: NSObject {

    static let shared = ModelDownloadManager()

    // HuggingFace CDN URLs for SmolVLM-500M-Instruct Q8_0
    private static let baseURL = "https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main"
    private static let files: [(name: String, url: String)] = [
        (LlamaService.textModelFilename,
         "\(baseURL)/\(LlamaService.textModelFilename)"),
        (LlamaService.visionProjectorFilename,
         "\(baseURL)/\(LlamaService.visionProjectorFilename)"),
    ]

    private var downloadTasks: [URLSessionDownloadTask] = []
    private var session: URLSession?
    private var progressCallback: ((Double) -> Void)?
    private var completionCallback: ((Bool, String?) -> Void)?
    private var filesDownloaded = 0
    private var totalFiles = 0
    private var currentFileProgress: Double = 0

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start downloading both model files sequentially.
    func startDownload(
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Bool, String?) -> Void
    ) {
        progressCallback = onProgress
        completionCallback = onComplete
        filesDownloaded = 0
        totalFiles = Self.files.count

        // Create models directory if needed
        let modelsDir = LlamaService.modelsDirectory()
        try? FileManager.default.createDirectory(at: modelsDir,
                                                  withIntermediateDirectories: true)

        // Set up URLSession with delegate for progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600 // 1 hour max for large files
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        downloadNextFile()
    }

    /// Cancel all in-progress downloads.
    func cancelDownload() {
        for task in downloadTasks {
            task.cancel()
        }
        downloadTasks.removeAll()
        session?.invalidateAndCancel()
        session = nil
        progressCallback = nil
        completionCallback = nil
    }

    /// Delete downloaded model files.
    func deleteModel() -> Bool {
        let modelsDir = LlamaService.modelsDirectory()
        do {
            if FileManager.default.fileExists(atPath: modelsDir.path) {
                try FileManager.default.removeItem(at: modelsDir)
            }
            return true
        } catch {
            print("[ModelDownload] Failed to delete models: \(error)")
            return false
        }
    }

    /// Get info about downloaded model.
    func getModelInfo() -> [String: Any] {
        let modelsDir = LlamaService.modelsDirectory()
        var totalSize: UInt64 = 0
        var allExist = true

        for file in Self.files {
            let path = modelsDir.appendingPathComponent(file.name).path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64 {
                totalSize += size
            } else {
                allExist = false
            }
        }

        return [
            "downloaded": allExist,
            "sizeBytes": totalSize,
            "path": modelsDir.path,
            "modelName": "SmolVLM-500M-Instruct Q8_0",
        ]
    }

    // MARK: - Private

    private func downloadNextFile() {
        guard filesDownloaded < totalFiles else {
            // All files downloaded
            session?.finishTasksAndInvalidate()
            completionCallback?(true, nil)
            return
        }

        let file = Self.files[filesDownloaded]
        let destPath = LlamaService.modelsDirectory().appendingPathComponent(file.name)

        // Skip if already downloaded (resume support)
        if FileManager.default.fileExists(atPath: destPath.path) {
            print("[ModelDownload] \(file.name) already exists, skipping")
            filesDownloaded += 1
            reportOverallProgress()
            downloadNextFile()
            return
        }

        guard let url = URL(string: file.url) else {
            completionCallback?(false, "Invalid URL for \(file.name)")
            return
        }

        print("[ModelDownload] Starting download: \(file.name)")
        let task = session!.downloadTask(with: url)
        downloadTasks.append(task)
        task.resume()
    }

    private func reportOverallProgress() {
        // Overall progress = (completed files + current file progress) / total files
        let overall = (Double(filesDownloaded) + currentFileProgress) / Double(totalFiles)
        progressCallback?(overall)
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard filesDownloaded < totalFiles else { return }

        let file = Self.files[filesDownloaded]
        let destPath = LlamaService.modelsDirectory().appendingPathComponent(file.name)

        do {
            // Move from temp location to models directory
            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }
            try FileManager.default.moveItem(at: location, to: destPath)
            print("[ModelDownload] Saved: \(file.name)")

            filesDownloaded += 1
            currentFileProgress = 0
            reportOverallProgress()
            downloadNextFile()
        } catch {
            print("[ModelDownload] Failed to save \(file.name): \(error)")
            completionCallback?(false, "Failed to save \(file.name): \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            currentFileProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            reportOverallProgress()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                print("[ModelDownload] Download cancelled")
            } else {
                print("[ModelDownload] Download error: \(error)")
                completionCallback?(false, error.localizedDescription)
            }
        }
    }
}
