import AppKit

final class PlayerWindowController: NSWindowController {
    private enum DefaultsKey {
        static let lastFolderPath = "lastFolderPath"
    }

    private var layout: PlayerWindowLayout!
    private let trackListDataSource = TrackListDataSource()
    private let playbackController = PlaybackController()
    private let lyricSearchService = LyricSearchService()
    private var lyricCandidateDialog: LyricCandidateDialog?

    private var tracks: [MusicTrack] = []
    private var currentFolderURL: URL?
    private var currentTrackIndex: Int?
    private var lrcLines: [LrcLine] = []
    private var progressTimer: Timer?
    private var isSeekingWithSlider = false
    private var wasPlayingBeforeSliderTracking = false
    private var seekGeneration = 0

    private var selectedLyricProvider: LyricProvider {
        let index = layout.lyricProviderPopup.indexOfSelectedItem
        guard LyricProvider.allCases.indices.contains(index) else {
            return .netEase
        }
        return LyricProvider.allCases[index]
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Local LRC Player"
        window.minSize = NSSize(width: 780, height: 520)
        self.init(window: window)
        setup()
    }

    deinit {
        progressTimer?.invalidate()
    }

    private func setup() {
        guard let contentView = window?.contentView else {
            return
        }

        layout = PlayerWindowLayout(contentView: contentView)
        bindActions()
        updateCookieButtonTitle(for: selectedLyricProvider)
        layout.lyricsView.showPlaceholder("请选择歌曲")
        updateControlState()
        startTimer()
        loadLastFolderIfAvailable()
    }

    private func bindActions() {
        layout.chooseButton.target = self
        layout.chooseButton.action = #selector(chooseFolder)
        layout.lyricProviderPopup.target = self
        layout.lyricProviderPopup.action = #selector(lyricProviderChanged)
        layout.setNetEaseCookieButton.target = self
        layout.setNetEaseCookieButton.action = #selector(setNetEaseCookie)
        layout.resetNetEaseCookieButton.target = self
        layout.resetNetEaseCookieButton.action = #selector(resetNetEaseCookie)
        layout.downloadCurrentLyricButton.target = self
        layout.downloadCurrentLyricButton.action = #selector(downloadCurrentLyric)
        layout.fillMissingLyricsButton.target = self
        layout.fillMissingLyricsButton.action = #selector(fillMissingLyrics)
        layout.playButton.target = self
        layout.playButton.action = #selector(togglePlayback)
        layout.previousButton.target = self
        layout.previousButton.action = #selector(playPrevious)
        layout.nextButton.target = self
        layout.nextButton.action = #selector(playNext)
        layout.progressSlider.target = self
        layout.progressSlider.action = #selector(progressChanged)
        layout.progressSlider.isContinuous = true
        layout.progressSlider.onTrackingBegan = { [weak self] in
            self?.beginProgressTracking()
        }
        layout.progressSlider.onTrackingEnded = { [weak self] in
            self?.commitProgressSeek(resumeAfterSeek: self?.wasPlayingBeforeSliderTracking == true)
        }

        trackListDataSource.configure(tableView: layout.tableView)
        trackListDataSource.onDoubleClick = { [weak self] row in
            self?.playTrack(at: row)
        }

        playbackController.onPlaybackEnded = { [weak self] in
            self?.playerItemDidEnd()
        }
    }

