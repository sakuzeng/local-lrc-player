import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) throws {
    if !condition {
        throw TestFailure.message("\((file as NSString).lastPathComponent):\(line) \(message)")
    }
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    if lhs != rhs {
        let detail = message.isEmpty ? "" : " — \(message)"
        throw TestFailure.message("\((file as NSString).lastPathComponent):\(line) expected \(rhs), got \(lhs)\(detail)")
    }
}

struct TrackContentHasherTests {
    func runAll() throws {
        try testSameContentProducesSameHash()
    }

    private func testSameContentProducesSameHash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileA = directory.appendingPathComponent("a.mp3")
        let fileB = directory.appendingPathComponent("b.mp3")
        let payload = Data("test-audio-payload".utf8)
        try payload.write(to: fileA)
        try payload.write(to: fileB)

        let hashA = try TrackContentHasher.hash(fileURL: fileA)
        let hashB = try TrackContentHasher.hash(fileURL: fileB)
        try assertEqual(hashA, hashB, "identical payloads should hash equally")
    }
}

final class MasterPlaylistRepositoryTests {
    private var database: AppDatabase!
    private var libraryRepository: LibraryRepository!
    private var trackRepository: TrackRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testDuplicateContentAcrossLibrariesAppearsOnceInMasterPlaylist() }
        try runIsolated { try self.testMultipleLibrariesAccumulateInMasterPlaylist() }
        try runIsolated { try self.testPlayerStatePersistsAcrossLibraries() }
        try runIsolated { try self.testRemovingFileUnlinksLibraryTrackAndKeepsDuplicateCopy() }
        try runIsolated { try self.testRemovingLibraryKeepsSharedTrack() }
        try runIsolated { try self.testRemovingLibraryClearsPlayerState() }
        try runIsolated { try self.testSyncReordersMasterPlaylistByFileName() }
        try runIsolated { try self.testRenamingFileKeepsSameTrackAndRepointsPath() }
    }

    private func runIsolated(_ work: () throws -> Void) throws {
        try setUp()
        defer { tearDown() }
        try work()
    }

    private func setUp() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let dbURL = tempRoot.appendingPathComponent("test.sqlite")
        database = try AppDatabase(fileURL: dbURL)
        libraryRepository = LibraryRepository(database: database)
        trackRepository = TrackRepository(database: database)
    }

    private func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        database = nil
        libraryRepository = nil
        trackRepository = nil
        tempRoot = nil
    }

    private func testDuplicateContentAcrossLibrariesAppearsOnceInMasterPlaylist() throws {
        let libraryA = tempRoot.appendingPathComponent("LibraryA", isDirectory: true)
        let libraryB = tempRoot.appendingPathComponent("LibraryB", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryB, withIntermediateDirectories: true)

        let payload = Data("duplicate-song-content".utf8)
        try payload.write(to: libraryA.appendingPathComponent("song.mp3"))
        try payload.write(to: libraryB.appendingPathComponent("copy.mp3"))

        let registeredA = try libraryRepository.registerLibrary(at: libraryA)
        let registeredB = try libraryRepository.registerLibrary(at: libraryB)

        _ = try trackRepository.sync(libraryId: registeredA.id, folderURL: libraryA)
        let secondSummary = try trackRepository.sync(libraryId: registeredB.id, folderURL: libraryB)

        try assertEqual(secondSummary.deduplicated, 1)
        let masterTracks = try trackRepository.masterPlaylistTracks()
        try assertEqual(masterTracks.count, 1)
        try assertTrue(masterTracks.first?.contentHash != nil, "track should have content hash")
    }

    private func testMultipleLibrariesAccumulateInMasterPlaylist() throws {
        let libraryA = tempRoot.appendingPathComponent("A", isDirectory: true)
        let libraryB = tempRoot.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryB, withIntermediateDirectories: true)

        try Data("song-a".utf8).write(to: libraryA.appendingPathComponent("a.mp3"))
        try Data("song-b".utf8).write(to: libraryB.appendingPathComponent("b.mp3"))

        let registeredA = try libraryRepository.registerLibrary(at: libraryA)
        let registeredB = try libraryRepository.registerLibrary(at: libraryB)

        _ = try trackRepository.sync(libraryId: registeredA.id, folderURL: libraryA)
        _ = try trackRepository.sync(libraryId: registeredB.id, folderURL: libraryB)

        try assertEqual(try libraryRepository.allLibraries().count, 2)
        try assertEqual(try trackRepository.masterPlaylistTracks().count, 2)
    }

    private func testPlayerStatePersistsAcrossLibraries() throws {
        let playerStateRepository = PlayerStateRepository(database: database)
        try playerStateRepository.updatePlaybackState(trackId: 42, position: 12.5)
        let state = try playerStateRepository.playbackState()
        try assertEqual(state.lastTrackId, 42)
        try assertEqual(state.lastPosition, 12.5)
    }

    private func testRemovingFileUnlinksLibraryTrackAndKeepsDuplicateCopy() throws {
        let libraryA = tempRoot.appendingPathComponent("Keep", isDirectory: true)
        let libraryB = tempRoot.appendingPathComponent("Remove", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryB, withIntermediateDirectories: true)

        let payload = Data("shared-song".utf8)
        let keepFile = libraryA.appendingPathComponent("keep.mp3")
        let removeFile = libraryB.appendingPathComponent("remove.mp3")
        try payload.write(to: keepFile)
        try payload.write(to: removeFile)

        let registeredA = try libraryRepository.registerLibrary(at: libraryA)
        let registeredB = try libraryRepository.registerLibrary(at: libraryB)
        _ = try trackRepository.sync(libraryId: registeredA.id, folderURL: libraryA)
        _ = try trackRepository.sync(libraryId: registeredB.id, folderURL: libraryB)

        try FileManager.default.removeItem(at: removeFile)
        _ = try trackRepository.sync(libraryId: registeredB.id, folderURL: libraryB)

        let masterTracks = try trackRepository.masterPlaylistTracks()
        try assertEqual(masterTracks.count, 1)
        try assertTrue(FileManager.default.fileExists(atPath: masterTracks[0].filePath), "canonical path should remain")
    }

    private func testRemovingLibraryKeepsSharedTrack() throws {
        let libraryA = tempRoot.appendingPathComponent("KeepLib", isDirectory: true)
        let libraryB = tempRoot.appendingPathComponent("RemoveLib", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryB, withIntermediateDirectories: true)

        let payload = Data("shared-remove-library".utf8)
        try payload.write(to: libraryA.appendingPathComponent("shared.mp3"))
        try payload.write(to: libraryB.appendingPathComponent("copy.mp3"))

        let registeredA = try libraryRepository.registerLibrary(at: libraryA)
        let registeredB = try libraryRepository.registerLibrary(at: libraryB)
        _ = try trackRepository.sync(libraryId: registeredA.id, folderURL: libraryA)
        _ = try trackRepository.sync(libraryId: registeredB.id, folderURL: libraryB)

        try assertEqual(try trackRepository.masterPlaylistTracks().count, 1)
        try libraryRepository.deleteLibrary(id: registeredB.id)
        try assertEqual(try libraryRepository.allLibraries().count, 1)
        try assertEqual(try trackRepository.masterPlaylistTracks().count, 1)
    }

    private func testRemovingLibraryClearsPlayerState() throws {
        let library = tempRoot.appendingPathComponent("Solo", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("solo-song".utf8).write(to: library.appendingPathComponent("solo.mp3"))

        let registered = try libraryRepository.registerLibrary(at: library)
        _ = try trackRepository.sync(libraryId: registered.id, folderURL: library)
        let track = try trackRepository.masterPlaylistTracks().first
        try assertTrue(track != nil, "track should exist")

        let playerStateRepository = PlayerStateRepository(database: database)
        try playerStateRepository.updatePlaybackState(trackId: track!.id, position: 8)
        try libraryRepository.deleteLibrary(id: registered.id)

        let state = try playerStateRepository.playbackState()
        try assertEqual(state.lastTrackId, nil)
        try assertEqual(state.lastPosition, 0)
        try assertEqual(try trackRepository.masterPlaylistTracks().count, 0)
    }

    private func testSyncReordersMasterPlaylistByFileName() throws {
        let library = tempRoot.appendingPathComponent("Reorder", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)

        try Data("z-song".utf8).write(to: library.appendingPathComponent("z-last.mp3"))
        try Data("a-song".utf8).write(to: library.appendingPathComponent("a-first.mp3"))

        let registered = try libraryRepository.registerLibrary(at: library)
        _ = try trackRepository.sync(libraryId: registered.id, folderURL: library)

        let namesAfterFirstSync = try trackRepository.masterPlaylistTracks().map(\.fileName)
        try assertEqual(namesAfterFirstSync, ["a-first.mp3", "z-last.mp3"], "sync should order by file name")

        try Data("m-song".utf8).write(to: library.appendingPathComponent("m-middle.mp3"))
        _ = try trackRepository.sync(libraryId: registered.id, folderURL: library)

        let namesAfterSecondSync = try trackRepository.masterPlaylistTracks().map(\.fileName)
        try assertEqual(
            namesAfterSecondSync,
            ["a-first.mp3", "m-middle.mp3", "z-last.mp3"],
            "refresh should reorder newly added tracks"
        )
    }

    /// 在 Finder 里改名 + 刷新：内容哈希去重必须把它认成同一首（track id 不变、路径重指、
    /// 不产生重复行），窗口层才有可能靠 track id 把播放行认回来。
    private func testRenamingFileKeepsSameTrackAndRepointsPath() throws {
        let library = tempRoot.appendingPathComponent("Rename", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)

        try Data("a-song".utf8).write(to: library.appendingPathComponent("a-first.mp3"))
        try Data("m-song".utf8).write(to: library.appendingPathComponent("m-middle.mp3"))

        let registered = try libraryRepository.registerLibrary(at: library)
        _ = try trackRepository.sync(libraryId: registered.id, folderURL: library)

        let before = try trackRepository.masterPlaylistTracks()
        try assertEqual(before.map(\.fileName), ["a-first.mp3", "m-middle.mp3"])
        let renamedTrackId = before[0].id

        try FileManager.default.moveItem(
            at: library.appendingPathComponent("a-first.mp3"),
            to: library.appendingPathComponent("z-renamed.mp3")
        )
        let summary = try trackRepository.sync(libraryId: registered.id, folderURL: library)
        try assertEqual(summary.total, 2, "rename must not create a second row")

        let after = try trackRepository.masterPlaylistTracks()
        try assertEqual(after.map(\.fileName), ["m-middle.mp3", "z-renamed.mp3"], "rename reorders the list")
        try assertEqual(after[1].id, renamedTrackId, "renamed file must keep its track id")
        try assertEqual(
            after[1].filePath,
            library.appendingPathComponent("z-renamed.mp3").standardizedFileURL.path,
            "canonical path should follow the rename"
        )
        try assertTrue(
            try trackRepository.track(forFilePath: library.appendingPathComponent("a-first.mp3").path) == nil,
            "old path should no longer resolve"
        )
    }
}

