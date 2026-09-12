import Foundation

/// 播放队列的出队查找：按 id 匹配、无 id 时按路径匹配、被过滤掉的排在前面时跳过、全找不到返回 nil。
struct PlayQueueTests {
    func runAll() throws {
        try testMatchesByIdThenPath()
        try testSkipsQueuedTracksMissingFromList()
        try testReturnsNilWhenNothingPlayable()
    }

    private func track(_ id: Int64?, _ name: String) -> MusicTrack {
        MusicTrack(id: id, audioURL: URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/\(name).mp3"))
    }

    private func testMatchesByIdThenPath() throws {
        let tracks = [track(1, "a"), track(2, "b"), track(nil, "c")]
        // 同 id 但路径变了（文件被改名）仍认得出来。
        let renamed = MusicTrack(id: 2, audioURL: URL(fileURLWithPath: "/tmp/LocalLrcPlayerTests/b-renamed.mp3"))
        let byId = PlayerWindowController.firstPlayable(in: [renamed], tracks: tracks)
        try assertEqual(byId?.trackIndex, 1, "match by id")
        try assertEqual(byId?.queueOffset, 0)

        // 没有 id 时按标准化路径。
        let byPath = PlayerWindowController.firstPlayable(in: [track(nil, "c")], tracks: tracks)
        try assertEqual(byPath?.trackIndex, 2, "match by path")
    }

    private func testSkipsQueuedTracksMissingFromList() throws {
        let tracks = [track(1, "a"), track(2, "b")]
        let queue = [track(9, "filtered-out"), track(2, "b"), track(1, "a")]
        let hit = PlayerWindowController.firstPlayable(in: queue, tracks: tracks)
        try assertEqual(hit?.queueOffset, 1, "first missing entry is skipped, not consumed")
        try assertEqual(hit?.trackIndex, 1)
    }

    private func testReturnsNilWhenNothingPlayable() throws {
        let tracks = [track(1, "a")]
        try assertTrue(PlayerWindowController.firstPlayable(in: [track(7, "x")], tracks: tracks) == nil, "nothing playable")
        try assertTrue(PlayerWindowController.firstPlayable(in: [], tracks: tracks) == nil, "empty queue")
    }
}

/// 顺序模式手动切歌的首尾循环：末首下一首回第一首，首首上一首到末首。
struct TrackNavigationTests {
    func runAll() throws {
        try assertEqual(PlayerWindowController.wrappedIndex(5, count: 5), 0, "next after the last wraps to first")
        try assertEqual(PlayerWindowController.wrappedIndex(-1, count: 5), 4, "previous before the first wraps to last")
        try assertEqual(PlayerWindowController.wrappedIndex(2, count: 5), 2, "in-range index is unchanged")
        try assertEqual(PlayerWindowController.wrappedIndex(1, count: 1), 0, "single track loops on itself")
        try assertEqual(PlayerWindowController.wrappedIndex(3, count: 0), 0, "empty list is safe")
    }
}
