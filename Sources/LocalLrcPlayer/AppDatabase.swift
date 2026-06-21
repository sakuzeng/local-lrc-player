import Foundation
import SQLite3

enum AppDatabaseError: LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .execFailed(let message),
             .prepareFailed(let message), .stepFailed(let message):
            return message
        }
    }
}

enum MasterPlaylist {
    static let id: Int64 = 1
}

final class AppDatabase {
    static let shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            fatalError("无法打开数据库：\(error.localizedDescription)")
        }
    }()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "local.lrc.player.database")
    private let fileURL: URL

    var databaseURL: URL {
        fileURL
    }

    init(fileURL: URL? = nil) throws {
        self.fileURL = try fileURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        if sqlite3_open(self.fileURL.path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw AppDatabaseError.openFailed("打开数据库失败：\(message)")
        }
        db = handle
        try migrate()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("LocalLrcPlayer", isDirectory: true)
            .appendingPathComponent("LocalLrcPlayer.sqlite")
    }

    func read<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            guard let db else {
                throw AppDatabaseError.openFailed("数据库未打开")
            }
            return try work(db)
        }
    }

    func write(_ work: (OpaquePointer) throws -> Void) throws {
        try queue.sync {
            guard let db else {
                throw AppDatabaseError.openFailed("数据库未打开")
            }
            try work(db)
        }
    }

    func write<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            guard let db else {
                throw AppDatabaseError.openFailed("数据库未打开")
            }
            return try work(db)
        }
    }

    private func migrate() throws {
        try write { db in
            try exec(db, sql: "PRAGMA foreign_keys = ON;")

            var schemaVersion = try currentSchemaVersion(db)
            if schemaVersion < 1 {
                try exec(db, sql: Self.schemaV1)
                try exec(db, sql: "PRAGMA user_version = 1;")
                schemaVersion = 1
            }
            if schemaVersion < 2 {
                try migrateToV2(db)
                try exec(db, sql: "PRAGMA user_version = 2;")
            }
        }
    }

    private func migrateToV2(_ db: OpaquePointer) throws {
        try exec(db, sql: Self.schemaV2DDL)

        var tracks: [(id: Int64, libraryId: Int64, filePath: String, fileName: String, mtime: TimeInterval, size: Int64, updatedAt: TimeInterval)] = []
        let selectSQL = """
        SELECT id, library_id, file_path, file_name, file_mtime, file_size, updated_at
        FROM tracks ORDER BY id ASC;
        """
        let select = try prepare(db, sql: selectSQL)
        defer { sqlite3_finalize(select) }
        while sqlite3_step(select) == SQLITE_ROW {
            tracks.append((
                id: sqlite3_column_int64(select, 0),
                libraryId: sqlite3_column_int64(select, 1),
                filePath: String(cString: sqlite3_column_text(select, 2)),
                fileName: String(cString: sqlite3_column_text(select, 3)),
                mtime: sqlite3_column_double(select, 4),
                size: sqlite3_column_int64(select, 5),
                updatedAt: sqlite3_column_double(select, 6)
            ))
        }

        var hashToCanonicalTrackId: [String: Int64] = [:]
        var sortOrder = 1

        for track in tracks {
            let fileURL = URL(fileURLWithPath: track.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                try deleteTrack(db: db, trackId: track.id)
                continue
            }

            let hash = try TrackContentHasher.hash(fileURL: fileURL)
            if let canonicalId = hashToCanonicalTrackId[hash] {
                try insertLibraryTrack(
                    db: db,
                    libraryId: track.libraryId,
                    trackId: canonicalId,
                    filePath: track.filePath,
                    mtime: track.mtime,
                    size: track.size
                )
                try ensureMasterPlaylistMembership(db: db, trackId: canonicalId, addedAt: track.updatedAt, sortOrder: &sortOrder)
                if track.id != canonicalId {
                    try deleteTrack(db: db, trackId: track.id)
                }
                continue
            }

            try bindTrackHash(db: db, trackId: track.id, hash: hash)
            try insertLibraryTrack(
                db: db,
                libraryId: track.libraryId,
                trackId: track.id,
                filePath: track.filePath,
                mtime: track.mtime,
                size: track.size
            )
            try ensureMasterPlaylistMembership(db: db, trackId: track.id, addedAt: track.updatedAt, sortOrder: &sortOrder)
            hashToCanonicalTrackId[hash] = track.id
        }

        let playerStateSQL = """
        SELECT last_track_id, last_position
        FROM libraries
        WHERE is_active = 1
        ORDER BY id DESC
        LIMIT 1;
        """
        let playerSelect = try prepare(db, sql: playerStateSQL)
        defer { sqlite3_finalize(playerSelect) }
        if sqlite3_step(playerSelect) == SQLITE_ROW {
            let lastTrackId = sqlite3_column_type(playerSelect, 0) == SQLITE_NULL
                ? nil as Int64?
                : sqlite3_column_int64(playerSelect, 0)
            let lastPosition = sqlite3_column_double(playerSelect, 1)
            let updateSQL = """
            UPDATE player_state
            SET last_track_id = ?, last_position = ?
            WHERE id = 1;
            """
            let update = try prepare(db, sql: updateSQL)
            defer { sqlite3_finalize(update) }
            if let lastTrackId {
                sqlite3_bind_int64(update, 1, lastTrackId)
            } else {
                sqlite3_bind_null(update, 1)
            }
            sqlite3_bind_double(update, 2, lastPosition)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(errorMessage(db))
            }
        }
    }

    private func bindTrackHash(db: OpaquePointer, trackId: Int64, hash: String) throws {
        let sql = "UPDATE tracks SET content_hash = ? WHERE id = ?;"
        let statement = try prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, hash, -1, Self.sqliteTransient)
        sqlite3_bind_int64(statement, 2, trackId)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(errorMessage(db))
        }
    }

    private func insertLibraryTrack(
        db: OpaquePointer,
        libraryId: Int64,
        trackId: Int64,
        filePath: String,
        mtime: TimeInterval,
        size: Int64
    ) throws {
        let sql = """
        INSERT OR REPLACE INTO library_tracks (library_id, track_id, file_path, file_mtime, file_size)
        VALUES (?, ?, ?, ?, ?);
        """
        let statement = try prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, libraryId)
        sqlite3_bind_int64(statement, 2, trackId)
        sqlite3_bind_text(statement, 3, filePath, -1, Self.sqliteTransient)
        sqlite3_bind_double(statement, 4, mtime)
        sqlite3_bind_int64(statement, 5, size)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(errorMessage(db))
        }
    }

    private func ensureMasterPlaylistMembership(
        db: OpaquePointer,
        trackId: Int64,
        addedAt: TimeInterval,
        sortOrder: inout Int
    ) throws {
        let checkSQL = """
        SELECT 1 FROM playlist_tracks
        WHERE playlist_id = ? AND track_id = ? LIMIT 1;
        """
        let check = try prepare(db, sql: checkSQL)
        defer { sqlite3_finalize(check) }
        sqlite3_bind_int64(check, 1, MasterPlaylist.id)
        sqlite3_bind_int64(check, 2, trackId)
        if sqlite3_step(check) == SQLITE_ROW {
            return
        }

        let insertSQL = """
        INSERT INTO playlist_tracks (playlist_id, track_id, added_at, sort_order)
        VALUES (?, ?, ?, ?);
        """
        let insert = try prepare(db, sql: insertSQL)
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_int64(insert, 1, MasterPlaylist.id)
        sqlite3_bind_int64(insert, 2, trackId)
        sqlite3_bind_double(insert, 3, addedAt)
        sqlite3_bind_int64(insert, 4, Int64(sortOrder))
        sortOrder += 1
        guard sqlite3_step(insert) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(errorMessage(db))
        }
    }

    private func deleteTrack(db: OpaquePointer, trackId: Int64) throws {
        let sql = "DELETE FROM tracks WHERE id = ?;"
        let statement = try prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, trackId)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppDatabaseError.stepFailed(errorMessage(db))
        }
    }

    private func currentSchemaVersion(_ db: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw AppDatabaseError.prepareFailed(errorMessage(db))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func exec(_ db: OpaquePointer, sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? self.errorMessage(db)
            if let errorPointer {
                sqlite3_free(errorPointer)
            }
            throw AppDatabaseError.execFailed(message)
        }
    }

    func prepare(_ db: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw AppDatabaseError.prepareFailed(errorMessage(db))
        }
        guard let statement else {
            throw AppDatabaseError.prepareFailed("无法创建 SQL 语句")
        }
        return statement
    }

    func errorMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let schemaV1 = """
    CREATE TABLE IF NOT EXISTS libraries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        display_name TEXT,
        last_track_id INTEGER,
        last_position REAL NOT NULL DEFAULT 0,
        last_scanned_at REAL,
        is_active INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL,
        file_mtime REAL NOT NULL,
        file_size INTEGER NOT NULL,
        title TEXT,
        artist TEXT,
        album TEXT,
        duration REAL,
        has_lyric INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tracks_library ON tracks(library_id);
    CREATE INDEX IF NOT EXISTS idx_tracks_has_lyric ON tracks(library_id, has_lyric);

    CREATE TABLE IF NOT EXISTS play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        started_at REAL NOT NULL,
        position_seconds REAL NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id, started_at DESC);

    CREATE TABLE IF NOT EXISTS lyric_download_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        provider TEXT NOT NULL,
        candidate_id TEXT,
        candidate_name TEXT,
        score INTEGER,
        success INTEGER NOT NULL,
        error_message TEXT,
        created_at REAL NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_lyric_log_track ON lyric_download_log(track_id, created_at DESC);
    """

    private static let schemaV2DDL = """
    CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0
    );

    INSERT OR IGNORE INTO playlists (id, name, is_system) VALUES (1, '全部', 1);

    CREATE TABLE IF NOT EXISTS playlist_tracks (
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        added_at REAL NOT NULL,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id)
    );

    CREATE TABLE IF NOT EXISTS library_tracks (
        library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        file_mtime REAL NOT NULL,
        file_size INTEGER NOT NULL,
        PRIMARY KEY (library_id, file_path),
        UNIQUE (library_id, track_id)
    );

    CREATE TABLE IF NOT EXISTS player_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_track_id INTEGER,
        last_position REAL NOT NULL DEFAULT 0
    );

    INSERT OR IGNORE INTO player_state (id) VALUES (1);

    ALTER TABLE tracks ADD COLUMN content_hash TEXT;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_content_hash ON tracks(content_hash);
    CREATE INDEX IF NOT EXISTS idx_playlist_tracks_order ON playlist_tracks(playlist_id, sort_order);
    CREATE INDEX IF NOT EXISTS idx_library_tracks_track ON library_tracks(track_id);
    """
}
