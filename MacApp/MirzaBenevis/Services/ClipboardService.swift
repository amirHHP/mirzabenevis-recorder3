import AppKit
import Foundation

enum ClipboardService {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copySession(_ session: TranscriptionSession) {
        var output = session.fullText
        if let summary = session.summary, !summary.isEmpty {
            output += "\n\n--- خلاصه ---\n\n\(summary)"
        }
        copy(output)
    }
}
