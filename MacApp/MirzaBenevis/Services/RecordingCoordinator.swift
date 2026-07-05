import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published var statusMessage = "آماده"
    @Published var isActive = false
    @Published var selectedLanguage: String? = "fa"
    @Published var audioSource: AudioSourceMode = AppSettings.audioSource

    let micCapture = AudioCaptureService()
    let systemCapture = SystemAudioCaptureService()
    let whisperEngine = WhisperEngine()
    let transcriptStore: TranscriptStore

    private let audioMixer = AudioMixer()
    private var pcmBuffer = Data()
    private let chunkBytes = 16000 * 2 * 3 // 3 seconds at 16kHz mono int16

    /// Accumulator for saving the full audio as a WAV file
    private var audioRecording = Data()
    private var audioChunkCount = 0

    init(transcriptStore: TranscriptStore) {
        self.transcriptStore = transcriptStore
    }

    func prepareModel() async {
        let modelSize = AppSettings.whisperModelSize
        if !whisperEngine.isModelLoaded {
            statusMessage = "بارگذاری مدل \(modelSize.rawValue)..."
            await whisperEngine.loadModel(size: modelSize)
            statusMessage = whisperEngine.isModelLoaded ? "آماده" : (whisperEngine.loadError ?? "خطا")
        }
    }

    private func wireAudioCallbacks(for mode: AudioSourceMode) {
        micCapture.onAudioData = nil
        systemCapture.onAudioData = nil
        audioMixer.reset()

        switch mode {
        case .microphone:
            micCapture.onAudioData = { [weak self] data in
                Task { @MainActor in self?.handleAudioChunk(data) }
            }
        case .systemAudio:
            systemCapture.onAudioData = { [weak self] data in
                Task { @MainActor in self?.handleAudioChunk(data) }
            }
        case .both:
            micCapture.onAudioData = { [weak self] data in
                self?.audioMixer.appendMic(data)
            }
            systemCapture.onAudioData = { [weak self] data in
                self?.audioMixer.appendSystem(data)
            }
            audioMixer.onMixedData = { [weak self] data in
                Task { @MainActor in self?.handleAudioChunk(data) }
            }
            audioMixer.start()
        }
    }

    private func handleAudioChunk(_ data: Data) {
        guard isActive else { return }

        // Save audio for file export
        audioRecording.append(data)
        audioChunkCount += 1

        pcmBuffer.append(data)

        while pcmBuffer.count >= chunkBytes {
            let chunk = pcmBuffer.prefix(chunkBytes)
            pcmBuffer.removeFirst(chunkBytes)
            Task { await transcribeChunk(Data(chunk)) }
        }
    }

    private func transcribeChunk(_ chunk: Data) async {
        print("[RecordingCoordinator] transcribeChunk called, size: \(chunk.count) bytes")

        guard let result = await whisperEngine.transcribe(pcm16: chunk, language: selectedLanguage) else {
            print("[RecordingCoordinator] whisperEngine.transcribe returned nil")
            return
        }

        print("[RecordingCoordinator] result: text='\(result.text)', words=\(result.words.count), lang=\(result.detectedLanguage ?? "?")")

        // If we have word-level tokens, use them
        if !result.words.isEmpty {
            let words = result.words.map { w in
                TranscriptWord(
                    text: w.text,
                    start: w.start,
                    end: w.end,
                    confidence: w.confidence
                )
            }
            transcriptStore.appendWords(words)
            return
        }

        // Fallback: if token_timestamps didn't produce words, but we got segment text,
        // create a single TranscriptWord from the full text so it still shows up.
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            print("[RecordingCoordinator] Using fallback: full text without word timestamps")
            let word = TranscriptWord(
                text: text,
                start: 0,
                end: Double(chunk.count) / (16000 * 2),
                confidence: 0
            )
            transcriptStore.appendWords([word])
        }
    }

    func startRecording() async {
        await prepareModel()
        guard whisperEngine.isModelLoaded else {
            statusMessage = whisperEngine.loadError ?? "مدل بارگذاری نشد"
            return
        }

        audioSource = AppSettings.audioSource
        wireAudioCallbacks(for: audioSource)
        whisperEngine.resetTiming()
        pcmBuffer.removeAll(keepingCapacity: true)
        audioRecording.removeAll(keepingCapacity: true)
        audioChunkCount = 0

        switch audioSource {
        case .microphone:
            guard await micCapture.requestPermission() else {
                statusMessage = "دسترسی میکروفون رد شد. لطفاً دسترسی به میکروفون را در تنظیمات سیستم فعال کنید."
                return
            }
        case .systemAudio:
            guard await systemCapture.requestPermission() else {
                statusMessage = "دسترسی Screen Recording رد شد. اگر دسترسی داده‌اید، برنامه را ببندید و دوباره باز کنید."
                return
            }
        case .both:
            let micOK = await micCapture.requestPermission()
            let sysOK = await systemCapture.requestPermission()
            if !micOK && !sysOK {
                statusMessage = "دسترسی میکروفون و Screen Recording رد شد."
            } else if !micOK {
                statusMessage = "دسترسی میکروفون رد شد. لطفاً دسترسی به میکروفون را در تنظیمات سیستم فعال کنید."
            } else if !sysOK {
                statusMessage = "دسترسی Screen Recording (صدای سیستم) رد شد. اگر دسترسی داده‌اید، برنامه را ببندید و دوباره باز کنید."
            }
            guard micOK && sysOK else {
                return
            }
        }

        transcriptStore.startNewSession(language: selectedLanguage)

        do {
            switch audioSource {
            case .microphone:
                try micCapture.startCapture()
            case .systemAudio:
                try await systemCapture.startCapture()
            case .both:
                try micCapture.startCapture()
                try await systemCapture.startCapture()
            }
            isActive = true
            statusMessage = statusLabel(for: audioSource)
            print("[RecordingCoordinator] ✅ Recording started, source: \(audioSource.rawValue)")
        } catch {
            statusMessage = "خطا: \(error.localizedDescription)"
            print("[RecordingCoordinator] ❌ Failed to start recording: \(error)")
            await stopAllCapture()
        }
    }

    func stopRecording() async {
        await stopAllCapture()

        if !pcmBuffer.isEmpty {
            await transcribeChunk(pcmBuffer)
            pcmBuffer.removeAll()
        }

        // Save audio file
        let audioPath = saveAudioFile()

        transcriptStore.stopSession(audioFilePath: audioPath)
        isActive = false
        statusMessage = "ضبط متوقف شد"
        print("[RecordingCoordinator] Recording stopped. Audio chunks: \(audioChunkCount), total bytes: \(audioRecording.count)")
    }

    func copyCurrentTranscript() {
        guard let session = transcriptStore.currentSession else { return }
        ClipboardService.copySession(session)
        statusMessage = "در کلیپ‌بورد کپی شد"
    }

    private func stopAllCapture() async {
        micCapture.stopCapture()
        await systemCapture.stopCapture()
        audioMixer.reset()
    }

    private func statusLabel(for mode: AudioSourceMode) -> String {
        switch mode {
        case .microphone: return "ضبط — میکروفون (on-device)"
        case .systemAudio: return "ضبط — صدای سیستم (on-device)"
        case .both: return "ضبط — میک + سیستم (on-device)"
        }
    }

    // MARK: - Audio File Saving

    /// Save accumulated PCM data as a WAV file. Returns the file path if successful.
    private func saveAudioFile() -> String? {
        guard !audioRecording.isEmpty else {
            print("[RecordingCoordinator] No audio data to save")
            return nil
        }

        let dir = audioDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).wav"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            let wavData = Self.createWAVFile(from: audioRecording, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            try wavData.write(to: fileURL, options: .atomic)
            print("[RecordingCoordinator] ✅ Audio saved: \(fileURL.path) (\(wavData.count) bytes)")
            return fileURL.path
        } catch {
            print("[RecordingCoordinator] ❌ Failed to save audio: \(error)")
            return nil
        }
    }

    private var audioDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MirzaBenevis/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Create a WAV file from raw PCM data.
    static func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + pcmData.count)

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })     // sub-chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })      // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)

        return header
    }
}
