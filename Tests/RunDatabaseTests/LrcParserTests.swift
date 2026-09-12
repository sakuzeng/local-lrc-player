import Foundation

/// LrcParser：时间戳格式、跳过规则、排序、同时刻多语言分组与 activeLineIndex 的边界。
struct LrcParserTests {
    func runAll() throws {
        try testParsesTimestampVariants()
        try testMultipleTimestampsOnOneLineFanOut()
        try testSkipsMetadataAndEmptyLines()
        try testSortsByTime()
        try testGroupsSimultaneousLinesByLanguage()
        try testActiveLineIndexBoundaries()
        try testActiveLineIndexPrefersChineseWithinGroup()
    }

    private func testParsesTimestampVariants() throws {
        let lines = LrcParser.parse("[00:01.50]两位小数\n[00:02.250]三位小数\n[00:03:75]冒号分隔\n[01:04]无小数")
        try assertEqual(lines.count, 4)
        try assertEqual(lines[0].time, 1.5)
        try assertEqual(lines[1].time, 2.25)
        try assertEqual(lines[2].time, 3.75)
        try assertEqual(lines[3].time, 64)
        try assertEqual(lines[3].text, "无小数")
    }

    private func testMultipleTimestampsOnOneLineFanOut() throws {
        let lines = LrcParser.parse("[00:20.00][00:10.00]副歌")
        try assertEqual(lines.map(\.time), [10, 20])
        try assertEqual(lines.map(\.text), ["副歌", "副歌"])
    }

    private func testSkipsMetadataAndEmptyLines() throws {
        let lines = LrcParser.parse("[ti:标题]\n[ar:歌手]\n[00:01.00]\n[00:02.00]   \n\n[00:03.00]正文")
        try assertEqual(lines.count, 1)
        try assertEqual(lines[0].time, 3)
        try assertEqual(lines[0].text, "正文")
    }

    private func testSortsByTime() throws {
        let lines = LrcParser.parse("[00:05.00]后\n[00:01.00]前")
        try assertEqual(lines.map(\.text), ["前", "后"])
    }

    private func testGroupsSimultaneousLinesByLanguage() throws {
        // 50ms 内视为同一组；日文歌按 日 → 中 → 英，英文歌按 英 → 中。
        let japanese = LrcParser.parse("[00:01.00]中文译文\n[00:01.02]こんにちは\n[00:01.04]Hello")
        try assertEqual(japanese.map(\.text), ["こんにちは", "中文译文", "Hello"])

        let english = LrcParser.parse("[00:01.00]中文译文\n[00:01.01]Hello")
        try assertEqual(english.map(\.text), ["Hello", "中文译文"])

        // 超过 50ms 就不是同一组，保持时间顺序。
        let apart = LrcParser.parse("[00:01.00]中文\n[00:01.10]Hello")
        try assertEqual(apart.map(\.text), ["中文", "Hello"])
    }

    private func testActiveLineIndexBoundaries() throws {
        let lines = LrcParser.parse("[00:01.00]一\n[00:05.00]二\n[00:10.00]三")
        try assertEqual(LrcParser.activeLineIndex(for: 0.5, in: lines), nil)
        try assertEqual(LrcParser.activeLineIndex(for: 1.0, in: lines), 0)
        try assertEqual(LrcParser.activeLineIndex(for: 4.99, in: lines), 0)
        try assertEqual(LrcParser.activeLineIndex(for: 5.0, in: lines), 1)
        try assertEqual(LrcParser.activeLineIndex(for: 100, in: lines), 2)
        try assertEqual(LrcParser.activeLineIndex(for: 3, in: []), nil)
    }

    private func testActiveLineIndexPrefersChineseWithinGroup() throws {
        let lines = LrcParser.parse("[00:01.00]こんにちは\n[00:01.00]你好\n[00:05.00]次の行")
        guard let index = LrcParser.activeLineIndex(for: 2, in: lines) else {
            throw TestFailure.message("expected an active line at 2s")
        }
        try assertEqual(lines[index].text, "你好", "高亮应落在组内的中文译文行")
    }
}
