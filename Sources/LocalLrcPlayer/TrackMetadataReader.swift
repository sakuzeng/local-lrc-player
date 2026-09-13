import AVFoundation
import Foundation

enum TrackMetadataReader {
    struct Metadata {
        let title: String?
        let artist: String?
        let album: String?
        let duration: TimeInterval?
    }

    static func read(from url: URL) -> Metadata {
        let asset = AVURLAsset(url: url)
        let common = asset.commonMetadata

        let title = firstString(in: common, identifiers: [
            .commonIdentifierTitle,
            AVMetadataIdentifier(rawValue: "titl")
        ])
        let artist = firstString(in: common, identifiers: [
            .commonIdentifierArtist,
            AVMetadataIdentifier(rawValue: "art")
        ])
        let album = firstString(in: common, identifiers: [
            .commonIdentifierAlbumName,
            AVMetadataIdentifier(rawValue: "alb")
        ])

        let durationSeconds = asset.duration.seconds
        let duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil

        let commonTitle = cleaned(title)
        let commonArtist = cleaned(artist)
        let commonAlbum = cleaned(album)

        // AVFoundation 读不出 FLAC 的 vorbis comment(时长能读,标签全是 nil),
        // 这类文件只好退回 ffprobe 再读一次,否则列表、菜单栏、系统「正在播放」都只能显示文件名。
        // 只在三项全空时才走这条路:ffprobe 是外部进程,不该每首歌都开一次。
        if commonTitle == nil, commonArtist == nil, commonAlbum == nil,
           let probed = try? MetadataWriter.readExisting(from: url),
           probed.title != nil || probed.artist != nil || probed.album != nil {
            return Metadata(
                title: probed.title,
                artist: probed.artist,
                album: probed.album,
                duration: duration
            )
        }

        return Metadata(
            title: commonTitle,
            artist: commonArtist,
            album: commonAlbum,
            duration: duration
        )
    }

    /// 读取内嵌封面（ID3 APIC / FLAC PICTURE / MP4 covr），无则返回 nil。
    static func artworkData(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let items = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            filteredByIdentifier: .commonIdentifierArtwork
        )
        return items.first?.dataValue
    }

    private static func firstString(in metadata: [AVMetadataItem], identifiers: [AVMetadataIdentifier]) -> String? {
        for identifier in identifiers {
            if let value = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first?.stringValue {
                return value
            }
        }
        return nil
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
