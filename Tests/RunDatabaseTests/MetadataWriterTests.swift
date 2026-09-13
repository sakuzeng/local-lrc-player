import Foundation

/// 元数据写入：只补缺失字段的判定、ffmpeg 参数构造，以及一次真实的端到端写入（需要 ffmpeg）。
struct MetadataWriterTests {
    func runAll() throws {
        try testPlanOnlyFillsMissingFields()
        try testPlanKeepsExistingArtwork()
        try testArgumentsWithoutArtworkKeepAllStreams()
        try testArgumentsWithArtworkAttachCoverAndUppercaseFlacKeys()
        try testEndToEndWriteAndBackup()
        try testIndexStaysOnTheSameTrackAfterWriting()
    }

    private func existing(_ tags: [String: String], artwork: Bool = false) -> MetadataWriter.Existing {
        MetadataWriter.Existing(tags: tags, hasEmbeddedArtwork: artwork)
    }

    private func fullCandidate(artwork: URL? = URL(fileURLWithPath: "/tmp/cover.jpg")) -> MetadataWriter.Fields {
        MetadataWriter.Fields(
            title: "新歌名",
            artist: "新歌手",
            album: "新专辑",
            lyrics: "[00:01.00]词",
            artworkFileURL: artwork
        )
    }

    private func testPlanOnlyFillsMissingFields() throws {
        // 已有歌名与歌手，只补专辑和歌词。
        let plan = MetadataWriter.plan(
            format: .mp3,
            existing: existing(["title": "原歌名", "artist": "原歌手"]),
            candidate: fullCandidate(artwork: nil)
        )
        try assertTrue(plan.fields.title == nil, "existing title must not be overwritten")
        try assertTrue(plan.fields.artist == nil, "existing artist must not be overwritten")
        try assertEqual(plan.fields.album, "新专辑")
        try assertEqual(plan.fields.lyrics, "[00:01.00]词")
        try assertEqual(plan.writtenFieldNames, ["专辑", "歌词"])

        // 空白字符串等于没有，要补。
        let blank = MetadataWriter.plan(format: .mp3, existing: existing(["title": "   "]), candidate: fullCandidate(artwork: nil))
        try assertEqual(blank.fields.title, "新歌名", "whitespace-only tags count as missing")

        // 什么都不缺时没有活干。
        let nothing = MetadataWriter.plan(
            format: .mp3,
            existing: existing(["title": "a", "artist": "b", "album": "c", "lyrics": "d"], artwork: true),
            candidate: fullCandidate()
        )
        try assertTrue(!nothing.hasWork, "nothing missing means nothing to write")
    }

    private func testPlanKeepsExistingArtwork() throws {
        let withCover = MetadataWriter.plan(format: .mp3, existing: existing([:], artwork: true), candidate: fullCandidate())
        try assertTrue(withCover.fields.artworkFileURL == nil, "existing artwork is never replaced")
        try assertTrue(withCover.keepsExistingArtwork, "plan records that the cover stays")

        let withoutCover = MetadataWriter.plan(format: .mp3, existing: existing([:], artwork: false), candidate: fullCandidate())
        try assertTrue(withoutCover.fields.artworkFileURL != nil, "missing artwork gets filled")
    }

