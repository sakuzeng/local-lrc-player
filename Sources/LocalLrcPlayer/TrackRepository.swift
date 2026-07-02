import Foundation
import SQLite3

// tracks / library_tracks 表的查询、CRUD 与音乐库删除。
// 文件夹扫描 + 增量 sync 引擎在 TrackRepository_Sync.swift。
// 注: database / playlistRepository 及下方标注"共享"的助手是 internal(非 private),
// 因为 Swift 的 private 是文件级作用域, 同一类型在另一文件里的 extension(sync 引擎)需要访问它们。
final class TrackRepository {
    let database: AppDatabase
    let playlistRepository: PlaylistRepository

    init(database: AppDatabase = .shared, playlistRepository: PlaylistRepository? = nil) {
        self.database = database
        self.playlistRepository = playlistRepository ?? PlaylistRepository(database: database)
    }

    // MARK: 查询

    func masterPlaylistTracks(
        keyword: String? = nil,
        missingLyricsOnly: Bool = false
    ) throws -> [TrackRecord] {
        try playlistRepository.masterPlaylistTracks(keyword: keyword, missingLyricsOnly: missingLyricsOnly)
    }

    func track(id: Int64) throws -> TrackRecord? {
        try database.read { db in
            let sql = """
            SELECT id, library_id, file_path, file_name, file_mtime, file_size,
                   title, artist, album, duration, has_lyric, updated_at, content_hash
            FROM tracks WHERE id = ? LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return TrackRecord.read(from: statement)
        }
    }

    func track(forFilePath path: String) throws -> TrackRecord? {
        try database.read { db in
            let sql = """
            SELECT id, library_id, file_path, file_name, file_mtime, file_size,
                   title, artist, album, duration, has_lyric, updated_at, content_hash
            FROM tracks WHERE file_path = ? LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, path, -1, Self.sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return TrackRecord.read(from: statement)
        }
    }

    func missingLyricTracksInMaster() throws -> [TrackRecord] {
        try masterPlaylistTracks(missingLyricsOnly: true)
    }

    func masterPlaylistCounts() throws -> (total: Int, missingLyrics: Int) {
        try playlistRepository.masterPlaylistCounts()
    }

    // MARK: 音乐库删除

    func removeLibrary(libraryId: Int64) throws -> Set<Int64> {
        try database.write { db in
            var trackIds = Set<Int64>()
            let selectSQL = "SELECT DISTINCT track_id FROM library_tracks WHERE library_id = ?;"
            let select = try database.prepare(db, sql: selectSQL)
            defer { sqlite3_finalize(select) }
            sqlite3_bind_int64(select, 1, libraryId)
            while sqlite3_step(select) == SQLITE_ROW {
                trackIds.insert(sqlite3_column_int64(select, 0))
            }

            let deleteLinksSQL = "DELETE FROM library_tracks WHERE library_id = ?;"
            let deleteLinks = try database.prepare(db, sql: deleteLinksSQL)
            defer { sqlite3_finalize(deleteLinks) }
            sqlite3_bind_int64(deleteLinks, 1, libraryId)
            guard sqlite3_step(deleteLinks) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }

            var deletedTrackIds = Set<Int64>()
            for trackId in trackIds {
                if try shouldDeleteTrack(db: db, trackId: trackId) {
                    try deleteTrack(db: db, trackId: trackId)
                    deletedTrackIds.insert(trackId)
                } else {
                    try repointLibraryIdIfNeeded(db: db, trackId: trackId, removedLibraryId: libraryId)
                    try repointCanonicalPathIfNeeded(db: db, trackId: trackId)
                }
            }

            let deleteLibrarySQL = "DELETE FROM libraries WHERE id = ?;"
            let deleteLibrary = try database.prepare(db, sql: deleteLibrarySQL)
            defer { sqlite3_finalize(deleteLibrary) }
            sqlite3_bind_int64(deleteLibrary, 1, libraryId)
            guard sqlite3_step(deleteLibrary) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }

