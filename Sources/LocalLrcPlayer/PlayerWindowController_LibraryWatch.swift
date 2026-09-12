import AppKit

/// 音乐文件夹变化的自动同步：目录事件 → 静默 2s → 后台增量 sync → 主线程刷新列表。
/// 与 ⌘R 的区别只在 sync 跑在后台队列，扫描/哈希不卡 UI；数据库访问本就串行，线程安全。
extension PlayerWindowController {
    func bindLibraryWatcher() {
        libraryWatcher.onChange = { [weak self] in
            self?.autoSyncLibraries()
        }
    }

    /// 库集合变了（启动、添加、移除）或一轮自动同步结束后调；幂等。
    /// 同步结束后再对一次，是为了把被拔掉又插回的卷重新盯上。
    func updateLibraryWatchers() {
        let libraries = (try? libraryRepository.allLibraries()) ?? []
        libraryWatcher.watch(folders: libraries.map(\.url))
    }

    func autoSyncLibraries() {
        // 进行中再来事件就记一笔，这轮结束再跑，避免两轮 sync 交错。
        guard !isAutoSyncInProgress else {
            autoSyncRequestedWhileRunning = true
            return
        }
        guard let libraries = try? libraryRepository.allLibraries(), !libraries.isEmpty else {
            return
        }
        isAutoSyncInProgress = true
        AppLog.library.notice("目录变化触发自动同步（\(libraries.count, privacy: .public) 个音乐库）")
        showTransientStatus("检测到音乐文件夹变化，正在同步…", restoringAfter: 30)
        LibraryBookmarkStore.activateLibraries(libraries)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }
            let result = Result { try self.trackRepository.syncAll(libraries: libraries) }
            DispatchQueue.main.async {
                self.finishAutoSync(libraries: libraries, result: result)
            }
        }
    }

    private func finishAutoSync(libraries: [LibraryRecord], result: Result<TrackSyncSummary, Error>) {
        isAutoSyncInProgress = false

        switch result {
        case .success(let summary):
            for library in libraries {
                try? libraryRepository.markScanned(libraryId: library.id)
            }
            let hadPlayingTrack = playingTrackURL != nil
            reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
            // 正在播放的文件被删了：AVPlayer 还握着已 unlink 的文件能继续放，但列表里已经没有这首，
            // 与设置里移除文件夹的处理一致，停下来清掉。
            if hadPlayingTrack, currentTrackIndex == nil {
                playbackController.stop()
                playingTrackURL = nil
                playingTrackId = nil
                lrcLines = []
                layout.lyricsView.showPlaceholder("双击左侧歌曲开始播放")
                layout.setPlayButtonShowsPause(false)
                publishNowPlayingState()
            }
            let changes = summary.inserted + summary.updated + summary.removed + summary.deduplicated
            AppLog.library.notice("自动同步完成：共 \(summary.total, privacy: .public) 首，+\(summary.inserted, privacy: .public)/~\(summary.updated, privacy: .public)/-\(summary.removed, privacy: .public)，去重 \(summary.deduplicated, privacy: .public)")
            showTransientStatus(
                changes > 0
                    ? "文件夹有变化，已" + statusSummary(
                        total: summary.total,
                        missingLyrics: summary.missingLyrics,
                        inserted: summary.inserted,
                        updated: summary.updated,
                        removed: summary.removed,
                        deduplicated: summary.deduplicated
                    )
                    : "音乐库已是最新（共 \(summary.total) 首）",
                restoringAfter: 4
            )
            updateControlState()
            syncMenuBarLyrics()
        case .failure(let error):
            AppLog.library.error("自动同步失败：\(error.localizedDescription, privacy: .public)")
            showTransientStatus("自动同步失败：\(error.localizedDescription)", restoringAfter: 6)
        }

        updateLibraryWatchers()
        if autoSyncRequestedWhileRunning {
            autoSyncRequestedWhileRunning = false
            autoSyncLibraries()
        }
    }
}
