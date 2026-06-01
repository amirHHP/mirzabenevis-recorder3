import Foundation

@MainActor
final class WhisperEngine: ObservableObject {
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isProcessing = false
    @Published private(set) var modelName = ""
    @Published var loadError: String?

    private var context: WhisperContext?
    private var timeOffsetMs: Int32 = 0

    func loadModel(size: WhisperModelSize) async {
        loadError = nil
        isModelLoaded = false
        context = nil

        do {
            let path = try await ModelManager.shared.ensureModel(size)
            context = try await WhisperContext.createContext(
                modelPath: path.path,
                useGPU: AppSettings.useGPU
            )
            modelName = size.rawValue
            isModelLoaded = true
            timeOffsetMs = 0
        } catch {
            loadError = error.localizedDescription
            isModelLoaded = false
        }
    }

    func resetTiming() {
        timeOffsetMs = 0
    }

    func transcribe(pcm16: Data, language: String?) async -> WhisperTranscriptionResult? {
        guard let context, !pcm16.isEmpty else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        let samples = Self.pcm16ToFloat(pcm16)
        guard samples.count >= 16_000 else { return nil } // min ~1 sec

        do {
            let result = try await context.transcribe(
                samples: samples,
                language: language,
                offsetMs: timeOffsetMs
            )
            timeOffsetMs += Int32(Double(pcm16.count) / (16000 * 2) * 1000)
            return result
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    private static func pcm16ToFloat(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            return samples.map { Float($0) / 32768.0 }
        }
    }
}
