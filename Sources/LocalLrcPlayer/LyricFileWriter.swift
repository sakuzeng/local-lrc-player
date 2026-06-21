import Foundation

enum LyricFileWriter {
    static func lyricURL(for track: MusicTrack) -> URL {
        track.audioURL.deletingPathExtension().appendingPathExtension("lrc")
    }

    static func write(_ lyric: String, for track: MusicTrack, replaceExisting: Bool) throws -> URL {
        let url = lyricURL(for: track)
        if FileManager.default.fileExists(atPath: url.path), !replaceExisting {
            throw LyricFileWriterError.fileAlreadyExists
        }

        try lyric.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func writeIfMissing(_ lyric: String, for track: MusicTrack) throws -> URL {
        try write(lyric, for: track, replaceExisting: false)
    }
}

enum LyricFileWriterError: LocalizedError {
    case fileAlreadyExists

    var errorDescription: String? {
        switch self {
        case .fileAlreadyExists:
            return "同名 LRC 已存在，已跳过"
        }
    }
}
