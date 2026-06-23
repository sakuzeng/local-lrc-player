import AppKit

enum MenuBarLyricsSettingsMenu {
    private static let customWidthTag = -1

    static func appendSettings(to menu: NSMenu, controller: MenuBarLyricsController, leadingSeparator: Bool = true) {
        if leadingSeparator {
            menu.addItem(.separator())
        }

        let enabledItem = NSMenuItem(
            title: "在菜单栏显示歌词",
            action: #selector(MenuBarLyricsController.toggleMenuBarLyricsEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = controller
        menu.addItem(enabledItem)

        let widthMenu = NSMenu()
        for option in MenuBarLyricsMaxWidthOption.allCases {
            let item = NSMenuItem(
                title: "\(option.title) pt",
                action: #selector(MenuBarLyricsController.setMenuBarLyricsMaxWidth(_:)),
                keyEquivalent: ""
            )
            item.target = controller
            item.tag = Int(option.rawValue)
            widthMenu.addItem(item)
        }

        let customItem = NSMenuItem(
            title: "自定义…",
            action: #selector(MenuBarLyricsController.promptCustomMenuBarLyricsMaxWidth(_:)),
            keyEquivalent: ""
        )
        customItem.target = controller
        customItem.tag = customWidthTag
        widthMenu.addItem(customItem)

        let widthParent = NSMenuItem(title: "菜单栏歌词宽度", action: nil, keyEquivalent: "")
        widthParent.submenu = widthMenu
        menu.addItem(widthParent)

        let iconItem = NSMenuItem(
            title: "显示音符图标",
            action: #selector(MenuBarLyricsController.toggleMenuBarLyricsShowIcon(_:)),
            keyEquivalent: ""
        )
        iconItem.target = controller
        menu.addItem(iconItem)
    }

    static func refreshCheckmarks(in menu: NSMenu, settings: AppSettings) {
        let maxWidth = MenuBarLyricsMaxWidth.clamp(settings.menuBarLyricsMaxWidth)
        for item in menu.items {
            switch item.title {
            case "在菜单栏显示歌词":
                item.state = settings.menuBarLyricsEnabled ? .on : .off
            case "显示音符图标":
                item.state = settings.menuBarLyricsShowIcon ? .on : .off
            default:
                break
            }

            if let submenu = item.submenu, item.title == "菜单栏歌词宽度" {
                for widthItem in submenu.items {
                    if widthItem.tag == customWidthTag {
                        widthItem.title = customMenuTitle(for: maxWidth)
                        widthItem.state = MenuBarLyricsMaxWidth.isPreset(maxWidth) ? .off : .on
                    } else if widthItem.tag > 0 {
                        let width = CGFloat(widthItem.tag)
                        widthItem.state = abs(maxWidth - width) < 0.5 ? .on : .off
                    }
                }
            }

            if let submenu = item.submenu {
                refreshCheckmarks(in: submenu, settings: settings)
            }
        }
    }

    private static func customMenuTitle(for width: CGFloat) -> String {
        if MenuBarLyricsMaxWidth.isPreset(width) {
            return "自定义…"
        }
        return "自定义（\(Int(width.rounded())) pt）"
    }
}

final class MenuBarLyricsController: NSObject, NSMenuDelegate {
    private weak var playerWindowController: PlayerWindowController?
    private let settingsRepository: AppSettingsRepository
    private var statusItem: NSStatusItem?
    private let lyricsView = MenuBarLyricsView()
    private var currentSettings = AppSettings.defaults
    private var lastDisplayedText = ""
    private var lastActiveLineIndex: Int?

    init(
        playerWindowController: PlayerWindowController,
        settingsRepository: AppSettingsRepository = AppSettingsRepository()
    ) {
        self.playerWindowController = playerWindowController
        self.settingsRepository = settingsRepository
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reloadSettingsFromDatabase() {
        currentSettings = (try? settingsRepository.settings()) ?? .defaults
        if currentSettings.menuBarLyricsEnabled {
            enable(with: currentSettings)
        } else {
            disable()
        }
        refreshOpenMenus()
    }

    func update(lines: [LrcLine], time: TimeInterval, isPlaying: Bool) {
        guard currentSettings.menuBarLyricsEnabled, statusItem != nil else {
            return
        }

        lyricsView.isScrollingEnabled = isPlaying

        guard let index = LrcParser.activeLineIndex(for: time, in: lines),
              lines.indices.contains(index) else {
            return
        }

        let lineText = lines[index].text
        let isNewLine = lastActiveLineIndex != index
        lastActiveLineIndex = index
        setDisplayText(lineText, resetScroll: isNewLine)
    }

    func showPlaceholder(_ text: String) {
        guard currentSettings.menuBarLyricsEnabled, statusItem != nil else {
            return
        }
        lyricsView.isScrollingEnabled = false
        lastActiveLineIndex = nil
        setDisplayText(text, resetScroll: true)
    }

    func setTrackTitle(_ title: String) {
        guard currentSettings.menuBarLyricsEnabled, statusItem != nil else {
            return
        }
        lyricsView.isScrollingEnabled = false
        lastActiveLineIndex = nil
        setDisplayText("♪ \(title)", resetScroll: true)
    }

    func currentSettingsSnapshot() -> AppSettings {
        currentSettings
    }

    func makeSettingsMenu(delegate: NSMenuDelegate?) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = delegate ?? self
        MenuBarLyricsSettingsMenu.appendSettings(to: menu, controller: self)
        refreshMenuState(in: menu)
        return menu
    }

