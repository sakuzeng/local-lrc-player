import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var playerWindowController: PlayerWindowController?
    private var menuBarLyricsController: MenuBarLyricsController?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        AppLog.app.notice("App 启动，版本 \(version, privacy: .public)，macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
        // 先应用外观再建窗口，避免启动瞬间闪一下系统默认外观。
        let appearance = ((try? AppSettingsRepository().settings()) ?? .defaults).appearance
        appearance.applyToApp()

        let controller = PlayerWindowController()
        playerWindowController = controller
        let menuBarLyrics = MenuBarLyricsController(playerWindowController: controller)
        menuBarLyricsController = menuBarLyrics
        controller.menuBarLyricsController = menuBarLyrics

        let settings = SettingsWindowController(
            playerWindowController: controller,
            menuBarLyricsController: menuBarLyrics
        )
        settingsWindowController = settings
        controller.settingsWindowController = settings

        AppMenuBuilder.installMainMenu(
            playerWindowController: controller,
            menuBarLyricsController: menuBarLyrics
        )
        menuBarLyrics.reloadSettingsFromDatabase()
        controller.syncMenuBarLyrics()
        DispatchQueue.main.async {
            menuBarLyrics.ensureStatusItemVisible()
            controller.syncMenuBarLyrics()
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            playerWindowController?.showWindow(nil)
            playerWindowController?.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        LibraryBookmarkStore.stopAll()
        playerWindowController?.saveSession()
    }

    @objc func showSettings() {
        settingsWindowController?.showSettings()
    }

    @objc func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// 帮助 → 导出诊断信息：环境 / 设置 / 音乐库 / 播放态 / 最近歌词下载记录 / 本次运行日志，存成纯文本。
    @objc func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "导出诊断信息"
        panel.nameFieldStringValue = DiagnosticsReport.suggestedFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let report = DiagnosticsReport.generate(
            playerWindowController: playerWindowController,
            menuBarLyricsController: menuBarLyricsController
        )
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            AppLog.app.info("诊断信息已导出：\(url.lastPathComponent, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            AppLog.app.error("导出诊断信息失败：\(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "导出诊断信息失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Local LRC Player"
        alert.informativeText = """
        快捷键：
        ⌘O  选择文件夹
        ⌘,  设置
        ⌘R  刷新全部已注册文件夹
        ⌘W  关闭窗口
        ⌘Q  退出
        空格  播放/暂停
        ⌘[  上一首
        ⌘]  下一首

        关闭主窗口后应用仍在后台运行；可在菜单栏歌词处继续控制播放。
        歌词与音乐文件保存在所选文件夹内；数据库仅作索引与历史记录。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
