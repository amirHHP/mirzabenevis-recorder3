import Foundation

enum GeminiService {
    enum GeminiError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "کلید API جمینای تنظیم نشده است"
            case .invalidResponse:
                return "پاسخ نامعتبر از سرور جمینای"
            case .apiError(let msg):
                return msg
            }
        }
    }

    static func summarize(
        text: String,
        apiKey: String,
        language: String = "fa"
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "متنی برای خلاصه‌سازی وجود ندارد."
        }

        let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        )!

        let prompt = """
        متن زیر رونوشت یک جلسه است. لطفاً یک خلاصه ساختاریافته و مفید به زبان فارسی بنویس.
        شامل این بخش‌ها باشد:
        - موضوعات اصلی
        - نکات کلیدی
        - تصمیمات (در صورت وجود)
        - اقدامات بعدی (در صورت وجود)

        رونوشت:
        \(text)
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2048
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if http.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.apiError(message)
            }
            throw GeminiError.apiError("HTTP \(http.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let summary = parts.first?["text"] as? String else {
            throw GeminiError.invalidResponse
        }

        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
