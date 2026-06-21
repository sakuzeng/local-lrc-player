import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var playerWindowController: PlayerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PlayerWindowController()
        playerWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
