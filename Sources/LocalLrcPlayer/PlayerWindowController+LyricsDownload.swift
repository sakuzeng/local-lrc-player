import AppKit

extension PlayerWindowController {
    @objc func downloadCurrentLyric() {
        guard let index = currentTrackIndex ?? trackListDataSource.selectedTrackIndex(), tracks.indices.contains(index) else {
            layout.statusLabel.stringValue = "请先选择一首歌曲"
            return
        }

        downloadLyric(for: tracks[index], reloadCurrentTrack: true)
    }

    @objc func fillMissingLyrics() {
        let missingTracks: [MusicTrack]
        do {
            missingTracks = try trackRepository.missingLyricTracksInMaster().map { $0.asMusicTrack() }
        } catch {
            layout.statusLabel.stringValue = "读取缺失歌词列表失败：\(error.localizedDescription)"
            return
        }

        guard !missingTracks.isEmpty else {
            layout.statusLabel.stringValue = "总播放列表没有缺失歌词的歌曲"
            return
        }

        layout.statusLabel.stringValue = "开始补全缺失歌词：\(missingTracks.count) 首"
        setLyricButtonsEnabled(false)
        downloadMissingLyrics(missingTracks, index: 0, successCount: 0, failureCount: 0)
    }

    private func downloadMissingLyrics(_ missingTracks: [MusicTrack], index: Int, successCount: Int, failureCount: Int) {
        guard index < missingTracks.count else {
            setLyricButtonsEnabled(true)
            refreshAllLibraries(preserveTrackURL: currentTrackIndex.flatMap { tracks.indices.contains($0) ? tracks[$0].audioURL : nil })
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
                        self.refreshAllLibraries(preserveTrackURL: track.audioURL)
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

    func setLyricButtonsEnabled(_ isEnabled: Bool) {
        layout.setNetEaseCookieButton.isEnabled = isEnabled
        layout.resetNetEaseCookieButton.isEnabled = isEnabled
        layout.downloadCurrentLyricButton.isEnabled = isEnabled && !tracks.isEmpty
        layout.fillMissingLyricsButton.isEnabled = isEnabled && !tracks.isEmpty
    }
}
