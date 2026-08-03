import AppKit
import Foundation
import SQLite3

struct AppSettings: Equatable {
    let menuBarLyricsEnabled: Bool
    let menuBarLyricsMaxWidth: CGFloat
    let menuBarLyricsShowIcon: Bool
    let milestoneAlertsEnabled: Bool
    let memoryAlertsEnabled: Bool
    /// 「往年今日」上次弹出的日期（YYYY-MM-DD，本地时区）；每天最多弹一次。
    let lastMemoryShownOn: String?

    static let defaults = AppSettings(
        menuBarLyricsEnabled: true,
        menuBarLyricsMaxWidth: 160,
        menuBarLyricsShowIcon: true,
        milestoneAlertsEnabled: true,
        memoryAlertsEnabled: true,
        lastMemoryShownOn: nil
    )
}

enum MenuBarLyricsMaxWidthOption: CGFloat, CaseIterable {
    case compact = 120
    case standard = 140
    case comfortable = 160

    var title: String {
        String(Int(rawValue))
    }
}

enum MenuBarLyricsMaxWidth {
    static let minimum: CGFloat = 80
    static let maximum: CGFloat = 400

    static let presets: [CGFloat] = MenuBarLyricsMaxWidthOption.allCases.map(\.rawValue)

    static func isPreset(_ width: CGFloat) -> Bool {
        presets.contains { abs($0 - width) < 0.5 }
    }

    static func clamp(_ width: CGFloat) -> CGFloat {
        min(maximum, max(minimum, width))
    }
}

final class AppSettingsRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func settings() throws -> AppSettings {
        try database.read { db in
            let sql = """
            SELECT menu_bar_lyrics_enabled, menu_bar_lyrics_max_width, menu_bar_lyrics_show_icon,
                   milestone_alerts_enabled, memory_alerts_enabled, last_memory_shown_on
            FROM app_settings
            WHERE id = 1
            LIMIT 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return .defaults
            }
            return AppSettings(
                menuBarLyricsEnabled: sqlite3_column_int(statement, 0) != 0,
                menuBarLyricsMaxWidth: CGFloat(sqlite3_column_double(statement, 1)),
                menuBarLyricsShowIcon: sqlite3_column_int(statement, 2) != 0,
                milestoneAlertsEnabled: sqlite3_column_int(statement, 3) != 0,
                memoryAlertsEnabled: sqlite3_column_int(statement, 4) != 0,
                lastMemoryShownOn: sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 5))
            )
        }
    }

    func updateMenuBarLyrics(
        enabled: Bool? = nil,
        maxWidth: CGFloat? = nil,
        showIcon: Bool? = nil
    ) throws {
        let current = try settings()
        try write(AppSettings(
            menuBarLyricsEnabled: enabled ?? current.menuBarLyricsEnabled,
            menuBarLyricsMaxWidth: MenuBarLyricsMaxWidth.clamp(maxWidth ?? current.menuBarLyricsMaxWidth),
            menuBarLyricsShowIcon: showIcon ?? current.menuBarLyricsShowIcon,
            milestoneAlertsEnabled: current.milestoneAlertsEnabled,
            memoryAlertsEnabled: current.memoryAlertsEnabled,
            lastMemoryShownOn: current.lastMemoryShownOn
        ))
    }

    func updateMilestoneAlerts(enabled: Bool) throws {
        let current = try settings()
        try write(AppSettings(
            menuBarLyricsEnabled: current.menuBarLyricsEnabled,
            menuBarLyricsMaxWidth: current.menuBarLyricsMaxWidth,
            menuBarLyricsShowIcon: current.menuBarLyricsShowIcon,
            milestoneAlertsEnabled: enabled,
            memoryAlertsEnabled: current.memoryAlertsEnabled,
            lastMemoryShownOn: current.lastMemoryShownOn
        ))
    }

    func updateMemoryAlerts(enabled: Bool) throws {
        let current = try settings()
        try write(AppSettings(
            menuBarLyricsEnabled: current.menuBarLyricsEnabled,
            menuBarLyricsMaxWidth: current.menuBarLyricsMaxWidth,
            menuBarLyricsShowIcon: current.menuBarLyricsShowIcon,
            milestoneAlertsEnabled: current.milestoneAlertsEnabled,
            memoryAlertsEnabled: enabled,
            lastMemoryShownOn: current.lastMemoryShownOn
        ))
    }

    func markMemoryShown(on day: String) throws {
        let current = try settings()
        try write(AppSettings(
            menuBarLyricsEnabled: current.menuBarLyricsEnabled,
            menuBarLyricsMaxWidth: current.menuBarLyricsMaxWidth,
            menuBarLyricsShowIcon: current.menuBarLyricsShowIcon,
            milestoneAlertsEnabled: current.milestoneAlertsEnabled,
            memoryAlertsEnabled: current.memoryAlertsEnabled,
            lastMemoryShownOn: day
        ))
    }

    private func write(_ next: AppSettings) throws {
        try database.write { db in
            let sql = """
            UPDATE app_settings
            SET menu_bar_lyrics_enabled = ?,
                menu_bar_lyrics_max_width = ?,
                menu_bar_lyrics_show_icon = ?,
                milestone_alerts_enabled = ?,
                memory_alerts_enabled = ?,
                last_memory_shown_on = ?
            WHERE id = 1;
            """
            let statement = try database.prepare(db, sql: sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, next.menuBarLyricsEnabled ? 1 : 0)
            sqlite3_bind_double(statement, 2, Double(next.menuBarLyricsMaxWidth))
            sqlite3_bind_int(statement, 3, next.menuBarLyricsShowIcon ? 1 : 0)
            sqlite3_bind_int(statement, 4, next.milestoneAlertsEnabled ? 1 : 0)
            sqlite3_bind_int(statement, 5, next.memoryAlertsEnabled ? 1 : 0)
            if let day = next.lastMemoryShownOn {
                sqlite3_bind_text(statement, 6, day, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppDatabaseError.stepFailed(database.errorMessage(db))
            }
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
