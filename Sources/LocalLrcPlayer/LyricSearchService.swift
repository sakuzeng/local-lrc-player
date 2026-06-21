import Foundation

enum LyricProvider: String, CaseIterable {
    case netEase
    case qqMusic

    var displayName: String {
        switch self {
        case .netEase:
            return "网易云"
        case .qqMusic:
            return "QQ音乐"
        }
    }
}

final class LyricSearchService {
    private let netEaseClient = NetEaseLyricClient()
    private let qqMusicClient = QQMusicLyricClient()
    private let lyricLogRepository = LyricLogRepository()
    private let trackRepository = TrackRepository()
    private let minimumScore = 55

    func hasCookie(provider: LyricProvider) -> Bool {
        ((try? CookieStore.read(provider: provider)) ?? nil)?.isEmpty == false
    }

    func saveCookie(_ cookie: String, provider: LyricProvider) throws {
        try CookieStore.save(cookie, provider: provider)
    }

    func resetCookie(provider: LyricProvider) throws {
        try CookieStore.delete(provider: provider)
    }

    func searchCandidates(
        for track: MusicTrack,
        provider: LyricProvider,
        completion: @escaping (Result<[ScoredLyricCandidate], Error>) -> Void
    ) {
        let query = SearchQuery(track: track)

        switch provider {
        case .netEase:
            guard let cookie = readCookie(provider: provider) else {
                completion(.failure(LyricDownloadError.missingCookie(provider)))
                return
            }

            netEaseClient.search(keyword: query.keyword, cookie: cookie) { [weak self] result in
                guard let self else {
                    return
                }
                completion(result.map { candidates in
                    candidates
                        .map { self.scoredCandidate(from: $0, query: query) }
                        .sorted { $0.score > $1.score }
                })
            }

        case .qqMusic:
            guard let cookie = readCookie(provider: provider) else {
                completion(.failure(LyricDownloadError.missingCookie(provider)))
                return
            }

            qqMusicClient.search(keyword: query.keyword, cookie: cookie) { [weak self] result in
                guard let self else {
                    return
                }
                completion(result.map { candidates in
                    candidates
                        .map { self.scoredCandidate(from: $0, query: query) }
                        .sorted { $0.score > $1.score }
                })
            }
        }
    }

    func searchAllCandidates(
        for track: MusicTrack,
        completion: @escaping (Result<[LyricCandidateSection], Error>) -> Void
    ) {
        let hasNetEase = hasCookie(provider: .netEase)
        let hasQQMusic = hasCookie(provider: .qqMusic)

        guard hasNetEase || hasQQMusic else {
            completion(.failure(LyricDownloadError.noCookiesConfigured))
            return
        }

        let group = DispatchGroup()
        var netEaseCandidates: [ScoredLyricCandidate] = []
        var qqMusicCandidates: [ScoredLyricCandidate] = []
        var errors: [Error] = []
        let lock = NSLock()

        if hasNetEase {
            group.enter()
            searchCandidates(for: track, provider: .netEase) { result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let candidates):
                    netEaseCandidates = candidates
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }

        if hasQQMusic {
            group.enter()
            searchCandidates(for: track, provider: .qqMusic) { result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let candidates):
                    qqMusicCandidates = candidates
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            var sections: [LyricCandidateSection] = []
            if !netEaseCandidates.isEmpty {
                sections.append(LyricCandidateSection(provider: .netEase, candidates: netEaseCandidates))
            }
            if !qqMusicCandidates.isEmpty {
                sections.append(LyricCandidateSection(provider: .qqMusic, candidates: qqMusicCandidates))
            }

            if sections.isEmpty {
                if let error = errors.first {
                    completion(.failure(error))
                } else {
                    completion(.failure(LyricDownloadError.noCandidatesFound))
                }
                return
            }

            completion(.success(sections))
        }
    }

    func formattedLyric(for candidate: LyricCandidate, completion: @escaping (Result<String, Error>) -> Void) {
        switch candidate.provider {
        case .netEase:
            guard let cookie = readCookie(provider: candidate.provider) else {
                completion(.failure(LyricDownloadError.missingCookie(candidate.provider)))
                return
            }
            guard let songID = Int(candidate.identifier) else {
                completion(.failure(LyricDownloadError.invalidCandidate))
                return
            }
            netEaseClient.lyric(songID: songID, cookie: cookie) { result in
                completion(result.map { LyricFormatter.interleaved($0) })
            }

        case .qqMusic:
            guard let cookie = readCookie(provider: candidate.provider) else {
                completion(.failure(LyricDownloadError.missingCookie(candidate.provider)))
                return
            }
            qqMusicClient.lyric(songMid: candidate.identifier, cookie: cookie) { result in
                completion(result.map { LyricFormatter.interleaved($0) })
            }
        }
    }

