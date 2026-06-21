import Foundation

struct LrcLine {
    let time: TimeInterval
    let text: String
}

enum LrcParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    private static let displayGroupTolerance: TimeInterval = 0.05

    static func parse(_ contents: String) -> [LrcLine] {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        var lines: [LrcLine] = []
        let rawLines = contents.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else {
                continue
            }

            let text = regex.stringByReplacingMatches(
                in: rawLine,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                continue
            }

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: rawLine),
                    let secondRange = Range(match.range(at: 2), in: rawLine),
                    let minutes = Double(rawLine[minuteRange]),
                    let seconds = Double(rawLine[secondRange])
                else {
                    continue
                }

                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: rawLine),
                   let fractionValue = Double(rawLine[fractionRange]) {
                    let digits = rawLine[fractionRange].count
                    fraction = fractionValue / pow(10.0, Double(digits))
                }

                lines.append(LrcLine(time: minutes * 60.0 + seconds + fraction, text: text))
            }
        }

        return normalizedDisplayOrder(lines)
    }

    /// 将时间接近（50ms 内）的多行歌词归为一组，组内按语言组合固定显示顺序：
    /// - 日文歌：日文原文 → 中文译文 → 英文译文
    /// - 英文歌：英文原文 → 中文译文
    /// - 仅一种语言时保持原顺序
    static func normalizedDisplayOrder(_ lines: [LrcLine]) -> [LrcLine] {
        guard !lines.isEmpty else {
            return []
        }

        let sorted = lines.enumerated().sorted { lhs, rhs in
            if lhs.element.time != rhs.element.time {
                return lhs.element.time < rhs.element.time
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var groups: [[LrcLine]] = []
        var currentGroup: [LrcLine] = [sorted[0]]

        for line in sorted.dropFirst() {
            if line.time - currentGroup[0].time <= displayGroupTolerance {
                currentGroup.append(line)
            } else {
                groups.append(sortGroupForDisplay(currentGroup))
                currentGroup = [line]
            }
        }
        groups.append(sortGroupForDisplay(currentGroup))

        return groups.flatMap { $0 }
    }

    static func activeLineIndex(for time: TimeInterval, in lines: [LrcLine]) -> Int? {
        guard !lines.isEmpty else {
            return nil
        }

        var groups: [[Int]] = []
        var currentGroup: [Int] = [0]

        for index in 1..<lines.count {
            if lines[index].time - lines[currentGroup[0]].time <= displayGroupTolerance {
                currentGroup.append(index)
            } else {
                groups.append(currentGroup)
                currentGroup = [index]
            }
        }
        groups.append(currentGroup)

        var activeGroup: [Int]?
        for group in groups {
            guard let first = group.first else {
                continue
            }
            if lines[first].time <= time {
                activeGroup = group
            } else {
                break
            }
        }

        guard let activeGroup else {
            return nil
        }

        return activeGroup.max { lhs, rhs in
            displayPreferenceScore(for: lines[lhs].text) < displayPreferenceScore(for: lines[rhs].text)
        }
    }

    private static func sortGroupForDisplay(_ group: [LrcLine]) -> [LrcLine] {
        let kinds = Set(group.map { languageKind(for: $0.text) })
        let hasJapanese = kinds.contains(.japanese)

        return group.sorted { lhs, rhs in
            let leftRank = displayOrderRank(for: lhs.text, groupKinds: kinds, hasJapaneseInGroup: hasJapanese)
            let rightRank = displayOrderRank(for: rhs.text, groupKinds: kinds, hasJapaneseInGroup: hasJapanese)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.text < rhs.text
        }
    }

    private static func displayOrderRank(
        for text: String,
        groupKinds: Set<LyricLanguageKind>,
        hasJapaneseInGroup: Bool
    ) -> Int {
        switch languageKind(for: text) {
        case .japanese:
            return 0
        case .chinese:
            if hasJapaneseInGroup || groupKinds.contains(.english) {
                return 1
            }
            return 0
        case .english:
            if hasJapaneseInGroup {
                return 2
            }
            return 0
        case .other:
            return 3
        }
    }

    private static func displayPreferenceScore(for text: String) -> Int {
        switch languageKind(for: text) {
        case .chinese:
            return 3
        case .english:
            return 2
        case .japanese:
            return 1
        case .other:
            return 0
        }
    }

    private enum LyricLanguageKind {
        case japanese
        case chinese
        case english
        case other
    }

    private static func languageKind(for text: String) -> LyricLanguageKind {
        let hasKana = text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
        }
        let hasHan = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
        let hasLatin = text.unicodeScalars.contains(where: { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        })

        if hasKana {
            return .japanese
        }
        if hasHan {
            return .chinese
        }
        if hasLatin {
            return .english
        }
        return .other
    }
}
