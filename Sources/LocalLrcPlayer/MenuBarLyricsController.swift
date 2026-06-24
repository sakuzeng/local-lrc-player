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
    private var statusMenu: NSMenu?
    private var currentSettings = AppSettings.defaults
    private var lastDisplayedText = ""
    private var lastActiveLineIndex: Int?
    private var scrollTimer: Timer?
    private var scrollOffsetX: CGFloat = 0
    private var scrollTextSize = NSSize.zero
    private var scrollNeedsMarquee = false
    private var scrollStartPauseRemaining = 0
    private var scrollReachedEnd = false
    private var isScrollingEnabled = false
    private var configureAttempt = 0
    private var visibilityCheckScheduled = false
    private var visibilityRecoveryAttempt = 0

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopScrollTimer()
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

        setScrollingEnabled(isPlaying)

        let index: Int
        if let activeIndex = LrcParser.activeLineIndex(for: time, in: lines),
           lines.indices.contains(activeIndex) {
            index = activeIndex
        } else if let fallbackIndex = Self.fallbackLineIndex(for: time, in: lines) {
            index = fallbackIndex
        } else if !lastDisplayedText.isEmpty {
            return
        } else {
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
        setScrollingEnabled(false)
        lastActiveLineIndex = nil
        setDisplayText(text, resetScroll: true)
    }

    func setTrackTitle(_ title: String) {
        guard currentSettings.menuBarLyricsEnabled, statusItem != nil else {
            return
        }
        setScrollingEnabled(false)
        lastActiveLineIndex = nil
        setDisplayText("♪ \(title)", resetScroll: true)
    }

    func currentSettingsSnapshot() -> AppSettings {
        currentSettings
    }

    func makeSettingsMenu(delegate: NSMenuDelegate?) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = delegate ?? self
        menu.appearance = NSAppearance(named: .aqua)
        MenuBarLyricsSettingsMenu.appendSettings(to: menu, controller: self)
        refreshMenuState(in: menu)
        return menu
    }

    func refreshOpenMenus() {
        guard let menu = statusMenu else {
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
        ensureStatusItemVisible()
    }

    @objc private func applicationDidBecomeActive() {
        ensureStatusItemVisible()
    }

    func ensureStatusItemVisible() {
        guard currentSettings.menuBarLyricsEnabled else {
            return
        }

        if statusItem == nil {
            enable(with: currentSettings)
            return
        }

        MenuBarStatusItemVisibility.install(statusItem!)
        applyLayout()
        playerWindowController?.syncMenuBarLyrics()
    }

    private func attachStatusMenu(to item: NSStatusItem) {
        if statusMenu == nil {
            statusMenu = makeStatusMenu()
        }
        item.menu = statusMenu
        item.button?.target = nil
        item.button?.action = nil
    }

    private func createStatusItem() -> NSStatusItem {
        MenuBarStatusItemVisibility.clearPersistedVisibility()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = makeStatusMenu()
        attachStatusMenu(to: item)
        MenuBarStatusItemVisibility.install(item)

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.title = ""
            let maxWidth = max(effectiveMaxWidth(), NSStatusItem.squareLength)
            let width = MenuBarLyricsStatusImage.preferredContentWidth(
                text: "Local LRC Player",
                showIcon: currentSettings.menuBarLyricsShowIcon,
                maxWidth: maxWidth,
                useFullWidth: false
            )
            item.length = width
            button.image = MenuBarLyricsStatusImage.make(
                text: "Local LRC Player",
                width: width,
                showIcon: currentSettings.menuBarLyricsShowIcon
            )
        }

        return item
    }

    private func enable(with settings: AppSettings) {
        currentSettings = settings
        visibilityRecoveryAttempt = 0

        if let button = statusItem?.button, !button.subviews.isEmpty {
            let savedText = lastDisplayedText
            disable()
            lastDisplayedText = savedText
        }

        if statusItem == nil {
            statusItem = createStatusItem()
        } else if statusMenu == nil {
            statusMenu = makeStatusMenu()
        }
        if let statusItem {
            attachStatusMenu(to: statusItem)
        }

        MenuBarStatusItemVisibility.install(statusItem!)
        scheduleStatusItemConfiguration(resetAttempts: true)
    }

    private func scheduleStatusItemConfiguration(resetAttempts: Bool) {
        if resetAttempts {
            configureAttempt = 0
            visibilityCheckScheduled = false
        }
        attemptConfigureStatusItem()
    }

    private func attemptConfigureStatusItem() {
        guard currentSettings.menuBarLyricsEnabled, let item = statusItem else {
            return
        }

        guard item.button != nil else {
            configureAttempt += 1
            if configureAttempt < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attemptConfigureStatusItem()
                }
            } else {
                recoverHiddenStatusItem()
            }
            return
        }

        MenuBarStatusItemVisibility.install(item)
        attachStatusMenu(to: item)

        applyLayout()
        if lastDisplayedText.isEmpty {
            setDisplayText("Local LRC Player", resetScroll: true)
        } else {
            setDisplayText(lastDisplayedText, resetScroll: true)
        }
        playerWindowController?.syncMenuBarLyrics()
        publishDiagnostics(for: item)
        scheduleVisibilityVerification()
    }

    private func publishDiagnostics(for item: NSStatusItem) {
        guard let controller = playerWindowController else {
            return
        }

        let button = item.button
        let screenAttached = button?.window?.screen != nil
        let hasImage = button?.image != nil
        guard !screenAttached || !hasImage else {
            return
        }

        let summary = "菜单栏: 可见=\(item.isVisible) 屏幕=\(screenAttached ? "已连接" : "未连接") 图像=\(hasImage ? "有" : "无")"
        controller.layout.statusLabel.stringValue = summary
    }

    private func scheduleVisibilityVerification() {
        guard !visibilityCheckScheduled else {
            return
        }
        visibilityCheckScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else {
                return
            }
            self.visibilityCheckScheduled = false
            guard self.currentSettings.menuBarLyricsEnabled else {
                return
            }
            if MenuBarVisibilityGuide.isStatusItemLikelyHidden(self.statusItem) {
                self.recoverHiddenStatusItem()
            }
        }
    }

    private func recoverHiddenStatusItem() {
        guard visibilityRecoveryAttempt < 2 else {
            MenuBarVisibilityGuide.showIfLikelyBlocked(force: true)
            return
        }
        visibilityRecoveryAttempt += 1

        let savedText = lastDisplayedText
        disable()
        lastDisplayedText = savedText
        enable(with: currentSettings)
    }

    private func disable() {
        stopScrollTimer()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusMenu = nil
        MenuBarStatusItemVisibility.clearPersistedVisibility()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.appearance = NSAppearance(named: .aqua)

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
        guard currentSettings.menuBarLyricsEnabled, let item = statusItem, item.button != nil else {
            return
        }

        MenuBarStatusItemVisibility.install(item)
        refreshButtonTitle(resetScroll: false)
    }

    private func setDisplayText(_ text: String, resetScroll: Bool) {
        lastDisplayedText = text
        applyLayout()
        refreshButtonTitle(resetScroll: resetScroll)
    }

    private func setScrollingEnabled(_ enabled: Bool) {
        isScrollingEnabled = enabled
        if enabled {
            refreshButtonTitle(resetScroll: false)
            updateScrollTimer()
        } else {
            stopScrollTimer()
            scrollOffsetX = 0
            scrollReachedEnd = false
            refreshButtonTitle(resetScroll: false)
        }
    }

    private func refreshButtonTitle(resetScroll: Bool) {
        guard let button = statusItem?.button, let item = statusItem else {
            return
        }

        let maxWidth = max(effectiveMaxWidth(), NSStatusItem.squareLength)
        let font = NSFont.systemFont(ofSize: 13)
        scrollTextSize = (lastDisplayedText as NSString).size(withAttributes: [.font: font])
        let fullTextWidth = textAreaWidth(for: maxWidth)
        scrollNeedsMarquee = scrollTextSize.width > fullTextWidth + 0.5

        if resetScroll || !scrollNeedsMarquee {
            scrollOffsetX = 0
            scrollStartPauseRemaining = 30
            scrollReachedEnd = false
        }

        let displayText: String
        let textOffsetX: CGFloat
        let useFullWidth: Bool
        if scrollNeedsMarquee, isScrollingEnabled || scrollReachedEnd {
            displayText = lastDisplayedText
            let maxScroll = max(scrollTextSize.width - fullTextWidth, 0)
            textOffsetX = scrollReachedEnd ? maxScroll : scrollOffsetX
            useFullWidth = true
        } else if scrollNeedsMarquee {
            displayText = Self.truncatedText(lastDisplayedText, maxWidth: fullTextWidth, font: font)
            textOffsetX = 0
            useFullWidth = false
        } else {
            displayText = lastDisplayedText
            textOffsetX = 0
            useFullWidth = false
        }

        let width = MenuBarLyricsStatusImage.preferredContentWidth(
            text: displayText,
            showIcon: currentSettings.menuBarLyricsShowIcon,
            maxWidth: maxWidth,
            useFullWidth: useFullWidth
        )
        item.length = width

        button.toolTip = lastDisplayedText.isEmpty ? "Local LRC Player" : lastDisplayedText
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = MenuBarLyricsStatusImage.make(
            text: displayText,
            width: width,
            showIcon: currentSettings.menuBarLyricsShowIcon,
            textOffsetX: textOffsetX
        )

        updateScrollTimer()
    }

    private func textAreaWidth(for totalWidth: CGFloat) -> CGFloat {
        let iconBlock: CGFloat = currentSettings.menuBarLyricsShowIcon ? 18 : 0
        return max(totalWidth - iconBlock - 8, 20)
    }

    private static func truncatedText(_ text: String, maxWidth: CGFloat, font: NSFont) -> String {
        guard !text.isEmpty else {
            return ""
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (text as NSString).size(withAttributes: attributes)
        if measured.width <= maxWidth {
            return text
        }

        var trimmed = text
        while trimmed.count > 1 {
            trimmed = String(trimmed.dropLast())
            let candidate = trimmed + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= maxWidth {
                return candidate
            }
        }
        return "…"
    }

    private func updateScrollTimer() {
        if isScrollingEnabled, scrollNeedsMarquee, !scrollReachedEnd {
            startScrollTimerIfNeeded()
        } else {
            stopScrollTimer()
        }
    }

    private func startScrollTimerIfNeeded() {
        guard scrollTimer == nil else {
            return
        }

        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.advanceScroll()
        }
        if let scrollTimer {
            RunLoop.main.add(scrollTimer, forMode: .common)
        }
    }

    private func stopScrollTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func advanceScroll() {
        guard isScrollingEnabled, scrollNeedsMarquee, !scrollReachedEnd, statusItem?.button != nil else {
            stopScrollTimer()
            return
        }

        let textWidth = textAreaWidth(for: max(effectiveMaxWidth(), NSStatusItem.squareLength))

        if scrollStartPauseRemaining > 0 {
            scrollStartPauseRemaining -= 1
            refreshButtonTitle(resetScroll: false)
            return
        }

        scrollOffsetX += 0.7
        let maxScroll = max(scrollTextSize.width - textWidth, 0)
        if scrollOffsetX >= maxScroll {
            scrollOffsetX = maxScroll
            scrollReachedEnd = true
            stopScrollTimer()
        }

        refreshButtonTitle(resetScroll: false)
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

    /// 当前时间尚未进入任何一行时，取最近已过的行；若还在前奏则取第一行。
    private static func fallbackLineIndex(for time: TimeInterval, in lines: [LrcLine]) -> Int? {
        guard !lines.isEmpty else {
            return nil
        }

        var lastPassed: Int?
        for index in lines.indices where lines[index].time <= time {
            lastPassed = index
        }
        if let lastPassed {
            return lastPassed
        }
        return 0
    }
}
