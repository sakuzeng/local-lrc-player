import AppKit

extension PlayerWindowController {
    func restoreLastSelection(at index: Int, position: TimeInterval) {
        guard tracks.indices.contains(index) else {
            return
        }

        playbackController.stop()
        let track = tracks[index]
        playingTrackURL = track.audioURL
        currentTrackIndex = index
        trackListDataSource.playingTrackURL = playingTrackURL
        trackListDataSource.selectRow(index, scrollToVisible: true, isUserInitiated: false)
        layout.tableView.reloadData()
        restoredPlaybackPosition = max(position, 0)
        loadLyrics(for: track, highlightAt: restoredPlaybackPosition)
        DispatchQueue.main.async { [weak self] in
            self?.syncPlaybackPreview(at: position, updateLyrics: false)
        }

        layout.setPlayButtonShowsPause(false)
        layout.statusLabel.stringValue = "已恢复上次选中的歌曲：\(track.displayName)"
        updateControlState()
    }

    func playTrack(
        at index: Int,
        resumePosition: TimeInterval? = nil,
        startFromSavedPosition: Bool = false
    ) {
        guard tracks.indices.contains(index) else {
            return
        }

        let track = tracks[index]
        playingTrackURL = track.audioURL
        currentTrackIndex = index
        trackListDataSource.playingTrackURL = playingTrackURL
        trackListDataSource.selectRow(index, scrollToVisible: true, isUserInitiated: false)
        layout.tableView.reloadData()
        let playbackURL: URL
        do {
            layout.statusLabel.stringValue = track.audioURL.pathExtension.lowercased() == "flac"
                ? "正在准备 FLAC 播放缓存：\(track.displayName)"
                : "正在播放：\(track.displayName)"
            playbackURL = try PlaybackAssetResolver.playbackURL(for: track)
        } catch {
            layout.statusLabel.stringValue = error.localizedDescription
            return
        }

        playbackController.play(url: playbackURL)

        let highlightAt = resumePosition ?? restoredPlaybackPosition ?? currentSliderPreviewTime()
        loadLyrics(for: track, highlightAt: highlightAt > 0 ? highlightAt : nil)

        layout.statusLabel.stringValue = "正在播放：\(track.displayName)"
        layout.setPlayButtonShowsPause(true)
        updateControlState()

        if let trackId = track.id {
            let positionForHistory = resumePosition ?? restoredPlaybackPosition ?? highlightAt
            try? playHistoryRepository.recordPlayback(
                trackId: trackId,
                position: positionForHistory
            )
            persistPlaybackState(
                trackId: trackId,
                position: positionForHistory
            )
        }

        let seekTarget: TimeInterval?
        if let resumePosition {
            seekTarget = resumePosition
            restoredPlaybackPosition = nil
        } else if startFromSavedPosition, let saved = restoredPlaybackPosition {
            seekTarget = saved
            restoredPlaybackPosition = nil
        } else {
            seekTarget = nil
            restoredPlaybackPosition = nil
        }

        if let seekTarget, seekTarget > 0 {
            syncPlaybackPreview(at: seekTarget)
            playbackController.seek(to: seekTarget) { [weak self] _ in
                self?.syncUIWithPlayback()
            }
        } else if highlightAt > 0 {
            syncPlaybackPreview(at: highlightAt)
        }
    }

    func loadLyrics(for track: MusicTrack, highlightAt time: TimeInterval? = nil) {
        menuBarLyricsController?.setTrackTitle(track.displayName)

        guard let lyricURL = track.lyricURL else {
            lrcLines = []
            layout.lyricsView.showPlaceholder("未找到同名 LRC 歌词")
            syncMenuBarLyrics()
            return
        }

        do {
            let contents = try String(contentsOf: lyricURL, encoding: .utf8)
            renderLyrics(contents, highlightAt: time)
        } catch {
            do {
                let contents = try String(contentsOf: lyricURL, encoding: .utf16)
                renderLyrics(contents, highlightAt: time)
            } catch {
                lrcLines = []
                layout.lyricsView.showPlaceholder("歌词读取失败")
                syncMenuBarLyrics()
            }
        }
    }

