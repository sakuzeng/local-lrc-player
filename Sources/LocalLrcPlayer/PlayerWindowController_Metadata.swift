import AppKit

/// 「写入元数据」的 UI 接线：曲目行右键写单首，播放菜单批量写当前列表。
/// 这是唯一会改用户音乐文件的功能,所以一律手动触发 + 先弹确认 + 写前备份(见 MetadataWriter)。
/// 正在播放的那首跳过:AVPlayer 正握着文件句柄,替换掉会让 seek 落到旧内容上。
extension PlayerWindowController {
    private static let writableExtensions: Set<String> = ["mp3", "flac", "m4a"]

    /// 曲目行右键：写这一首。行号放 tag 里带过去，菜单关掉后 clickedRow 会失效。
    func appendMetadataItems(to menu: NSMenu, forRow row: Int) {
        guard tracks.indices.contains(row) else {
            return
        }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "写入元数据…", action: #selector(writeMetadataFromContextMenu(_:)), keyEquivalent: "")
        item.target = self
        item.tag = row
        item.isEnabled = !metadataWriteService.isRunning
        menu.addItem(item)
    }

    @objc private func writeMetadataFromContextMenu(_ sender: NSMenuItem) {
        writeMetadata(forRow: sender.tag)
    }

    @objc func writeMetadataForSelectedTrack() {
        guard let row = trackListDataSource.userSelectedTrackIndex ?? trackListDataSource.indexOfSelectedTrack(),
              tracks.indices.contains(row) else {
            showTransientStatus("请先在列表里选中一首歌")
            return
        }
        writeMetadata(for: [tracks[row]], isBatch: false)
    }

    func writeMetadata(forRow row: Int) {
        guard tracks.indices.contains(row) else {
            return
        }
        writeMetadata(for: [tracks[row]], isBatch: false)
    }

    /// 批量：当前列表里所有支持的格式。
    @objc func writeMetadataForCurrentPlaylist() {
        writeMetadata(for: tracks, isBatch: true)
    }

    @objc func stopMetadataWriting() {
        metadataWriteService.cancel()
        showTransientStatus("正在停止写入元数据…")
    }

    var isWritingMetadata: Bool {
        metadataWriteService.isRunning
    }

    private func writeMetadata(for candidates: [MusicTrack], isBatch: Bool) {
        guard !metadataWriteService.isRunning else {
            showTransientStatus("已有写入任务在进行中")
            return
        }

        let playingURL = playingTrackURL
        var skippedPlaying = 0
        var skippedFormat = 0
        let targets = candidates.filter { track in
            guard Self.writableExtensions.contains(track.audioURL.pathExtension.lowercased()) else {
                skippedFormat += 1
                return false
            }
            if let playingURL, TrackListDataSource.matchesTrackURL(track.audioURL, playingURL) {
                skippedPlaying += 1
                return false
            }
            return true
        }

        guard !targets.isEmpty else {
            let reason = skippedPlaying > 0 ? "这首正在播放，先切歌或暂停后再试" : "所选歌曲的格式暂不支持写入（仅 mp3 / flac / m4a）"
            showTransientStatus(reason, restoringAfter: 5)
            return
        }

        guard confirmWrite(targets: targets, skippedPlaying: skippedPlaying, skippedFormat: skippedFormat, isBatch: isBatch) else {
            return
        }

        setLyricButtonsEnabled(false)
        AppLog.library.notice("开始写入元数据：\(targets.count, privacy: .public) 首")
        metadataWriteService.run(
            tracks: targets,
            progress: { [weak self] index, track in
                self?.layout.statusLabel.stringValue = "正在写入元数据 \(index + 1)/\(targets.count)：\(track.displayName)"
            },
            completion: { [weak self] summary in
                self?.finishMetadataWriting(summary, skippedPlaying: skippedPlaying, skippedFormat: skippedFormat)
            }
        )
    }