final class AppSettingsRepositoryTests {
    private var database: AppDatabase!
    private var repository: AppSettingsRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testDefaultSettingsAfterV3Migration() }
        try runIsolated { try self.testUpdateMenuBarLyricsPersists() }
        try runIsolated { try self.testMilestoneAlertsDefaultOnAndPersists() }
    }

    private func runIsolated(_ work: () throws -> Void) throws {
        try setUp()
        defer { tearDown() }
        try work()
    }

    private func setUp() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let dbURL = tempRoot.appendingPathComponent("test.sqlite")
        database = try AppDatabase(fileURL: dbURL)
        repository = AppSettingsRepository(database: database)
    }

    private func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        database = nil
        repository = nil
        tempRoot = nil
    }

    private func testDefaultSettingsAfterV3Migration() throws {
        let settings = try repository.settings()
        try assertEqual(settings.menuBarLyricsEnabled, true)
        try assertEqual(settings.menuBarLyricsMaxWidth, 160)
        try assertEqual(settings.menuBarLyricsShowIcon, true)
    }

    private func testUpdateMenuBarLyricsPersists() throws {
        try repository.updateMenuBarLyrics(enabled: false, maxWidth: 200, showIcon: false)
        let settings = try repository.settings()
        try assertEqual(settings.menuBarLyricsEnabled, false)
        try assertEqual(settings.menuBarLyricsMaxWidth, 200)
        try assertEqual(settings.menuBarLyricsShowIcon, false)
    }

    private func testMilestoneAlertsDefaultOnAndPersists() throws {
        try assertEqual(try repository.settings().milestoneAlertsEnabled, true, "v5 迁移默认开启")

        try repository.updateMilestoneAlerts(enabled: false)
        try assertEqual(try repository.settings().milestoneAlertsEnabled, false)

        // 两组设置写的是同一行，互不覆盖。
        try repository.updateMenuBarLyrics(showIcon: false)
        try assertEqual(try repository.settings().milestoneAlertsEnabled, false, "改菜单栏设置不应重置里程碑开关")
        try repository.updateMilestoneAlerts(enabled: true)
        try assertEqual(try repository.settings().menuBarLyricsShowIcon, false, "改里程碑开关不应重置菜单栏设置")
    }
}