    func renderLyrics(_ contents: String, highlightAt time: TimeInterval? = nil) {
        lrcLines = LrcParser.parse(contents)
        if lrcLines.isEmpty {
            layout.lyricsView.showPlaceholder("歌词文件为空或格式无法识别")
        } else {
            layout.lyricsView.render(lrcLines, scrollToTop: time == nil)
            if let time, time >= 0 {
                layout.lyricsView.updateWhenReady(for: time, forceScroll: true)
            }
        }
        syncMenuBarLyrics(at: time)
    }

    func syncPlaybackPreview(at time: TimeInterval, updateLyrics: Bool = true) {
        guard time.isFinite, time >= 0 else {
            return
        }

        if let duration = resolvedPlaybackDuration(), duration > 0 {
            let clamped = min(time, duration)
            isApplyingProgrammaticSliderUpdate = true
            defer { isApplyingProgrammaticSliderUpdate = false }
            layout.progressSlider.doubleValue = min(max(clamped / duration, 0), 1)
            updateTimeLabel(current: clamped, duration: duration)
            if updateLyrics {
                layout.lyricsView.updateWhenReady(for: clamped, forceScroll: true)
            }
            syncMenuBarLyrics(at: clamped)
        } else if updateLyrics {
            updateTimeLabel(current: time, duration: 0)
            layout.lyricsView.updateWhenReady(for: time, forceScroll: true)
            syncMenuBarLyrics(at: time)
        } else {
            updateTimeLabel(current: time, duration: 0)
            syncMenuBarLyrics(at: time)
        }
    }

    func currentSliderPreviewTime() -> TimeInterval {
        guard let duration = resolvedPlaybackDuration(), duration > 0 else {
            return 0
        }
        return min(max(duration * layout.progressSlider.doubleValue, 0), duration)
    }

    func syncMenuBarLyrics(at time: TimeInterval? = nil) {
        guard let menuBarLyricsController else {
            return
        }

        let currentTime = time ?? playbackController.currentTime() ?? 0
        let isPlaying = playbackController.isPlaying

        if lrcLines.isEmpty {
            if let index = currentTrackIndex, tracks.indices.contains(index) {
                let track = tracks[index]
                if track.lyricURL == nil {
                    menuBarLyricsController.showPlaceholder("♪ \(track.displayName)")
                } else {
                    menuBarLyricsController.showPlaceholder("暂无歌词")
                }
            } else {
                menuBarLyricsController.showPlaceholder("请选择歌曲")
            }
            return
        }

        menuBarLyricsController.update(lines: lrcLines, time: currentTime, isPlaying: isPlaying)
    }

    @objc func togglePlayback() {
        let playing = currentTrackIndex ?? trackListDataSource.indexOfPlayingTrack()
        if let userSelected = trackListDataSource.userSelectedTrackIndex,
           let playing,
           userSelected != playing {
            resetShuffleHistory(for: userSelected)
            playTrack(at: userSelected)
            return
        }

        guard let playing, tracks.indices.contains(playing) else {
            if let userSelected = trackListDataSource.userSelectedTrackIndex {
                playTrack(at: userSelected)
            } else if let selected = trackListDataSource.indexOfSelectedTrack() {
                playTrack(at: selected)
            } else if !tracks.isEmpty {
                playTrack(at: 0)
            }
            return
        }

        if playbackController.isPlaying {
            playbackController.pause()
            layout.setPlayButtonShowsPause(false)
            layout.statusLabel.stringValue = "已暂停"
            saveCurrentPlaybackState()
            syncMenuBarLyrics()
        } else if playbackController.hasLoadedItem {
            playbackController.resume()
            layout.setPlayButtonShowsPause(true)
            layout.statusLabel.stringValue = "正在播放：\(tracks[playing].displayName)"
        } else {
            playTrack(at: playing, startFromSavedPosition: true)
        }
    }

