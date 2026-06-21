import Foundation

enum PlaybackAssetResolver {
    private static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    static func playbackURL(for track: MusicTrack) throws -> URL {
        guard track.audioURL.pathExtension.lowercased() == "flac" else {
            return track.audioURL
        }

        let siblingM4A = track.audioURL.deletingPathExtension().appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: siblingM4A.path) {
            return siblingM4A
        }

        let cachedURL = try cachedALACURL(for: track.audioURL)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        try convertFLACToALAC(sourceURL: track.audioURL, outputURL: cachedURL)
        return cachedURL
    }

    private static func cachedALACURL(for sourceURL: URL) throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LocalLrcPlayer/Transcoded", isDirectory: true)

        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = attributes[.size] as? UInt64 ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fingerprint = "\(size)-\(Int(modified))"
        let name = "\(sourceURL.deletingPathExtension().lastPathComponent)-\(fingerprint)"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        return cacheRoot.appendingPathComponent(name).appendingPathExtension("m4a")
    }

    private static func convertFLACToALAC(sourceURL: URL, outputURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            throw PlaybackAssetResolverError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-y",
            "-i",
            sourceURL.path,
            "-map_metadata",
            "0",
            "-vn",
            "-c:a",
            "alac",
            outputURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown ffmpeg error"
            throw PlaybackAssetResolverError.conversionFailed(message)
        }
    }
}

enum PlaybackAssetResolverError: LocalizedError {
    case ffmpegNotFound
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "未找到 ffmpeg，无法为 FLAC 生成可精确跳转的播放缓存"
        case .conversionFailed(let message):
            return "FLAC 转 ALAC 缓存失败：\(message)"
        }
    }
}
