import AppKit

final class PlayerWindowController: NSWindowController {
    var layout: PlayerWindowLayout!
    let trackListDataSource = TrackListDataSource()
    let playbackController = PlaybackController()
    let lyricSearchService = LyricSearchService()
    let libraryRepository = LibraryRepository()
    let trackRepository = TrackRepository()
    let playHistoryRepository = PlayHistoryRepository()
    let playerStateRepository = PlayerStateRepository()
    var menuBarLyricsController: MenuBarLyricsController?
    weak var settingsWindowController: SettingsWindowController?
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
    var restoredPlaybackPosition: TimeInterval?
    var lastSavedPlaybackTick = 0
    var isApplyingProgrammaticSliderUpdate = false

    private var mouseDownMonitor: Any?
    private var keyDownMonitor: Any?
    private var windowToolbar: PlayerWindowToolbar?
    private var windowFrameSaveTimer: Timer?

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
        trackListDataSource.onSelectionChanged = { [weak self] _ in
            self?.resignSearchFieldFocus()
        }
        trackListDataSource.onDoubleClick = { [weak self] row in
            self?.resignSearchFieldFocus()
            self?.playTrack(at: row)
        }

        layout.lyricsView.onMouseDown = { [weak self] in
            self?.resignSearchFieldFocus()
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
        windowToolbar?.updateEnabledState(hasLibrary: hasLibrary)
        layout.playButton.isEnabled = hasTracks
        layout.previousButton.isEnabled = hasTracks
        layout.nextButton.isEnabled = hasTracks
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
