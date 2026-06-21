import Foundation
import SQLite3

final class LyricLogRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
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
