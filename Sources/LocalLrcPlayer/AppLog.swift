import Foundation
import os

/// 统一的结构化日志入口：subsystem 用 bundle id，category 按模块分，
/// Console.app 里按 subsystem 过滤即可；「帮助 → 导出诊断信息」用 OSLogStore 把本进程的日志读出来。
/// 需要排查时看得到的动态值（文件名、错误描述、计数）都标 public；Cookie 值永远不进日志。
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "local.lrc.player.v2"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let lyrics = Logger(subsystem: subsystem, category: "lyrics")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let database = Logger(subsystem: subsystem, category: "database")
}
