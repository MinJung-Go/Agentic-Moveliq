import SwiftUI

/// 渲染 AI 输出的轻量 Markdown。
///
/// 规则是**保留结构，去掉层级**（设计系统 §3）：气泡不是文档，不需要六级标题。
/// 所以标题降级成一行 17/600 的加粗，列表转成真项目符号与序号，`---` 转成分隔线。
///
/// 注意：`Text(字符串变量)` 不会解析 Markdown（只有 `LocalizedStringKey` 会），
/// 所以 `**加粗**` 必须经 `AttributedString` 解析后才会生效 —— 那是**块内**的渲染，
/// 块与块的切分由 `MarkdownFormatter.blocks(from:)` 负责。
struct MarkdownText: View {

    let content: String
    var font: Font = Theme.Font.body
    var foreground: Color = .primary
    var justifiedParagraphs = false
    var blockSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing) {
            ForEach(Array(MarkdownFormatter.blocks(from: content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let text):
            inline(text, font: Theme.Font.headline)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 0) {
                Text("•")
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(width: 17, alignment: .leading)
                inline(text)
            }

        case .numbered(let marker, let text):
            HStack(alignment: .top, spacing: 0) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 17, alignment: .leading)
                inline(text)
            }

        case .divider:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
                .padding(.vertical, Theme.Spacing.xs)

        case .paragraph(let text):
            if justifiedParagraphs {
                JustifiedChatParagraph(content: text)
            } else {
                inline(text)
            }
        }
    }

    private func inline(_ text: String, font overrideFont: Font? = nil) -> some View {
        Text(Self.attributedString(from: text))
            .font(overrideFont ?? font)
            .foregroundStyle(foreground)
            .textSelection(.enabled)
    }

    static func attributedString(from content: String) -> AttributedString {
        let normalized = MarkdownFormatter.normalize(content)

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard let parsed = try? AttributedString(markdown: normalized, options: options) else {
            // 解析失败也要显示原文，不能因为格式问题丢内容
            return AttributedString(normalized)
        }
        return stylingInlineCode(parsed)
    }

    /// 行内代码给等宽 + chip 底，让重量、组次这类数值从正文里跳出来。
    /// 先收集 range 再改 —— 边遍历 runs 边改属性会让 run 结构失效。
    private static func stylingInlineCode(_ source: AttributedString) -> AttributedString {
        let codeRanges = source.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        guard !codeRanges.isEmpty else { return source }

        var result = source
        for range in codeRanges {
            result[range].backgroundColor = Theme.chip
            result[range].font = .system(.footnote, design: .monospaced)
        }
        return result
    }
}

// MARK: - 块

/// 一个 Markdown 块。切分是纯函数，便于单测。
enum MarkdownBlock: Equatable {
    /// `## 今日建议` → 一行 17/600 的加粗，不是真标题
    case heading(String)
    /// `- 深蹲` / `* 卧推` → 真项目符号
    case bullet(String)
    /// `1. 热身` → 序号 + 内容（序号保留原文，避免重排）
    case numbered(marker: String, text: String)
    /// `---` → 0.5pt 分隔线
    case divider
    case paragraph(String)
}

/// Markdown 预处理：把块级语法切成块，行内语法原样留给 `AttributedString`。
/// 纯函数，便于单测。
enum MarkdownFormatter {

    static func blocks(from text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        // 空行是**段落分隔**，不是可忽略的噪音：跨空行的两行不能并成一段。
        // 只有紧挨着的普通行才合并，段内保留换行。
        var previousLineWasBlank = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                previousLineWasBlank = true
                continue
            }

            if isDivider(line) {
                result.append(.divider)
            } else if let (_, rest) = split(line, #"^#{1,6}\s+"#) {
                result.append(.heading(rest))
            } else if let (_, rest) = split(line, #"^[-*+]\s+"#) {
                result.append(.bullet(rest))
            } else if let (marker, rest) = split(line, #"^\d{1,3}[.)]\s+"#) {
                result.append(.numbered(marker: marker, text: rest))
            } else if !previousLineWasBlank, case .paragraph(let existing)? = result.last {
                result[result.count - 1] = .paragraph(existing + "\n" + line)
            } else {
                result.append(.paragraph(line))
            }

            previousLineWasBlank = false
        }

        return result
    }

    /// 按正则切出前缀与剩余内容；不匹配返回 nil
    private static func split(_ line: String, _ pattern: String) -> (prefix: String, rest: String)? {
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return (
            String(line[range]).trimmingCharacters(in: .whitespaces),
            String(line[range.upperBound...])
        )
    }

    private static func isDivider(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    /// 旧的逐行规范化：把块级标记降级成可读文本。
    /// 块级渲染走 `blocks(from:)` 之后，这里只用来处理**单块内部**的文本。
    static func normalize(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(normalizeLine)
            .joined(separator: "\n")
    }

    private static func normalizeLine(_ line: Substring) -> String {
        var content = String(line)

        // 「### 标题」→「标题」：行内渲染不支持块级标题
        if let range = content.range(of: #"^\s*#{1,6}\s+"#, options: .regularExpression) {
            content.removeSubrange(range)
        }

        // 无序列表统一成「• 」：行内渲染不会把 "- " 变成项目符号
        if let range = content.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) {
            let indent = String(content.prefix { $0 == " " || $0 == "\t" })
            content = indent + "• " + String(content[range.upperBound...])
        }

        return content
    }
}
