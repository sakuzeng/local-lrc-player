import AppKit
import Foundation

/// 下载封面的本地缓存，按 tracks.id 命名存放在 Caches 目录；只缓存网络封面，
/// 内嵌封面始终直接读音频文件。缓存丢失无害，下次播放会重新下载。
enum ArtworkCache {
    static func cacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = caches
            .appendingPathComponent("LocalLrcPlayer", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func fileURL(trackId: Int64) throws -> URL {
        try cacheDirectory().appendingPathComponent("track-\(trackId).jpg")
    }

    static func load(trackId: Int64) -> NSImage? {
        guard let url = try? fileURL(trackId: trackId),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func save(_ data: Data, trackId: Int64) {
        guard let url = try? fileURL(trackId: trackId) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
