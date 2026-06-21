import AppKit

extension PlayerWindowController {
    func restoreLastSelection(at index: Int, position: TimeInterval) {
        guard tracks.indices.contains(index) else {
            return
        }

        playbackController.stop()
        let track = tracks[index]
        currentTrackIndex = index
        trackListDataSource.selectRow(index)
        loadLyrics(for: track)

        restoredPlaybackPosition = max(position, 0)
        let duration = track.duration ?? 0
        if duration > 0 {
            let preview = min(restoredPlaybackPosition ?? 0, duration)
            layout.progressSlider.doubleValue = preview / duration
            updateTimeLabel(current: preview, duration: duration)
            layout.lyricsView.update(for: preview, forceScroll: true)
        } else {
            layout.progressSlider.doubleValue = 0
            updateTimeLabel(current: restoredPlaybackPosition ?? 0, duration: 0)
            if let preview = restoredPlaybackPosition {
                layout.lyricsView.update(for: preview, forceScroll: true)
            }
        }

        layout.playButton.title = "播放"
        layout.statusLabel.stringValue = "已恢复上次选中的歌曲：\(track.displayName)"
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
        currentTrackIndex = index
        trackListDataSource.selectRow(index)
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
        loadLyrics(for: track)
        layout.statusLabel.stringValue = "正在播放：\(track.displayName)"
        layout.playButton.title = "暂停"
        updateControlState()

        if let trackId = track.id {
            try? playHistoryRepository.recordPlayback(
                trackId: trackId,
                position: resumePosition ?? restoredPlaybackPosition ?? 0
            )
            persistPlaybackState(
                trackId: trackId,
                position: resumePosition ?? restoredPlaybackPosition ?? 0
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
            playbackController.seek(to: seekTarget) { [weak self] _ in
                self?.syncUIWithPlayback()
            }
        }
    }

    func loadLyrics(for track: MusicTrack) {
        guard let lyricURL = track.lyricURL else {
            lrcLines = []
            layout.lyricsView.showPlaceholder("未找到同名 LRC 歌词")
            return
        }

        do {
            let contents = try String(contentsOf: lyricURL, encoding: .utf8)
            renderLyrics(contents)
        } catch {
            do {
                let contents = try String(contentsOf: lyricURL, encoding: .utf16)
                renderLyrics(contents)
            } catch {
                lrcLines = []
                layout.lyricsView.showPlaceholder("歌词读取失败")
            }
        }
    }

    func renderLyrics(_ contents: String) {
        lrcLines = LrcParser.parse(contents)
        if lrcLines.isEmpty {
            layout.lyricsView.showPlaceholder("歌词文件为空或格式无法识别")
        } else {
            layout.lyricsView.render(lrcLines)
        }
    }

    @objc func togglePlayback() {
        if currentTrackIndex == nil {
            if let selected = trackListDataSource.selectedTrackIndex() {
                playTrack(at: selected)
            } else if !tracks.isEmpty {
                playTrack(at: 0)
            }
            return
        }

        if playbackController.isPlaying {
            playbackController.pause()
            layout.playButton.title = "播放"
            layout.statusLabel.stringValue = "已暂停"
            saveCurrentPlaybackState()
        } else if playbackController.hasLoadedItem {
            playbackController.resume()
            layout.playButton.title = "暂停"
            if let index = currentTrackIndex {
                layout.statusLabel.stringValue = "正在播放：\(tracks[index].displayName)"
            }
        } else if let index = currentTrackIndex {
            playTrack(at: index, startFromSavedPosition: true)
        }
    }

    @objc func playPrevious() {
        guard !tracks.isEmpty else {
            return
        }

        let nextIndex = max((currentTrackIndex ?? trackListDataSource.selectedTrackIndex() ?? 0) - 1, 0)
        playTrack(at: nextIndex)
    }

    @objc func playNext() {
        guard !tracks.isEmpty else {
            return
        }

        let baseIndex = currentTrackIndex ?? trackListDataSource.selectedTrackIndex() ?? -1
        let nextIndex = min(baseIndex + 1, tracks.count - 1)
        playTrack(at: nextIndex)
    }

    func playerItemDidEnd() {
        guard let currentTrackIndex else {
            return
        }

        let nextIndex = currentTrackIndex + 1
        if tracks.indices.contains(nextIndex) {
            playTrack(at: nextIndex)
        } else {
            playbackController.resetToStart()
            layout.playButton.title = "播放"
            layout.statusLabel.stringValue = "播放结束"
            saveCurrentPlaybackState(position: 0)
        }
    }

    @objc func progressChanged() {
        guard let duration = playbackController.duration(), duration > 0 else {
            return
        }

        let targetTime = duration * layout.progressSlider.doubleValue
        updateTimeLabel(current: targetTime, duration: duration)
        layout.lyricsView.update(for: targetTime, forceScroll: true)

        if !layout.progressSlider.isTrackingMouse {
            commitProgressSeek(resumeAfterSeek: false)
        }
    }

    func beginProgressTracking() {
        isSeekingWithSlider = true
        wasPlayingBeforeSliderTracking = playbackController.isPlaying
        if wasPlayingBeforeSliderTracking {
            playbackController.pause()
        }
    }

    func commitProgressSeek(resumeAfterSeek: Bool) {
        guard let duration = playbackController.duration(), duration > 0 else {
            isSeekingWithSlider = false
            wasPlayingBeforeSliderTracking = false
            return
        }

        isSeekingWithSlider = true
        seekGeneration += 1
        let generation = seekGeneration
        let targetTime = duration * layout.progressSlider.doubleValue
        updateTimeLabel(current: targetTime, duration: duration)
        layout.lyricsView.update(for: targetTime, forceScroll: true)

        playbackController.seek(to: targetTime) { [weak self] _ in
            guard let self else {
                return
            }
            guard generation == self.seekGeneration else {
                return
            }

            self.syncUIWithPlayback()
            self.isSeekingWithSlider = false
            self.wasPlayingBeforeSliderTracking = false
            self.saveCurrentPlaybackState()
            if resumeAfterSeek {
                self.playbackController.resume()
                if let index = self.currentTrackIndex {
                    self.layout.statusLabel.stringValue = "正在播放：\(self.tracks[index].displayName)"
                    self.layout.playButton.title = "暂停"
                }
            }
        }
    }

    func syncUIWithPlayback() {
        let current = playbackController.currentTime() ?? 0
        let duration = playbackController.duration() ?? 0
        if duration > 0 {
            layout.progressSlider.doubleValue = min(max(current / duration, 0), 1)
        }
        updateTimeLabel(current: current, duration: duration)
        layout.lyricsView.update(for: current, forceScroll: true)
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
            layout.progressSlider.doubleValue = min(max(current / duration, 0), 1)
            updateTimeLabel(current: current, duration: duration)
            layout.lyricsView.update(for: current, forceScroll: false)

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
}
