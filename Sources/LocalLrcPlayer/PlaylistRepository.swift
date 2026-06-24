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
            sql += " ORDER BY pt.sort_order ASC, t.file_name COLLATE NOCASE ASC;"

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

    func reorderMasterPlaylistByFileName(db: OpaquePointer) throws {
        let selectSQL = """
        SELECT pt.track_id
        FROM playlist_tracks pt
        JOIN tracks t ON t.id = pt.track_id
        WHERE pt.playlist_id = ?
        ORDER BY t.file_name COLLATE NOCASE ASC;
        """
        let select = try database.prepare(db, sql: selectSQL)
        defer { sqlite3_finalize(select) }
        sqlite3_bind_int64(select, 1, MasterPlaylist.id)

        var trackIds: [Int64] = []
        while sqlite3_step(select) == SQLITE_ROW {
            trackIds.append(sqlite3_column_int64(select, 0))
        }

        let updateSQL = """
        UPDATE playlist_tracks
        SET sort_order = ?
        WHERE playlist_id = ? AND track_id = ?;
        """
        let update = try database.prepare(db, sql: updateSQL)
        defer { sqlite3_finalize(update) }

        for (index, trackId) in trackIds.enumerated() {
            sqlite3_reset(update)
            sqlite3_clear_bindings(update)
            sqlite3_bind_int64(update, 1, Int64(index + 1))
            sqlite3_bind_int64(update, 2, MasterPlaylist.id)
            sqlite3_bind_int64(update, 3, trackId)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
