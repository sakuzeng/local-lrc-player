import AppKit

/// 播放态的对外出口：快照 → NowPlayingModel（菜单栏卡片等消费者订阅）；
/// 系统「正在播放」接线：远程指令 → 既有播放入口；播放态 → NowPlayingCenter。
extension PlayerWindowController {
    /// 消费者通过 model.commands 控制播放，这里把命令接到既有入口。
    func bindNowPlayingModel() {
        nowPlayingModel.commands = NowPlayingModel.Commands(
            togglePlayPause: { [weak self] in self?.togglePlayback() },
            next: { [weak self] in self?.playNext() },
            previous: { [weak self] in self?.playPrevious() },
            cycleMode: { [weak self] in self?.cyclePlaybackMode() },
            seek: { [weak self] fraction in self?.seekFromRemote(toFraction: fraction) },
            setVolume: { [weak self] value in self?.setVolumeFromRemote(value) }
        )
    }

    /// 媒体键的播放/暂停只作用于当前曲目，不像空格（togglePlayback）那样会跳去列表选中行。
    func bindNowPlayingCenter() {
        nowPlayingCenter.onPlay = { [weak self] in
            self?.resumeCurrentTrack()
        }
        nowPlayingCenter.onPause = { [weak self] in
            self?.pauseCurrentTrack()
        }
        nowPlayingCenter.onTogglePlayPause = { [weak self] in
            guard let self else {
                return
            }
            if playbackController.isPlaying {
                pauseCurrentTrack()
            } else {
                resumeCurrentTrack()
            }
        }
        nowPlayingCenter.onNext = { [weak self] in
            self?.playNext()
        }
        nowPlayingCenter.onPrevious = { [weak self] in
            self?.playPrevious()
        }
        nowPlayingCenter.onSeek = { [weak self] seconds in
            guard let self, let duration = resolvedPlaybackDuration(), duration > 0 else {
                return
            }
            seekFromRemote(toFraction: seconds / duration)
        }
        nowPlayingCenter.attach()
    }

    /// 播放态的唯一出口：切歌、播放/暂停、seek 完成后调；没有曲目就清掉系统卡片。
    /// play() 之后 AVPlayer 会短暂处于 waiting，此时 isPlaying 还是 false，调用方可显式指定。
    func publishNowPlayingState(isPlaying: Bool? = nil) {
        nowPlayingModel.publish(currentNowPlayingSnapshot())
        guard var state = currentNowPlayingState() else {
            nowPlayingCenter.clear()
            return
        }
        guard !isWaitingForArtwork(state) else {
            return
        }
        if let isPlaying {
            state.isPlaying = isPlaying
        }
        nowPlayingCenter.publish(state)
    }

    /// 挂在 0.2s tick 上的对账，只在真的变了才重发；封面宽限到期后也由这里补发。
    func reconcileNowPlayingState() {
        nowPlayingModel.publish(currentNowPlayingSnapshot())
        guard let state = currentNowPlayingState() else {
            nowPlayingCenter.clear()
            return
        }
        guard !isWaitingForArtwork(state) else {
            return
        }
        nowPlayingCenter.reconcile(state)
    }

    /// 切歌后封面还在异步读时先不发：系统卡片多停留一拍在上一首，好过闪一下 App 图标。
    /// 封面一到或宽限到期即放行，并清掉宽限。
    private func isWaitingForArtwork(_ state: NowPlayingCenter.State) -> Bool {
        guard let until = nowPlayingArtworkGraceUntil else {
            return false
        }
        if state.artwork == nil, until > Date() {
            return true
        }
        nowPlayingArtworkGraceUntil = nil
        return false
    }

    private func currentNowPlayingState() -> NowPlayingCenter.State? {
        guard playingTrackId != nil, let rawTitle = nowPlayingTitle, !rawTitle.isEmpty else {
            return nil
        }
        // ID3 常缺歌手、标题多是「歌手 - 歌名」，与列表和悬停卡片一样拆开给系统。
        var title = rawTitle
        var artist = nowPlayingArtist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if artist.isEmpty, let parsed = MusicTrack.parseArtistTitle(rawTitle) {
            title = parsed.title
            artist = parsed.artist
        }
        return NowPlayingCenter.State(
            title: title,
            artist: artist.isEmpty ? nil : artist,
            artwork: nowPlayingArtwork,
            duration: resolvedPlaybackDuration() ?? 0,
            elapsed: playbackController.currentTime() ?? restoredPlaybackPosition ?? 0,
            isPlaying: playbackController.isPlaying
        )
    }
}
