import Foundation
import SQLite3

struct LibraryRecord {
    let id: Int64
    let path: String
    let displayName: String?
    let lastTrackId: Int64?
    let lastPosition: TimeInterval
    let lastScannedAt: Date?
    let isActive: Bool

    var url: URL {
        URL(fileURLWithPath: path)
    }
}

struct TrackRecord {
    let id: Int64
    let libraryId: Int64
    let filePath: String
    let fileName: String
    let fileMtime: TimeInterval
    let fileSize: Int64
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let hasLyric: Bool
    let updatedAt: Date
    let contentHash: String?

    var audioURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var lyricURL: URL? {
        guard hasLyric else {
            return nil
        }
        let url = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func asMusicTrack() -> MusicTrack {
        MusicTrack(
            id: id,
            audioURL: audioURL,
            lyricURL: lyricURL,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }

    var listTitle: String {
        if let title, !title.isEmpty {
            if let artist, !artist.isEmpty {
                return "\(artist) - \(title)"
            }
            return title
        }
        return (fileName as NSString).deletingPathExtension
    }

    static func read(from statement: OpaquePointer) -> TrackRecord {
        let duration = sqlite3_column_type(statement, 9) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, 9)
        let contentHash: String?
        if sqlite3_column_count(statement) > 12,
           sqlite3_column_type(statement, 12) != SQLITE_NULL,
           let cString = sqlite3_column_text(statement, 12) {
            contentHash = String(cString: cString)
        } else {
            contentHash = nil
        }

        return TrackRecord(
            id: sqlite3_column_int64(statement, 0),
            libraryId: sqlite3_column_int64(statement, 1),
            filePath: String(cString: sqlite3_column_text(statement, 2)),
            fileName: String(cString: sqlite3_column_text(statement, 3)),
            fileMtime: sqlite3_column_double(statement, 4),
            fileSize: sqlite3_column_int64(statement, 5),
            title: optionalString(statement, index: 6),
            artist: optionalString(statement, index: 7),
            album: optionalString(statement, index: 8),
            duration: duration,
            hasLyric: sqlite3_column_int(statement, 10) != 0,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
            contentHash: contentHash
        )
    }

    private static func optionalString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}

struct ScannedAudioFile {
    let url: URL
    let fileName: String
    let mtime: TimeInterval
    let size: Int64
    let hasLyric: Bool
}
