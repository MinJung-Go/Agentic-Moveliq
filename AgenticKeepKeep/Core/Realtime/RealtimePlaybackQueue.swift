import Foundation

/// 通话下行音频的积压策略。
///
/// 长回复时上游会一次推很多音频；排不上队的块过去直接抛错，整通电话因此断开。
/// 现在只做纯计算：按固定长度切块，积压超过上限的新块丢掉并计入 `droppedFrames`，
/// 由调用方决定要不要提示一次。正常播放（上游略快于实时）远达不到上限。
///
/// 不碰 AVFoundation，便于单测。
struct RealtimePlaybackQueue {

    /// 单块上限：24kHz 输出的一秒
    static let chunkFrames = 24_000
    /// 允许的最大积压：20 秒。只作兜底，不用来控制正常延迟。
    static let maxQueuedFrames = 480_000

    private(set) var queuedFrames = 0
    private(set) var droppedFrames = 0

    /// 收到一段音频：返回可以排队的块长，首尾相接、从这段的开头算起。
    /// 积压满了以后剩下的部分整块丢弃并计入 `droppedFrames`，调用方按返回顺序切样本即可。
    mutating func admit(frames: Int) -> [Int] {
        guard frames > 0 else { return [] }
        var admitted: [Int] = []
        var offset = 0
        while offset < frames {
            let size = min(Self.chunkFrames, frames - offset)
            if queuedFrames + size <= Self.maxQueuedFrames {
                queuedFrames += size
                admitted.append(size)
            } else {
                droppedFrames += size
            }
            offset += size
        }
        return admitted
    }

    /// 块播放结束，或排队失败时回滚预留
    mutating func played(frames: Int) {
        queuedFrames = max(0, queuedFrames - frames)
    }

    mutating func reset() { queuedFrames = 0; droppedFrames = 0 }
}