    @objc private func lyricProviderChanged() {
        let provider = selectedLyricProvider
        updateCookieButtonTitle(for: provider)
        layout.statusLabel.stringValue = "Cookie 来源：\(provider.displayName)"
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: DefaultsKey.lastFolderPath)
            loadFolder(url)
        }
    }

    private func loadLastFolderIfAvailable() {
        guard let path = UserDefaults.standard.string(forKey: DefaultsKey.lastFolderPath) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            loadFolder(url)
        }
    }

    private func loadFolder(_ url: URL) {
        do {
            currentFolderURL = url
            tracks = try MusicLibrary.scan(folderURL: url)
            trackListDataSource.tracks = tracks
            currentTrackIndex = nil
            playbackController.stop()
            lrcLines = []
            layout.folderLabel.stringValue = url.path

            if tracks.isEmpty {
                layout.statusLabel.stringValue = "该目录没有找到支持的音乐文件"
                layout.lyricsView.showPlaceholder("未找到音乐文件")
            } else {
                layout.statusLabel.stringValue = "找到 \(tracks.count) 首歌曲。双击歌曲开始播放。"
                trackListDataSource.selectRow(0)
                layout.lyricsView.showPlaceholder("双击左侧歌曲开始播放")
            }

            updateControlState()
        } catch {
            tracks = []
            trackListDataSource.tracks = []
            layout.statusLabel.stringValue = "读取目录失败：\(error.localizedDescription)"
            layout.lyricsView.showPlaceholder("读取目录失败")
            updateControlState()
        }
    }

    private func playTrack(at index: Int) {
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
    }

    private func loadLyrics(for track: MusicTrack) {
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

    private func renderLyrics(_ contents: String) {
        lrcLines = LrcParser.parse(contents)
        if lrcLines.isEmpty {
            layout.lyricsView.showPlaceholder("歌词文件为空或格式无法识别")
        } else {
            layout.lyricsView.render(lrcLines)
        }
    }

    @objc private func togglePlayback() {
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
        } else {
            playbackController.resume()
            layout.playButton.title = "暂停"
            if let index = currentTrackIndex {
                layout.statusLabel.stringValue = "正在播放：\(tracks[index].displayName)"
            }
        }
    }

    @objc private func playPrevious() {
        guard !tracks.isEmpty else {
            return
        }

        let nextIndex = max((currentTrackIndex ?? trackListDataSource.selectedTrackIndex() ?? 0) - 1, 0)
        playTrack(at: nextIndex)
    }

    @objc private func playNext() {
        guard !tracks.isEmpty else {
            return
        }

        let baseIndex = currentTrackIndex ?? trackListDataSource.selectedTrackIndex() ?? -1
        let nextIndex = min(baseIndex + 1, tracks.count - 1)
        playTrack(at: nextIndex)
    }

    private func playerItemDidEnd() {
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
        }
    }

    @objc private func progressChanged() {
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

    private func beginProgressTracking() {
        isSeekingWithSlider = true
        wasPlayingBeforeSliderTracking = playbackController.isPlaying
        if wasPlayingBeforeSliderTracking {
            playbackController.pause()
        }
    }

    private func commitProgressSeek(resumeAfterSeek: Bool) {
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

            let actualTime = self.playbackController.currentTime() ?? targetTime
            let actualDuration = self.playbackController.duration() ?? duration
            if actualDuration > 0 {
                self.layout.progressSlider.doubleValue = min(max(actualTime / actualDuration, 0), 1)
            }
            self.updateTimeLabel(current: actualTime, duration: actualDuration)
            self.layout.lyricsView.update(for: actualTime, forceScroll: true)
            self.isSeekingWithSlider = false
            self.wasPlayingBeforeSliderTracking = false
            if resumeAfterSeek {
                self.playbackController.resume()
                if let index = self.currentTrackIndex {
                    self.layout.statusLabel.stringValue = "正在播放：\(self.tracks[index].displayName)"
                    self.layout.playButton.title = "暂停"
                }
            }
        }
    }

    private func startTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard !isSeekingWithSlider else {
            return
        }

        let current = playbackController.currentTime() ?? 0
        let duration = playbackController.duration() ?? 0

        if duration.isFinite, duration > 0, current.isFinite {
            layout.progressSlider.doubleValue = min(max(current / duration, 0), 1)
            updateTimeLabel(current: current, duration: duration)
            layout.lyricsView.update(for: current, forceScroll: false)
        } else {
            updateTimeLabel(current: 0, duration: 0)
        }
    }

    private func updateTimeLabel(current: TimeInterval, duration: TimeInterval) {
        layout.timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(duration))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(time.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func updateControlState() {
        let hasTracks = !tracks.isEmpty
        layout.playButton.isEnabled = hasTracks
        layout.previousButton.isEnabled = hasTracks
        layout.nextButton.isEnabled = hasTracks
        layout.progressSlider.isEnabled = hasTracks
        layout.downloadCurrentLyricButton.isEnabled = hasTracks
        layout.fillMissingLyricsButton.isEnabled = hasTracks
    }

    @objc private func setNetEaseCookie() {
        let provider = selectedLyricProvider
        let alert = NSAlert()
        alert.messageText = "设置\(provider.displayName) Cookie"
        alert.informativeText = "粘贴登录\(provider.displayName)后的 Cookie。Cookie 会保存到本机私有配置文件，不再使用 Keychain。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 520, height: 28))
        input.placeholderString = cookiePlaceholder(for: provider)
        if let existing = try? CookieStore.read(provider: provider) {
            input.stringValue = existing
        }
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try lyricSearchService.saveCookie(
                input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: provider
            )
            layout.statusLabel.stringValue = "\(provider.displayName) Cookie 已保存"
        } catch {
            layout.statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func resetNetEaseCookie() {
        let provider = selectedLyricProvider
        do {
            try lyricSearchService.resetCookie(provider: provider)
            layout.statusLabel.stringValue = "\(provider.displayName) Cookie 已重置，请重新设置"
        } catch {
            layout.statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func downloadCurrentLyric() {
        guard let index = currentTrackIndex ?? trackListDataSource.selectedTrackIndex(), tracks.indices.contains(index) else {
            layout.statusLabel.stringValue = "请先选择一首歌曲"
            return
        }

        downloadLyric(for: tracks[index], reloadCurrentTrack: true)
    }

    @objc private func fillMissingLyrics() {
        let missingTracks = tracks.filter { $0.lyricURL == nil }
        guard !missingTracks.isEmpty else {
            layout.statusLabel.stringValue = "当前目录没有缺失歌词的歌曲"
            return
        }

        layout.statusLabel.stringValue = "开始补全缺失歌词：\(missingTracks.count) 首"
        setLyricButtonsEnabled(false)
        downloadMissingLyrics(missingTracks, index: 0, successCount: 0, failureCount: 0)
    }

    private func downloadMissingLyrics(_ missingTracks: [MusicTrack], index: Int, successCount: Int, failureCount: Int) {
        guard index < missingTracks.count else {
            setLyricButtonsEnabled(true)
            refreshCurrentFolder(preserveTrackURL: currentTrackIndex.flatMap { tracks.indices.contains($0) ? tracks[$0].audioURL : nil })
            layout.statusLabel.stringValue = "补全完成：成功 \(successCount)，失败 \(failureCount)"
            return
        }

        let track = missingTracks[index]
        layout.statusLabel.stringValue = "正在下载歌词 \(index + 1)/\(missingTracks.count)：\(track.displayName)"
        lyricSearchService.downloadBestAvailableLyric(for: track) { [weak self] result in
            guard let self else {
                return
            }

            let nextSuccess = successCount + (result.isSuccess ? 1 : 0)
            let nextFailure = failureCount + (result.isSuccess ? 0 : 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.downloadMissingLyrics(
                    missingTracks,
                    index: index + 1,
                    successCount: nextSuccess,
                    failureCount: nextFailure
                )
            }
        }
    }

    private func downloadLyric(for track: MusicTrack, reloadCurrentTrack: Bool) {
        setLyricButtonsEnabled(false)
        layout.statusLabel.stringValue = "正在搜索歌词：\(track.displayName)"

        lyricSearchService.searchAllCandidates(for: track) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .failure(let error):
                self.setLyricButtonsEnabled(true)
                self.layout.statusLabel.stringValue = "歌词下载失败：\(error.localizedDescription)"
            case .success(let sections):
                guard !sections.isEmpty else {
                    self.setLyricButtonsEnabled(true)
                    self.layout.statusLabel.stringValue = "歌词下载失败：未找到候选结果"
                    return
                }

                let sourceNames = sections.map(\.provider.displayName).joined(separator: "、")
                self.layout.statusLabel.stringValue = "请选择歌词候选（\(sourceNames)）：\(track.displayName)"
                let dialog = LyricCandidateDialog(
                    service: self.lyricSearchService,
                    track: track,
                    sections: sections,
                    replaceExisting: true
                ) { [weak self] saveResult in
                    guard let self else {
                        return
                    }

                    self.lyricCandidateDialog = nil
                    self.setLyricButtonsEnabled(true)
                    switch saveResult {
                    case .failure(let error):
                        if !(error is LyricCandidateDialogError) {
                            self.layout.statusLabel.stringValue = "歌词保存失败：\(error.localizedDescription)"
                        } else {
                            self.layout.statusLabel.stringValue = "已取消歌词下载"
                        }
                    case .success:
                        self.refreshCurrentFolder(preserveTrackURL: track.audioURL)
                        self.layout.statusLabel.stringValue = "歌词已保存：\(track.displayName)"
                        if reloadCurrentTrack,
                           let index = self.tracks.firstIndex(where: { $0.audioURL == track.audioURL }) {
                            self.loadLyrics(for: self.tracks[index])
                        }
                    }
                }

                self.lyricCandidateDialog = dialog
                dialog.showModal()
            }
        }
    }

    private func refreshCurrentFolder(preserveTrackURL: URL?) {
        guard let currentFolderURL else {
            return
        }

        do {
            tracks = try MusicLibrary.scan(folderURL: currentFolderURL)
            trackListDataSource.tracks = tracks
            if let preserveTrackURL,
               let index = tracks.firstIndex(where: { $0.audioURL == preserveTrackURL }) {
                trackListDataSource.selectRow(index)
                if currentTrackIndex != nil {
                    currentTrackIndex = index
                }
            }
        } catch {
            layout.statusLabel.stringValue = "刷新目录失败：\(error.localizedDescription)"
        }
    }

    private func setLyricButtonsEnabled(_ isEnabled: Bool) {
        layout.setNetEaseCookieButton.isEnabled = isEnabled
        layout.resetNetEaseCookieButton.isEnabled = isEnabled
        layout.downloadCurrentLyricButton.isEnabled = isEnabled && !tracks.isEmpty
        layout.fillMissingLyricsButton.isEnabled = isEnabled && !tracks.isEmpty
    }

    private func updateCookieButtonTitle(for provider: LyricProvider) {
        layout.setNetEaseCookieButton.title = "设置\(provider.displayName) Cookie"
    }

    private func cookiePlaceholder(for provider: LyricProvider) -> String {
        switch provider {
        case .netEase:
            return "MUSIC_U=...; __csrf=..."
        case .qqMusic:
            return "uin=...; p_uin=...; p_skey=...; qqmusic_key=..."
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
