import Foundation

enum WhisperModelSize: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tiny: return "Tiny (~75 MB) — سریع"
        case .base: return "Base (~142 MB) — متعادل"
        case .small: return "Small (~466 MB) — دقیق"
        }
    }

    var downloadFileName: String { "ggml-\(rawValue).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(downloadFileName)")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 142
        case .small: return 466
        }
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var statusMessage = ""

    static let shared = ModelManager()

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
        FileManager.default.fileExists(atPath: modelPath(for: size).path)
    }

    func ensureModel(_ size: WhisperModelSize) async throws -> URL {
        let path = modelPath(for: size)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        try await downloadModel(size)
        return path
    }

    func downloadModel(_ size: WhisperModelSize) async throws {
        isDownloading = true
        downloadProgress = 0
        statusMessage = "در حال دانلود \(size.downloadFileName)..."
        defer {
            isDownloading = false
        }

        let destination = modelPath(for: size)
        let (tempURL, response) = try await URLSession.shared.download(from: size.downloadURL)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        downloadProgress = 1
        statusMessage = "مدل دانلود شد"
    }
}
