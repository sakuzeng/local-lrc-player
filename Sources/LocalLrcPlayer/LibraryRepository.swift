import Foundation
import SQLite3

final class LibraryRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func migrateLegacyLastFolderIfNeeded() throws {
        let legacyKey = "lastFolderPath"
        guard let path = UserDefaults.standard.string(forKey: legacyKey) else {
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }

        _ = try registerLibrary(at: URL(fileURLWithPath: path))
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    func allLibraries() throws -> [LibraryRecord] {
        try database.read { db in
            let sql = """
            SELECT id, path, display_name, last_track_id, last_position, last_scanned_at, is_active
            FROM libraries
            ORDER BY id ASC;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }

            var results: [LibraryRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(readLibrary(from: statement))
            }
            return results
        }
    }

    func activeLibrary() throws -> LibraryRecord? {
        try database.read { db in
            let sql = """
            SELECT id, path, display_name, last_track_id, last_position, last_scanned_at, is_active
            FROM libraries
            WHERE is_active = 1
            ORDER BY id DESC
            LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return readLibrary(from: statement)
        }
    }

    @discardableResult
    func registerLibrary(at url: URL) throws -> LibraryRecord {
        let standardizedPath = url.standardizedFileURL.path
        let displayName = url.lastPathComponent

        return try database.write { db in
            try database.exec(db, sql: "UPDATE libraries SET is_active = 0;")

            let selectSQL = """
            SELECT id, path, display_name, last_track_id, last_position, last_scanned_at, is_active
            FROM libraries WHERE path = ? LIMIT 1;
            """
            let select = try database.prepare(db, sql: selectSQL)
            defer { sqlite3_finalize(select) }
            sqlite3_bind_text(select, 1, standardizedPath, -1, Self.sqliteTransient)

            if sqlite3_step(select) == SQLITE_ROW {
                let id = sqlite3_column_int64(select, 0)
                let updateSQL = """
                UPDATE libraries
                SET is_active = 1, display_name = ?
                WHERE id = ?;
                """
                let update = try database.prepare(db, sql: updateSQL)
                defer { sqlite3_finalize(update) }
                sqlite3_bind_text(update, 1, displayName, -1, Self.sqliteTransient)
                sqlite3_bind_int64(update, 2, id)
                guard sqlite3_step(update) == SQLITE_DONE else {
                    throw AppDatabaseError.stepFailed(database.errorMessage(db))
                }
                return try fetchLibrary(db: db, id: id)
            }

            let insertSQL = """
            INSERT INTO libraries (path, display_name, is_active)
            VALUES (?, ?, 1);
            """
            let insert = try database.prepare(db, sql: insertSQL)
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_text(insert, 1, standardizedPath, -1, Self.sqliteTransient)
            sqlite3_bind_text(insert, 2, displayName, -1, Self.sqliteTransient)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
            return try fetchLibrary(db: db, id: sqlite3_last_insert_rowid(db))
        }
    }

    func deleteLibrary(id: Int64) throws {
        let wasActive = try database.read { db in
            let sql = "SELECT is_active FROM libraries WHERE id = ? LIMIT 1;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return false
            }
            return sqlite3_column_int(statement, 0) != 0
        }

        _ = try TrackRepository(database: database).removeLibrary(libraryId: id)

        if wasActive {
            try database.write { db in
                let selectSQL = "SELECT id FROM libraries ORDER BY id DESC LIMIT 1;"
                let select = try database.prepare(db, sql: selectSQL)
                defer { sqlite3_finalize(select) }
                guard sqlite3_step(select) == SQLITE_ROW else {
                    return
                }
                let nextId = sqlite3_column_int64(select, 0)
                try database.exec(db, sql: "UPDATE libraries SET is_active = 0;")
                let updateSQL = "UPDATE libraries SET is_active = 1 WHERE id = ?;"
                let update = try database.prepare(db, sql: updateSQL)
                defer { sqlite3_finalize(update) }
                sqlite3_bind_int64(update, 1, nextId)
                guard sqlite3_step(update) == SQLITE_DONE else {
                    throw AppDatabaseError.stepFailed(database.errorMessage(db))
                }
            }
        }
    }

    func markScanned(libraryId: Int64) throws {
        let now = Date().timeIntervalSince1970
        try database.write { db in
            let sql = "UPDATE libraries SET last_scanned_at = ? WHERE id = ?;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, now)
            sqlite3_bind_int64(statement, 2, libraryId)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    private func fetchLibrary(db: OpaquePointer, id: Int64) throws -> LibraryRecord {
        let sql = """
        SELECT id, path, display_name, last_track_id, last_position, last_scanned_at, is_active
        FROM libraries WHERE id = ? LIMIT 1;
        """
        let statement = try database.prepare(db, sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AppDatabaseError.stepFailed("找不到音乐库记录")
        }
        return readLibrary(from: statement)
    }

    private func readLibrary(from statement: OpaquePointer) -> LibraryRecord {
        let lastScannedAt = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let lastTrackId = sqlite3_column_type(statement, 3) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 3)

        return LibraryRecord(
            id: sqlite3_column_int64(statement, 0),
            path: stringColumn(statement, index: 1) ?? "",
            displayName: stringColumn(statement, index: 2),
            lastTrackId: lastTrackId,
            lastPosition: sqlite3_column_double(statement, 4),
            lastScannedAt: lastScannedAt,
            isActive: sqlite3_column_int(statement, 6) != 0
        )
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
