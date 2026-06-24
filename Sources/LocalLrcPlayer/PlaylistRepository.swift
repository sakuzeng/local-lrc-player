import Foundation
import SQLite3

final class PlaylistRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func masterPlaylistTracks(
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
            if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            sqlite3_bind_int64(statement, bindIndex, MasterPlaylist.id)
            bindIndex += 1

            if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pattern = "%\(keyword.trimmingCharacters(in: .whitespacesAndNewlines))%"
                sqlite3_bind_text(statement, bindIndex, pattern, -1, Self.sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(statement, bindIndex, pattern, -1, Self.sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(statement, bindIndex, pattern, -1, Self.sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(statement, bindIndex, pattern, -1, Self.sqliteTransient)
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

    func ensureInMasterPlaylist(db: OpaquePointer, trackId: Int64, addedAt: TimeInterval) throws {
        let checkSQL = """
        SELECT 1 FROM playlist_tracks
        WHERE playlist_id = ? AND track_id = ?
        LIMIT 1;
        """
        let check = try database.prepare(db, sql: checkSQL)
        defer { sqlite3_finalize(check) }
        sqlite3_bind_int64(check, 1, MasterPlaylist.id)
        sqlite3_bind_int64(check, 2, trackId)
        if sqlite3_step(check) == SQLITE_ROW {
            return
        }

        let maxOrderSQL = """
        SELECT IFNULL(MAX(sort_order), 0) FROM playlist_tracks WHERE playlist_id = ?;
        """
        let maxOrder = try database.prepare(db, sql: maxOrderSQL)
        defer { sqlite3_finalize(maxOrder) }
        sqlite3_bind_int64(maxOrder, 1, MasterPlaylist.id)
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
        sqlite3_bind_int64(insert, 1, MasterPlaylist.id)
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
