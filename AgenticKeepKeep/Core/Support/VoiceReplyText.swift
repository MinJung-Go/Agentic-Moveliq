import Foundation

/// Only final conversational text is passed here, never reasoning or tool arguments.
enum VoiceReplyText {
    static func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[*_`~]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
