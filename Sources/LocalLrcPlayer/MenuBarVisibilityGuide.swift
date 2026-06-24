import AppKit

enum MenuBarVisibilityGuide {
    private static let lastShownKey = "menuBarVisibilityGuideLastShown"
    private static let reshowInterval: TimeInterval = 24 * 60 * 60

    static func isRunningOnTahoeOrNewer() -> Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    static func isStatusItemLikelyHidden(_ item: NSStatusItem?) -> Bool {
        guard let item else {
            return true
        }

        guard let button = item.button else {
            return true
        }

        guard let window = button.window else {
            return true
        }

        if window.screen == nil {
            return true
        }

        if window.frame.origin.y < 0 {
            return true
        }

        return button.image == nil && button.title.isEmpty
    }

    static func showIfLikelyBlocked(force: Bool = false) {
        guard isRunningOnTahoeOrNewer() else {
            return
        }

        let now = Date().timeIntervalSince1970
        if !force {
            let lastShown = UserDefaults.standard.double(forKey: lastShownKey)
            if lastShown > 0, now - lastShown < reshowInterval {
                return
            }
        }

        UserDefaults.standard.set(now, forKey: lastShownKey)

        let alert = NSAlert()
        alert.messageText = "无法在菜单栏显示歌词"
        alert.informativeText = """
        macOS 26 可能已在系统层面隐藏本应用的菜单栏项。

        请打开「系统设置 → 菜单栏」，在「允许在菜单栏中显示」里打开 Local LRC Player。

        若仍不显示，可完全退出应用（⌘Q）后重新打开；必要时重新运行 ./build.sh 构建最新版本。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "知道了")

        if alert.runModal() == .alertFirstButtonReturn {
            openMenuBarSettings()
        }
    }

    static func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.MenuBarSettings",
            "x-apple.systempreferences:com.apple.control-center-extension.menu-bar"
        ]
        for urlString in candidates {
            guard let url = URL(string: urlString) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
