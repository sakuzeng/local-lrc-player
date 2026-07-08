import AppKit
import Foundation

/// 无内嵌封面时的网络兜底：复用歌词搜索的候选评分挑最可靠的匹配，
/// 再向对应来源要专辑图。全程静默失败，成功后写入 ArtworkCache。
final class ArtworkDownloadService {
    private let lyricSearchService: LyricSearchService
    private let minimumScore = 55
    private let maxAttempts = 4

    init(lyricSearchService: LyricSearchService) {
        self.lyricSearchService = lyricSearchService
    }

    func fetchArtwork(for track: MusicTrack, completion: @escaping (NSImage?) -> Void) {
        lyricSearchService.searchAllCandidates(for: track) { [weak self] result in
            guard let self, case .success(let sections) = result else {
                completion(nil)
                return
            }

            let qualified = sections
                .flatMap(\.candidates)
                .filter { $0.score >= self.minimumScore }
                .sorted { $0.score > $1.score }
                .map(\.candidate)

            self.tryFetch(from: qualified, index: 0, trackId: track.id, completion: completion)
        }
    }

    private func tryFetch(
        from candidates: [LyricCandidate],
        index: Int,
        trackId: Int64?,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard index < min(candidates.count, maxAttempts) else {
            completion(nil)
            return
        }

        lyricSearchService.albumPicURL(for: candidates[index]) { [weak self] url in
            guard let self else {
                return
            }
            guard let url else {
                self.tryFetch(from: candidates, index: index + 1, trackId: trackId, completion: completion)
                return
            }

            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    if let data, let image = NSImage(data: data) {
                        if let trackId {
                            ArtworkCache.save(data, trackId: trackId)
                        }
                        completion(image)
                    } else {
                        self.tryFetch(from: candidates, index: index + 1, trackId: trackId, completion: completion)
                    }
                }
            }.resume()
        }
    }
}
