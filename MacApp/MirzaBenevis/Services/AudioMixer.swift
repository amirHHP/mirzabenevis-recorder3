import Foundation

/// Buffers mic and system audio streams and emits mixed PCM when both have data.
/// Uses a timer-based flush to ensure audio still flows even when one source is silent.
final class AudioMixer {
    var onMixedData: ((Data) -> Void)?

    private var micBuffer = Data()
    private var systemBuffer = Data()
    private let lock = NSLock()
    private let emitChunkSize = 3200 // ~100ms at 16kHz mono int16
    private var flushTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.mirzabenevis.mixer-timer")

    /// Start the periodic flush timer. Must be called before audio begins.
    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        // 300ms grace period gives both sources time to buffer, then flushes whatever is available
        timer.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.timerFlush()
        }
        timer.resume()
        flushTimer = timer
    }

    /// Stop the timer and clear buffers.
    func stop() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    func appendMic(_ data: Data) {
        lock.lock()
        micBuffer.append(data)
        lock.unlock()
        mixIfBothReady()
    }

    func appendSystem(_ data: Data) {
        lock.lock()
        systemBuffer.append(data)
        lock.unlock()
        mixIfBothReady()
    }

    func reset() {
        stop()
        lock.lock()
        micBuffer.removeAll()
        systemBuffer.removeAll()
        lock.unlock()
    }

    /// Mix and emit when both sources have enough data (lowest latency path).
    private func mixIfBothReady() {
        lock.lock()
        defer { lock.unlock() }

        while micBuffer.count >= emitChunkSize && systemBuffer.count >= emitChunkSize {
            let micChunk = Data(micBuffer.prefix(emitChunkSize))
            let sysChunk = Data(systemBuffer.prefix(emitChunkSize))
            micBuffer.removeFirst(emitChunkSize)
            systemBuffer.removeFirst(emitChunkSize)

            let mixed = PCMConverter.mixPCM16(micChunk, sysChunk)
            onMixedData?(mixed)
        }
    }

    /// Timer-based flush: if only one source has data after the grace period,
    /// pass it through instead of waiting forever for the other source.
    private func timerFlush() {
        lock.lock()
        defer { lock.unlock() }

        // First, mix anything where both sources have data
        while micBuffer.count >= emitChunkSize && systemBuffer.count >= emitChunkSize {
            let micChunk = Data(micBuffer.prefix(emitChunkSize))
            let sysChunk = Data(systemBuffer.prefix(emitChunkSize))
            micBuffer.removeFirst(emitChunkSize)
            systemBuffer.removeFirst(emitChunkSize)
            onMixedData?(PCMConverter.mixPCM16(micChunk, sysChunk))
        }

        // Then, flush any remaining mic data (system might be silent)
        while micBuffer.count >= emitChunkSize {
            let chunk = Data(micBuffer.prefix(emitChunkSize))
            micBuffer.removeFirst(emitChunkSize)
            onMixedData?(chunk)
        }

        // Flush any remaining system data (mic might be muted)
        while systemBuffer.count >= emitChunkSize {
            let chunk = Data(systemBuffer.prefix(emitChunkSize))
            systemBuffer.removeFirst(emitChunkSize)
            onMixedData?(chunk)
        }
    }
}
