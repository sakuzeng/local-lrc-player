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

do {
    try TrackContentHasherTests().runAll()
    try MasterPlaylistRepositoryTests().runAll()
    try AppSettingsRepositoryTests().runAll()
    try MenuBarLyricsMaxWidthTests().runAll()
    print("All tests passed.")
} catch {
    fputs("TEST FAILED: \(error)\n", stderr)
    exit(1)
}
