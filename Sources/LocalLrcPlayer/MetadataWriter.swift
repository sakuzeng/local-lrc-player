import Foundation

/// 把歌名/歌手/专辑/封面/歌词写进音频文件本身的标签。
///
/// 三条红线(ROADMAP 定的,别放宽):
/// 1. 只补缺失字段,已有值一律不覆盖 —— 这是对用户文件的修改,宁可少写也不能改错。
/// 2. 写前整份备份到 Application Support,ffmpeg 写临时文件成功后才原子替换原文件。
/// 3. 写完文件内容变了、SHA256 随之变化,调用方必须同步更新数据库里的 content_hash 与 mtime/size
///    (`TrackRepository.refreshAfterMetadataWrite`),否则下次扫描会把它当成另一首歌。
///
/// 只支持 mp3 / flac / m4a:wav 的 INFO chunk 与 aiff 装不下封面和歌词,ffmpeg 对它们的写入也不可靠。
enum MetadataWriter {
    enum Format: String {
        case mp3
        case flac
        case m4a

        /// vorbis comment 惯例是大写键;ID3 与 MP4 用小写。
        var usesUppercaseKeys: Bool {
            self == .flac
        }
    }

    /// 想写进去的内容,nil 表示这项没素材可写。
    struct Fields {
        var title: String?
        var artist: String?
        var album: String?
        var lyrics: String?
        /// 本地图片文件;仅在原文件没有内嵌封面时才会被使用。
        var artworkFileURL: URL?

        var isEmpty: Bool {
            title == nil && artist == nil && album == nil && lyrics == nil && artworkFileURL == nil
        }
    }

    /// 文件现有的标签状况,用来决定哪些字段还缺。
    struct Existing {
        let tags: [String: String]
        let hasEmbeddedArtwork: Bool

