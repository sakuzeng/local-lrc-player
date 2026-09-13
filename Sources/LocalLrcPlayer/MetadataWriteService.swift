import AppKit

/// 批量/单首元数据写入的编排：收集素材 → 写文件 → 更新索引 → 报进度。
/// 素材优先用本地已有的东西(文件名、旁边的 .lrc、封面缓存),都缺才去歌词源搜一次;
/// 没配 Cookie 就纯本地补,不报错。串行处理,随时可停。
final class MetadataWriteService {
    struct Outcome {
        let track: MusicTrack
        /// 实际写进去的字段名；空数组表示这首没什么可补的。
        let writtenFields: [String]
        let error: Error?

        var didWrite: Bool {
            error == nil && !writtenFields.isEmpty
        }
    }

    struct Summary {
        var written: [Outcome] = []
        var skipped: [Outcome] = []
        var failed: [Outcome] = []
        var cancelled = false

        var text: String {
            var parts = ["成功 \(written.count)"]
            if !skipped.isEmpty {
                parts.append("无需补写 \(skipped.count)")
            }
            if !failed.isEmpty {
                parts.append("失败 \(failed.count)")
            }
            if cancelled {
                parts.append("已停止")
            }
            return parts.joined(separator: "，")
        }
    }

    private let lyricSearchService: LyricSearchService
    private let trackRepository: TrackRepository
    private let queue = DispatchQueue(label: "local.lrc.player.metadata-write", qos: .userInitiated)
    private var isCancelled = false

    private(set) var isRunning = false

    init(lyricSearchService: LyricSearchService, trackRepository: TrackRepository) {
        self.lyricSearchService = lyricSearchService
        self.trackRepository = trackRepository
    }

    func cancel() {
        isCancelled = true
    }

    /// tracks 按顺序逐首处理；progress 在每首开始前回调（主线程），completion 在全部结束后回调。
    func run(
        tracks: [MusicTrack],
        progress: @escaping (Int, MusicTrack) -> Void,
        completion: @escaping (Summary) -> Void
    ) {
        guard !isRunning else {
            return
        }
        isRunning = true
        isCancelled = false
        process(tracks: tracks, index: 0, summary: Summary(), progress: progress, completion: completion)
    }

    private func process(
        tracks: [MusicTrack],
        index: Int,
        summary: Summary,
        progress: @escaping (Int, MusicTrack) -> Void,
        completion: @escaping (Summary) -> Void
    ) {
        var summary = summary
        guard index < tracks.count, !isCancelled else {
            summary.cancelled = isCancelled
            isRunning = false
            completion(summary)
            return
        }

        let track = tracks[index]
        progress(index, track)

        collectFields(for: track) { [weak self] candidate in
            guard let self else {
                return
            }
            self.queue.async {
                let outcome = self.writeSynchronously(track: track, candidate: candidate)
                DispatchQueue.main.async {
                    var next = summary
                    if outcome.error != nil {
                        next.failed.append(outcome)
                    } else if outcome.writtenFields.isEmpty {
                        next.skipped.append(outcome)
                    } else {
                        next.written.append(outcome)
                    }
                    self.process(
                        tracks: tracks,
                        index: index + 1,
                        summary: next,
                        progress: progress,
                        completion: completion
                    )
                }
            }
        }
    }