    private func testArgumentsWithoutArtworkKeepAllStreams() throws {
        let plan = MetadataWriter.plan(format: .mp3, existing: existing([:], artwork: true), candidate: fullCandidate())
        let args = MetadataWriter.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mp3"),
            output: URL(fileURLWithPath: "/tmp/out.mp3"),
            plan: plan
        )
        try assertTrue(args.contains("-map") && args.contains("0"), "all input streams are kept")
        try assertTrue(!args.contains("attached_pic"), "no cover is attached when one already exists")
        try assertTrue(args.contains("-c") && args.contains("copy"), "tags must never re-encode audio")
        try assertTrue(args.contains("-id3v2_version"), "mp3 needs an explicit ID3 version")
        try assertTrue(args.contains("title=新歌名"), "missing title is written")
        try assertEqual(args.last, "/tmp/out.mp3", "output path goes last")
    }

    private func testArgumentsWithArtworkAttachCoverAndUppercaseFlacKeys() throws {
        let plan = MetadataWriter.plan(format: .flac, existing: existing([:]), candidate: fullCandidate())
        let args = MetadataWriter.arguments(
            input: URL(fileURLWithPath: "/tmp/in.flac"),
            output: URL(fileURLWithPath: "/tmp/out.flac"),
            plan: plan
        )
        try assertTrue(args.contains("0:a") && args.contains("1:v"), "audio from input 0, cover from input 1")
        try assertTrue(args.contains("attached_pic"), "cover stream is marked as attached picture")
        try assertTrue(args.contains("TITLE=新歌名"), "vorbis comments use uppercase keys")
        try assertTrue(!args.contains("-id3v2_version"), "flac has no ID3 version flag")
    }

    /// 真机口径的验证：生成一个无标签 mp3 → 写入 → ffprobe 读回 → 备份存在且原文件被替换。
    private func testEndToEndWriteAndBackup() throws {
        guard FileManager.default.isExecutableFile(atPath: PlaybackAssetResolver.ffmpegPath),
              FileManager.default.isExecutableFile(atPath: MetadataWriter.ffprobePath) else {
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = root.appendingPathComponent("sample.mp3")
        try runFFmpeg(["-f", "lavfi", "-i", "sine=frequency=440:duration=1", audioURL.path])

        let before = try MetadataWriter.readExisting(from: audioURL)
        try assertTrue(before.title == nil, "generated file starts without a title")

        let plan = MetadataWriter.plan(
            format: .mp3,
            existing: before,
            candidate: MetadataWriter.Fields(title: "端到端", artist: "测试歌手", album: "测试专辑", lyrics: "[00:00.00]一行", artworkFileURL: nil)
        )
        try assertTrue(plan.hasWork, "an untagged file always has work")
        let backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        let backupURL = try MetadataWriter.write(plan: plan, to: audioURL, backupDirectory: backupsDirectory)

        let after = try MetadataWriter.readExisting(from: audioURL)
        try assertEqual(after.title, "端到端")
        try assertEqual(after.artist, "测试歌手")
        try assertEqual(after.album, "测试专辑")
        try assertTrue(after.lyrics?.contains("一行") == true, "lyrics are embedded")

        try assertTrue(FileManager.default.fileExists(atPath: backupURL.path), "the original is backed up before writing")
        let backupTags = try MetadataWriter.readExisting(from: backupURL)
        try assertTrue(backupTags.title == nil, "the backup keeps the pre-write state")

        // 内容变了 → 哈希必须变，这正是索引需要跟着更新的原因。
        let backupHash = try TrackContentHasher.hash(fileURL: backupURL)
        let writtenHash = try TrackContentHasher.hash(fileURL: audioURL)
        try assertTrue(backupHash != writtenHash, "writing tags changes the content hash")
    }

    /// ROADMAP 定的关键约束：写标签改变了文件内容与哈希，索引必须跟着更新，
    /// 否则下次扫描会把同一首歌当成新曲目，播放状态与列表位置都会丢。
    private func testIndexStaysOnTheSameTrackAfterWriting() throws {
        guard FileManager.default.isExecutableFile(atPath: PlaybackAssetResolver.ffmpegPath),
              FileManager.default.isExecutableFile(atPath: MetadataWriter.ffprobePath) else {
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = folder.appendingPathComponent("sample.mp3")
        try runFFmpeg(["-f", "lavfi", "-i", "sine=frequency=440:duration=1", audioURL.path])

        let database = try AppDatabase(fileURL: root.appendingPathComponent("test.sqlite"))
        let libraryRepository = LibraryRepository(database: database)
        let trackRepository = TrackRepository(database: database)
        let library = try libraryRepository.registerLibrary(at: folder)
        _ = try trackRepository.sync(libraryId: library.id, folderURL: folder)

        let before = try trackRepository.masterPlaylistTracks()
        try assertEqual(before.count, 1)
        let trackId = before[0].id
        let hashBefore = before[0].contentHash

        let plan = MetadataWriter.plan(
            format: .mp3,
            existing: try MetadataWriter.readExisting(from: audioURL),
            candidate: MetadataWriter.Fields(title: "写入后的歌名", artist: "写入后的歌手", album: nil, lyrics: nil, artworkFileURL: nil)
        )
        try MetadataWriter.write(plan: plan, to: audioURL, backupDirectory: root.appendingPathComponent("Backups", isDirectory: true))
        try trackRepository.refreshAfterMetadataWrite(trackId: trackId, fileURL: audioURL)

        let updated = try trackRepository.masterPlaylistTracks()
        try assertEqual(updated.count, 1, "still one track")
        try assertEqual(updated[0].id, trackId, "same row, same id")
        try assertEqual(updated[0].title, "写入后的歌名", "index picks up the new tags")
        try assertTrue(updated[0].contentHash != hashBefore, "content hash is refreshed")

        // 关键：再同步一次不能多出一首，也不能换 id。
        _ = try trackRepository.syncAll(libraries: try libraryRepository.allLibraries())
        let rescanned = try trackRepository.masterPlaylistTracks()
        try assertEqual(rescanned.count, 1, "rescan must not treat the rewritten file as a new song")
        try assertEqual(rescanned[0].id, trackId, "rescan keeps the original track id")
    }

    private func runFFmpeg(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PlaybackAssetResolver.ffmpegPath)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + arguments
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TestFailure.message("ffmpeg fixture failed: \(arguments.joined(separator: " "))")
        }
    }
}
