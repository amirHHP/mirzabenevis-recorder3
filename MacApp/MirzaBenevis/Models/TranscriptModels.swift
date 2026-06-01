import Foundation

struct TranscriptWord: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        start: Double,
        end: Double,
        confidence: Double = 0,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.receivedAt = receivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt) ?? Date()
    }
}

struct TranscriptionSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var words: [TranscriptWord]
    var summary: String?
    var createdAt: Date
    var updatedAt: Date
    var language: String?

    init(
        id: UUID = UUID(),
        title: String = "جلسه جدید",
        words: [TranscriptWord] = [],
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        language: String? = nil
    ) {
        self.id = id
        self.title = title
        self.words = words
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.language = language
    }

    var fullText: String {
        words.map(\.text).joined(separator: " ")
    }

    var wordCount: Int { words.count }
}

struct TranscriptionMessage: Codable {
    let type: String
    let words: [WordPayload]?
    let text: String?
    let language: String?
    let message: String?

    struct WordPayload: Codable {
        let text: String
        let start: Double
        let end: Double
        let confidence: Double?
    }
}
