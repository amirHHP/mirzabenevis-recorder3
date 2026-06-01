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
        }
    }

    private func handleAudioChunk(_ data: Data) {
        guard isActive else { return }
        pcmBuffer.append(data)

        while pcmBuffer.count >= chunkBytes {
            let chunk = pcmBuffer.prefix(chunkBytes)
            pcmBuffer.removeFirst(chunkBytes)
            Task { await transcribeChunk(Data(chunk)) }
        }
    }

    private func transcribeChunk(_ chunk: Data) async {
        guard let result = await whisperEngine.transcribe(pcm16: chunk, language: selectedLanguage),
              !result.words.isEmpty else { return }

        let words = result.words.map { w in
            TranscriptWord(
                text: w.text,
                start: w.start,
                end: w.end,
                confidence: w.confidence
            )
        }
        transcriptStore.appendWords(words)
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

        switch audioSource {
        case .microphone:
            guard await micCapture.requestPermission() else {
                statusMessage = "دسترسی میکروفون رد شد"
                return
            }
        case .systemAudio:
            guard await systemCapture.requestPermission() else {
                statusMessage = "دسترسی Screen Recording رد شد"
                return
            }
        case .both:
            let micOK = await micCapture.requestPermission()
            let sysOK = await systemCapture.requestPermission()
            guard micOK && sysOK else {
                statusMessage = "دسترسی میکروفون یا صدای سیستم رد شد"
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
        } catch {
            statusMessage = "خطا: \(error.localizedDescription)"
            await stopAllCapture()
        }
    }

    func stopRecording() async {
        await stopAllCapture()

        if !pcmBuffer.isEmpty {
            await transcribeChunk(pcmBuffer)
            pcmBuffer.removeAll()
        }

        transcriptStore.stopSession()
        isActive = false
        statusMessage = "ضبط متوقف شد"
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
}
