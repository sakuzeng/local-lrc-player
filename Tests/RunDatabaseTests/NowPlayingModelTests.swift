import Foundation

/// NowPlayingModel：发布即通知所有订阅者并保留最新快照；凭证释放或 cancel 后不再收到。
struct NowPlayingModelTests {
    func runAll() throws {
        try testPublishNotifiesObserversAndKeepsSnapshot()
        try testCancelledObservationStopsReceiving()
        try testDefaultCommandsAreSafeNoops()
    }

    private func snapshot(_ title: String) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title, artist: nil, artwork: nil, lyricLine: nil,
            currentTime: 0, duration: 0, isPlaying: false, mode: .sequential, volume: 1
        )
    }

    private func testPublishNotifiesObserversAndKeepsSnapshot() throws {
        let model = NowPlayingModel()
        var received: [String?] = []
        let observation = model.observe { received.append($0?.title) }
        defer { observation.cancel() }

        model.publish(snapshot("A"))
        model.publish(nil)
        try assertEqual(received.map { $0 ?? "-" }, ["A", "-"])
        try assertTrue(model.snapshot == nil, "latest snapshot is kept")
        model.publish(snapshot("B"))
        try assertEqual(model.snapshot?.title, "B")
    }

    private func testCancelledObservationStopsReceiving() throws {
        let model = NowPlayingModel()
        var count = 0
        var observation: NowPlayingModel.Observation? = model.observe { _ in count += 1 }
        model.publish(snapshot("A"))
        observation?.cancel()
        model.publish(snapshot("B"))
        observation = nil
        model.publish(snapshot("C"))
        try assertEqual(count, 1, "no notifications after cancel or release")
    }

    private func testDefaultCommandsAreSafeNoops() throws {
        let model = NowPlayingModel()
        model.commands.togglePlayPause()
        model.commands.next()
        model.commands.previous()
        model.commands.cycleMode()
        model.commands.seek(0.5)
        model.commands.setVolume(0.2)
        try assertTrue(true, "default commands do nothing and do not crash")
    }
}
