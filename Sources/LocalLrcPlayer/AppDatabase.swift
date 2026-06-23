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
    static let currentSchemaVersion = 3

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

            if try currentSchemaVersion(db) < 1 {
                try exec(db, sql: Self.schemaV1)
            }
            if try currentSchemaVersion(db) < 2 {
                try Self.applyMigrationV2(db, database: self)
            }
            if try currentSchemaVersion(db) < 3 {
                try Self.applyMigrationV3(db, database: self)
            }

            let version = try currentSchemaVersion(db)
            if version < Self.currentSchemaVersion {
                try exec(db, sql: "PRAGMA user_version = \(Self.currentSchemaVersion);")
            }
        }
    }

    private static func applyMigrationV2(_ db: OpaquePointer, database: AppDatabase) throws {
        let statements = [
            "ALTER TABLE player_state ADD COLUMN window_origin_x REAL;",
            "ALTER TABLE player_state ADD COLUMN window_origin_y REAL;",
            "ALTER TABLE player_state ADD COLUMN window_width REAL;",
            "ALTER TABLE player_state ADD COLUMN window_height REAL;"
        ]
        for sql in statements {
            try database.exec(db, sql: sql)
        }
    }

    private static func applyMigrationV3(_ db: OpaquePointer, database: AppDatabase) throws {
        try database.exec(
            db,
            sql: "ALTER TABLE player_state ADD COLUMN playback_mode TEXT NOT NULL DEFAULT 'sequential';"
        )
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

    /// 当前完整 schema（本地开发基线 v1）。后续结构变更请新增 v2 迁移。
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
        content_hash TEXT,
        updated_at REAL NOT NULL
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_tracks_content_hash ON tracks(content_hash);
    CREATE INDEX IF NOT EXISTS idx_tracks_library ON tracks(library_id);
    CREATE INDEX IF NOT EXISTS idx_tracks_has_lyric ON tracks(library_id, has_lyric);

    CREATE TABLE IF NOT EXISTS library_tracks (
        library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        file_mtime REAL NOT NULL,
        file_size INTEGER NOT NULL,
        PRIMARY KEY (library_id, file_path),
        UNIQUE (library_id, track_id)
    );

    CREATE INDEX IF NOT EXISTS idx_library_tracks_track ON library_tracks(track_id);

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

    CREATE INDEX IF NOT EXISTS idx_playlist_tracks_order ON playlist_tracks(playlist_id, sort_order);

    CREATE TABLE IF NOT EXISTS player_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_track_id INTEGER,
        last_position REAL NOT NULL DEFAULT 0
    );

    INSERT OR IGNORE INTO player_state (id) VALUES (1);

    CREATE TABLE IF NOT EXISTS app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        menu_bar_lyrics_enabled INTEGER NOT NULL DEFAULT 1,
        menu_bar_lyrics_max_width REAL NOT NULL DEFAULT 160,
        menu_bar_lyrics_show_icon INTEGER NOT NULL DEFAULT 1
    );

    INSERT OR IGNORE INTO app_settings (id) VALUES (1);

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
}