    @objc func playPrevious() {
        guard !tracks.isEmpty else {
            return
        }

        let current = currentTrackIndex ?? trackListDataSource.indexOfSelectedTrack() ?? 0
        switch playbackMode {
        case .sequential, .repeatOne:
            playTrack(at: max(current - 1, 0))
        case .shuffle:
            if shuffleHistory.count > 1 {
                shuffleHistory.removeLast()
                if let previous = shuffleHistory.last {
                    playTrack(at: previous)
                    return
                }
            }
            playTrack(at: max(current - 1, 0))
        }
    }

    @objc func playNext() {
        guard !tracks.isEmpty else {
            return
        }

        let current = currentTrackIndex ?? trackListDataSource.indexOfSelectedTrack() ?? 0
        switch playbackMode {
        case .sequential, .repeatOne:
            playTrack(at: min(current + 1, tracks.count - 1))
        case .shuffle:
            appendShuffleHistory(current)
            playTrack(at: randomTrackIndex(excluding: current))
        }
    }

    func playerItemDidEnd() {
        guard let currentTrackIndex else {
            return
        }

        switch playbackMode {
        case .sequential:
            let nextIndex = currentTrackIndex + 1
            if tracks.indices.contains(nextIndex) {
                playTrack(at: nextIndex)
            } else {
                playTrack(at: 0)
            }
        case .repeatOne:
            playTrack(at: currentTrackIndex, resumePosition: 0)
        case .shuffle:
            appendShuffleHistory(currentTrackIndex)
            playTrack(at: randomTrackIndex(excluding: currentTrackIndex))
        }
    }

    private func appendShuffleHistory(_ index: Int) {
        guard playbackMode == .shuffle, tracks.indices.contains(index) else {
            return
        }
        if shuffleHistory.last != index {
            shuffleHistory.append(index)
        }
    }

    private func randomTrackIndex(excluding excluded: Int?) -> Int {
        guard tracks.count > 1, let excluded, tracks.indices.contains(excluded) else {
            return excluded ?? 0
        }
        let candidates = tracks.indices.filter { $0 != excluded }
        return candidates.randomElement() ?? excluded
    }

    @objc func progressChanged() {
        guard !isApplyingProgrammaticSliderUpdate else {
            return
        }
        guard let duration = resolvedPlaybackDuration(), duration > 0 else {
            return
        }

        let targetTime = min(max(duration * layout.progressSlider.doubleValue, 0), duration)
        applyPlaybackDisplayTime(targetTime, duration: duration, forceScroll: true)
    }

    func beginProgressTracking() {
        isSeekingWithSlider = true
        wasPlayingBeforeSliderTracking = playbackController.isPlaying
        if wasPlayingBeforeSliderTracking {
            playbackController.pause()
        }
    }

    func commitProgressSeek(resumeAfterSeek: Bool) {
        guard let duration = resolvedPlaybackDuration(), duration > 0 else {
            isSeekingWithSlider = false
            wasPlayingBeforeSliderTracking = false
            return
        }

        let targetTime = min(max(duration * layout.progressSlider.doubleValue, 0), duration)
        applyPlaybackDisplayTime(targetTime, duration: duration, forceScroll: true)
        restoredPlaybackPosition = targetTime

        guard playbackController.hasLoadedItem else {
            saveCurrentPlaybackState(position: targetTime)
            isSeekingWithSlider = false
            wasPlayingBeforeSliderTracking = false
            return
        }

        isSeekingWithSlider = true
        seekGeneration += 1
        let generation = seekGeneration

        playbackController.seek(to: targetTime) { [weak self] _ in
            guard let self else {
                return
            }
            guard generation == self.seekGeneration else {
                return
            }

            self.completeSliderSeek(
                expectedTime: targetTime,
                duration: duration,
                generation: generation,
                resumeAfterSeek: resumeAfterSeek
            )
        }
    }

