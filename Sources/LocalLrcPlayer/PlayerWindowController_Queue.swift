import AppKit

/// 播放队列（第一期）：内存里的「接下来播放」列表，不持久化，退出即空。
/// 「下一首播放」插队首、「稍后播放」追加队尾，与 Apple Music 语义一致。
/// playNext 与顺序/随机模式的自动播完优先出队；单曲循环自动播完仍循环本曲，只有手动「下一首」才走队列。
/// 出队时按 id 再按路径在当前列表里找；找不到的（被搜索过滤、已删除）先跳过留在队列里，等列表回来再播。
extension PlayerWindowController {
    enum QueueInsertion {
        case next
        case later
    }

    func enqueue(trackAt row: Int, insertion: QueueInsertion) {
        guard tracks.indices.contains(row) else {
            return
        }
        let track = tracks[row]
        // 重复入队就挪位置，不留两份。
        playQueue.removeAll { Self.isSameTrack($0, track) }
        switch insertion {
        case .next:
            playQueue.insert(track, at: 0)
        case .later:
            playQueue.append(track)
        }
        syncQueueBadges()

        let position = playQueue.firstIndex { Self.isSameTrack($0, track) }.map { $0 + 1 } ?? 1
        let verb = insertion == .next ? "下一首播放" : "稍后播放"
        showTransientStatus("\(verb)：\(track.displayName)（队列第 \(position) 位，共 \(playQueue.count) 首）")
    }

    func clearPlayQueue() {
        guard !playQueue.isEmpty else {
            showTransientStatus("播放队列是空的")
            return
        }
        playQueue.removeAll()
        syncQueueBadges()
        showTransientStatus("已清空播放队列")
    }

    /// 取队列里第一首当前列表能找到的歌并出队；都找不到返回 nil，队列原样保留。
    func dequeueNextPlayableIndex() -> Int? {
        guard let hit = Self.firstPlayable(in: playQueue, tracks: tracks) else {
            return nil
        }
        playQueue.remove(at: hit.queueOffset)
        syncQueueBadges()
        return hit.trackIndex
    }

    /// 纯函数便于测试：队列里第一首能在 tracks 里找到的歌，返回它在队列和列表中的位置。
    static func firstPlayable(in queue: [MusicTrack], tracks: [MusicTrack]) -> (queueOffset: Int, trackIndex: Int)? {
        for (offset, queued) in queue.enumerated() {
            if let index = tracks.firstIndex(where: { isSameTrack($0, queued) }) {
                return (offset, index)
            }
        }
        return nil
    }

    /// 列表行副标题末尾的「队列 N」徽标。
    func syncQueueBadges() {
        var positions: [String: Int] = [:]
        for (offset, track) in playQueue.enumerated() {
            positions[track.audioURL.standardizedFileURL.path] = offset + 1
        }
        trackListDataSource.queuedPositions = positions
    }

    static func isSameTrack(_ lhs: MusicTrack, _ rhs: MusicTrack) -> Bool {
        if let left = lhs.id, let right = rhs.id {
            return left == right
        }
        return TrackListDataSource.matchesTrackURL(lhs.audioURL, rhs.audioURL)
    }

    // 播放菜单入口：作用于列表选中行（用户点选优先）。

    @objc func playSelectedNextFromMenu() {
        enqueueSelected(.next)
    }

    @objc func playSelectedLaterFromMenu() {
        enqueueSelected(.later)
    }

    @objc func clearPlayQueueFromMenu() {
        clearPlayQueue()
    }

    private func enqueueSelected(_ insertion: QueueInsertion) {
        guard let row = trackListDataSource.userSelectedTrackIndex ?? trackListDataSource.indexOfSelectedTrack() else {
            showTransientStatus("请先在列表里选中一首歌")
            return
        }
        enqueue(trackAt: row, insertion: insertion)
    }
}
