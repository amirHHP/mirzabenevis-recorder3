import Foundation
import whisper

enum WhisperBridgeError: Error, LocalizedError {
    case couldNotInitializeContext
    case transcriptionFailed
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext: return "بارگذاری مدل Whisper ناموفق بود"
        case .transcriptionFailed: return "تبدیل گفتار به متن ناموفق بود"
        case .modelNotFound: return "فایل مدل پیدا نشد"
        }
    }
}

struct WhisperWordResult: Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
}

struct WhisperTranscriptionResult: Sendable {
    let text: String
    let words: [WhisperWordResult]
    let detectedLanguage: String?
}

/// Thread-safe wrapper around whisper.cpp (Metal + Neural Engine on Apple Silicon).
actor WhisperContext {
    private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(
        samples: [Float],
        language: String? = "fa",
        offsetMs: Int32 = 0
    ) throws -> WhisperTranscriptionResult {
        if let language {
            return try language.withCString { langPtr in
                try runTranscription(samples: samples, language: langPtr, detectLanguage: false, offsetMs: offsetMs)
            }
        }
        return try runTranscription(samples: samples, language: nil, detectLanguage: true, offsetMs: offsetMs)
    }

    private func runTranscription(
        samples: [Float],
        language: UnsafePointer<CChar>?,
        detectLanguage: Bool,
        offsetMs: Int32
    ) throws -> WhisperTranscriptionResult {
        let maxThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = true
        params.print_special = false
        params.token_timestamps = true
        params.translate = false
        params.language = language
        params.detect_language = detectLanguage
        params.n_threads = maxThreads
        params.offset_ms = offsetMs
        params.no_context = false
        params.single_segment = false
        params.max_len = 0

        whisper_reset_timings(context)

        let status = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }

        guard status == 0 else {
            throw WhisperBridgeError.transcriptionFailed
        }

        let langId = whisper_full_lang_id(context)
        let detected = String(cString: whisper_lang_str(langId))

        var words: [WhisperWordResult] = []
        var fullText = ""
        let eot = whisper_token_eot(context)

        let segmentCount = whisper_full_n_segments(context)
        for segmentIndex in 0..<segmentCount {
            fullText += String(cString: whisper_full_get_segment_text(context, segmentIndex))

            let tokenCount = whisper_full_n_tokens(context, segmentIndex)
            for tokenIndex in 0..<tokenCount {
                let tokenData = whisper_full_get_token_data(context, segmentIndex, tokenIndex)
                guard tokenData.id < eot else { continue }

                let tokenText = String(cString: whisper_full_get_token_text(context, segmentIndex, tokenIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tokenText.isEmpty, !tokenText.hasPrefix("[") else { continue }

                words.append(
                    WhisperWordResult(
                        text: tokenText,
                        start: Double(tokenData.t0) / 1000.0 + Double(offsetMs) / 1000.0,
                        end: Double(tokenData.t1) / 1000.0 + Double(offsetMs) / 1000.0,
                        confidence: Double(tokenData.p)
                    )
                )
            }
        }

        return WhisperTranscriptionResult(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            words: words,
            detectedLanguage: detected.isEmpty ? nil : detected
        )
    }

    static func createContext(modelPath: String, useGPU: Bool = true) throws -> WhisperContext {
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperBridgeError.couldNotInitializeContext
        }
        return WhisperContext(context: context)
    }
}
