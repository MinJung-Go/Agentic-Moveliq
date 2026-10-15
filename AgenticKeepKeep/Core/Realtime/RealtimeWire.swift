import Foundation

enum RealtimeWire {
    static func connectionMessage(status: Int?, reason: String?) -> String {
        switch reason {
        case "minute_limit": return "连接尝试过于频繁，请等待一分钟再试。"
        case "daily_limit": return "今天的实时通话次数已用完，请稍后再试或联系管理员调整限额。"
        case "active_call": return "上一通电话仍在结束，请稍等片刻再连接。"
        case "disabled": return "实时通话已被管理员关闭。"
        case "capacity": return "实时服务繁忙，请稍后再试。"
        default:
            if status == 401 { return "登录已失效，请重新登录。" }
            if status == 429 { return "实时通话连接次数受限，请稍后再试。" }
            return "实时连接已中断，请检查网络后重试。"
        }
    }

    /// 传输层断开时补一个可对照的码，便于区分「对端主动关闭」和「连接自己断了」：
    /// 对端给了关闭帧就报关闭码，否则报本地错误码（-999 任务被取消、-1005 连接丢失、-1001 超时、57 套接字未连接）。
    static func transportNote(closeCode: Int, errorCode: Int) -> String {
        if closeCode > 0, closeCode != 1005 { return "（对端关闭 \(closeCode)）" }
        return "（连接错误 \(errorCode)）"
    }

    static func wav(_ pcm: Data, sampleRate: UInt32 = 16000) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(pcm.count + 36)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(sampleRate)
        number(sampleRate * 2); number(UInt16(2)); number(UInt16(16)); text("data")
        number(UInt32(pcm.count)); data.append(pcm)
        return data
    }
    static func mode(_ video: Bool) -> [String: Any] {
        ["type": "session.update", "session": ["beta_fields": ["chat_mode": video ? "video_passive" : "audio"]]]
    }
    static func history(_ turns: [(role: String, text: String)]) -> [[String: Any]] {
        turns.suffix(12).filter { ["user", "assistant"].contains($0.role) && !$0.text.isEmpty }.map {
            ["type": "conversation.item.create", "item": ["type": "message", "role": $0.role,
                "content": [["type": $0.role == "user" ? "input_text" : "text", "text": String(decoding: $0.text.utf8.prefix(3000), as: UTF8.self)]]]]
        }
    }
}
