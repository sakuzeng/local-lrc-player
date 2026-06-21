import Foundation

struct QQMusicSongCandidate {
    let songMid: String
    let name: String
    let artists: [String]
    let album: String?
}

final class QQMusicLyricClient {
    func search(keyword: String, cookie: String, completion: @escaping (Result<[QQMusicSongCandidate], Error>) -> Void) {
        let loginUin = qqNumber(from: cookie)
        let payload: [String: Any] = [
            "comm": [
                "ct": 24,
                "cv": 0,
                "uin": loginUin,
                "g_tk": gTk(from: cookie)
            ],
            "req_1": [
                "module": "music.search.SearchCgiService",
                "method": "DoSearchForQQMusicDesktop",
                "param": [
                    "query": keyword,
                    "num_per_page": 20,
                    "page_num": 1,
                    "search_type": 0
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(to: &request, cookie: cookie)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let data = try Self.requireData(data)
                let response = try JSONDecoder().decode(QQMusicSearchResponse.self, from: data)
                let items = response.req_1?.data?.body.song.list ?? []
                let songs = items.compactMap { item -> QQMusicSongCandidate? in
                    guard let songMid = item.songMid, !songMid.isEmpty else {
                        return nil
                    }
                    return QQMusicSongCandidate(
                        songMid: songMid,
                        name: item.songName,
                        artists: item.singer.map(\.name),
                        album: item.albumName
                    )
                }
                DispatchQueue.main.async { completion(.success(songs)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    func lyric(songMid: String, cookie: String, completion: @escaping (Result<LyricBundle, Error>) -> Void) {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        let loginUin = qqNumber(from: cookie)
        components.queryItems = [
            URLQueryItem(name: "songmid", value: songMid),
            URLQueryItem(name: "g_tk", value: String(gTk(from: cookie))),
            URLQueryItem(name: "loginUin", value: loginUin),
            URLQueryItem(name: "hostUin", value: loginUin),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "inCharset", value: "utf8"),
            URLQueryItem(name: "outCharset", value: "utf-8"),
            URLQueryItem(name: "notice", value: "0"),
            URLQueryItem(name: "platform", value: "yqq.json"),
            URLQueryItem(name: "needNewCode", value: "0"),
            URLQueryItem(name: "nobase64", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        applyCommonHeaders(to: &request, cookie: cookie)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let data = try Self.requireData(data)
                let response = try JSONDecoder().decode(QQMusicLyricResponse.self, from: data)
                let original = self.decodePossibleBase64(response.lyric)
                guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw QQMusicLyricClientError.noLyric
                }
                let bundle = LyricBundle(
                    original: original,
                    translated: self.decodeOptionalPossibleBase64(response.trans),
                    english: nil
                )
                DispatchQueue.main.async { completion(.success(bundle)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func applyCommonHeaders(to request: inout URLRequest, cookie: String) {
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) LocalLrcPlayer", forHTTPHeaderField: "User-Agent")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    private func qqNumber(from cookie: String) -> String {
        let values = cookieValues(from: cookie)
        let raw = values["uin"] ?? values["p_uin"] ?? values["ptui_loginuin"] ?? "0"
        return raw.replacingOccurrences(of: #"^\D+"#, with: "", options: .regularExpression)
    }

    private func gTk(from cookie: String) -> Int {
        let values = cookieValues(from: cookie)
        guard let skey = values["p_skey"] ?? values["skey"] ?? values["qqmusic_key"] ?? values["qm_keyst"],
              !skey.isEmpty else {
            return 5381
        }

        var hash: Int64 = 5381
        for byte in skey.utf8 {
            hash = hash &+ (hash << 5) &+ Int64(byte)
        }
        return Int(hash & 0x7fffffff)
    }

    private func cookieValues(from cookie: String) -> [String: String] {
        cookie
            .split(separator: ";")
            .reduce(into: [String: String]()) { values, item in
                let parts = item.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    return
                }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                values[key] = value
            }
    }

    private func decodeOptionalPossibleBase64(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return decodePossibleBase64(value)
    }

    private func decodePossibleBase64(_ value: String) -> String {
        if value.contains("[") {
            return value
        }

        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8) else {
            return value
        }
        return decoded
    }

    private static func requireData(_ data: Data?) throws -> Data {
        guard let data, !data.isEmpty else {
            throw QQMusicLyricClientError.emptyResponse
        }
        return data
    }
}

private struct QQMusicSearchResponse: Decodable {
    let req_1: QQMusicSearchModule?
}

private struct QQMusicSearchModule: Decodable {
    let data: QQMusicSearchData?
}

private struct QQMusicSearchData: Decodable {
    let body: QQMusicSearchBody
}

private struct QQMusicSearchBody: Decodable {
    let song: QQMusicSongList
}

private struct QQMusicSongList: Decodable {
    let list: [QQMusicSearchItem]
}

private struct QQMusicSearchItem: Decodable {
    let mid: String?
    let songmid: String?
    let title: String?
    let name: String?
    let singer: [QQMusicSinger]
    let album: QQMusicAlbum?
    let albumname: String?

    var songMid: String? {
        mid ?? songmid
    }

    var songName: String {
        title ?? name ?? ""
    }

    var albumName: String? {
        album?.title ?? album?.name ?? albumname
    }
}

private struct QQMusicSinger: Decodable {
    let name: String
}

private struct QQMusicAlbum: Decodable {
    let title: String?
    let name: String?
}

private struct QQMusicLyricResponse: Decodable {
    let lyric: String
    let trans: String?
}

enum QQMusicLyricClientError: LocalizedError {
    case emptyResponse
    case noLyric

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "QQ 音乐返回为空"
        case .noLyric:
            return "QQ 音乐未返回可用歌词"
        }
    }
}
