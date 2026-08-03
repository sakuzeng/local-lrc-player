import AppKit

/// 「往年今日」。数据还不满一年，所以按 12 → 6 → 3 → 1 个月的顺序取第一个有记录的偏移量：
/// 现在命中的是「1 个月前的今天」，等历史攒够一年，同一段代码自己就变成真正的往年今日。
enum OnThisDayMemory {
    /// 从大到小，优先选跨度更长、更有回望感的那个。
    static let monthOffsets = [12, 6, 3, 1]

    struct Match {
        let monthsAgo: Int
        let day: Date
        let track: TrackRecord
        let plays: Int
    }

    /// 用 Calendar 往前推月份，而不是减固定秒数 ——
    /// 3 月 31 日减一个月得到的是 2 月 28/29 日，减 30 天则会落到 3 月 1 日。
    static func candidateDays(from today: Date, calendar: Calendar = .current) -> [(monthsAgo: Int, day: Date)] {
        monthOffsets.compactMap { months in
            guard let day = calendar.date(byAdding: .month, value: -months, to: today) else {
                return nil
            }
            return (months, calendar.startOfDay(for: day))
        }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func findMatch(
        today: Date = Date(),
        calendar: Calendar = .current,
        lookup: (String) throws -> (track: TrackRecord, plays: Int)?
    ) rethrows -> Match? {
        for candidate in candidateDays(from: today, calendar: calendar) {
            guard let hit = try lookup(dayKey(for: candidate.day, calendar: calendar)) else {
                continue
            }
            return Match(
                monthsAgo: candidate.monthsAgo,
                day: candidate.day,
                track: hit.track,
                plays: hit.plays
            )
        }
        return nil
    }

    static func content(for match: Match, artwork: NSImage?) -> CelebrationContent {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"

        let headline = match.monthsAgo % 12 == 0
            ? "\(match.monthsAgo / 12) 年前"
            : "\(match.monthsAgo) 个月前"

        let listTitle = match.track.listTitle
        let parsed = MusicTrack.parseArtistTitle(listTitle)
        return CelebrationContent(
            kind: .memory,
            headline: headline,
            caption: "的今天，你在听",
            title: parsed?.title ?? listTitle,
            artist: parsed?.artist ?? match.track.artist,
            artwork: artwork,
            footnote: match.plays > 1
                ? "\(formatter.string(from: match.day))，你把它循环了 \(match.plays) 遍"
                : "\(formatter.string(from: match.day))，你听过它一次",
            countsUpTo: nil
        )
    }
}
