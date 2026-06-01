import Foundation

/// Buffers mic and system audio streams and emits mixed PCM when both have data.
final class AudioMixer {
    var onMixedData: ((Data) -> Void)?

    private var micBuffer = Data()
    private var systemBuffer = Data()
    private let lock = NSLock()
    private let emitChunkSize = 3200 // ~100ms at 16kHz mono int16

    func appendMic(_ data: Data) {
        lock.lock()
        micBuffer.append(data)
        lock.unlock()
        flushIfReady()
    }

    func appendSystem(_ data: Data) {
        lock.lock()
        systemBuffer.append(data)
        lock.unlock()
        flushIfReady()
    }

    func reset() {
        lock.lock()
        micBuffer.removeAll()
        systemBuffer.removeAll()
        lock.unlock()
    }

    private func flushIfReady() {
        lock.lock()
        defer { lock.unlock() }

        while micBuffer.count >= emitChunkSize && systemBuffer.count >= emitChunkSize {
            let micChunk = micBuffer.prefix(emitChunkSize)
            let sysChunk = systemBuffer.prefix(emitChunkSize)
            micBuffer.removeFirst(emitChunkSize)
            systemBuffer.removeFirst(emitChunkSize)

            let mixed = PCMConverter.mixPCM16(Data(micChunk), Data(sysChunk))
            onMixedData?(mixed)
        }
    }
}
