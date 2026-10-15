import SwiftUI

/// 首页与记录页共用：时间退到左侧，名称、摘要与来源沿同一阅读线排列。
struct RecordRow: View {
    let item: RecordItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var timeWidth = Theme.Journal.timeWidth
    @ScaledMetric(relativeTo: .subheadline) private var summarySize: CGFloat = 14

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 极大字号下不让时间列挤走正文；时间与完整内容仍按顺序朗读。
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    timestamp
                    content
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Journal.columnGap) {
                    timestamp.frame(width: timeWidth, alignment: .leading)
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 17)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var timestamp: some View {
        Text(Format.time(item.date))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.Journal.metadata)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            heading
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: summarySize))
                    .foregroundStyle(Theme.Journal.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metadata
                .font(.caption)
                .foregroundStyle(Theme.Journal.metadata)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: Text {
        let title = item.listHeading
        let name = Text(title.name).font(.body.weight(.medium)).foregroundColor(Theme.Journal.label)
        guard title.itemCount > 1 else { return name }
        return name + Text(" 等 \(title.itemCount) 项")
            .font(.footnote).foregroundColor(Theme.Journal.secondary)
    }

    private var metadata: Text {
        var text = Text(item.kind.displayName)
        if item.hasPhoto {
            text = text + Text(" · ") + Text(Image(systemName: "camera"))
        }
        if let badge = item.badge {
            let source = Text(badge.text)
                .foregroundColor(item.isPendingNote ? Theme.Journal.action : Theme.Journal.metadata)
            text = text + Text(" · ") + source
        }
        if !item.isEditable { text = text + Text(" · 只读") }
        return text
    }

    private var accessibilitySummary: String {
        [Format.time(item.date), item.kind.displayName, item.accessibilityTitle,
         item.subtitle, item.badge?.text, item.hasPhoto ? "附有照片" : nil,
         item.isEditable ? nil : "只读"]
            .compactMap { $0 }.joined(separator: "，")
    }
}

/// 与共享行使用同一缩进；辅助功能大字号改为时间在上时，分隔线同步通栏。
struct RecordRowDivider: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var timeWidth = Theme.Journal.timeWidth

    var body: some View {
        Rectangle()
            .fill(Theme.Journal.line)
            .frame(height: 0.5)
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : timeWidth + Theme.Journal.columnGap)
            .accessibilityHidden(true)
    }
}
