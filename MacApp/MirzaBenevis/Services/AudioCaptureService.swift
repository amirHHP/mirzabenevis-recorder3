import AVFoundation
import Foundation

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published var permissionGranted = false

    var onAudioData: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            permissionGranted = granted
            return granted
        default:
            permissionGranted = false
            return false
        }
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw CaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw CaptureError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: outputFormat,
                      frameCapacity: frameCount
                  ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            guard error == nil,
                  let channelData = convertedBuffer.int16ChannelData else { return }

            let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData[0], count: byteCount)

            Task { @MainActor in
                self.onAudioData?(data)
            }
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    enum CaptureError: LocalizedError {
        case formatError
        case converterError

        var errorDescription: String? {
            switch self {
            case .formatError: return "Could not create audio format"
            case .converterError: return "Could not create audio converter"
            }
        }
    }
}
