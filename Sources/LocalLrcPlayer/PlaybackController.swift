import AVFoundation
import Foundation

final class PlaybackController: NSObject {
    var onPlaybackEnded: (() -> Void)?
    /// 播放项加载失败或中途失败（文件损坏、格式不支持）；以前只会静默无声，主线程回调。
    var onPlaybackFailed: ((String) -> Void)?

    private var player: AVPlayer?
    private weak var observedItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?

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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemFailedToPlayToEnd(_:)),
                name: .AVPlayerItemFailedToPlayToEndTime,
                object: item
            )
            let fileName = url.lastPathComponent
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else {
                    return
                }
                let message = item.error?.localizedDescription ?? "未知错误"
                AppLog.playback.error("播放项加载失败 \(fileName, privacy: .public)：\(message, privacy: .public)")
                DispatchQueue.main.async {
                    self?.onPlaybackFailed?(message)
                }
            }
        }

        AppLog.playback.info("开始播放 \(url.lastPathComponent, privacy: .public)")
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
        statusObservation?.invalidate()
        statusObservation = nil
        if let observedItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: observedItem
            )
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemFailedToPlayToEndTime,
                object: observedItem
            )
        }
    }

    @objc private func playerItemDidEnd() {
        onPlaybackEnded?()
    }

    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        let message = error?.localizedDescription ?? "未知错误"
        AppLog.playback.error("播放中途失败：\(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackFailed?(message)
        }
    }
}
