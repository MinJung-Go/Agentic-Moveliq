import Foundation
import SwiftUI

/// 跨 Tab 的 UI 状态
@MainActor
final class AppState: ObservableObject {

    enum Tab: Hashable {
        case today, records, plan, insights, settings
    }

    @Published var selectedTab: Tab = .today
    @Published var isQuickLogPresented = false
    /// 今日页输入条里已经敲好的内容 —— 打开记录弹窗时带过去，不让用户重打一遍
    @Published var pendingLogText = ""
    /// 首页选中的照片只作为待发送附件，记录弹窗接收后清空。
    @Published var pendingLogPhoto: Data?
    @Published var toast: String?
    @Published var showsCoachDay = false
    @Published var showsMiloChat = false

    /// 显示一条短暂提示
    func showToast(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if self?.toast == message {
                self?.toast = nil
            }
        }
    }
}
