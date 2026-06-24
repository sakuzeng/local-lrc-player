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
}

final class AppSettingsRepositoryTests {
    private var database: AppDatabase!
    private var repository: AppSettingsRepository!
    private var tempRoot: URL!

    func runAll() throws {
        try runIsolated { try self.testDefaultSettingsAfterV3Migration() }
        try runIsolated { try self.testUpdateMenuBarLyricsPersists() }
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
}

do {
    try TrackContentHasherTests().runAll()
    try MasterPlaylistRepositoryTests().runAll()
    try AppSettingsRepositoryTests().runAll()
    try PlayerStateRepositoryTests().runAll()
    try MenuBarLyricsMaxWidthTests().runAll()
    print("All tests passed.")
} catch {
    fputs("TEST FAILED: \(error)\n", stderr)
    exit(1)
}
