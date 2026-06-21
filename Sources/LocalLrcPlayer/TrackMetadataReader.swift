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

        return Metadata(
            title: cleaned(title),
            artist: cleaned(artist),
            album: cleaned(album),
            duration: duration
        )
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