    func saveFormattedLyric(_ lyric: String, for track: MusicTrack, replaceExisting: Bool = false) throws -> URL {
        let url = try LyricFileWriter.write(lyric, for: track, replaceExisting: replaceExisting)
        if let trackId = track.id {
            try trackRepository.markHasLyric(trackId: trackId, hasLyric: true)
        }
        return url
    }

    func downloadLyric(
        for track: MusicTrack,
        provider: LyricProvider,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if track.lyricURL != nil || FileManager.default.fileExists(atPath: LyricFileWriter.lyricURL(for: track).path) {
            completion(.failure(LyricDownloadError.lyricAlreadyExists))
            return
        }

        searchCandidates(for: track, provider: provider) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let candidates):
                let qualified = candidates.filter { $0.score >= self.minimumScore }
                guard !qualified.isEmpty else {
                    completion(.failure(LyricDownloadError.noReliableMatch(provider)))
                    return
                }

                self.tryDownloadLyric(from: qualified, for: track, index: 0, completion: completion)
            }
        }
    }

    /// 从已设置 Cookie 的所有来源中，按匹配分从高到低尝试，直到成功获取并保存歌词。
    func downloadBestAvailableLyric(
        for track: MusicTrack,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if track.lyricURL != nil || FileManager.default.fileExists(atPath: LyricFileWriter.lyricURL(for: track).path) {
            completion(.failure(LyricDownloadError.lyricAlreadyExists))
            return
        }

        searchAllCandidates(for: track) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let sections):
                let qualified = sections
                    .flatMap(\.candidates)
                    .filter { $0.score >= self.minimumScore }
                    .sorted { $0.score > $1.score }

                guard !qualified.isEmpty else {
                    completion(.failure(LyricDownloadError.noReliableMatchAnySource))
                    return
                }

                self.tryDownloadLyric(from: qualified, for: track, index: 0, completion: completion)
            }
        }
    }

    private let maxAutoDownloadAttempts = 8

    private func tryDownloadLyric(
        from candidates: [ScoredLyricCandidate],
        for track: MusicTrack,
        index: Int,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let attemptLimit = min(candidates.count, maxAutoDownloadAttempts)
        guard index < attemptLimit else {
            completion(.failure(LyricDownloadError.noUsableLyric))
            return
        }

        let match = candidates[index]
        formattedLyric(for: match.candidate) { [weak self] lyricResult in
            guard let self else {
                return
            }

            switch lyricResult {
            case .failure(let error):
                self.logAttempt(
                    track: track,
                    candidate: match.candidate,
                    score: match.score,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                self.tryDownloadLyric(from: candidates, for: track, index: index + 1, completion: completion)
            case .success(let lyric):
                self.logAttempt(
                    track: track,
                    candidate: match.candidate,
                    score: match.score,
                    success: true
                )
                do {
                    let url = try LyricFileWriter.writeIfMissing(lyric, for: track)
                    if let trackId = track.id {
                        try self.trackRepository.markHasLyric(trackId: trackId, hasLyric: true)
                    }
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func logAttempt(
        track: MusicTrack,
        candidate: LyricCandidate?,
        score: Int?,
        success: Bool,
        errorMessage: String? = nil
    ) {
        guard let trackId = track.id else {
            return
        }
        try? lyricLogRepository.logAttempt(
            trackId: trackId,
            provider: candidate?.provider ?? .netEase,
            candidate: candidate,
            score: score,
            success: success,
            errorMessage: errorMessage
        )
    }

    private func readCookie(provider: LyricProvider) -> String? {
        guard let cookie = try? CookieStore.read(provider: provider),
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return cookie
    }

    private func scoredCandidate(from candidate: NetEaseSongCandidate, query: SearchQuery) -> ScoredLyricCandidate {
        let lyricCandidate = LyricCandidate(
            provider: .netEase,
            identifier: String(candidate.id),
            name: candidate.name,
            artists: candidate.artists,
            album: candidate.album
        )
        return ScoredLyricCandidate(candidate: lyricCandidate, score: score(lyricCandidate, for: query))
    }

    private func scoredCandidate(from candidate: QQMusicSongCandidate, query: SearchQuery) -> ScoredLyricCandidate {
        let lyricCandidate = LyricCandidate(
            provider: .qqMusic,
            identifier: candidate.songMid,
            name: candidate.name,
            artists: candidate.artists,
            album: candidate.album
        )
        return ScoredLyricCandidate(candidate: lyricCandidate, score: score(lyricCandidate, for: query))
    }

    private func score(_ candidate: LyricCandidate, for query: SearchQuery) -> Int {
        let targetTitle = normalize(query.title)
        let candidateTitle = normalize(
            normalizedTitle(name: candidate.name, artists: candidate.artists, targetTitle: query.title)
        )
        let targetArtist = normalize(query.artist ?? "")

        var score = 0
        if candidateTitle == targetTitle {
            score += 70
        } else if candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle) {
            score += 45
        }

        if !targetArtist.isEmpty {
            let apiArtists = candidate.artists.map { normalize($0) }
            if apiArtists.contains(targetArtist) {
                score += 30
            }
        } else {
            score += 10
        }

        return score
    }

    /// 从 API 返回的混杂歌名中提取用于打分的干净歌名；不把从歌名识别出的歌手计入歌手分。
    private func normalizedTitle(name: String, artists: [String], targetTitle: String) -> String {
        var title = stripVersionSuffix(name.trimmingCharacters(in: .whitespacesAndNewlines))

        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for artist in artists {
            let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedArtist.isEmpty else {
                continue
            }

            if title.hasSuffix(" " + trimmedArtist) {
                title = String(title.dropLast(trimmedArtist.count + 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let trimmedTarget = targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTarget.isEmpty, title.hasPrefix(trimmedTarget) {
            let remainder = title.dropFirst(trimmedTarget.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.isEmpty || (!remainder.contains(" ") && remainder.count <= 12) {
                return trimmedTarget
            }
        }

        return title.isEmpty ? name : title
    }

    private func stripVersionSuffix(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*[\(\（][^)\）]*(?:Live|live|伴奏|Remix|remix|版|变速)[^)\）]*[\)\）]\s*$"#
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\(\)（）\[\]【】《》\-_.·]"#, with: "", options: .regularExpression)
    }
}

struct LyricCandidate {
    let provider: LyricProvider
    let identifier: String
    let name: String
    let artists: [String]
    let album: String?
}

struct ScoredLyricCandidate {
    let candidate: LyricCandidate
    let score: Int

    var displayTitle: String {
        "\(candidate.name) - \(candidate.artists.joined(separator: "/"))"
    }

    var detail: String {
        let album = candidate.album ?? "未知专辑"
        return "ID \(candidate.identifier) · \(album) · 匹配 \(score)"
    }
}

struct LyricCandidateSection {
    let provider: LyricProvider
    let candidates: [ScoredLyricCandidate]
}

struct SearchQuery {
    let title: String
    let artist: String?

    var keyword: String {
        if let artist, !artist.isEmpty {
            return "\(artist) \(title)"
        }
        return title
    }

    init(track: MusicTrack) {
        if let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = title
            return
        }

        let name = track.displayName
        let parts = name.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            artist = track.artist
            title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

enum LyricDownloadError: LocalizedError {
    case missingCookie(LyricProvider)
    case noCookiesConfigured
    case noCandidatesFound
    case lyricAlreadyExists
    case noReliableMatch(LyricProvider)
    case noReliableMatchAnySource
    case noUsableLyric
    case invalidCandidate

    var errorDescription: String? {
        switch self {
        case .missingCookie(let provider):
            return "请先设置\(provider.displayName) Cookie"
        case .noCookiesConfigured:
            return "请至少设置网易云或 QQ 音乐其中一个 Cookie"
        case .noCandidatesFound:
            return "未找到候选结果"
        case .lyricAlreadyExists:
            return "同名 LRC 已存在，已跳过"
        case .noReliableMatch(let provider):
            return "\(provider.displayName) 未找到可靠匹配的歌曲"
        case .noReliableMatchAnySource:
            return "所有来源均未找到可靠匹配的歌曲"
        case .noUsableLyric:
            return "高分候选均未返回可用歌词"
        case .invalidCandidate:
            return "候选歌曲信息无效"
        }
    }
}
