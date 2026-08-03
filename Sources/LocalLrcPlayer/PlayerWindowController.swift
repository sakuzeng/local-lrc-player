import AppKit

final class PlayerWindowController: NSWindowController {
    var layout: PlayerWindowLayout!
    let trackListDataSource = TrackListDataSource()
    let playbackController = PlaybackController()
    let lyricSearchService = LyricSearchService()
    let libraryRepository = LibraryRepository()
    let trackRepository = TrackRepository()
    let playHistoryRepository = PlayHistoryRepository()
    let appSettingsRepository = AppSettingsRepository()
    let playerStateRepository = PlayerStateRepository()
    lazy var artworkDownloadService = ArtworkDownloadService(lyricSearchService: lyricSearchService)
    var menuBarLyricsController: MenuBarLyricsController?
    weak var settingsWindowController: SettingsWindowController?
    var celebrationPanelController: CelebrationPanelController?
    var lyricCandidateDialog: LyricCandidateDialog?

    var tracks: [MusicTrack] = []
    var activeLibrary: LibraryRecord?
    var currentTrackIndex: Int?
    var lrcLines: [LrcLine] = []
    var progressTimer: Timer?
    var isSeekingWithSlider = false
    var wasPlayingBeforeSliderTracking = false
    var seekGeneration = 0
    var searchKeyword = ""
    var playingTrackURL: URL?
    /// 正在播放曲目的数据库 id。文件在 Finder 里被改名后路径会失配，靠它把播放行重新认回来。
    var playingTrackId: Int64?
    var restoredPlaybackPosition: TimeInterval?
    var lastSavedPlaybackTick = 0
    var isApplyingProgrammaticSliderUpdate = false
    var playbackMode: PlaybackMode = .sequential
    var shuffleHistory: [Int] = []
    var nowPlayingArtworkTrackURL: URL?
    var artworkDownloadAttemptedTrackIds: Set<Int64> = []
    // 播放区信息的控制器侧副本，供菜单栏卡片取用（layout 只把它们存进私有子视图）。
    var nowPlayingTitle: String?
    var nowPlayingArtist: String?
    var nowPlayingArtwork: NSImage?
    // 里程碑计数：本次播放对应的 play_history 行、已实际播放的秒数、是否已计为有效播放。
    var currentPlayHistoryId: Int64?
    var listenedSecondsThisPlay: TimeInterval = 0
    var hasCountedCurrentPlayback = false
    /// 命中的里程碑先存着，等这首播完或被切走再弹 —— 播放中途打断的正是要庆祝的那个体验。
    var pendingMilestone: CelebrationContent?

    private var mouseDownMonitor: Any?
    private var keyDownMonitor: Any?
    private var statusRestoreTimer: Timer?
    private var pendingStatusRestoreText: String?
    private var windowToolbar: PlayerWindowToolbar?
    private var windowFrameSaveTimer: Timer?
    private var volumeSaveTimer: Timer?

    var selectedLyricProvider: LyricProvider {
        settingsWindowController?.selectedLyricProvider ?? .netEase
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
        Self.configureWindowChrome(window)
        self.init(window: window)
        setup()
    }