        /// ffprobe 对 MP3 返回小写键、FLAC 返回大写键,统一按小写查。
        private func value(anyOf names: [String]) -> String? {
            for name in names {
                if let value = tags[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        var title: String? { value(anyOf: ["title"]) }
        var artist: String? { value(anyOf: ["artist", "album_artist", "performer"]) }
        var album: String? { value(anyOf: ["album"]) }
        /// MP3 的 USLT 会被 ffprobe 报成 lyrics 或 lyrics-eng,FLAC 常见 LYRICS / UNSYNCEDLYRICS。
        var lyrics: String? {
            for (key, value) in tags where key.contains("lyric") {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return nil
        }
    }

    /// 一首歌这次实际会写什么。用于确认对话框与总结,也避免无谓地跑一次 ffmpeg。
    struct Plan {
        let format: Format
        let fields: Fields
        let keepsExistingArtwork: Bool

        var writtenFieldNames: [String] {
            var names: [String] = []
            if fields.title != nil { names.append("歌名") }
            if fields.artist != nil { names.append("歌手") }
            if fields.album != nil { names.append("专辑") }
            if fields.artworkFileURL != nil { names.append("封面") }
            if fields.lyrics != nil { names.append("歌词") }
            return names
        }

        var hasWork: Bool {
            !fields.isEmpty
        }
    }

    static var ffprobePath: String {
        (PlaybackAssetResolver.ffmpegPath as NSString).deletingLastPathComponent + "/ffprobe"
    }

    static func format(of url: URL) -> Format? {
        Format(rawValue: url.pathExtension.lowercased())
    }

    // MARK: - 读

    static func readExisting(from url: URL) throws -> Existing {
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw MetadataWriterError.ffprobeNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-show_entries", "format_tags:stream=codec_type,disposition",
            "-of", "json",
            url.path
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MetadataWriterError.probeFailed(url.lastPathComponent)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rawTags = (json["format"] as? [String: Any])?["tags"] as? [String: Any] ?? [:]
        var tags: [String: String] = [:]
        for (key, value) in rawTags {
            tags[key.lowercased()] = String(describing: value)
        }

        // 封面在容器里是一条视频流。个别文件没标 attached_pic，
        // 但音频容器里的视频流只可能是封面，所以只看 codec_type 就够。
        let streams = json["streams"] as? [[String: Any]] ?? []
        let hasArtwork = streams.contains { ($0["codec_type"] as? String) == "video" }

        return Existing(tags: tags, hasEmbeddedArtwork: hasArtwork)
    }

    /// 拿候选素材与文件现状对一遍,只留下真正缺的那几项。
    static func plan(format: Format, existing: Existing, candidate: Fields) -> Plan {
        var fields = Fields()
        if existing.title == nil { fields.title = nonEmpty(candidate.title) }
        if existing.artist == nil { fields.artist = nonEmpty(candidate.artist) }
        if existing.album == nil { fields.album = nonEmpty(candidate.album) }
        if existing.lyrics == nil { fields.lyrics = nonEmpty(candidate.lyrics) }
        if !existing.hasEmbeddedArtwork {
            fields.artworkFileURL = candidate.artworkFileURL
        }
        return Plan(format: format, fields: fields, keepsExistingArtwork: existing.hasEmbeddedArtwork)
    }

    // MARK: - 写

    /// ffmpeg 参数。抽成纯函数便于测试 —— 这几个 -map / -disposition 的组合最容易写错。
    static func arguments(input: URL, output: URL, plan: Plan) -> [String] {
        var args = [
            "-hide_banner",
            "-loglevel", "error",
            "-nostdin",
            "-y",
            "-i", input.path
        ]

        let addsArtwork = plan.fields.artworkFileURL != nil
        if let artwork = plan.fields.artworkFileURL {
            args += ["-i", artwork.path]
        }

        if addsArtwork {
            // 只取原文件的音频流,新封面作为第二路输入接上；否则原有的空视频流位会打架。
            args += ["-map", "0:a", "-map", "1:v"]
        } else {
            args += ["-map", "0"]
        }
        // 一律流拷贝：写标签不该重新编码，音质与耗时都不能动。
        args += ["-c", "copy"]

        if plan.format == .mp3 {
            args += ["-id3v2_version", "3"]
        }

        let upper = plan.format.usesUppercaseKeys
        func metadata(_ key: String, _ value: String) {
            args += ["-metadata", "\(upper ? key.uppercased() : key)=\(value)"]
        }
        if let title = plan.fields.title { metadata("title", title) }
        if let artist = plan.fields.artist { metadata("artist", artist) }
        if let album = plan.fields.album { metadata("album", album) }
        if let lyrics = plan.fields.lyrics { metadata("lyrics", lyrics) }

        if addsArtwork {
            args += [
                "-metadata:s:v", "title=Album cover",
                "-metadata:s:v", "comment=Cover (front)",
                "-disposition:v:0", "attached_pic"
            ]
        }

        args.append(output.path)
        return args
    }

    /// 备份保留策略：同一个文件只留最新一份，整体保留 14 天且总量不超过 1GB。
    /// 备份的价值是「刚写完发现不对能回滚」，放久了价值就没了，不该无限堆在磁盘上。
    static let backupRetentionDays = 14
    static let backupSizeLimitBytes: Int64 = 1_073_741_824

    static func backupUsage() -> (count: Int, bytes: Int64) {
        let entries = backupEntries()
        return (entries.count, entries.reduce(0) { $0 + $1.size })
    }

    static func clearAllBackups() throws {
        let directory = try backupDirectory()
        for entry in backupEntries() {
            try FileManager.default.removeItem(at: entry.url)
        }
        AppLog.library.notice("已清空元数据备份：\(directory.path, privacy: .public)")
    }

    /// 先按保留期删，仍超限就从最旧的继续删。写入任务结束后调一次。
    static func pruneBackups() {
        var entries = backupEntries().sorted { $0.date < $1.date }
        let cutoff = Date().addingTimeInterval(-Double(backupRetentionDays) * 86_400)
        var total = entries.reduce(0) { $0 + $1.size }
        var removed = 0

        entries.removeAll { entry in
            guard entry.date < cutoff else {
                return false
            }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            removed += 1
            return true
        }

        for entry in entries where total > backupSizeLimitBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            removed += 1
        }

        if removed > 0 {
            AppLog.library.notice("清理旧的元数据备份 \(removed, privacy: .public) 份")
        }
    }

    /// 同一个源文件的旧备份：重复写同一首歌时没必要留好几份。
    private static func removeEarlierBackups(ofStem stem: String) {
        for entry in backupEntries() where entry.url.lastPathComponent.hasPrefix("\(stem)-") {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    private static func backupEntries() -> [(url: URL, date: Date, size: Int64)] {
        guard let directory = try? backupDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
    }

    static func backupDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("LocalLrcPlayer", isDirectory: true)
            .appendingPathComponent("MetadataBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 备份 → ffmpeg 写临时文件 → 原子替换。任何一步失败都抛错,原文件保持不动。
    /// backupDirectory 默认是 Application Support 下的 MetadataBackups;测试传临时目录,免得污染用户数据。
    @discardableResult
    static func write(plan: Plan, to url: URL, backupDirectory: URL? = nil) throws -> URL {
        guard plan.hasWork else {
            throw MetadataWriterError.nothingToWrite
        }
        guard FileManager.default.isExecutableFile(atPath: PlaybackAssetResolver.ffmpegPath) else {
            throw MetadataWriterError.ffmpegNotFound
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw MetadataWriterError.notWritable(url.lastPathComponent)
        }

        let stamp = Self.backupStampFormatter.string(from: Date())
        let backupRoot = try backupDirectory ?? Self.backupDirectory()
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        if backupDirectory == nil {
            removeEarlierBackups(ofStem: url.deletingPathExtension().lastPathComponent)
        }
        let backupURL = backupRoot
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(stamp)")
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: backupURL)

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayer-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        // 临时文件必须保持同样的扩展名，ffmpeg 靠它决定输出容器。
        let outputURL = workDirectory.appendingPathComponent("out").appendingPathExtension(url.pathExtension)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: PlaybackAssetResolver.ffmpegPath)
        process.arguments = arguments(input: url, output: outputURL, plan: plan)
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            let message = String(data: errorData, encoding: .utf8) ?? "未知 ffmpeg 错误"
            throw MetadataWriterError.conversionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: outputURL)
        AppLog.library.notice("已写入元数据 \(url.lastPathComponent, privacy: .public)：\(plan.writtenFieldNames.joined(separator: "/"), privacy: .public)")
        return backupURL
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static let backupStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

enum MetadataWriterError: LocalizedError {
    case ffmpegNotFound
    case ffprobeNotFound
    case unsupportedFormat(String)
    case probeFailed(String)
    case conversionFailed(String)
    case notWritable(String)
    case nothingToWrite

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "未找到 ffmpeg，无法写入元数据（brew install ffmpeg）"
        case .ffprobeNotFound:
            return "未找到 ffprobe，无法读取现有标签（brew install ffmpeg）"
        case .unsupportedFormat(let ext):
            return "暂不支持写入 .\(ext) 的标签（仅 mp3 / flac / m4a）"
        case .probeFailed(let name):
            return "读取标签失败：\(name)"
        case .conversionFailed(let message):
            return "写入标签失败：\(message)"
        case .notWritable(let name):
            return "文件不可写：\(name)"
        case .nothingToWrite:
            return "没有需要补写的字段"
        }
    }
}
