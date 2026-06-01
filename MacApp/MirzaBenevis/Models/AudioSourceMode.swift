import Foundation

enum AudioSourceMode: String, CaseIterable, Identifiable, Codable {
    case microphone
    case systemAudio
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .microphone: return "میکروفون"
        case .systemAudio: return "صدای سیستم"
        case .both: return "هر دو (میک + سیستم)"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .both: return "mic.and.signal.meter.fill"
        }
    }
}