            try clearPlayerStateIfTracksDeleted(db: db, deletedTrackIds: deletedTrackIds)
            return deletedTrackIds
        }
    }

    func markHasLyric(trackId: Int64, hasLyric: Bool = true) throws {
        try database.write { db in
            try updateHasLyric(db: db, trackId: trackId, hasLyric: hasLyric)
        }
    }

    // MARK: 与 sync 引擎共享的底层写入助手(故为 internal, 供 TrackRepository_Sync.swift 调用)

    func shouldDeleteTrack(db: OpaquePointer, trackId: Int64) throws -> Bool {
        let sql = "SELECT COUNT(*) FROM library_tracks WHERE track_id = ?;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, trackId)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return true
        }
        return sqlite3_column_int(statement, 0) == 0
    }

    func deleteTrack(db: OpaquePointer, trackId: Int64) throws {
        let sql = "DELETE FROM tracks WHERE id = ?;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, trackId)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    func repointCanonicalPathIfNeeded(db: OpaquePointer, trackId: Int64) throws {
        let sql = """
        SELECT file_path, library_id, file_mtime, file_size
        FROM library_tracks
        WHERE track_id = ?
        ORDER BY file_mtime DESC
        LIMIT 1;
        """
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, trackId)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return
        }
        let path = String(cString: sqlite3_column_text(statement, 0))
        let libraryId = sqlite3_column_int64(statement, 1)
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        let file = ScannedAudioFile(
            url: fileURL,
            fileName: fileURL.lastPathComponent,
            mtime: sqlite3_column_double(statement, 2),
            size: sqlite3_column_int64(statement, 3),
            hasLyric: FileManager.default.fileExists(
                atPath: fileURL.deletingPathExtension().appendingPathExtension("lrc").path
            )
        )
        try updateTrackPathAndMetadata(
            db: db,
            trackId: trackId,
            libraryId: libraryId,
            file: file,
            contentHash: try TrackContentHasher.hash(fileURL: fileURL),
            updatedAt: Date().timeIntervalSince1970
        )
    }

    func updateTrackPathAndMetadata(
        db: OpaquePointer,
        trackId: Int64,
        libraryId: Int64,
        file: ScannedAudioFile,
        contentHash: String,
        updatedAt: TimeInterval
    ) throws {
        let metadata = TrackMetadataReader.read(from: file.url)
        let sql = """
        UPDATE tracks SET
            library_id = ?, file_path = ?, file_name = ?, file_mtime = ?, file_size = ?,
            title = ?, artist = ?, album = ?, duration = ?,
            has_lyric = ?, updated_at = ?, content_hash = ?
        WHERE id = ?;
        """
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, libraryId)
        sqlite3_bind_text(statement, 2, file.url.path, -1, Self.sqliteTransient)
        bindFileAndMetadata(
            statement: statement,
            file: file,
            metadata: metadata,
            hasLyric: file.hasLyric,
            updatedAt: updatedAt,
            startingAt: 3
        )
        sqlite3_bind_text(statement, 12, contentHash, -1, Self.sqliteTransient)
        sqlite3_bind_int64(statement, 13, trackId)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    func updateHasLyric(db: OpaquePointer, trackId: Int64, hasLyric: Bool) throws {
        let sql = "UPDATE tracks SET has_lyric = ?, updated_at = ? WHERE id = ?;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, hasLyric ? 1 : 0)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, trackId)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    func bindFileAndMetadata(
        statement: OpaquePointer,
        file: ScannedAudioFile,
        metadata: TrackMetadataReader.Metadata,
        hasLyric: Bool,
        updatedAt: TimeInterval,
        startingAt: Int32
    ) {
        var index = startingAt
        sqlite3_bind_text(statement, index, file.fileName, -1, Self.sqliteTransient)
        index += 1
        sqlite3_bind_double(statement, index, file.mtime)
        index += 1
        sqlite3_bind_int64(statement, index, file.size)
        index += 1
        bindOptionalText(statement, index: index, value: metadata.title)
        index += 1
        bindOptionalText(statement, index: index, value: metadata.artist)
        index += 1
        bindOptionalText(statement, index: index, value: metadata.album)
        index += 1
        if let duration = metadata.duration {
            sqlite3_bind_double(statement, index, duration)
        } else {
            sqlite3_bind_null(statement, index)
        }
        index += 1
        sqlite3_bind_int(statement, index, hasLyric ? 1 : 0)
        index += 1
        sqlite3_bind_double(statement, index, updatedAt)
    }

    // MARK: removeLibrary 专用助手

    private func repointLibraryIdIfNeeded(
        db: OpaquePointer,
        trackId: Int64,
        removedLibraryId: Int64
    ) throws {
        let currentSQL = "SELECT library_id FROM tracks WHERE id = ? LIMIT 1;"
        let current = try database.prepare(db, sql: currentSQL)
        defer { sqlite3_finalize(current) }
        sqlite3_bind_int64(current, 1, trackId)
        guard sqlite3_step(current) == SQLITE_ROW else {
            return
        }
        let libraryId = sqlite3_column_int64(current, 0)
        guard libraryId == removedLibraryId else {
            return
        }

        let nextSQL = "SELECT library_id FROM library_tracks WHERE track_id = ? LIMIT 1;"
        let next = try database.prepare(db, sql: nextSQL)
        defer { sqlite3_finalize(next) }
        sqlite3_bind_int64(next, 1, trackId)
        guard sqlite3_step(next) == SQLITE_ROW else {
            return
        }
        let nextLibraryId = sqlite3_column_int64(next, 0)

        let updateSQL = "UPDATE tracks SET library_id = ? WHERE id = ?;"
        let update = try database.prepare(db, sql: updateSQL)
        defer { sqlite3_finalize(update) }
        sqlite3_bind_int64(update, 1, nextLibraryId)
        sqlite3_bind_int64(update, 2, trackId)
        guard sqlite3_step(update) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    private func clearPlayerStateIfTracksDeleted(db: OpaquePointer, deletedTrackIds: Set<Int64>) throws {
        guard !deletedTrackIds.isEmpty else {
            return
        }

        let stateSQL = "SELECT last_track_id FROM player_state WHERE id = 1 LIMIT 1;"
        let state = try database.prepare(db, sql: stateSQL)
        defer { sqlite3_finalize(state) }
        guard sqlite3_step(state) == SQLITE_ROW else {
            return
        }
        guard sqlite3_column_type(state, 0) != SQLITE_NULL else {
            return
        }
        let lastTrackId = sqlite3_column_int64(state, 0)
        guard deletedTrackIds.contains(lastTrackId) else {
            return
        }

        let updateSQL = "UPDATE player_state SET last_track_id = NULL, last_position = 0 WHERE id = 1;"
        let update = try database.prepare(db, sql: updateSQL)
        defer { sqlite3_finalize(update) }
        guard sqlite3_step(update) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    private func bindOptionalText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
