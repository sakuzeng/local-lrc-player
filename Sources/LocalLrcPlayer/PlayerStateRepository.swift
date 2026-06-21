import Foundation
import SQLite3

struct PlayerState {
    let lastTrackId: Int64?
    let lastPosition: TimeInterval
}

final class PlayerStateRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func playbackState() throws -> PlayerState {
        try database.read { db in
            let sql = """
            SELECT last_track_id, last_position
            FROM player_state
            WHERE id = 1
            LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return PlayerState(lastTrackId: nil, lastPosition: 0)
            }
            let lastTrackId = sqlite3_column_type(statement, 0) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 0)
            return PlayerState(
                lastTrackId: lastTrackId,
                lastPosition: sqlite3_column_double(statement, 1)
            )
        }
    }

    func updatePlaybackState(trackId: Int64?, position: TimeInterval) throws {
        try database.write { db in
            let sql = """
            UPDATE player_state
            SET last_track_id = ?, last_position = ?
            WHERE id = 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            if let trackId {
                sqlite3_bind_int64(statement, 1, trackId)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqlite3_bind_double(statement, 2, position)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }
}
