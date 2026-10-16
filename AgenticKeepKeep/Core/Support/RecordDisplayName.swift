import Foundation

/// 只生成列表展示名；完整名称与说明仍来自原记录，不改写数据。
enum RecordDisplayName {
    struct Presentation: Equatable {
        let name: String
        let itemCount: Int

        var text: String {
            itemCount > 1 ? "\(name) 等 \(itemCount) 项" : name
        }
    }

    static func meal(names: [String], fallback: String) -> String {
        mealPresentation(names: names, fallback: fallback).text
    }

    static func mealPresentation(names: [String], fallback: String) -> Presentation {
        guard !names.isEmpty, names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return Presentation(name: fallback, itemCount: 1)
        }
        return Presentation(name: compactFoodName(names[0]), itemCount: names.count)
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
