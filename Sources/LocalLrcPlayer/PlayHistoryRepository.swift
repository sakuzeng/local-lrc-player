import Foundation
import SQLite3

final class PlayHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func recordPlayback(trackId: Int64, position: TimeInterval = 0) throws {
        let now = Date().timeIntervalSince1970
        try database.write { db in
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
        }
    }
}
