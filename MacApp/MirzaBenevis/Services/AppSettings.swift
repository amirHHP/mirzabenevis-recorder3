import Foundation

enum AppSettings {
    private static let whisperModelKey = "mirza.whisperModelSize"
    private static let audioSourceKey = "mirza.audioSource"
    private static let useGPUKey = "mirza.useGPU"

    static var whisperModelSize: WhisperModelSize {
        get {
            let raw = UserDefaults.standard.string(forKey: whisperModelKey) ?? WhisperModelSize.base.rawValue
            return WhisperModelSize(rawValue: raw) ?? .base
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: whisperModelKey)
        }
    }

    static var audioSource: AudioSourceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: audioSourceKey) ?? AudioSourceMode.systemAudio.rawValue
            return AudioSourceMode(rawValue: raw) ?? .systemAudio
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: audioSourceKey)
        }
    }

    static var useGPU: Bool {
        get {
            if UserDefaults.standard.object(forKey: useGPUKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: useGPUKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useGPUKey)
        }
    }
}
