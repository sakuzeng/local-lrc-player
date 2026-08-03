import AppKit

extension PlayerWindowController {
    func bootstrapLibraries(restoreLastSession: Bool) {
        do {
            let libraries = try libraryRepository.allLibraries()
            guard !libraries.isEmpty else {
                updateControlState()
                return
            }

            activeLibrary = try libraryRepository.activeLibrary() ?? libraries.last
            LibraryBookmarkStore.activateLibraries(libraries)
            layout.statusLabel.stringValue = "正在同步音乐库…"
            let summary = try trackRepository.syncAll(libraries: libraries)
            for library in libraries {
                LibraryBookmarkStore.persistBookmarkIfNeeded(for: library.url)
            }
            reloadMasterPlaylist(restoreLastSession: restoreLastSession, preserveTrackURL: nil)
            layout.statusLabel.stringValue = statusSummary(
                total: summary.total,
                missingLyrics: summary.missingLyrics,
                inserted: summary.inserted,
                updated: summary.updated,
                removed: summary.removed,
                deduplicated: summary.deduplicated
            )
            updateControlState()

            // 音乐库同步完才有 tracks 可 JOIN；延一帧避开启动时的窗口恢复动画。
            DispatchQueue.main.async { [weak self] in
                self?.presentOnThisDayMemoryIfAvailable()
            }
        } catch {
            layout.statusLabel.stringValue = "数据库初始化失败：\(error.localizedDescription)"
        }
    }