    func refreshOpenMenus() {
        guard let menu = statusItem?.menu else {
            return
        }
        refreshMenuState(in: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState(in: menu)
    }

    @objc func showMainWindow(_ sender: Any?) {
        guard let controller = playerWindowController else {
            return
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func togglePlayback(_ sender: Any?) {
        playerWindowController?.togglePlaybackFromMenu()
    }

    @objc func playPrevious(_ sender: Any?) {
        playerWindowController?.playPreviousFromMenu()
    }

    @objc func playNext(_ sender: Any?) {
        playerWindowController?.playNextFromMenu()
    }

    @objc func toggleMenuBarLyricsEnabled(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        applyAndPersist {
            try settingsRepository.updateMenuBarLyrics(enabled: enabled)
        }
    }

    @objc func setMenuBarLyricsMaxWidth(_ sender: NSMenuItem) {
        let width = CGFloat(sender.tag)
        applyAndPersist {
            try settingsRepository.updateMenuBarLyrics(maxWidth: width)
        }
    }

    @objc func promptCustomMenuBarLyricsMaxWidth(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "自定义菜单栏歌词宽度"
        alert.informativeText = "请输入宽度（\(Int(MenuBarLyricsMaxWidth.minimum))–\(Int(MenuBarLyricsMaxWidth.maximum)) pt）"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(Int(effectiveMaxWidth().rounded()))
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let raw = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(raw), value > 0 else {
            playerWindowController?.layout.statusLabel.stringValue = "请输入有效的宽度数值"
            return
        }

        applyAndPersist {
            try settingsRepository.updateMenuBarLyrics(maxWidth: CGFloat(value))
        }
    }

    @objc func toggleMenuBarLyricsShowIcon(_ sender: NSMenuItem) {
        let showIcon = sender.state != .on
        applyAndPersist {
            try settingsRepository.updateMenuBarLyrics(showIcon: showIcon)
        }
    }

    @objc private func screenConfigurationChanged() {
        applyLayout()
        refreshOpenMenus()
    }

    private func enable(with settings: AppSettings) {
        currentSettings = settings

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = makeStatusMenu()
            statusItem = item
            item.button?.addSubview(lyricsView)
        }

        applyLayout()
        if lastDisplayedText.isEmpty {
            setDisplayText("Local LRC Player", resetScroll: true)
        } else {
            setDisplayText(lastDisplayedText, resetScroll: true)
        }
    }

    private func disable() {
        if let statusItem {
            lyricsView.removeFromSuperview()
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let showWindowItem = NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        let toggleItem = NSMenuItem(
            title: "播放/暂停",
            action: #selector(togglePlayback(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let previousItem = NSMenuItem(
            title: "上一首",
            action: #selector(playPrevious(_:)),
            keyEquivalent: ""
        )
        previousItem.target = self
        menu.addItem(previousItem)

        let nextItem = NSMenuItem(
            title: "下一首",
            action: #selector(playNext(_:)),
            keyEquivalent: ""
        )
        nextItem.target = self
        menu.addItem(nextItem)

        MenuBarLyricsSettingsMenu.appendSettings(to: menu, controller: self)
        refreshMenuState(in: menu)
        return menu
    }

    private func refreshMenuState(in menu: NSMenu) {
        MenuBarLyricsSettingsMenu.refreshCheckmarks(in: menu, settings: currentSettings)
    }

    private func effectiveMaxWidth() -> CGFloat {
        MenuBarLyricsMaxWidth.clamp(currentSettings.menuBarLyricsMaxWidth)
    }

    private func applyLayout() {
        guard currentSettings.menuBarLyricsEnabled, statusItem != nil else {
            return
        }

        let width = effectiveMaxWidth()
        lyricsView.configure(maxWidth: width, showIcon: currentSettings.menuBarLyricsShowIcon)
        statusItem?.length = width
        lyricsView.frame = MenuBarLyricsView.makeFrame(width: width)
        statusItem?.button?.frame.size = lyricsView.frame.size
        lyricsView.needsLayout = true
    }

    private func setDisplayText(_ text: String, resetScroll: Bool) {
        lastDisplayedText = text
        lyricsView.setText(text, resetScroll: resetScroll)
        applyLayout()
    }

    private func applyAndPersist(_ update: () throws -> Void) {
        do {
            try update()
            reloadSettingsFromDatabase()
            playerWindowController?.syncMenuBarLyrics()
        } catch {
            playerWindowController?.layout.statusLabel.stringValue = "保存菜单栏歌词设置失败：\(error.localizedDescription)"
        }
    }
}
