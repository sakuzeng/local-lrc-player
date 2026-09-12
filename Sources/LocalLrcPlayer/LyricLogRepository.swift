import Foundation
import SQLite3

final class LyricLogRepository {
    struct AttemptRecord {
        let createdAt: Date
        let provider: LyricProvider
        let fileName: String
        let candidateName: String?
        let score: Int?
        let success: Bool
        let errorMessage: String?
    }

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// 诊断导出用：最近的下载尝试，带曲目文件名，新的在前。
    func recentAttempts(limit: Int) throws -> [AttemptRecord] {
        try database.read { db in
            let sql = """
            SELECT l.created_at, l.provider, t.file_name, l.candidate_name, l.score, l.success, l.error_message
            FROM lyric_download_log l
            JOIN tracks t ON t.id = l.track_id
            ORDER BY l.created_at DESC
            LIMIT ?;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var records: [AttemptRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let provider = LyricProvider(rawValue: String(cString: sqlite3_column_text(statement, 1))) ?? .netEase
                records.append(AttemptRecord(
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    provider: provider,
                    fileName: String(cString: sqlite3_column_text(statement, 2)),
                    candidateName: Self.optionalText(statement, 3),
                    score: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 4)),
                    success: sqlite3_column_int(statement, 5) != 0,
                    errorMessage: Self.optionalText(statement, 6)
                ))
            }
            return records
        }
    }

    private static func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func logAttempt(
        trackId: Int64,
        provider: LyricProvider,
        candidate: LyricCandidate?,
        score: Int?,
        success: Bool,
        errorMessage: String? = nil
    ) throws {
        let now = Date().timeIntervalSince1970
        try database.write { db in
            let sql = """
            INSERT INTO lyric_download_log (
                track_id, provider, candidate_id, candidate_name, score, success, error_message, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, trackId)
            sqlite3_bind_text(statement, 2, provider.rawValue, -1, Self.sqliteTransient)

            if let candidate {
                sqlite3_bind_text(statement, 3, candidate.identifier, -1, Self.sqliteTransient)
                sqlite3_bind_text(statement, 4, candidate.name, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 3)
                sqlite3_bind_null(statement, 4)
            }

            if let score {
                sqlite3_bind_int(statement, 5, Int32(score))
            } else {
                sqlite3_bind_null(statement, 5)
            }

            sqlite3_bind_int(statement, 6, success ? 1 : 0)

            if let errorMessage, !errorMessage.isEmpty {
                sqlite3_bind_text(statement, 7, errorMessage, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 7)
            }

            sqlite3_bind_double(statement, 8, now)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }
}

private extension LyricLogRepository {
    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
