import Foundation

/// 旧报告长正文的显示分段，不修改持久化原文或 Markdown 结构。
enum ReportTextLayout {
    static func paragraphs(in text: String) -> [String] {
        // 已排版的正文、链接、加粗或代码原样交给 Markdown 渲染器。
        guard text.count > 180, !text.contains("\n"),
              !text.contains(where: { "*_`[]<>".contains($0) }) else { return [text] }
        var result: [String] = []
        var current = ""
        var nesting: [Character] = []
        let closing: [Character: Character] = ["（": "）", "(": ")", "【": "】", "「": "」", "『": "』", "“": "”", "‘": "’"]
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            if let end = closing[character] { nesting.append(end) }
            else if nesting.last == character { nesting.removeLast() }
            // 仅在明确的中文句末分段，不误切小数、单位、英文缩写或括注。
            let endsSentence = "。！？".contains(character)
                || ("”’」』".contains(character) && index > 0 && "。！？".contains(characters[index - 1]))
            if endsSentence, nesting.isEmpty, current.count >= 110 {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            if current.count < 35, !result.isEmpty { result[result.count - 1] += current }
            else { result.append(current) }
        }
        return result.isEmpty ? [text] : result
    }
}
