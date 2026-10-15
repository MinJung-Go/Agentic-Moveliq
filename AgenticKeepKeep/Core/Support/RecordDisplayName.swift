import Foundation

/// 只生成列表展示名；完整名称与说明仍来自原记录，不改写数据。
enum RecordDisplayName {
    static func meal(names: [String], fallback: String) -> String {
        guard !names.isEmpty, names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return fallback
        }
        let title = names.prefix(2).map(compactFoodName).joined(separator: "、")
        return names.count > 1 ? "\(title) 等 \(names.count) 项" : title
    }

    static func compactFoodName(_ name: String) -> String {
        // 只收起末尾完整的长括注，短限定词（无糖、熟重等）和不完整括号原样保留。
        let pairs: [(Character, Character)] = [("（", "）"), ("(", ")")]
        for (open, close) in pairs {
            guard name.last == close, let start = name.firstIndex(of: open) else { continue }
            let base = name[..<start].trimmingCharacters(in: .whitespaces)
            let annotation = name[name.index(after: start)..<name.index(before: name.endIndex)]
            guard !base.isEmpty, annotation.count >= 12,
                  !annotation.contains(where: { "（）()".contains($0) }) else { continue }
            return base
        }
        return name
    }
}
