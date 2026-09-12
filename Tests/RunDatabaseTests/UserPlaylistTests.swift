import Foundation

/// 自建播放列表：建/加/查/改名/移出/删，系统列表保护，曲目消失后自动退出自建列表。
final class UserPlaylistRepositoryTests {
    private var database: AppDatabase!
    private var libraryRepository: LibraryRepository!
    private var trackRepository: TrackRepository!
    private var playlistRepository: PlaylistRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testCreateAddListRenameRemoveDelete() }
        try runIsolated { try self.testSystemPlaylistAndNamesAreProtected() }
        try runIsolated { try self.testDeletedTrackLeavesUserPlaylist() }
    }

    private func runIsolated(_ work: () throws -> Void) throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
            database = nil
        }
        database = try AppDatabase(fileURL: tempRoot.appendingPathComponent("test.sqlite"))
        libraryRepository = LibraryRepository(database: database)
        playlistRepository = PlaylistRepository(database: database)
        trackRepository = TrackRepository(database: database, playlistRepository: playlistRepository)
        try work()
    }

    /// 建一个含 a/b 两首歌的库并 sync，返回总列表里的记录（按名字排序）。
    private func seedLibrary() throws -> (folder: URL, a: TrackRecord, b: TrackRecord) {
        let folder = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("song-a".utf8).write(to: folder.appendingPathComponent("a.mp3"))
        try Data("song-b".utf8).write(to: folder.appendingPathComponent("b.mp3"))
        let library = try libraryRepository.registerLibrary(at: folder)
        _ = try trackRepository.sync(libraryId: library.id, folderURL: folder)
        let master = try playlistRepository.masterPlaylistTracks()
        try assertEqual(master.count, 2)
        return (folder, master[0], master[1])
    }

    private func testCreateAddListRenameRemoveDelete() throws {
        let seed = try seedLibrary()
        try assertEqual(try playlistRepository.allPlaylists().map(\.name), ["全部"])

        let playlist = try playlistRepository.createPlaylist(name: "  夜跑  ")
        try assertEqual(playlist.name, "夜跑", "name is trimmed")
        try assertTrue(!playlist.isSystem, "user playlist is not system")
        try assertEqual(try playlistRepository.allPlaylists().map(\.name), ["全部", "夜跑"], "system first")

        try playlistRepository.addTrack(trackId: seed.b.id, toPlaylist: playlist.id)
        try playlistRepository.addTrack(trackId: seed.b.id, toPlaylist: playlist.id)
        try playlistRepository.addTrack(trackId: seed.a.id, toPlaylist: playlist.id)
        let members = try playlistRepository.tracks(inPlaylist: playlist.id)
        try assertEqual(members.map(\.id), [seed.b.id, seed.a.id], "insertion order, no duplicates")
        try assertTrue(try playlistRepository.playlistIds(containing: seed.a.id).contains(playlist.id), "membership lookup")
        try assertEqual(try playlistRepository.tracks(inPlaylist: playlist.id, keyword: "a.mp3").count, 1, "keyword filter within playlist")
        try assertEqual(try playlistRepository.masterPlaylistTracks().count, 2, "master untouched")

        try playlistRepository.renamePlaylist(id: playlist.id, name: "晨跑")
        try assertEqual(try playlistRepository.allPlaylists().last?.name, "晨跑")

        try playlistRepository.removeTrack(trackId: seed.b.id, fromPlaylist: playlist.id)
        try assertEqual(try playlistRepository.tracks(inPlaylist: playlist.id).map(\.id), [seed.a.id])

        try playlistRepository.deletePlaylist(id: playlist.id)
        try assertEqual(try playlistRepository.allPlaylists().map(\.name), ["全部"])
        try assertEqual(try playlistRepository.tracks(inPlaylist: playlist.id).count, 0, "cascade clears playlist_tracks")
        try assertEqual(try playlistRepository.masterPlaylistTracks().count, 2, "deleting a playlist never deletes tracks")
    }

    private func testSystemPlaylistAndNamesAreProtected() throws {
        _ = try seedLibrary()
        try assertThrows { try playlistRepository.deletePlaylist(id: MasterPlaylist.id) }
        try assertThrows { try playlistRepository.renamePlaylist(id: MasterPlaylist.id, name: "x") }
        try assertThrows { try playlistRepository.createPlaylist(name: "   ") }
        _ = try playlistRepository.createPlaylist(name: "Chill")
        try assertThrows { try playlistRepository.createPlaylist(name: "chill") }
        try assertThrows { try playlistRepository.createPlaylist(name: "全部") }
        try assertEqual(try playlistRepository.allPlaylists().count, 2)
    }

    private func testDeletedTrackLeavesUserPlaylist() throws {
        let seed = try seedLibrary()
        let playlist = try playlistRepository.createPlaylist(name: "收藏")
        try playlistRepository.addTrack(trackId: seed.a.id, toPlaylist: playlist.id)

        try FileManager.default.removeItem(at: seed.a.audioURL)
        let libraries = try libraryRepository.allLibraries()
        _ = try trackRepository.syncAll(libraries: libraries)

        try assertEqual(try playlistRepository.masterPlaylistTracks().count, 1)
        try assertEqual(try playlistRepository.tracks(inPlaylist: playlist.id).count, 0, "cascade removes the vanished track")
    }

    private func assertThrows(_ work: () throws -> Void, file: String = #file, line: Int = #line) throws {
        do {
            try work()
        } catch {
            return
        }
        throw TestFailure.message("\((file as NSString).lastPathComponent):\(line) expected an error")
    }
}