    private func completeSliderSeek(
        expectedTime: TimeInterval,
        duration: TimeInterval,
        generation: Int,
        resumeAfterSeek: Bool,
        attempt: Int = 0
    ) {
        guard generation == seekGeneration else {
            return
        }

        let playerTime = playbackController.currentTime() ?? 0
        let playerMatches = playerTime.isFinite
            && playerTime > 0.1
            && abs(playerTime - expectedTime) <= 0.35
        let timedOut = attempt >= 30
        let settled = playerMatches || timedOut
        let displayTime = playerMatches
            ? min(max(playerTime, 0), duration)
            : expectedTime

        applyPlaybackDisplayTime(displayTime, duration: duration, forceScroll: true)

        guard settled else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.completeSliderSeek(
                    expectedTime: expectedTime,
                    duration: duration,
                    generation: generation,
                    resumeAfterSeek: resumeAfterSeek,
                    attempt: attempt + 1
                )
            }
            return
        }

        saveCurrentPlaybackState(position: displayTime)
        isSeekingWithSlider = false
        wasPlayingBeforeSliderTracking = false
        if resumeAfterSeek {
            playbackController.resume()
            if let index = currentTrackIndex {
                layout.statusLabel.stringValue = "正在播放：\(tracks[index].displayName)"
                layout.setPlayButtonShowsPause(true)
            }
        }
    }

    func syncUIWithPlayback() {
        let current = playbackController.currentTime() ?? 0
        let duration = playbackController.duration() ?? 0
        applyPlaybackDisplayTime(current, duration: duration, forceScroll: true)
    }

    private func applyPlaybackDisplayTime(
        _ time: TimeInterval,
        duration: TimeInterval,
        forceScroll: Bool
    ) {
        isApplyingProgrammaticSliderUpdate = true
        defer { isApplyingProgrammaticSliderUpdate = false }

        if duration.isFinite, duration > 0, time.isFinite {
            layout.progressSlider.doubleValue = min(max(time / duration, 0), 1)
        }
        updateTimeLabel(current: time, duration: duration)
        if forceScroll {
            layout.lyricsView.updateWhenReady(for: time, forceScroll: true)
        } else {
            layout.lyricsView.update(for: time, forceScroll: false)
        }
        syncMenuBarLyrics(at: time)
    }

    func startTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        guard !isSeekingWithSlider else {
            return
        }

        let current = playbackController.currentTime() ?? 0
        let duration = playbackController.duration() ?? 0

        if duration.isFinite, duration > 0, current.isFinite {
            applyPlaybackDisplayTime(current, duration: duration, forceScroll: false)

            if playbackController.isPlaying {
                lastSavedPlaybackTick += 1
                if lastSavedPlaybackTick >= 25 {
                    lastSavedPlaybackTick = 0
                    saveCurrentPlaybackState()
                }
            }
        } else {
            updateTimeLabel(current: 0, duration: 0)
        }
    }

    func saveCurrentPlaybackState(position: TimeInterval? = nil) {
        guard let index = currentTrackIndex, tracks.indices.contains(index), let trackId = tracks[index].id else {
            return
        }
        let currentPosition = position ?? playbackController.currentTime() ?? 0
        persistPlaybackState(trackId: trackId, position: currentPosition)
    }

    func persistPlaybackState(trackId: Int64, position: TimeInterval) {
        try? playerStateRepository.updatePlaybackState(trackId: trackId, position: position)
    }

    func updateTimeLabel(current: TimeInterval, duration: TimeInterval) {
        layout.timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(duration))"
    }

    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(time.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// 播放中用 AVPlayer 时长；未播放时用曲目 ID3 缓存时长，供进度条预览与 seek 落点。
    func resolvedPlaybackDuration() -> TimeInterval? {
        if let duration = playbackController.duration(), duration.isFinite, duration > 0 {
            return duration
        }
        guard let index = currentTrackIndex, tracks.indices.contains(index) else {
            return nil
        }
        if let duration = tracks[index].duration, duration.isFinite, duration > 0 {
            return duration
        }
        let fileDuration = TrackMetadataReader.read(from: tracks[index].audioURL).duration
        if let fileDuration, fileDuration.isFinite, fileDuration > 0 {
            return fileDuration
        }
        return nil
    }
}
