import Foundation

struct NetEaseSongCandidate {
    let id: Int
    let name: String
    let artists: [String]
    let album: String?
}

final class NetEaseLyricClient {
    func search(keyword: String, cookie: String, completion: @escaping (Result<[NetEaseSongCandidate], Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://music.163.com/api/search/get/web")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(to: &request, cookie: cookie)

        let body = [
            "s": keyword,
            "type": "1",
            "limit": "10",
            "offset": "0"
        ]
        request.httpBody = formEncoded(body).data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let data = try Self.requireData(data)
                let response = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
                let songs = response.result?.songs?.map {
                    NetEaseSongCandidate(
                        id: $0.id,
                        name: $0.name,
                        artists: $0.artists.map(\.name),
                        album: $0.album?.name
                    )
                } ?? []
                DispatchQueue.main.async { completion(.success(songs)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    func lyric(songID: Int, cookie: String, completion: @escaping (Result<LyricBundle, Error>) -> Void) {
        lyric(songID: songID, cookie: cookie, includeTranslations: true, completion: completion)
    }

    private func lyric(
        songID: Int,
        cookie: String,
        includeTranslations: Bool,
        completion: @escaping (Result<LyricBundle, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")!
        var queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1")
        ]
        if includeTranslations {
            queryItems.append(URLQueryItem(name: "tv", value: "1"))
            queryItems.append(URLQueryItem(name: "rv", value: "1"))
        } else {
            queryItems.append(URLQueryItem(name: "tv", value: "-1"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        applyCommonHeaders(to: &request, cookie: cookie)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                if includeTranslations {
                    self.lyric(songID: songID, cookie: cookie, includeTranslations: false, completion: completion)
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            do {
                let data = try Self.requireData(data)
                let response = try JSONDecoder().decode(NetEaseLyricResponse.self, from: data)
                guard let lyric = response.lrc?.lyric, !lyric.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NetEaseLyricClientError.noLyric
                }
                let bundle = LyricBundle(
                    original: lyric,
                    translated: response.tlyric?.lyric,
                    english: response.ytlrc?.lyric
                )
                DispatchQueue.main.async { completion(.success(bundle)) }
            } catch {
                if includeTranslations {
                    self.lyric(songID: songID, cookie: cookie, includeTranslations: false, completion: completion)
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }

    private func applyCommonHeaders(to request: inout URLRequest, cookie: String) {
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) LocalLrcPlayer", forHTTPHeaderField: "User-Agent")
        if !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
    }

    private func formEncoded(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func requireData(_ data: Data?) throws -> Data {
        guard let data, !data.isEmpty else {
            throw NetEaseLyricClientError.emptyResponse
        }
        return data
    }
}

private struct NetEaseSearchResponse: Decodable {
    let result: NetEaseSearchResult?
}

private struct NetEaseSearchResult: Decodable {
    let songs: [NetEaseSearchSong]?
}

private struct NetEaseSearchSong: Decodable {
    let id: Int
    let name: String
    let artists: [NetEaseArtist]
    let album: NetEaseAlbum?
}

private struct NetEaseArtist: Decodable {
    let name: String
}

private struct NetEaseAlbum: Decodable {
    let name: String
}

private struct NetEaseLyricResponse: Decodable {
    let lrc: NetEaseLyricContent?
    let tlyric: NetEaseLyricContent?
    let ytlrc: NetEaseLyricContent?
}

private struct NetEaseLyricContent: Decodable {
    let lyric: String?
}

enum NetEaseLyricClientError: LocalizedError {
    case emptyResponse
    case noLyric

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "网易云返回为空"
        case .noLyric:
            return "网易云未返回可用歌词"
        }
    }
}
