import Foundation
import SQLite3

struct TrackSyncSummary {
    let inserted: Int
    let updated: Int
    let removed: Int
    let deduplicated: Int
    let total: Int
    let missingLyrics: Int
}

// 扫描文件夹并把结果增量同步进 SQLite 索引的引擎部分。
// 与 TrackRepository.swift 里的查询/CRUD 分开维护; 两者共享的底层写入助手留在主文件。
extension TrackRepository {
    func sync(libraryId: Int64, folderURL: URL) throws -> TrackSyncSummary {
        let scanned = try MusicLibrary.scanFiles(folderURL: folderURL)
        return try database.write { db in
            var existingLibraryTracks: [String: LibraryTrackSnapshot] = [:]
            let selectSQL = """
            SELECT lt.file_path, lt.track_id, lt.file_mtime, lt.file_size, t.content_hash, t.file_path
            FROM library_tracks lt
            JOIN tracks t ON t.id = lt.track_id
            WHERE lt.library_id = ?;
            """
            let select = try database.prepare(db, sql: selectSQL)
            defer { sqlite3_finalize(select) }
            sqlite3_bind_int64(select, 1, libraryId)
            while sqlite3_step(select) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(select, 0))
                let canonicalPath = String(cString: sqlite3_column_text(select, 5))
                let contentHash = sqlite3_column_type(select, 4) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(select, 4))
                existingLibraryTracks[path] = LibraryTrackSnapshot(
                    trackId: sqlite3_column_int64(select, 1),
                    mtime: sqlite3_column_double(select, 2),
                    size: sqlite3_column_int64(select, 3),
                    contentHash: contentHash,
                    canonicalFilePath: canonicalPath
                )
            }

            var inserted = 0
            var updated = 0
            var deduplicated = 0
            let now = Date().timeIntervalSince1970
            var seenPaths = Set<String>()

            for file in scanned {
                seenPaths.insert(file.url.path)
                if let snapshot = existingLibraryTracks[file.url.path],
                   snapshot.mtime == file.mtime,
                   snapshot.size == file.size {
                    try updateHasLyric(db: db, trackId: snapshot.trackId, hasLyric: file.hasLyric)
                    try upsertLibraryTrack(
                        db: db,
                        libraryId: libraryId,
                        trackId: snapshot.trackId,
                        file: file
                    )
                    continue
                }

                let contentHash = try TrackContentHasher.hash(fileURL: file.url)
                if let existingTrackId = try trackId(forContentHash: contentHash, db: db) {
                    try linkExistingTrack(
                        db: db,
                        libraryId: libraryId,
                        trackId: existingTrackId,
                        file: file,
                        updatedAt: now
                    )
                    try playlistRepository.ensureInMasterPlaylist(db: db, trackId: existingTrackId, addedAt: now)
                    if existingLibraryTracks[file.url.path] == nil {
                        deduplicated += 1
                    } else {
                        updated += 1
                    }
                    continue
                }

                if let snapshot = existingLibraryTracks[file.url.path] {
                    try updateTrackWithHash(
                        db: db,
                        libraryId: libraryId,
                        trackId: snapshot.trackId,
                        file: file,
                        contentHash: contentHash,
                        updatedAt: now
                    )
                    try playlistRepository.ensureInMasterPlaylist(db: db, trackId: snapshot.trackId, addedAt: now)
                    updated += 1
                } else {
                    let trackId = try insertTrack(
                        db: db,
                        libraryId: libraryId,
                        file: file,
                        contentHash: contentHash,
                        updatedAt: now
                    )
                    try upsertLibraryTrack(
                        db: db,
                        libraryId: libraryId,
                        trackId: trackId,
                        file: file
                    )
                    try playlistRepository.ensureInMasterPlaylist(db: db, trackId: trackId, addedAt: now)
                    inserted += 1
                }
            }

            var removed = 0
            for (path, snapshot) in existingLibraryTracks where !seenPaths.contains(path) {
                try deleteLibraryTrack(db: db, libraryId: libraryId, filePath: path)
                if try shouldDeleteTrack(db: db, trackId: snapshot.trackId) {
                    try deleteTrack(db: db, trackId: snapshot.trackId)
                } else if !FileManager.default.fileExists(atPath: snapshot.canonicalFilePath) {
                    try repointCanonicalPathIfNeeded(db: db, trackId: snapshot.trackId)
                }
                removed += 1
            }

            try playlistRepository.reorderMasterPlaylist(db: db)

            let counts = try playlistRepository.masterPlaylistCounts(db: db)
            return TrackSyncSummary(
                inserted: inserted,
                updated: updated,
                removed: removed,
                deduplicated: deduplicated,
                total: counts.total,
                missingLyrics: counts.missingLyrics
            )
        }
    }

    func syncAll(libraries: [LibraryRecord]) throws -> TrackSyncSummary {
        var inserted = 0
        var updated = 0
        var removed = 0
        var deduplicated = 0

        for library in libraries {
            let summary = try sync(libraryId: library.id, folderURL: library.url)
            inserted += summary.inserted
            updated += summary.updated
            removed += summary.removed
            deduplicated += summary.deduplicated
        }

        let counts = try playlistRepository.masterPlaylistCounts()
        return TrackSyncSummary(
            inserted: inserted,
            updated: updated,
            removed: removed,
            deduplicated: deduplicated,
            total: counts.total,
            missingLyrics: counts.missingLyrics
        )
    }

    private struct LibraryTrackSnapshot {
        let trackId: Int64
        let mtime: TimeInterval
        let size: Int64
        let contentHash: String?
        let canonicalFilePath: String
    }

    private func trackId(forContentHash hash: String, db: OpaquePointer) throws -> Int64? {
        let sql = "SELECT id FROM tracks WHERE content_hash = ? LIMIT 1;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, hash, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func linkExistingTrack(
        db: OpaquePointer,
        libraryId: Int64,
        trackId: Int64,
        file: ScannedAudioFile,
        updatedAt: TimeInterval
    ) throws {
        try upsertLibraryTrack(db: db, libraryId: libraryId, trackId: trackId, file: file)
        if let track = try fetchTrackSnapshot(db: db, trackId: trackId),
           !FileManager.default.fileExists(atPath: track.filePath) {
            try updateTrackPathAndMetadata(
                db: db,
                trackId: trackId,
                libraryId: libraryId,
                file: file,
                contentHash: try TrackContentHasher.hash(fileURL: file.url),
                updatedAt: updatedAt
            )
        } else {
            try updateHasLyric(db: db, trackId: trackId, hasLyric: file.hasLyric)
        }
    }

    private func fetchTrackSnapshot(db: OpaquePointer, trackId: Int64) throws -> (filePath: String, contentHash: String?)? {
        let sql = "SELECT file_path, content_hash FROM tracks WHERE id = ? LIMIT 1;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, trackId)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        let hash = sqlite3_column_type(statement, 1) == SQLITE_NULL
            ? nil
            : String(cString: sqlite3_column_text(statement, 1))
        return (String(cString: sqlite3_column_text(statement, 0)), hash)
    }

    private func insertTrack(
        db: OpaquePointer,
        libraryId: Int64,
        file: ScannedAudioFile,
        contentHash: String,
        updatedAt: TimeInterval
    ) throws -> Int64 {
        let metadata = TrackMetadataReader.read(from: file.url)
        let sql = """
        INSERT INTO tracks (
            library_id, file_path, file_name, file_mtime, file_size,
            title, artist, album, duration, has_lyric, updated_at, content_hash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func updateTrackWithHash(
        db: OpaquePointer,
        libraryId: Int64,
        trackId: Int64,
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
        try upsertLibraryTrack(db: db, libraryId: libraryId, trackId: trackId, file: file)
    }

    private func upsertLibraryTrack(
        db: OpaquePointer,
        libraryId: Int64,
        trackId: Int64,
        file: ScannedAudioFile
    ) throws {
        let sql = """
        INSERT OR REPLACE INTO library_tracks (library_id, track_id, file_path, file_mtime, file_size)
        VALUES (?, ?, ?, ?, ?);
        """
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, libraryId)
        sqlite3_bind_int64(statement, 2, trackId)
        sqlite3_bind_text(statement, 3, file.url.path, -1, Self.sqliteTransient)
        sqlite3_bind_double(statement, 4, file.mtime)
        sqlite3_bind_int64(statement, 5, file.size)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }

    private func deleteLibraryTrack(db: OpaquePointer, libraryId: Int64, filePath: String) throws {
        let sql = "DELETE FROM library_tracks WHERE library_id = ? AND file_path = ?;"
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, libraryId)
        sqlite3_bind_text(statement, 2, filePath, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(database.errorMessage(db))
        }
    }
}