    private func confirmWrite(targets: [MusicTrack], skippedPlaying: Int, skippedFormat: Int, isBatch: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = isBatch ? "为 \(targets.count) 首歌写入元数据？" : "写入元数据：\(targets[0].displayName)"
        var lines = [
            "把歌名、歌手、专辑、封面和歌词写进音频文件本身，方便在其他播放器和设备上正确显示。",
            "",
            "只补空着的字段，已有内容不会被覆盖。",
            "每个文件写入前都会完整备份到 App 支持目录的 MetadataBackups 文件夹。"
        ]
        if skippedPlaying > 0 {
            lines.append("跳过正在播放的 \(skippedPlaying) 首。")
        }
        if skippedFormat > 0 {
            lines.append("跳过 \(skippedFormat) 首不支持的格式（仅 mp3 / flac / m4a）。")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "写入")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 文件菜单入口：看看备份占了多少，顺手清掉。
    @objc func manageMetadataBackups() {
        let usage = MetadataWriter.backupUsage()
        let alert = NSAlert()
        alert.messageText = "元数据备份"
        if usage.count == 0 {
            alert.informativeText = "目前没有备份文件。\n\n写入元数据时会先把原文件完整备份到 App 支持目录的 MetadataBackups 文件夹，同一首歌只保留最新一份，超过 \(MetadataWriter.backupRetentionDays) 天或总量超过 1 GB 的旧备份会自动清理。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        let size = ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file)
        alert.informativeText = "共 \(usage.count) 份备份，占用 \(size)。\n\n同一首歌只保留最新一份，超过 \(MetadataWriter.backupRetentionDays) 天或总量超过 1 GB 的旧备份会自动清理。确认写入结果无误后可以全部删除。"
        alert.addButton(withTitle: "全部删除")
        alert.addButton(withTitle: "打开文件夹")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try MetadataWriter.clearAllBackups()
                showTransientStatus("已删除 \(usage.count) 份元数据备份，释放 \(size)")
            } catch {
                showTransientStatus("删除备份失败：\(error.localizedDescription)", restoringAfter: 5)
            }
        case .alertSecondButtonReturn:
            if let directory = try? MetadataWriter.backupDirectory() {
                NSWorkspace.shared.open(directory)
            }
        default:
            break
        }
    }

    private func finishMetadataWriting(_ summary: MetadataWriteService.Summary, skippedPlaying: Int, skippedFormat: Int) {
        setLyricButtonsEnabled(true)
        MetadataWriter.pruneBackups()
        // 写入改了文件与索引，让列表重新读一遍歌名/歌手。
        reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
        syncQueueBadges()
        updateControlState()
        showTransientStatus("元数据写入完成：\(summary.text)", restoringAfter: 6)
        AppLog.library.notice("元数据写入结束：\(summary.text, privacy: .public)")

        guard !summary.failed.isEmpty || summary.written.count > 1 else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "元数据写入完成"
        var lines = [summary.text]
        if !summary.written.isEmpty {
            lines.append("")
            lines.append("已补写：")
            for outcome in summary.written.prefix(10) {
                lines.append("· \(outcome.track.displayName)（\(outcome.writtenFields.joined(separator: "、"))）")
            }
            if summary.written.count > 10 {
                lines.append("…… 另有 \(summary.written.count - 10) 首")
            }
        }
        if !summary.failed.isEmpty {
            lines.append("")
            lines.append("失败：")
            for outcome in summary.failed.prefix(5) {
                lines.append("· \(outcome.track.displayName)：\(outcome.error?.localizedDescription ?? "未知错误")")
            }
        }
        lines.append("")
        lines.append("原文件已备份在 App 支持目录的 MetadataBackups 文件夹。")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开备份文件夹")
        if alert.runModal() == .alertSecondButtonReturn, let directory = try? MetadataWriter.backupDirectory() {
            NSWorkspace.shared.open(directory)
        }
    }
}
