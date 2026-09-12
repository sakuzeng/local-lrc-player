import AppKit
import OSLog

/// 「帮助 → 导出诊断信息」：把环境、设置、音乐库、播放态、最近歌词下载记录和本进程的统一日志
/// 拼成一份纯文本，排查时整份发出来即可。不含 Cookie 值，只记录是否配置。
enum DiagnosticsReport {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func suggestedFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "LocalLrcPlayer-诊断-\(formatter.string(from: Date())).txt"
    }

    static func generate(
        playerWindowController: PlayerWindowController?,
        menuBarLyricsController: MenuBarLyricsController?
    ) -> String {
        var out: [String] = []
        func section(_ title: String) {
            out.append("")
            out.append("== \(title) ==")
        }

        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        out.append("Local LRC Player 诊断信息")
        out.append("生成时间：\(timestampFormatter.string(from: Date()))")

        section("环境")
        out.append("App 版本：\(version)（\(bundle.bundleIdentifier ?? "-")）")
        out.append("macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        let ffmpegInstalled = FileManager.default.isExecutableFile(atPath: PlaybackAssetResolver.ffmpegPath)
        out.append("ffmpeg：\(ffmpegInstalled ? "已安装" : "未找到")（\(PlaybackAssetResolver.ffmpegPath)）")
        out.append("数据库：\(AppDatabase.shared.databaseURL.path)")

        section("设置")
        let settings = (try? AppSettingsRepository().settings()) ?? .defaults
        out.append("菜单栏歌词：\(onOff(settings.menuBarLyricsEnabled))，最大宽度 \(Int(settings.menuBarLyricsMaxWidth))pt，音符图标 \(onOff(settings.menuBarLyricsShowIcon))")
        out.append("里程碑提醒：\(onOff(settings.milestoneAlertsEnabled))，往年今日：\(onOff(settings.memoryAlertsEnabled))（上次弹出 \(settings.lastMemoryShownOn ?? "-")）")
        out.append("外观：\(String(describing: settings.appearance))")
        out.append("网易云 Cookie：\(cookieState(.netEase))，QQ 音乐 Cookie：\(cookieState(.qqMusic))")

        section("音乐库")
        let libraries = (try? LibraryRepository().allLibraries()) ?? []
        if libraries.isEmpty {
            out.append("（未添加音乐文件夹）")
        }
        for library in libraries {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: library.path, isDirectory: &isDirectory) && isDirectory.boolValue
            let readable = FileManager.default.isReadableFile(atPath: library.path)
            let scanned = library.lastScannedAt.map { timestampFormatter.string(from: $0) } ?? "从未"
            out.append("- \(library.path)  存在:\(yesNo(exists)) 可读:\(yesNo(readable)) 上次同步:\(scanned)\(library.isActive ? " [活跃]" : "")")
        }
        if let counts = try? PlaylistRepository().masterPlaylistCounts() {
            out.append("总播放列表：\(counts.total) 首，其中 \(counts.missingLyrics) 首无歌词")
        }

        section("播放")
        if let state = try? PlayerStateRepository().playbackState() {
            let trackId = state.lastTrackId.map(String.init) ?? "-"
            out.append("上次曲目 id：\(trackId)，位置 \(format(state.lastPosition))，模式 \(state.playbackMode.title)，音量 \(Int((state.volume * 100).rounded()))%")
        }
        if let controller = playerWindowController {
            if let snapshot = controller.currentNowPlayingSnapshot() {
                let artist = snapshot.artist.map { " - \($0)" } ?? ""
                out.append("当前：\(snapshot.title)\(artist)，\(snapshot.isPlaying ? "播放中" : "已暂停")，\(format(snapshot.currentTime)) / \(format(snapshot.duration))，歌词 \(controller.lrcLines.count) 行，封面 \(snapshot.artwork == nil ? "无" : "有")")
            } else {
                out.append("当前：未在播放")
            }
            out.append("列表已加载 \(controller.tracks.count) 首")
        }

        section("菜单栏歌词")
        out.append(menuBarLyricsController?.diagnosticsSummary() ?? "（控制器未初始化）")

        section("最近歌词下载记录（最多 30 条）")
        let attempts = (try? LyricLogRepository().recentAttempts(limit: 30)) ?? []
        if attempts.isEmpty {
            out.append("（无）")
        }
        for attempt in attempts {
            let score = attempt.score.map(String.init) ?? "-"
            let error = attempt.errorMessage.map { "：\($0)" } ?? ""
            out.append("\(timestampFormatter.string(from: attempt.createdAt)) \(attempt.success ? "成功" : "失败") [\(attempt.provider.rawValue)] \(attempt.fileName) ← \(attempt.candidateName ?? "-")（分 \(score)）\(error)")
        }

        section("本次运行日志（统一日志，subsystem \(AppLog.subsystem)，最多 400 条）")
        out.append(contentsOf: recentLogLines(limit: 400))

        return out.joined(separator: "\n") + "\n"
    }

    /// 只读本进程的条目，按 subsystem 过滤；OSLogStore 需要 macOS 12。
    private static func recentLogLines(limit: Int) -> [String] {
        guard #available(macOS 12.0, *) else {
            return ["（当前系统不支持读取统一日志）"]
        }
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceLatestBoot: 0)
            let predicate = NSPredicate(format: "subsystem == %@", AppLog.subsystem)
            let entries = try store.getEntries(with: [], at: position, matching: predicate)
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                lines.append("\(logTimeFormatter.string(from: entry.date)) [\(entry.category)] \(levelName(entry.level)) \(entry.composedMessage)")
            }
            if lines.isEmpty {
                return ["（无）"]
            }
            return Array(lines.suffix(limit))
        } catch {
            return ["读取统一日志失败：\(error.localizedDescription)"]
        }
    }

    @available(macOS 12.0, *)
    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .notice:
            return "notice"
        case .error:
            return "error"
        case .fault:
            return "fault"
        default:
            return "log"
        }
    }

    private static func cookieState(_ provider: LyricProvider) -> String {
        let cookie = (try? CookieStore.read(provider: provider))??.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cookie.isEmpty ? "未配置" : "已配置"
    }

    private static func onOff(_ value: Bool) -> String {
        value ? "开" : "关"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "是" : "否"
    }

    private static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "00:00"
        }
        let total = Int(time.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
