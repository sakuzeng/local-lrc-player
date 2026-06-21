import Foundation

enum CookieStore {
    static func save(_ cookie: String, provider: LyricProvider) throws {
        let url = try cookieURL(provider: provider)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try cookie.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(provider: LyricProvider) throws -> String? {
        let url = try cookieURL(provider: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func delete(provider: LyricProvider) throws {
        let url = try cookieURL(provider: provider)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func cookieURL(provider: LyricProvider) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("LocalLrcPlayer", isDirectory: true)
            .appendingPathComponent(fileName(for: provider))
    }

    private static func fileName(for provider: LyricProvider) -> String {
        switch provider {
        case .netEase:
            return "netease-cookie.txt"
        case .qqMusic:
            return "qqmusic-cookie.txt"
        }
    }
}
