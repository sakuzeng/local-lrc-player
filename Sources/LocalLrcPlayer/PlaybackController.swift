import AVFoundation
import Foundation

final class PlaybackController: NSObject {
    var onPlaybackEnded: (() -> Void)?

    private var player: AVPlayer?
    private weak var observedItem: AVPlayerItem?

    /// 0...1；player 每次播放都会重建，所以这里持有并在 play 时套用。
    var volume: Float = 1 {
        didSet {
            player?.volume = volume
        }
    }

    var isPlaying: Bool {
        player?.timeControlStatus == .playing
    }

    var hasLoadedItem: Bool {
        player?.currentItem != nil
    }

    deinit {
        removeEndObserver()
    }

    func play(url: URL) {
        removeEndObserver()

        let player = AVPlayer(url: url)
        player.volume = volume
        self.player = player
        observedItem = player.currentItem

        if let item = player.currentItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )
        }

        player.play()
    }

    func resume() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        pause()
        removeEndObserver()
        player = nil
        observedItem = nil
    }

    func resetToStart() {
        player?.pause()
        player?.seek(to: .zero)
    }

    func seek(to seconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            DispatchQueue.main.async {
                completion?(finished)
            }
        }
    }

    func currentTime() -> TimeInterval? {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else {
            return nil
        }
        return seconds
    }

    func duration() -> TimeInterval? {
        guard let seconds = player?.currentItem?.duration.seconds, seconds.isFinite else {
            return nil
        }
        return seconds
    }

    private func removeEndObserver() {
        if let observedItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: observedItem
            )
        }
    }

    @objc private func playerItemDidEnd() {
        onPlaybackEnded?()
    }
}
