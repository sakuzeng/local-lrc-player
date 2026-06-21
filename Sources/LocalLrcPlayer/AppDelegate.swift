import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var playerWindowController: PlayerWindowController?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PlayerWindowController()
        playerWindowController = controller
        AppMenuBuilder.installMainMenu(playerWindowController: controller)
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
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerWindowController?.saveSession()
    }

    @objc func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Local LRC Player"
        alert.informativeText = """
        快捷键：
        ⌘O  选择文件夹
        ⌘R  刷新全部已注册文件夹
        ⌘W  关闭窗口
        ⌘Q  退出
        空格  播放/暂停
        ⌘[  上一首
        ⌘]  下一首

        歌词与音乐文件保存在所选文件夹内；数据库仅作索引与历史记录。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
