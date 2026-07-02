import Foundation

enum WhisperModelSize: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small
    case medium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tiny: return "Tiny (~75 MB) — سریع"
        case .base: return "Base (~142 MB) — متعادل"
        case .small: return "Small (~466 MB) — دقیق"
        case .medium: return "Medium (~1.5 GB) — بسیار دقیق"
        }
    }

    var downloadFileName: String { "ggml-\(rawValue).bin" }

    /// Multiple mirror URLs – tried in order until one works.
    var downloadURLs: [URL] {
        [
            // Primary: Hugging Face
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(downloadFileName)")!,
            // Fallback: GitHub releases (ggerganov/whisper.cpp)
            URL(string: "https://github.com/ggerganov/whisper.cpp/releases/download/v1.7.4/\(downloadFileName)")!,
        ]
    }

    var approximateSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 142
        case .small: return 466
        case .medium: return 1500
        }
    }
}

// MARK: - Download Error

enum ModelDownloadError: LocalizedError {
    case allMirrorsFailed(underlyingErrors: [Error])
    case cancelled
    case invalidResponse(statusCode: Int)
    case fileOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .allMirrorsFailed(let errors):
            let msgs = errors.map { $0.localizedDescription }.joined(separator: "\n  • ")
            return "دانلود از همه آدرس‌ها ناموفق بود:\n  • \(msgs)"
        case .cancelled:
            return "دانلود لغو شد."
        case .invalidResponse(let code):
            return "پاسخ نامعتبر از سرور (کد: \(code))"
        case .fileOperationFailed(let e):
            return "خطا در ذخیره فایل: \(e.localizedDescription)"
        }
    }
}

// MARK: - ModelManager

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var downloadError: String?
    @Published private(set) var downloadSpeed: String = ""

    static let shared = ModelManager()

    private var activeDelegate: DownloadDelegate?

    var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MirzaBenevis/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelPath(for size: WhisperModelSize) -> URL {
        modelsDirectory.appendingPathComponent(size.downloadFileName)
    }

    func isModelDownloaded(_ size: WhisperModelSize) -> Bool {
        if FileManager.default.fileExists(atPath: modelPath(for: size).path) {
            return true
        }
        if Bundle.main.url(forResource: size.downloadFileName, withExtension: nil) != nil {
            return true
        }
        return false
    }

    func ensureModel(_ size: WhisperModelSize) async throws -> URL {
        let path = modelPath(for: size)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        if let bundlePath = Bundle.main.url(forResource: size.downloadFileName, withExtension: nil) {
            return bundlePath
        }
        try await downloadModel(size)
        return path
    }

    /// Cancel the in-progress download.
    func cancelDownload() {
        activeDelegate?.cancel()
        isDownloading = false
        downloadProgress = 0
        statusMessage = "دانلود لغو شد"
        downloadSpeed = ""
    }

    /// Download with real progress, retries across mirrors, and cancel support.
    func downloadModel(_ size: WhisperModelSize) async throws {
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        downloadSpeed = ""
        statusMessage = "در حال دانلود \(size.downloadFileName)..."
        defer {
            isDownloading = false
            activeDelegate = nil
        }

        let destination = modelPath(for: size)
        var mirrorErrors: [Error] = []

        for (index, url) in size.downloadURLs.enumerated() {
            let mirrorName = index == 0 ? "Hugging Face" : "GitHub"
            statusMessage = "در حال دانلود از \(mirrorName)..."
            downloadProgress = 0
            downloadSpeed = ""

            do {
                try await downloadFromURL(url, to: destination, modelName: size.downloadFileName)
                // Success!
                downloadProgress = 1
                statusMessage = "✅ مدل دانلود شد"
                downloadError = nil
                return
            } catch is CancellationError {
                throw ModelDownloadError.cancelled
            } catch let error as ModelDownloadError where error.errorDescription?.contains("لغو") == true {
                throw error
            } catch {
                mirrorErrors.append(error)
                print("[ModelManager] Mirror \(mirrorName) failed: \(error.localizedDescription)")
                if index < size.downloadURLs.count - 1 {
                    statusMessage = "آدرس \(mirrorName) ناموفق، تلاش بعدی..."
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        let finalError = ModelDownloadError.allMirrorsFailed(underlyingErrors: mirrorErrors)
        downloadError = finalError.localizedDescription
        statusMessage = "❌ دانلود ناموفق"
        throw finalError
    }

    // MARK: - Private download implementation

    private func downloadFromURL(_ url: URL, to destination: URL, modelName: String) async throws {
        // Build a URLSession with a delegate for progress tracking
        let delegate = DownloadDelegate()
        activeDelegate = delegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30       // 30s for initial response
        config.timeoutIntervalForResource = 3600    // 1 hour max for the whole file
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 1

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) MirzaBenevis/1.0", forHTTPHeaderField: "User-Agent")

        // Check for partial download to support resume
        let partialURL = destination.appendingPathExtension("partial")
        if FileManager.default.fileExists(atPath: partialURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
           let fileSize = attrs[.size] as? Int64, fileSize > 0 {
            request.setValue("bytes=\(fileSize)-", forHTTPHeaderField: "Range")
            statusMessage = "ادامه دانلود از \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))..."
        }

        let downloadTask = session.downloadTask(with: request)
        delegate.startTask(downloadTask)

        // Observe progress on main actor
        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.downloadProgress = delegate.progress
                self.downloadSpeed = delegate.formattedSpeed
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        defer { progressTask.cancel() }

        // Wait for completion
        let result = await delegate.waitForCompletion()

        switch result {
        case .success(let tempURL):
            // Validate response
            if let httpResponse = delegate.httpResponse {
                guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                    throw ModelDownloadError.invalidResponse(statusCode: httpResponse.statusCode)
                }
            }

            do {
                // Remove old file if exists
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                // Remove partial if exists
                if FileManager.default.fileExists(atPath: partialURL.path) {
                    try FileManager.default.removeItem(at: partialURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
            } catch {
                throw ModelDownloadError.fileOperationFailed(error)
            }

        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                throw ModelDownloadError.cancelled
            }
            throw error
        }
    }
}

// MARK: - DownloadDelegate

/// Handles URLSession download callbacks and bridges to async/await.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Result<URL, Error>, Never>?
    private var downloadTask: URLSessionDownloadTask?

    private(set) var progress: Double = 0
    private(set) var httpResponse: HTTPURLResponse?

    // Speed tracking
    private var lastBytesWritten: Int64 = 0
    private var lastSpeedUpdate = Date()
    private var currentSpeed: Double = 0 // bytes per second

    var formattedSpeed: String {
        lock.lock()
        let speed = currentSpeed
        lock.unlock()
        if speed < 1 { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }

    func startTask(_ task: URLSessionDownloadTask) {
        lock.lock()
        downloadTask = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = downloadTask
        lock.unlock()
        task?.cancel()
    }

    func waitForCompletion() async -> Result<URL, Error> {
        await withCheckedContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        lock.lock()
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }

        // Calculate speed
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedUpdate)
        if elapsed >= 1.0 {
            let bytesInInterval = totalBytesWritten - lastBytesWritten
            currentSpeed = Double(bytesInInterval) / elapsed
            lastBytesWritten = totalBytesWritten
            lastSpeedUpdate = now
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Copy to a temp file we control (the system deletes `location` after this returns)
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent(UUID().uuidString + ".bin")
        do {
            try FileManager.default.moveItem(at: location, to: tmpFile)
            lock.lock()
            httpResponse = downloadTask.response as? HTTPURLResponse
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: .success(tmpFile))
        } catch {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: .failure(error))
    }
}