    /// 在后台队列上跑：读现有标签 → 算计划 → ffmpeg 写 → 更新索引。
    private func writeSynchronously(track: MusicTrack, candidate: MetadataWriter.Fields) -> Outcome {
        guard let format = MetadataWriter.format(of: track.audioURL) else {
            return Outcome(
                track: track,
                writtenFields: [],
                error: MetadataWriterError.unsupportedFormat(track.audioURL.pathExtension)
            )
        }

        do {
            let existing = try MetadataWriter.readExisting(from: track.audioURL)
            let plan = MetadataWriter.plan(format: format, existing: existing, candidate: candidate)
            guard plan.hasWork else {
                return Outcome(track: track, writtenFields: [], error: nil)
            }
            try MetadataWriter.write(plan: plan, to: track.audioURL)
            // 文件内容变了，索引里的哈希与 mtime/size 必须跟着走，否则下次扫描当成另一首。
            if let trackId = track.id {
                try trackRepository.refreshAfterMetadataWrite(trackId: trackId, fileURL: track.audioURL)
            }
            return Outcome(track: track, writtenFields: plan.writtenFieldNames, error: nil)
        } catch {
            AppLog.library.error("写入元数据失败 \(track.displayName, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            return Outcome(track: track, writtenFields: [], error: error)
        }
    }

    // MARK: - 素材收集

    /// 本地能凑出来的先凑；歌名/歌手/专辑/封面还缺才联网搜一次。回调在主线程。
    private func collectFields(for track: MusicTrack, completion: @escaping (MetadataWriter.Fields) -> Void) {
        var fields = MetadataWriter.Fields()

        // 歌名/歌手：ID3 有就用，没有就按文件名的「歌手 - 歌名」拆。
        let stem = track.audioURL.deletingPathExtension().lastPathComponent
        if let title = track.title, !title.isEmpty {
            fields.title = title
            fields.artist = track.artist
        } else if let parsed = MusicTrack.parseArtistTitle(stem) {
            fields.title = parsed.title
            fields.artist = parsed.artist
        } else {
            fields.title = stem
            fields.artist = track.artist
        }
        fields.album = track.album

        // 歌词：旁边的 .lrc 才是真相，原样带时间戳写进去，方便别的播放器同步显示。
        if let lyricURL = track.lyricURL,
           let contents = (try? String(contentsOf: lyricURL, encoding: .utf8))
            ?? (try? String(contentsOf: lyricURL, encoding: .utf16)),
           !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.lyrics = contents
        }

        // 封面：先看已下载的缓存。
        if let trackId = track.id,
           let cached = try? ArtworkCache.fileURL(trackId: trackId),
           FileManager.default.fileExists(atPath: cached.path) {
            fields.artworkFileURL = cached
        }

        let needsOnline = fields.album == nil || fields.artist == nil || fields.artworkFileURL == nil
        guard needsOnline, hasAnyCookie else {
            completion(fields)
            return
        }

        lyricSearchService.searchAllCandidates(for: track) { [weak self] result in
            guard let self, case .success(let sections) = result else {
                completion(fields)
                return
            }
            let best = sections
                .flatMap(\.candidates)
                .filter { $0.score >= Self.minimumCandidateScore }
                .sorted { $0.score > $1.score }
                .first?
                .candidate

            guard let best else {
                completion(fields)
                return
            }
            if fields.artist == nil, !best.artists.isEmpty {
                fields.artist = best.artists.joined(separator: "/")
            }
            if fields.album == nil {
                fields.album = best.album
            }
            guard fields.artworkFileURL == nil, let trackId = track.id else {
                completion(fields)
                return
            }
            self.downloadArtwork(for: best, trackId: trackId) { url in
                fields.artworkFileURL = url
                completion(fields)
            }
        }
    }

    private func downloadArtwork(for candidate: LyricCandidate, trackId: Int64, completion: @escaping (URL?) -> Void) {
        lyricSearchService.albumPicURL(for: candidate) { url in
            guard let url else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, !data.isEmpty else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                // 借用封面缓存目录存盘，写 tag 需要一个真实文件路径。
                ArtworkCache.save(data, trackId: trackId)
                let saved = try? ArtworkCache.fileURL(trackId: trackId)
                DispatchQueue.main.async {
                    completion(saved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil })
                }
            }.resume()
        }
    }

    private var hasAnyCookie: Bool {
        lyricSearchService.hasCookie(provider: .netEase) || lyricSearchService.hasCookie(provider: .qqMusic)
    }

    private static let minimumCandidateScore = 55
}
