import Foundation
import SQLite3

final class PlayHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// 每次开始播放记一行（含跳过），返回 rowid 供听满阈值后回标 counted。
    /// `at` 只为测试注入固定时间，正常调用不传。
    @discardableResult
    func recordPlayback(trackId: Int64, position: TimeInterval = 0, at date: Date = Date()) throws -> Int64 {
        let now = date.timeIntervalSince1970
        return try database.write { db in
            let sql = """
            INSERT INTO play_history (track_id, started_at, position_seconds)
            VALUES (?, ?, ?);
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, trackId)
            sqlite3_bind_double(statement, 2, now)
            sqlite3_bind_double(statement, 3, position)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// 听满阈值后把这一行升级成有效播放。里程碑只数 counted = 1 的行。
    func markCounted(historyId: Int64) throws {
        try database.write { db in
            let sql = "UPDATE play_history SET counted = 1 WHERE id = ?;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, historyId)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    func countedPlayCount(trackId: Int64) throws -> Int {
        try database.read { db in
            let sql = "SELECT COUNT(*) FROM play_history WHERE track_id = ? AND counted = 1;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, trackId)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    /// 首次播放时间取全量历史（含未计数行）——「这首歌你从哪天开始听」是独立于
    /// 计数口径的事实，功能上线前的历史同样成立。
    func firstPlayedAt(trackId: Int64) throws -> Date? {
        try database.read { db in
            let sql = "SELECT MIN(started_at) FROM play_history WHERE track_id = ?;"
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, trackId)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  sqlite3_column_type(statement, 0) != SQLITE_NULL else {
                return nil
            }
            return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
        }
    }

    /// 某一天听得最多的曲目。日期用 SQLite 的 localtime 折算，
    /// 与 Swift 侧 Calendar 算出的本地日期口径一致。
    func mostPlayedTrack(onDay day: String) throws -> (track: TrackRecord, plays: Int)? {
        try database.read { db in
            let sql = """
            SELECT t.id, t.library_id, t.file_path, t.file_name, t.file_mtime, t.file_size,
                   t.title, t.artist, t.album, t.duration, t.has_lyric, t.updated_at, t.content_hash,
                   COUNT(*) AS plays
            FROM play_history h
            JOIN tracks t ON t.id = h.track_id
            WHERE date(h.started_at, 'unixepoch', 'localtime') = ?
            GROUP BY h.track_id
            ORDER BY plays DESC, MIN(h.started_at) ASC
            LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, day, -1, Self.sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return (TrackRecord.read(from: statement), Int(sqlite3_column_int(statement, 13)))
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