    deinit {
        progressTimer?.invalidate()
        windowFrameSaveTimer?.invalidate()
        volumeSaveTimer?.invalidate()
        statusRestoreTimer?.invalidate()
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    private func setup() {
        guard let contentView = window?.contentView else {
            return
        }

        PlayerWindowLayout.installBackground(in: contentView)
        layout = PlayerWindowLayout(contentView: contentView)
        if let window {
            let toolbar = PlayerWindowToolbar(controller: self, layout: layout)
            toolbar.install(on: window)
            windowToolbar = toolbar
        }
        bindActions()
        restorePlaybackMode()
        layout.lyricsView.showPlaceholder("请选择歌曲")
        updateControlState()
        startTimer()

        do {
            try libraryRepository.migrateLegacyLastFolderIfNeeded()
            bootstrapLibraries(restoreLastSession: true)
        } catch {
            layout.statusLabel.stringValue = "数据库初始化失败：\(error.localizedDescription)"
        }

        window?.initialFirstResponder = layout.tableView
        window?.delegate = self
        restoreWindowFrame()
        DispatchQueue.main.async { [weak self] in
            self?.resignSearchFieldFocus()
        }
    }

    func resignSearchFieldFocus() {
        guard let window else {
            return
        }
        if let editor = layout.searchField.currentEditor(), window.firstResponder === editor {
            layout.searchField.abortEditing()
        }
        if window.firstResponder === layout.searchField {
            window.makeFirstResponder(nil)
        }
    }

    private func installSearchFieldFocusMonitor() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            let pointInSearchField = layout.searchField.convert(event.locationInWindow, from: nil)
            if !layout.searchField.bounds.contains(pointInSearchField) {
                resignSearchFieldFocus()
            }
            return event
        }
    }

    private func installKeyboardMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            if isTextInputFocused() {
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.charactersIgnoringModifiers == " " && modifiers.isEmpty {
                togglePlayback()
                return nil
            }
            // Esc 退出沉浸模式；非沉浸时不拦截，留给搜索框等原有行为。
            if event.keyCode == 53, modifiers.isEmpty, layout.isImmersive {
                setImmersiveMode(false)
                return nil
            }

            return event
        }
    }

    private func isTextInputFocused() -> Bool {
        guard let window, let responder = window.firstResponder else {
            return false
        }

        if let editor = layout.searchField.currentEditor(), responder === editor {
            return true
        }
        if responder === layout.searchField {
            return true
        }

        if let textView = responder as? NSTextView, textView.isEditable {
            return true
        }
        if let textField = responder as? NSTextField, textField.isEditable {
            return true
        }

        return false
    }

    private func bindActions() {
        layout.searchField.target = self
        layout.searchField.action = #selector(searchFieldChanged)
        layout.searchField.delegate = self
        layout.playButton.target = self
        layout.playButton.action = #selector(togglePlayback)
        layout.previousButton.target = self
        layout.previousButton.action = #selector(playPrevious)
        layout.nextButton.target = self
        layout.nextButton.action = #selector(playNext)
        layout.playbackModeButton.target = self
        layout.playbackModeButton.action = #selector(cyclePlaybackMode)
        layout.locatePlayingButton.target = self
        layout.locatePlayingButton.action = #selector(locatePlayingTrack)
        layout.immersiveEnterButton.target = self
        layout.immersiveEnterButton.action = #selector(toggleImmersiveMode)
        layout.immersiveExitButton.target = self
        layout.immersiveExitButton.action = #selector(toggleImmersiveMode)
        layout.progressSlider.target = self
        layout.progressSlider.action = #selector(progressChanged)
        layout.progressSlider.isContinuous = true
        layout.volumeSlider.target = self
        layout.volumeSlider.action = #selector(volumeChanged)
        layout.volumeSlider.isContinuous = true
        layout.volumeButton.target = self
        layout.volumeButton.action = #selector(toggleVolumePopover)
        layout.progressSlider.onTrackingBegan = { [weak self] in
            self?.beginProgressTracking()
        }
        layout.progressSlider.onTrackingEnded = { [weak self] in
            self?.commitProgressSeek(resumeAfterSeek: self?.wasPlayingBeforeSliderTracking == true)
        }
        layout.progressSlider.onHoverFraction = { [weak self] fraction in
            self?.updateSeekPreview(fraction: fraction)
        }

        trackListDataSource.configure(tableView: layout.tableView)
        trackListDataSource.onSelectionChanged = { [weak self] _ in
            self?.resignSearchFieldFocus()
        }
        trackListDataSource.onDoubleClick = { [weak self] row in
            self?.resignSearchFieldFocus()
            self?.resetShuffleHistory(for: row)
            self?.playTrack(at: row)
        }

        layout.lyricsView.onMouseDown = { [weak self] in
            self?.resignSearchFieldFocus()
        }
        layout.lyricsView.onLineClicked = { [weak self] time in
            self?.seekToLyricLine(at: time)
        }

        installSearchFieldFocusMonitor()
        installKeyboardMonitor()

        playbackController.onPlaybackEnded = { [weak self] in
            self?.playerItemDidEnd()
        }
    }

    @objc func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                LibraryBookmarkStore.saveBookmark(for: url)
                let library = try libraryRepository.registerLibrary(at: url)
                registerAndSyncLibrary(library, restoreLastSession: false)
                settingsWindowController?.reloadLibraries()
            } catch {
                layout.statusLabel.stringValue = "加载目录失败：\(error.localizedDescription)"
            }
        }
    }

    @objc func refreshFolder() {
        refreshAllLibraries(preserveTrackURL: trackURLForListHighlight())
    }

    @objc private func searchFieldChanged() {
        searchKeyword = layout.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        reloadMasterPlaylist(
            restoreLastSession: false,
            preserveTrackURL: trackURLForListHighlight()
        )
    }

    func trackURLForListHighlight() -> URL? {
        if let playingTrackURL {
            return playingTrackURL
        }
        if let index = currentTrackIndex, tracks.indices.contains(index) {
            return tracks[index].audioURL
        }
        if let url = trackListDataSource.selectedTrackURL {
            return url
        }
        if let row = trackListDataSource.selectedTrackIndex(), tracks.indices.contains(row) {
            return tracks[row].audioURL
        }
        return nil
    }

    func updateControlState() {
        let hasTracks = !tracks.isEmpty
        let hasLibrary: Bool
        if let libraries = try? libraryRepository.allLibraries() {
            hasLibrary = !libraries.isEmpty
        } else {
            hasLibrary = activeLibrary != nil
        }
        layout.refreshEmptyStates(
            hasLibraries: hasLibrary,
            trackCount: tracks.count,
            searchKeyword: searchKeyword
        )
        layout.updateListHeader(trackCount: tracks.count)
        windowToolbar?.updateEnabledState(hasLibrary: hasLibrary)
        layout.playButton.isEnabled = hasTracks
        layout.previousButton.isEnabled = hasTracks
        layout.nextButton.isEnabled = hasTracks
        layout.playbackModeButton.isEnabled = hasTracks
        layout.locatePlayingButton.isEnabled = playingTrackURL != nil
        layout.progressSlider.isEnabled = hasTracks
        settingsWindowController?.updateLyricDownloadButtonState(hasTracks: hasTracks)
    }

    @objc func setLyricCookie() {
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

    @objc func resetLyricCookie() {
        let provider = selectedLyricProvider
        do {
            try lyricSearchService.resetCookie(provider: provider)
            layout.statusLabel.stringValue = "\(provider.displayName) Cookie 已重置，请重新设置"
        } catch {
            layout.statusLabel.stringValue = error.localizedDescription
        }
    }

    private func cookiePlaceholder(for provider: LyricProvider) -> String {
        switch provider {
        case .netEase:
            return "MUSIC_U=...; __csrf=..."
        case .qqMusic:
            return "uin=...; p_uin=...; p_skey=...; qqmusic_key=..."
        }
    }

    /// 一次性操作反馈（切模式、切显示模式、定位）。statusLabel 平时承载的是持续状态
    /// （正在播放某首、共多少首），所以这类提示必须自己让位，否则会一直占着不走。
    /// 到点前若已被别的消息覆盖，就不再回填，免得把更新的状态顶掉。
    func showTransientStatus(_ message: String, restoringAfter seconds: TimeInterval = 3) {
        // 连续触发多条提示时，回填目标始终是最初那条持续状态，而不是上一条提示。
        let previous = pendingStatusRestoreText ?? layout.statusLabel.stringValue
        pendingStatusRestoreText = previous
        layout.statusLabel.stringValue = message

        statusRestoreTimer?.invalidate()
        statusRestoreTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            statusRestoreTimer = nil
            pendingStatusRestoreText = nil
            guard layout.statusLabel.stringValue == message else {
                return
            }
            layout.statusLabel.stringValue = previous
        }
    }

    func saveSession() {
        saveCurrentPlaybackState()
        saveWindowFrame()
    }

    private func restoreWindowFrame() {
        guard let window else {
            return
        }

        if let saved = try? playerStateRepository.windowFrame() {
            window.setFrame(Self.clampedFrame(saved.rect, for: window), display: false)
        } else {
            window.center()
        }
    }

    private func saveWindowFrame() {
        guard let window else {
            return
        }
        try? playerStateRepository.updateWindowFrame(window.frame)
    }

    private func scheduleWindowFrameSave() {
        windowFrameSaveTimer?.invalidate()
        windowFrameSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.saveWindowFrame()
        }
    }

    private static func clampedFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        var frame = frame
        let minSize = window.minSize
        if frame.width < minSize.width {
            frame.size.width = minSize.width
        }
        if frame.height < minSize.height {
            frame.size.height = minSize.height
        }

        let targetScreen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = targetScreen?.visibleFrame else {
            return frame
        }

        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        return frame
    }

    @objc func chooseFolderFromMenu() {
        chooseFolder()
    }

    @objc func refreshFolderFromMenu() {
        refreshFolder()
    }

    @objc func togglePlaybackFromMenu() {
        togglePlayback()
    }

    @objc func playPreviousFromMenu() {
        playPrevious()
    }

    @objc func playNextFromMenu() {
        playNext()
    }

    @objc func locatePlayingTrack() {
        resignSearchFieldFocus()

        if trackListDataSource.indexOfPlayingTrack() == nil,
           !searchKeyword.isEmpty,
           playingTrackURL != nil {
            layout.searchField.stringValue = ""
            searchKeyword = ""
            reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
        }

        guard let index = trackListDataSource.indexOfPlayingTrack(),
              tracks.indices.contains(index) else {
            layout.statusLabel.stringValue = playingTrackURL == nil
                ? "当前没有正在播放的歌曲"
                : "未在列表中找到正在播放的歌曲"
            return
        }

        trackListDataSource.selectRow(index, scrollToVisible: true, isUserInitiated: false)
        showTransientStatus("已定位：\(tracks[index].displayName)")
    }

    /// 沉浸模式：藏起曲目列表，换成大封面 + 大字歌词 + 底部悬浮控制条。
    /// 不持久化，启动总是日常模式（避免 schema 迁移，且启动时封面尚未就绪，沉浸首屏会是空封面）。
    @objc func toggleImmersiveMode() {
        setImmersiveMode(!layout.isImmersive)
    }

    func setImmersiveMode(_ enabled: Bool) {
        guard enabled != layout.isImmersive else {
            return
        }
        layout.setImmersiveMode(enabled)
        if enabled {
            showTransientStatus("沉浸模式（Esc 退出）")
        }
        // 换了排版档位，歌词要按当前播放位置重新落到视口中心。
        refreshIdlePlaybackDisplay(forceScroll: true)
        if playbackController.hasLoadedItem {
            syncUIWithPlayback()
        }
    }

    /// 里程碑弹窗预览（开发用）。数据层还没接，先拿当前曲目和假次数看视觉；
    /// 真正的触发接上有效播放计数后会替换掉这个入口。
    @objc func previewMilestoneCelebration() {
        let index = currentTrackIndex ?? trackListDataSource.indexOfSelectedTrack()
        let track = index.flatMap { tracks.indices.contains($0) ? tracks[$0] : nil }
        showCelebration(MilestoneCelebration.content(
            count: 100,
            title: nowPlayingTitle ?? track?.displayName ?? "妈妈的话",
            artist: nowPlayingArtist,
            artwork: nowPlayingArtwork,
            firstPlayedAt: Date().addingTimeInterval(-42 * 24 * 3600)
        ))
    }

    /// 启动同步完音乐库后调用（要先有 tracks 才 JOIN 得到曲目）。
    /// 每天最多弹一次，且只在那天真有记录时才弹 —— 没数据就安静，不弹空窗。
    func presentOnThisDayMemoryIfAvailable() {
        let settings = (try? appSettingsRepository.settings()) ?? .defaults
        let today = OnThisDayMemory.dayKey(for: Date())
        guard settings.memoryAlertsEnabled, settings.lastMemoryShownOn != today else {
            return
        }

        // try? 套在返回 Optional 的方法上会得到双层 Optional，用 ?? nil 压平。
        let found = (try? OnThisDayMemory.findMatch(lookup: { day in
            try playHistoryRepository.mostPlayedTrack(onDay: day)
        })) ?? nil
        guard let match = found else {
            return
        }

        try? appSettingsRepository.markMemoryShown(on: today)
        let artwork = ArtworkCache.load(trackId: match.track.id)
            ?? TrackMetadataReader.artworkData(from: match.track.audioURL).flatMap(NSImage.init(data:))
        showCelebration(OnThisDayMemory.content(for: match, artwork: artwork))
    }

    func showCelebration(_ content: CelebrationContent) {
        celebrationPanelController?.close()
        let controller = CelebrationPanelController(content: content) { [weak self] in
            guard let self else {
                return
            }
            switch content.kind {
            case .milestone:
                try? appSettingsRepository.updateMilestoneAlerts(enabled: false)
                showTransientStatus("已关闭里程碑提醒，可在 ⌘, 设置中重新打开")
            case .memory:
                try? appSettingsRepository.updateMemoryAlerts(enabled: false)
                showTransientStatus("已关闭往年今日提醒，可在 ⌘, 设置中重新打开")
            }
            settingsWindowController?.refreshMilestoneControls()
        }
        celebrationPanelController = controller
        controller.present(over: window)
    }

    @objc func cyclePlaybackMode() {
        playbackMode = playbackMode.next()
        applyPlaybackMode()
        try? playerStateRepository.updatePlaybackMode(playbackMode)
        showTransientStatus("播放模式：\(playbackMode.title)")
    }

    private func restorePlaybackMode() {
        if let state = try? playerStateRepository.playbackState() {
            playbackMode = state.playbackMode
            layout.volumeSlider.doubleValue = state.volume
            playbackController.volume = Float(state.volume)
        }
        applyPlaybackMode()
    }

    @objc private func toggleVolumePopover() {
        layout.toggleVolumePopover()
    }

    @objc private func volumeChanged() {
        playbackController.volume = Float(layout.volumeSlider.doubleValue)
        scheduleVolumeSave()
    }

    /// 拖动音量时防抖落库，避免每个 tick 都写 SQLite。
    func scheduleVolumeSave() {
        volumeSaveTimer?.invalidate()
        volumeSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            try? playerStateRepository.updateVolume(layout.volumeSlider.doubleValue)
        }
    }

    private func applyPlaybackMode() {
        layout.setPlaybackMode(playbackMode)
        if playbackMode != .shuffle {
            shuffleHistory.removeAll()
        } else if let index = currentTrackIndex, tracks.indices.contains(index) {
            shuffleHistory = [index]
        }
    }

    func resetShuffleHistory(for index: Int) {
        guard playbackMode == .shuffle, tracks.indices.contains(index) else {
            return
        }
        shuffleHistory = [index]
    }

    private static func configureWindowChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
    }
}

extension PlayerWindowController: NSSearchFieldDelegate {
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        guard sender === layout.searchField else {
            return
        }
        sender.stringValue = ""
        searchKeyword = ""
        reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
    }
}

extension PlayerWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        scheduleWindowFrameSave()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleWindowFrameSave()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        saveCurrentPlaybackState()
    }
}
