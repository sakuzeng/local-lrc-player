import AppKit

/// 自建播放列表：当前查看的列表存在控制器里并记进 player_state.current_playlist_id，重启后回到上次的列表。
/// 列表顶栏的列表按钮弹菜单切换 / 新建 / 重命名 / 删除；曲目行右键「加入播放列表 ▸」按成员关系打勾切换，
/// 查看自建列表时再给「从当前列表移除」。数据在 playlists / playlist_tracks，走 PlaylistRepository。
extension PlayerWindowController {
    struct PlaylistMembershipAction {
        let playlistId: Int64
        let playlistName: String
        let trackId: Int64
    }

    var isViewingMasterPlaylist: Bool {
        currentPlaylistId == MasterPlaylist.id
    }

    private var playlistRepository: PlaylistRepository {
        trackRepository.playlistRepository
    }

    // MARK: - 顶栏列表菜单

    @objc func showPlaylistMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let playlists = (try? playlistRepository.allPlaylists()) ?? []
        for playlist in playlists {
            let item = NSMenuItem(title: playlist.name, action: #selector(playlistChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = playlist
            item.state = playlist.id == currentPlaylistId ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let create = NSMenuItem(title: "新建播放列表…", action: #selector(createPlaylistFromMenu), keyEquivalent: "")
        create.target = self
        menu.addItem(create)
        if !isViewingMasterPlaylist {
            let rename = NSMenuItem(title: "重命名「\(currentPlaylistName)」…", action: #selector(renameCurrentPlaylist), keyEquivalent: "")
            rename.target = self
            menu.addItem(rename)
            let delete = NSMenuItem(title: "删除「\(currentPlaylistName)」…", action: #selector(deleteCurrentPlaylist), keyEquivalent: "")
            delete.target = self
            menu.addItem(delete)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func playlistChosen(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? PlaylistRecord else {
            return
        }
        selectPlaylist(playlist)
    }

    /// 启动时在恢复上次曲目之前调：先站到上次的列表上，再按 last_track_id 在这个列表里找歌。
    /// 列表已被删就回「全部」并把状态修正掉。
    func restoreCurrentPlaylistSelection() {
        guard let state = try? playerStateRepository.playbackState(), state.currentPlaylistId != MasterPlaylist.id else {
            currentPlaylistId = MasterPlaylist.id
            currentPlaylistName = "全部"
            return
        }
        if let playlist = ((try? playlistRepository.allPlaylists()) ?? []).first(where: { $0.id == state.currentPlaylistId }) {
            currentPlaylistId = playlist.id
            currentPlaylistName = playlist.name
        } else {
            currentPlaylistId = MasterPlaylist.id
            currentPlaylistName = "全部"
            try? playerStateRepository.updateCurrentPlaylist(id: MasterPlaylist.id)
        }
    }

    func selectPlaylist(_ playlist: PlaylistRecord) {
        currentPlaylistId = playlist.id
        currentPlaylistName = playlist.name
        try? playerStateRepository.updateCurrentPlaylist(id: playlist.id)
        // 正在播放的歌不在新列表里时 currentTrackIndex 会清空，播放继续，切歌从新列表算。
        reloadCurrentPlaylistKeepingPlayback()
        showTransientStatus(
            isViewingMasterPlaylist
                ? "已切换到全部歌曲（\(tracks.count) 首）"
                : "已切换到播放列表「\(playlist.name)」（\(tracks.count) 首）"
        )
    }

    @objc func createPlaylistFromMenu() {
        guard let name = promptForPlaylistName(title: "新建播放列表", message: "给这个列表起个名字。", defaultValue: "") else {
            return
        }
        do {
            let playlist = try playlistRepository.createPlaylist(name: name)
            AppLog.library.notice("新建播放列表 \(name, privacy: .public)")
            selectPlaylist(playlist)
        } catch {
            presentPlaylistError("新建播放列表失败", error)
        }
    }

    @objc func renameCurrentPlaylist() {
        guard !isViewingMasterPlaylist else {
            return
        }
        guard let name = promptForPlaylistName(title: "重命名播放列表", message: "", defaultValue: currentPlaylistName),
              name != currentPlaylistName else {
            return
        }
        do {
            try playlistRepository.renamePlaylist(id: currentPlaylistId, name: name)
            currentPlaylistName = name
            updateControlState()
            showTransientStatus("已重命名为「\(name)」")
        } catch {
            presentPlaylistError("重命名失败", error)
        }
    }

    @objc func deleteCurrentPlaylist() {
        guard !isViewingMasterPlaylist else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除播放列表「\(currentPlaylistName)」？"
        alert.informativeText = "只删除这个列表本身，不会删除任何歌曲文件，歌曲仍在「全部」里。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let name = currentPlaylistName
        do {
            try playlistRepository.deletePlaylist(id: currentPlaylistId)
            AppLog.library.notice("删除播放列表 \(name, privacy: .public)")
            selectPlaylist(PlaylistRecord(id: MasterPlaylist.id, name: "全部", isSystem: true))
            showTransientStatus("已删除播放列表「\(name)」")
        } catch {
            presentPlaylistError("删除播放列表失败", error)
        }
    }

    // MARK: - 曲目行右键

    func appendPlaylistItems(to menu: NSMenu, forRow row: Int) {
        guard tracks.indices.contains(row), let trackId = tracks[row].id else {
            return
        }
        let playlists = ((try? playlistRepository.allPlaylists()) ?? []).filter { !$0.isSystem }
        let memberships = (try? playlistRepository.playlistIds(containing: trackId)) ?? []
        if menu.numberOfItems > 0 {
            menu.addItem(.separator())
        }

        let submenu = NSMenu()
        for playlist in playlists {
            let item = NSMenuItem(title: playlist.name, action: #selector(togglePlaylistMembership(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = PlaylistMembershipAction(playlistId: playlist.id, playlistName: playlist.name, trackId: trackId)
            item.state = memberships.contains(playlist.id) ? .on : .off
            submenu.addItem(item)
        }
        if !playlists.isEmpty {
            submenu.addItem(.separator())
        }
        let createAndAdd = NSMenuItem(title: "新建播放列表并加入…", action: #selector(createPlaylistAndAdd(_:)), keyEquivalent: "")
        createAndAdd.target = self
        createAndAdd.representedObject = NSNumber(value: trackId)
        submenu.addItem(createAndAdd)

        let addItem = NSMenuItem(title: "加入播放列表", action: nil, keyEquivalent: "")
        addItem.submenu = submenu
        menu.addItem(addItem)

        if !isViewingMasterPlaylist {
            let remove = NSMenuItem(title: "从「\(currentPlaylistName)」移除", action: #selector(removeFromCurrentPlaylist(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = NSNumber(value: trackId)
            menu.addItem(remove)
        }
    }

    @objc private func togglePlaylistMembership(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PlaylistMembershipAction else {
            return
        }
        do {
            if sender.state == .on {
                try playlistRepository.removeTrack(trackId: action.trackId, fromPlaylist: action.playlistId)
                showTransientStatus("已从「\(action.playlistName)」移除")
            } else {
                try playlistRepository.addTrack(trackId: action.trackId, toPlaylist: action.playlistId)
                showTransientStatus("已加入「\(action.playlistName)」")
            }
            if action.playlistId == currentPlaylistId {
                reloadCurrentPlaylistKeepingPlayback()
            }
        } catch {
            presentPlaylistError("更新播放列表失败", error)
        }
    }

    @objc private func createPlaylistAndAdd(_ sender: NSMenuItem) {
        guard let trackId = (sender.representedObject as? NSNumber)?.int64Value,
              let name = promptForPlaylistName(title: "新建播放列表", message: "新列表会包含这首歌。", defaultValue: "") else {
            return
        }
        do {
            let playlist = try playlistRepository.createPlaylist(name: name)
            try playlistRepository.addTrack(trackId: trackId, toPlaylist: playlist.id)
            AppLog.library.notice("新建播放列表 \(name, privacy: .public) 并加入一首")
            showTransientStatus("已新建「\(name)」并加入这首歌")
        } catch {
            presentPlaylistError("新建播放列表失败", error)
        }
    }

    @objc private func removeFromCurrentPlaylist(_ sender: NSMenuItem) {
        guard !isViewingMasterPlaylist, let trackId = (sender.representedObject as? NSNumber)?.int64Value else {
            return
        }
        do {
            try playlistRepository.removeTrack(trackId: trackId, fromPlaylist: currentPlaylistId)
            reloadCurrentPlaylistKeepingPlayback()
            showTransientStatus("已从「\(currentPlaylistName)」移除")
        } catch {
            presentPlaylistError("移除失败", error)
        }
    }

    // MARK: - 助手

    private func reloadCurrentPlaylistKeepingPlayback() {
        reloadMasterPlaylist(restoreLastSession: false, preserveTrackURL: playingTrackURL)
        syncQueueBadges()
        updateControlState()
    }

    private func promptForPlaylistName(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "播放列表名称"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func presentPlaylistError(_ title: String, _ error: Error) {
        AppLog.library.error("\(title, privacy: .public)：\(error.localizedDescription, privacy: .public)")
        showTransientStatus("\(title)：\(error.localizedDescription)", restoringAfter: 5)
    }
}
