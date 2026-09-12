import AppKit
import MediaPlayer

/// 系统「正在播放」桥：把播放态喂给 MPNowPlayingInfoCenter，让控制中心、键盘媒体键、
/// AirPods 认得这个 App；远程指令经 MPRemoteCommandCenter 回调给播放控制器。
/// 只做翻译，不持有播放状态 —— 真相在 PlayerWindowController，这里每次全量重发。
final class NowPlayingCenter {
    struct State {
        let title: String
        let artist: String?
        let artwork: NSImage?
        let duration: TimeInterval
        let elapsed: TimeInterval
        var isPlaying: Bool
    }

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var registeredTargets: [(MPRemoteCommand, Any)] = []
    // MPMediaItemArtwork 按封面对象缓存，重发时不用每次重建。
    private weak var cachedArtworkSource: NSImage?
    private var cachedArtwork: MPMediaItemArtwork?

    private(set) var lastPublished: State?
    private var publishedAt = Date.distantPast

    func attach() {
        detach()
        register(commandCenter.playCommand) { [weak self] in self?.onPlay?() }
        register(commandCenter.pauseCommand) { [weak self] in self?.onPause?() }
        register(commandCenter.togglePlayPauseCommand) { [weak self] in self?.onTogglePlayPause?() }
        register(commandCenter.nextTrackCommand) { [weak self] in self?.onNext?() }
        register(commandCenter.previousTrackCommand) { [weak self] in self?.onPrevious?() }

        let seekCommand = commandCenter.changePlaybackPositionCommand
        let seekTarget = seekCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Self.onMain { self?.onSeek?(event.positionTime) }
            return .success
        }
        registeredTargets.append((seekCommand, seekTarget))
        seekCommand.isEnabled = true

        // 关掉跳秒类指令，控制中心才显示上一首/下一首而不是 ±15s。
        for command in [
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.seekForwardCommand,
            commandCenter.seekBackwardCommand
        ] {
            command.isEnabled = false
        }
    }

    func detach() {
        for (command, target) in registeredTargets {
            command.removeTarget(target)
        }
        registeredTargets.removeAll()
    }

    /// 全量重发。切歌、播放/暂停、seek 完成这些确定的转折点直接调。
    func publish(_ state: State) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artist = state.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if state.duration.isFinite, state.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = state.duration
        }
        if let artwork = mediaArtwork(for: state.artwork) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        infoCenter.nowPlayingInfo = info
        // macOS 靠 playbackState 决定谁是「正在播放的 App」，媒体键才会路由过来。
        infoCenter.playbackState = state.isPlaying ? .playing : .paused
        lastPublished = state
        publishedAt = Date()
    }

    /// 0.2s 刷新链上调：只在播放态/时长/曲目信息变了、或系统按速率外推的进度漂了才重发，
    /// 兜住 AVPlayer 时长晚到、play() 后短暂 waiting 这类异步落差，又不每 tick 走一次 XPC。
    func reconcile(_ state: State) {
        guard let last = lastPublished else {
            publish(state)
            return
        }
        let extrapolated = last.elapsed + (last.isPlaying ? Date().timeIntervalSince(publishedAt) : 0)
        let changed = last.isPlaying != state.isPlaying
            || last.title != state.title
            || last.artist != state.artist
            || last.artwork !== state.artwork
            || abs(last.duration - state.duration) > 0.5
            || abs(extrapolated - state.elapsed) > 1.5
        if changed {
            publish(state)
        }
    }

    func clear() {
        guard lastPublished != nil else {
            return
        }
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
        lastPublished = nil
    }

    private func register(_ command: MPRemoteCommand, handler: @escaping () -> Void) {
        let target = command.addTarget { _ in
            Self.onMain(handler)
            return .success
        }
        registeredTargets.append((command, target))
        command.isEnabled = true
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func mediaArtwork(for image: NSImage?) -> MPMediaItemArtwork? {
        guard let image else {
            cachedArtwork = nil
            cachedArtworkSource = nil
            return nil
        }
        if cachedArtworkSource === image, let cachedArtwork {
            return cachedArtwork
        }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        cachedArtworkSource = image
        cachedArtwork = artwork
        return artwork
    }
}
