import Foundation

struct MusicTrack {
    let audioURL: URL
    let lyricURL: URL?

    var displayName: String {
        audioURL.deletingPathExtension().lastPathComponent
    }
}

enum MusicLibrary {
    static let supportedExtensions: Set<String> = [
        "mp3",
        "m4a",
        "flac",
        "wav",
        "aac",
        "aiff",
        "aif"
    ]

    static func scan(folderURL: URL) throws -> [MusicTrack] {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )

        let tracks = urls.compactMap { url -> MusicTrack? in
            guard isRegularFile(url) else {
                return nil
            }

            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                return nil
            }

            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            let lyricURL = fileManager.fileExists(atPath: lrcURL.path) ? lrcURL : nil
            return MusicTrack(audioURL: url, lyricURL: lyricURL)
        }

        return tracks.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }
}
