import Foundation

struct MusicTrack {
    let id: Int64?
    let audioURL: URL
    let lyricURL: URL?
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?

    init(
        id: Int64? = nil,
        audioURL: URL,
        lyricURL: URL? = nil,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.audioURL = audioURL
        self.lyricURL = lyricURL
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    var displayName: String {
        if let title, !title.isEmpty {
            if let artist, !artist.isEmpty {
                return "\(artist) - \(title)"
            }
            return title
        }
        return audioURL.deletingPathExtension().lastPathComponent
    }

    /// 解析「歌手 - 歌名」格式（文件名或合并后的标题常用此写法）。
    /// 曲目列表与菜单栏卡片共用，ID3 缺歌手时靠它还原出副标题。
    static func parseArtistTitle(_ text: String) -> (artist: String, title: String)? {
        let separators = [" - ", " – ", " — ", "－"]
        for separator in separators {
            let parts = text.components(separatedBy: separator)
            guard parts.count >= 2 else {
                continue
            }
            let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts.dropFirst().joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty, !title.isEmpty {
                return (artist, title)
            }
        }
        return nil
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
        try scanFiles(folderURL: folderURL).map { file in
            MusicTrack(
                audioURL: file.url,
                lyricURL: file.hasLyric
                    ? file.url.deletingPathExtension().appendingPathExtension("lrc")
                    : nil
            )
        }
    }

    static func scanFiles(folderURL: URL) throws -> [ScannedAudioFile] {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let files = try urls.compactMap { url -> ScannedAudioFile? in
            guard isRegularFile(url) else {
                return nil
            }

            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = Int64(values.fileSize ?? 0)
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            let hasLyric = fileManager.fileExists(atPath: lrcURL.path)

            return ScannedAudioFile(
                url: url.standardizedFileURL,
                fileName: url.lastPathComponent,
                mtime: mtime,
                size: size,
                hasLyric: hasLyric
            )
        }

        return files.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }
}