    func registerAndSyncLibrary(
        _ library: LibraryRecord,
        restoreLastSession: Bool,
        preserveTrackURL: URL? = nil
    ) {
        do {
            activeLibrary = library
            LibraryBookmarkStore.activateAccess(for: library.url)
            layout.statusLabel.stringValue = "正在同步音乐库…"

            let summary = try trackRepository.sync(libraryId: library.id, folderURL: library.url)
            try libraryRepository.markScanned(libraryId: library.id)
            LibraryBookmarkStore.persistBookmarkIfNeeded(for: library.url)

            reloadMasterPlaylist(restoreLastSession: restoreLastSession, preserveTrackURL: preserveTrackURL)

            if tracks.isEmpty {
                layout.statusLabel.stringValue = "总播放列表为空（所选目录没有支持的音乐文件）"
                layout.lyricsView.showPlaceholder("未找到音乐文件")
                currentTrackIndex = nil
                playingTrackURL = nil
                playingTrackId = nil
                playbackController.stop()
                lrcLines = []
            } else {
                layout.statusLabel.stringValue = statusSummary(
                    total: summary.total,
                    missingLyrics: summary.missingLyrics,
                    inserted: summary.inserted,
                    updated: summary.updated,
                    removed: summary.removed,
                    deduplicated: summary.deduplicated
                )
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

    func reloadMasterPlaylist(restoreLastSession: Bool, preserveTrackURL: URL?) {
        do {
            let keyword = searchKeyword.isEmpty ? nil : searchKeyword
            let records = try trackRepository.masterPlaylistTracks(keyword: keyword)
            tracks = records.map { $0.asMusicTrack() }
            updatePlayingTrackInList(preferredURL: preserveTrackURL, scrollToVisible: true)
            pruneShuffleHistory()

            if restoreLastSession, playingTrackURL == nil {
                let state = try playerStateRepository.playbackState()
                if let lastTrackId = state.lastTrackId,
                   let index = tracks.firstIndex(where: { $0.id == lastTrackId }) {
                    restoreLastSelection(at: index, position: state.lastPosition)
                    return
                }
            }

            if playingTrackURL == nil, preserveTrackURL == nil, !tracks.isEmpty, currentTrackIndex == nil {
                trackListDataSource.selectRow(0)
                layout.lyricsView.showPlaceholder("双击左侧歌曲开始播放")
            }
        } catch {
            layout.statusLabel.stringValue = "读取歌曲列表失败：\(error.localizedDescription)"
        }
    }

    /// 刷新/搜索后把播放行重新对上号：先按路径找，路径失配（例如在 Finder 里改了文件名）再按
    /// track id 找回来并把路径纠正到新名字。都找不到就清空 currentTrackIndex ——
    /// 留着旧索引会指到列表里的另一首歌，甚至在列表变短时越界崩溃。
    func updatePlayingTrackInList(preferredURL: URL?, scrollToVisible: Bool) {
        if let preferredURL,
           let index = tracks.firstIndex(where: { TrackListDataSource.matchesTrackURL($0.audioURL, preferredURL) }) {
            playingTrackURL = tracks[index].audioURL
            currentTrackIndex = index
        } else if let playingTrackURL,
                  let index = tracks.firstIndex(where: { TrackListDataSource.matchesTrackURL($0.audioURL, playingTrackURL) }) {
            currentTrackIndex = index
        } else if let playingTrackId,
                  let index = tracks.firstIndex(where: { $0.id == playingTrackId }) {
            playingTrackURL = tracks[index].audioURL
            currentTrackIndex = index
        } else {
            currentTrackIndex = nil
        }

        trackListDataSource.playingTrackURL = playingTrackURL
        trackListDataSource.tracks = tracks

        if scrollToVisible, playingTrackURL != nil {
            trackListDataSource.scrollToPlayingTrack()
        }
    }

    @discardableResult
    func highlightTrackInList(audioURL: URL?) -> Bool {
        guard let audioURL else {
            return false
        }
        updatePlayingTrackInList(preferredURL: audioURL, scrollToVisible: true)
        return playingTrackURL != nil
    }

    func pruneShuffleHistory() {
        shuffleHistory = shuffleHistory.filter { tracks.indices.contains($0) }
        if playbackMode == .shuffle,
           shuffleHistory.isEmpty,
           let index = currentTrackIndex,
           tracks.indices.contains(index) {
            shuffleHistory = [index]
        }
    }

    func syncPlayingTrackVisuals(scrollToVisible: Bool = false) {
        trackListDataSource.playingTrackURL = playingTrackURL
        trackListDataSource.refreshRowAppearance()
        if scrollToVisible {
            trackListDataSource.scrollToPlayingTrack()
        }
    }

    func refreshAllLibraries(preserveTrackURL: URL?) {
        do {
            let libraries = try libraryRepository.allLibraries()
            guard !libraries.isEmpty else {
                layout.statusLabel.stringValue = "请先选择音乐文件夹"
                return
            }

            layout.statusLabel.stringValue = "正在刷新全部音乐库…"
            LibraryBookmarkStore.activateLibraries(libraries)
            let summary = try trackRepository.syncAll(libraries: libraries)
            for library in libraries {
                try libraryRepository.markScanned(libraryId: library.id)
                LibraryBookmarkStore.persistBookmarkIfNeeded(for: library.url)
            }
            reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: preserveTrackURL)
            layout.statusLabel.stringValue = statusSummary(
                total: summary.total,
                missingLyrics: summary.missingLyrics,
                inserted: summary.inserted,
                updated: summary.updated,
                removed: summary.removed,
                deduplicated: summary.deduplicated
            )
        } catch {
            layout.statusLabel.stringValue = "刷新目录失败：\(error.localizedDescription)"
        }
    }

    func handleLibraryRemoved() {
        do {
            let libraries = try libraryRepository.allLibraries()
            activeLibrary = try libraryRepository.activeLibrary()

            if libraries.isEmpty {
                tracks = []
                trackListDataSource.tracks = []
                currentTrackIndex = nil
                playingTrackURL = nil
                playingTrackId = nil
                playbackController.stop()
                lrcLines = []
                layout.lyricsView.showPlaceholder("请添加音乐文件夹")
                layout.statusLabel.stringValue = "请添加音乐文件夹（⌘, 打开设置）"
            } else {
                let hadPlayingTrack = playingTrackURL != nil
                reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
                // reloadMasterPlaylist 已按路径/id 重新认过播放行；仍认不回来才算这首歌真的没了。
                if hadPlayingTrack, currentTrackIndex == nil {
                    playbackController.stop()
                    playingTrackURL = nil
                    playingTrackId = nil
                    lrcLines = []
                    layout.lyricsView.showPlaceholder("双击左侧歌曲开始播放")
                }
                if !tracks.isEmpty {
                    layout.statusLabel.stringValue = "共 \(tracks.count) 首，双击歌曲开始播放"
                }
            }

            updateControlState()
            syncMenuBarLyrics()
        } catch {
            layout.statusLabel.stringValue = "更新播放列表失败：\(error.localizedDescription)"
        }
    }

    private func statusSummary(
        total: Int,
        missingLyrics: Int,
        inserted: Int,
        updated: Int,
        removed: Int,
        deduplicated: Int
    ) -> String {
        var parts = ["共 \(total) 首"]
        if missingLyrics > 0 {
            parts.append("\(missingLyrics) 首无歌词")
        }
        if inserted + updated + removed + deduplicated > 0 {
            parts.append("同步 +\(inserted)/~\(updated)/-\(removed)")
            if deduplicated > 0 {
                parts.append("去重 \(deduplicated)")
            }
        }
        parts.append("双击歌曲开始播放")
        return parts.joined(separator: "，")
    }
}
