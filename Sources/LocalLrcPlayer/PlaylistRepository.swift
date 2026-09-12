import Foundation
import SQLite3

enum PlaylistRepositoryError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case systemPlaylistProtected

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "播放列表名称不能为空"
        case .duplicateName(let name):
            return "已有同名播放列表「\(name)」"
        case .systemPlaylistProtected:
            return "「全部」是系统列表，不能改名或删除"
        }
    }
}

/// playlists / playlist_tracks：id = 1 是系统总列表「全部」，其余为用户自建。
/// 总列表由 sync 维护（入列 + 重排）；自建列表只由用户操作增删，曲目被删时靠 CASCADE 自动退出。
final class PlaylistRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: 查询

    func masterPlaylistTracks(
        keyword: String? = nil,
        missingLyricsOnly: Bool = false
    ) throws -> [TrackRecord] {
        try tracks(inPlaylist: MasterPlaylist.id, keyword: keyword, missingLyricsOnly: missingLyricsOnly)
    }

    func tracks(
        inPlaylist playlistId: Int64,
        keyword: String? = nil,
        missingLyricsOnly: Bool = false
    ) throws -> [TrackRecord] {
        try database.read { db in
            var sql = """
            SELECT t.id, t.library_id, t.file_path, t.file_name, t.file_mtime, t.file_size,
                   t.title, t.artist, t.album, t.duration, t.has_lyric, t.updated_at, t.content_hash
            FROM playlist_tracks pt
            JOIN tracks t ON t.id = pt.track_id
            WHERE pt.playlist_id = ?
            """
            if missingLyricsOnly {
                sql += " AND t.has_lyric = 0"
            }
            let trimmedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedKeyword.isEmpty {
                sql += """
                 AND (
                    t.file_name LIKE ? COLLATE NOCASE OR
                    IFNULL(t.title, '') LIKE ? COLLATE NOCASE OR
                    IFNULL(t.artist, '') LIKE ? COLLATE NOCASE OR
                    IFNULL(t.album, '') LIKE ? COLLATE NOCASE
                 )
                """
            }
            sql += " ORDER BY pt.sort_order ASC;"

            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }

            var bindIndex: Int32 = 1
            sqlite3_bind_int64(statement, bindIndex, playlistId)
            bindIndex += 1

            if !trimmedKeyword.isEmpty {
                let pattern = "%\(trimmedKeyword)%"
                for _ in 0..<4 {
                    sqlite3_bind_text(statement, bindIndex, pattern, -1, Self.sqliteTransient)
                    bindIndex += 1
                }
            }

            var results: [TrackRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(TrackRecord.read(from: statement))
            }
            return results
        }
    }

    func masterPlaylistCounts() throws -> (total: Int, missingLyrics: Int) {
        try database.read { db in
            try masterPlaylistCounts(db: db)
        }
    }

    func masterPlaylistCounts(db: OpaquePointer) throws -> (total: Int, missingLyrics: Int) {
        let sql = """
        SELECT
            COUNT(*),
            SUM(CASE WHEN t.has_lyric = 0 THEN 1 ELSE 0 END)
        FROM playlist_tracks pt
        JOIN tracks t ON t.id = pt.track_id
        WHERE pt.playlist_id = ?;
        """
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, MasterPlaylist.id)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return (0, 0)
        }
        return (
            total: Int(sqlite3_column_int(statement, 0)),
            missingLyrics: Int(sqlite3_column_int(statement, 1))
        )
    }

    // MARK: 自建列表

    /// 系统列表在前，其余按名字自然排序。
    func allPlaylists() throws -> [PlaylistRecord] {
        try database.read { db in
            let sql = "SELECT id, name, is_system FROM playlists;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            var results: [PlaylistRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(PlaylistRecord(
                    id: sqlite3_column_int64(statement, 0),
                    name: String(cString: sqlite3_column_text(statement, 1)),
                    isSystem: sqlite3_column_int(statement, 2) != 0
                ))
            }
            return results.sorted { lhs, rhs in
                if lhs.isSystem != rhs.isSystem {
                    return lhs.isSystem
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    @discardableResult
    func createPlaylist(name: String) throws -> PlaylistRecord {
        let trimmed = try Self.validated(name)
        return try database.write { db in
            try ensureNameAvailable(db: db, name: trimmed, excluding: nil)
            let sql = "INSERT INTO playlists (name, is_system) VALUES (?, 0);"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, trimmed, -1, Self.sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
            return PlaylistRecord(id: sqlite3_last_insert_rowid(db), name: trimmed, isSystem: false)
        }
    }

    func renamePlaylist(id: Int64, name: String) throws {
        guard id != MasterPlaylist.id else {
            throw PlaylistRepositoryError.systemPlaylistProtected
        }
        let trimmed = try Self.validated(name)
        try database.write { db in
            try ensureNameAvailable(db: db, name: trimmed, excluding: id)
            let sql = "UPDATE playlists SET name = ? WHERE id = ? AND is_system = 0;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, trimmed, -1, Self.sqliteTransient)
            sqlite3_bind_int64(statement, 2, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    /// 只删列表；playlist_tracks 靠 CASCADE 清掉，tracks 不动。
    func deletePlaylist(id: Int64) throws {
        guard id != MasterPlaylist.id else {
            throw PlaylistRepositoryError.systemPlaylistProtected
        }
        try database.write { db in
            let sql = "DELETE FROM playlists WHERE id = ? AND is_system = 0;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    /// 已在列表里就什么都不做；新加的排在末尾。
    func addTrack(trackId: Int64, toPlaylist playlistId: Int64) throws {
        let now = Date().timeIntervalSince1970
        try database.write { db in
            try ensureInPlaylist(db: db, playlistId: playlistId, trackId: trackId, addedAt: now)
        }
    }

    func removeTrack(trackId: Int64, fromPlaylist playlistId: Int64) throws {
        try database.write { db in
            let sql = "DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, playlistId)
            sqlite3_bind_int64(statement, 2, trackId)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    /// 某首歌所在的全部列表 id（含系统列表），右键菜单打勾用。
    func playlistIds(containing trackId: Int64) throws -> Set<Int64> {
        try database.read { db in
            let sql = "SELECT playlist_id FROM playlist_tracks WHERE track_id = ?;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, trackId)
            var ids = Set<Int64>()
            while sqlite3_step(statement) == SQLITE_ROW {
                ids.insert(sqlite3_column_int64(statement, 0))
            }
            return ids
        }
    }

    // MARK: sync 引擎共享

    func ensureInMasterPlaylist(db: OpaquePointer, trackId: Int64, addedAt: TimeInterval) throws {
        try ensureInPlaylist(db: db, playlistId: MasterPlaylist.id, trackId: trackId, addedAt: addedAt)
    }

    private func ensureInPlaylist(db: OpaquePointer, playlistId: Int64, trackId: Int64, addedAt: TimeInterval) throws {
        let checkSQL = """
        SELECT 1 FROM playlist_tracks
        WHERE playlist_id = ? AND track_id = ?
        LIMIT 1;
        """
        let check = try database.prepare(db, sql: checkSQL)
        defer { sqlite3_finalize(check) }
        sqlite3_bind_int64(check, 1, playlistId)
        sqlite3_bind_int64(check, 2, trackId)
        if sqlite3_step(check) == SQLITE_ROW {
            return
        }

        let maxOrderSQL = """
        SELECT IFNULL(MAX(sort_order), 0) FROM playlist_tracks WHERE playlist_id = ?;
        """
        let maxOrder = try database.prepare(db, sql: maxOrderSQL)
        defer { sqlite3_finalize(maxOrder) }
        sqlite3_bind_int64(maxOrder, 1, playlistId)
        var nextOrder: Int64 = 1
        if sqlite3_step(maxOrder) == SQLITE_ROW {
            nextOrder = sqlite3_column_int64(maxOrder, 0) + 1
        }

        let insertSQL = """
        INSERT INTO playlist_tracks (playlist_id, track_id, added_at, sort_order)
        VALUES (?, ?, ?, ?);
        """
        let insert = try database.prepare(db, sql: insertSQL)
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_int64(insert, 1, playlistId)
        sqlite3_bind_int64(insert, 2, trackId)
        sqlite3_bind_double(insert, 3, addedAt)
        sqlite3_bind_int64(insert, 4, nextOrder)
        guard sqlite3_step(insert) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    func reorderMasterPlaylist(db: OpaquePointer) throws {
        let selectSQL = """
        SELECT t.id, t.library_id, t.file_name, t.title, t.artist
        FROM playlist_tracks pt
        JOIN tracks t ON t.id = pt.track_id
        WHERE pt.playlist_id = ?;
        """
        let select = try database.prepare(db, sql: selectSQL)
        defer { sqlite3_finalize(select) }
        sqlite3_bind_int64(select, 1, MasterPlaylist.id)

        var entries: [(trackId: Int64, libraryId: Int64, sortKey: String)] = []
        while sqlite3_step(select) == SQLITE_ROW {
            let trackId = sqlite3_column_int64(select, 0)
            let libraryId = sqlite3_column_int64(select, 1)
            let fileName = String(cString: sqlite3_column_text(select, 2))
            let title = sqlite3_column_type(select, 3) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(select, 3))
            let artist = sqlite3_column_type(select, 4) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(select, 4))
            entries.append((
                trackId: trackId,
                libraryId: libraryId,
                sortKey: Self.playlistSortKey(fileName: fileName, title: title, artist: artist)
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.libraryId != rhs.libraryId {
                return lhs.libraryId < rhs.libraryId
            }
            return lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
        }

        let updateSQL = """
        UPDATE playlist_tracks
        SET sort_order = ?
        WHERE playlist_id = ? AND track_id = ?;
        """
        let update = try database.prepare(db, sql: updateSQL)
        defer { sqlite3_finalize(update) }

        for (index, entry) in entries.enumerated() {
            sqlite3_reset(update)
            sqlite3_clear_bindings(update)
            sqlite3_bind_int64(update, 1, Int64(index + 1))
            sqlite3_bind_int64(update, 2, MasterPlaylist.id)
            sqlite3_bind_int64(update, 3, entry.trackId)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    // MARK: 助手

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlaylistRepositoryError.emptyName
        }
        return trimmed
    }

    private func ensureNameAvailable(db: OpaquePointer, name: String, excluding excludedId: Int64?) throws {
        let sql = "SELECT id FROM playlists WHERE name = ? COLLATE NOCASE LIMIT 1;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, Self.sqliteTransient)
        if sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int64(statement, 0) != excludedId {
            throw PlaylistRepositoryError.duplicateName(name)
        }
    }

    /// 与列表展示一致：优先「歌手 - 歌名」，否则文件名（不含扩展名）；刷新时用系统自然排序。
    private static func playlistSortKey(fileName: String, title: String?, artist: String?) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            if !trimmedArtist.isEmpty {
                return "\(trimmedArtist) - \(trimmedTitle)"
            }
            return trimmedTitle
        }
        return (fileName as NSString).deletingPathExtension
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
