import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCaptureService: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published var permissionGranted = false

    var onAudioData: ((Data) -> Void)?

    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.mirzabenevis.system-audio", qos: .userInteractive)

    func requestPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            permissionGranted = true
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        permissionGranted = granted
        return granted
    }

    func startCapture() async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(PCMConverter.targetSampleRate)
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()

        self.stream = stream
        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing else { return }
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
    }

    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "نمایشگری برای ضبط صدای سیستم پیدا نشد"
            }
        }
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let pcmData = PCMConverter.toPCM16Mono(sampleBuffer) else { return }

        Task { @MainActor in
            self.onAudioData?(pcmData)
        }
    }
}
