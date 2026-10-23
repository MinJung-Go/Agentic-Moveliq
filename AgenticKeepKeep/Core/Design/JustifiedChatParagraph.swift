import SwiftUI
import UIKit

/// TextKit supplies paragraph justification; the last line remains natural.
struct JustifiedChatParagraph: UIViewRepresentable {
    let content: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // Read environment so a Dynamic Type change rebuilds attributed fonts.
        _ = dynamicTypeSize
        let base = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString(string: "")
        let parsed = MarkdownText.attributedString(from: content)
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
            if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.traitItalic) }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(descriptor: descriptor, size: base.pointSize), .foregroundColor: UIColor(Theme.Journal.label)
            ]
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributes[.font] = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
                attributes[.backgroundColor] = UIColor(Theme.chip)
            }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 5
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        if !view.attributedText.isEqual(to: result) { view.attributedText = result }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
}