final class PlayHistoryRepositoryTests {
    private var database: AppDatabase!
    private var libraryRepository: LibraryRepository!
    private var trackRepository: TrackRepository!
    private var repository: PlayHistoryRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testOnlyCountedPlaysCountTowardMilestones() }
        try runIsolated { try self.testFirstPlayedAtUsesFullHistory() }
        try runIsolated { try self.testMilestoneThresholdsFireOnExactCount() }
        try runIsolated { try self.testMostPlayedTrackOnDay() }
        try testMonthOffsetHandlesShortMonths()
        try runIsolated { try self.testFindMatchPrefersLongestOffsetWithData() }
    }

    private func runIsolated(_ work: () throws -> Void) throws {
        try setUp()
        defer { tearDown() }
        try work()
    }

    private func setUp() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        database = try AppDatabase(fileURL: tempRoot.appendingPathComponent("test.sqlite"))
        libraryRepository = LibraryRepository(database: database)
        trackRepository = TrackRepository(database: database)
        repository = PlayHistoryRepository(database: database)
    }

    private func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        database = nil
        libraryRepository = nil
        trackRepository = nil
        repository = nil
        tempRoot = nil
    }

    private func makeTrackId() throws -> Int64 {
        let library = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("milestone-song".utf8).write(to: library.appendingPathComponent("song.mp3"))
        let registered = try libraryRepository.registerLibrary(at: library)
        _ = try trackRepository.sync(libraryId: registered.id, folderURL: library)
        guard let track = try trackRepository.masterPlaylistTracks().first else {
            throw TestFailure.message("track should exist")
        }
        return track.id
    }

    /// 里程碑只数「听满阈值」的行；跳过产生的行不计入。
    /// 这条同时锁住「历史数据默认 counted = 0，里程碑从功能上线后重新起算」。
    private func testOnlyCountedPlaysCountTowardMilestones() throws {
        let trackId = try makeTrackId()

        for _ in 0 ..< 5 {
            _ = try repository.recordPlayback(trackId: trackId)
        }
        try assertEqual(try repository.countedPlayCount(trackId: trackId), 0, "只开始播放不算有效播放")

        let counted = try repository.recordPlayback(trackId: trackId)
        try repository.markCounted(historyId: counted)
        try assertEqual(try repository.countedPlayCount(trackId: trackId), 1)
    }

    /// 首次播放时间取全量历史，不受计数口径影响。
    private func testFirstPlayedAtUsesFullHistory() throws {
        let trackId = try makeTrackId()
        try assertTrue(try repository.firstPlayedAt(trackId: trackId) == nil, "无记录时应为 nil")

        let before = Date()
        _ = try repository.recordPlayback(trackId: trackId)
        guard let first = try repository.firstPlayedAt(trackId: trackId) else {
            throw TestFailure.message("first play should exist")
        }
        try assertTrue(first.timeIntervalSince1970 >= before.timeIntervalSince1970 - 1, "首播时间应接近刚才")
        try assertEqual(try repository.countedPlayCount(trackId: trackId), 0, "首播时间不依赖 counted")
    }

    /// 「往年今日」按本地日期分组，取那天听得最多的一首。
    private func testMostPlayedTrackOnDay() throws {
        let trackId = try makeTrackId()

        // 30 天前那天听了 3 次，31 天前听了 1 次。
        let calendar = Calendar.current
        guard let dayA = calendar.date(byAdding: .day, value: -30, to: Date()),
              let dayB = calendar.date(byAdding: .day, value: -31, to: Date()) else {
            throw TestFailure.message("date math failed")
        }
        for _ in 0 ..< 3 {
            _ = try repository.recordPlayback(trackId: trackId, at: dayA)
        }
        _ = try repository.recordPlayback(trackId: trackId, at: dayB)

        let keyA = OnThisDayMemory.dayKey(for: dayA)
        guard let hit = try repository.mostPlayedTrack(onDay: keyA) else {
            throw TestFailure.message("should find a play on that day")
        }
        try assertEqual(hit.track.id, trackId)
        try assertEqual(hit.plays, 3, "只数那一天的记录")

        let keyB = OnThisDayMemory.dayKey(for: dayB)
        try assertEqual(try repository.mostPlayedTrack(onDay: keyB)?.plays, 1)

        let today = OnThisDayMemory.dayKey(for: Date())
        try assertTrue(try repository.mostPlayedTrack(onDay: today) == nil, "今天没记录应为 nil")
    }

    /// 往前推月份必须走 Calendar：3 月 31 日减一个月是 2 月 28/29 日，
    /// 减 30 天则会落到 3 月 1 日，那是完全不同的一天。
    private func testMonthOffsetHandlesShortMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: "Asia/Shanghai") else {
            throw TestFailure.message("timezone unavailable")
        }
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 31
        components.hour = 12
        guard let march31 = calendar.date(from: components) else {
            throw TestFailure.message("date construction failed")
        }

        let days = OnThisDayMemory.candidateDays(from: march31, calendar: calendar)
        guard let oneMonthAgo = days.first(where: { $0.monthsAgo == 1 }) else {
            throw TestFailure.message("missing 1-month candidate")
        }
        try assertEqual(OnThisDayMemory.dayKey(for: oneMonthAgo.day, calendar: calendar), "2026-02-28")
    }

    /// 有数据的偏移里取跨度最长的那个，这样数据攒够一年后自动变成真正的「往年今日」。
    private func testFindMatchPrefersLongestOffsetWithData() throws {
        let trackId = try makeTrackId()
        _ = try repository.recordPlayback(trackId: trackId)
        guard let record = try trackRepository.masterPlaylistTracks().first else {
            throw TestFailure.message("track should exist")
        }

        var queried: [String] = []
        let match = OnThisDayMemory.findMatch(lookup: { day in
            queried.append(day)
            // 只有 3 个月前那天有数据。
            let target = OnThisDayMemory.dayKey(
                for: Calendar.current.date(byAdding: .month, value: -3, to: Date())!
            )
            return day == target ? (record, 5) : nil
        })

        try assertEqual(match?.monthsAgo, 3)
        try assertEqual(match?.plays, 5)
        try assertEqual(queried.count, 3, "命中 3 个月后就不再往下查 1 个月")
    }

    private func testMilestoneThresholdsFireOnExactCount() throws {
        try assertTrue(MilestoneCelebration.threshold(reachedBy: 10) != nil, "10 是里程碑")
        try assertTrue(MilestoneCelebration.threshold(reachedBy: 100) != nil, "100 是里程碑")
        try assertTrue(MilestoneCelebration.threshold(reachedBy: 11) == nil, "只在恰好命中时触发一次")
        try assertTrue(MilestoneCelebration.threshold(reachedBy: 0) == nil, "0 次不触发")
    }
}

