import Foundation

struct LyricBundle {
    let original: String
    let translated: String?
    let english: String?
}

enum LyricFormatter {
    static func interleaved(_ bundle: LyricBundle) -> String {
        let originals = parseTimedLines(bundle.original)
        guard !originals.isEmpty else {
            return bundle.original
        }

        let translations = dictionaryByTime(parseTimedLines(bundle.translated ?? ""))
        let english = dictionaryByTime(parseTimedLines(bundle.english ?? ""))

        var output: [String] = []
        for line in originals {
            output.append("[\(line.timestamp)]\(line.text)")

            if let translated = translations[line.timeKey], !translated.isEmpty, translated != line.text {
                output.append("[\(line.timestamp)]\(stripSingerPrefix(translated))")
            }

            if let englishLine = english[line.timeKey],
               !englishLine.isEmpty,
               englishLine != line.text,
               englishLine != translations[line.timeKey] {
                output.append("[\(line.timestamp)]\(stripSingerPrefix(englishLine))")
            }
        }

        return output.joined(separator: "\n")
    }

    private static func dictionaryByTime(_ lines: [TimedLyricLine]) -> [Int: String] {
        Dictionary(lines.map { ($0.timeKey, $0.text) }, uniquingKeysWith: { first, _ in first })
    }

    private static func parseTimedLines(_ contents: String) -> [TimedLyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#) else {
            return []
        }

        var result: [TimedLyricLine] = []
        for rawLine in contents.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else {
                continue
            }

            let text = stripSingerPrefix(
                regex.stringByReplacingMatches(
                    in: rawLine,
                    range: range,
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !text.isEmpty else {
                continue
            }

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: rawLine),
                    let secondRange = Range(match.range(at: 2), in: rawLine),
                    let minutes = Int(rawLine[minuteRange]),
                    let seconds = Int(rawLine[secondRange])
                else {
                    continue
                }

                let fractionText: String
                let milliseconds: Int
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: rawLine) {
                    fractionText = String(rawLine[fractionRange])
                    milliseconds = normalizedMilliseconds(fractionText)
                } else {
                    fractionText = "000"
                    milliseconds = 0
                }

                let timeKey = (minutes * 60 + seconds) * 1000 + milliseconds
                let timestamp = String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
                result.append(TimedLyricLine(timeKey: timeKey, timestamp: timestamp, text: text))
            }
        }

        return result.sorted { $0.timeKey < $1.timeKey }
    }

    private static let rolePrefixes: Set<String> = ["合", "男", "女", "合唱", "旁白", "A", "B", "C", "D"]

    /// 去掉行首的歌手名或角色前缀，例如 `田翌臣: `、`合： `。
    static func stripSingerPrefix(_ text: String) -> String {
        let colonIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" })
        guard let colonIndex else {
            return text
        }

        let prefix = String(text[..<colonIndex])
        let suffix = String(text[text.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)

        guard
            !prefix.isEmpty,
            prefix.count <= 10,
            !prefix.contains(" "),
            !suffix.isEmpty
        else {
            return text
        }

        let isRole = rolePrefixes.contains(prefix)
        let looksLikeName = prefix.allSatisfy { character in
            character.isLetter || character.isNumber || character == "·"
        }

        guard isRole || (looksLikeName && prefix.count <= 8) else {
            return text
        }

        return suffix
    }

    private static func normalizedMilliseconds(_ fractionText: String) -> Int {
        let padded = String((fractionText + "000").prefix(3))
        return Int(padded) ?? 0
    }
}

private struct TimedLyricLine {
    let timeKey: Int
    let timestamp: String
    let text: String
}