struct MenuBarLyricsMaxWidthTests {
    func runAll() throws {
        try testClamp()
        try testPresetDetection()
    }

    private func testClamp() throws {
        try assertEqual(MenuBarLyricsMaxWidth.clamp(50), 80)
        try assertEqual(MenuBarLyricsMaxWidth.clamp(180), 180)
        try assertEqual(MenuBarLyricsMaxWidth.clamp(999), 400)
    }

    private func testPresetDetection() throws {
        try assertTrue(MenuBarLyricsMaxWidth.isPreset(160), "160 is preset")
        try assertTrue(!MenuBarLyricsMaxWidth.isPreset(200), "200 is custom")
    }
}

final class PlayerStateRepositoryTests {
    private var database: AppDatabase!
    private var repository: PlayerStateRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testDefaultPlaybackModeAfterMigration() }
        try runIsolated { try self.testUpdatePlaybackModePersists() }
        try runIsolated { try self.testDefaultVolumeAfterMigration() }
        try runIsolated { try self.testUpdateVolumePersistsAndClamps() }
    }

    private func runIsolated(_ work: () throws -> Void) throws {
        try setUp()
        defer { tearDown() }
        try work()
    }

    private func setUp() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLrcPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let dbURL = tempRoot.appendingPathComponent("test.sqlite")
        database = try AppDatabase(fileURL: dbURL)
        repository = PlayerStateRepository(database: database)
    }

    private func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        database = nil
        repository = nil
        tempRoot = nil
    }

    private func testDefaultPlaybackModeAfterMigration() throws {
        let state = try repository.playbackState()
        try assertEqual(state.playbackMode, .sequential)
    }

    private func testUpdatePlaybackModePersists() throws {
        try repository.updatePlaybackMode(.shuffle)
        var state = try repository.playbackState()
        try assertEqual(state.playbackMode, .shuffle)

        try repository.updatePlaybackMode(.repeatOne)
        state = try repository.playbackState()
        try assertEqual(state.playbackMode, .repeatOne)
    }

    private func testDefaultVolumeAfterMigration() throws {
        let state = try repository.playbackState()
        try assertEqual(state.volume, 1)
    }

    private func testUpdateVolumePersistsAndClamps() throws {
        try repository.updateVolume(0.35)
        var state = try repository.playbackState()
        try assertEqual(state.volume, 0.35)

        try repository.updateVolume(1.7)
        state = try repository.playbackState()
        try assertEqual(state.volume, 1)
    }
}

do {
    try TrackContentHasherTests().runAll()
    try MasterPlaylistRepositoryTests().runAll()
    try AppSettingsRepositoryTests().runAll()
    try PlayHistoryRepositoryTests().runAll()
    try PlayerStateRepositoryTests().runAll()
    try MenuBarLyricsMaxWidthTests().runAll()
    print("All tests passed.")
} catch {
    fputs("TEST FAILED: \(error)\n", stderr)
    exit(1)
}
