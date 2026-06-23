import AppKit

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private weak var playerWindowController: PlayerWindowController?
    private weak var menuBarLyricsController: MenuBarLyricsController?

    private let libraryRepository = LibraryRepository()
    private let appSettingsRepository = AppSettingsRepository()

    private var libraries: [LibraryRecord] = []

    private let libraryTableView = NSTableView()
    private let addLibraryButton = NSButton(title: "添加文件夹…", target: nil, action: nil)
    private let removeLibraryButton = NSButton(title: "移除所选文件夹", target: nil, action: nil)

    private let lyricProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let setCookieButton = NSButton(title: "设置 Cookie", target: nil, action: nil)
    private let resetCookieButton = NSButton(title: "重置 Cookie", target: nil, action: nil)
    private let downloadCurrentLyricButton = NSButton(title: "下载当前歌词", target: nil, action: nil)
    private let fillMissingLyricsButton = NSButton(title: "补全缺失歌词", target: nil, action: nil)

    private let menuBarLyricsEnabledButton = NSButton(checkboxWithTitle: "在菜单栏显示歌词", target: nil, action: nil)
    private let menuBarWidthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarCustomWidthButton = NSButton(title: "自定义宽度…", target: nil, action: nil)
    private let menuBarShowIconButton = NSButton(checkboxWithTitle: "显示音符图标", target: nil, action: nil)

    var selectedLyricProvider: LyricProvider {
        let index = lyricProviderPopup.indexOfSelectedItem
        guard LyricProvider.allCases.indices.contains(index) else {
            return .netEase
        }
        return LyricProvider.allCases[index]
    }

    init(
        playerWindowController: PlayerWindowController,
        menuBarLyricsController: MenuBarLyricsController
    ) {
        self.playerWindowController = playerWindowController
        self.menuBarLyricsController = menuBarLyricsController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupContent()
        bindActions()
        reloadLibraries()
        refreshMenuBarControls()
        updateCookieButtonTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        positionOnActiveScreen()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reloadLibraries()
        refreshMenuBarControls()
    }

    /// 将设置窗口居中到主窗口所在屏幕；无主窗口时退回到鼠标或 key 窗口所在屏幕。
    private func positionOnActiveScreen() {
        guard let settingsWindow = window else {
            return
        }

        let referenceWindow = playerWindowController?.window
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow

        let screen: NSScreen
        if let referenceWindow, let referenceScreen = referenceWindow.screen {
            screen = referenceScreen
        } else if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            screen = mouseScreen
        } else if let mainScreen = NSScreen.main {
            screen = mainScreen
        } else if let firstScreen = NSScreen.screens.first {
            screen = firstScreen
        } else {
            return
        }

        let visibleFrame = screen.visibleFrame
        var frame = settingsWindow.frame
        frame.origin.x = visibleFrame.origin.x + (visibleFrame.width - frame.width) / 2
        frame.origin.y = visibleFrame.origin.y + (visibleFrame.height - frame.height) / 2
        settingsWindow.setFrame(frame, display: false)
    }

    func reloadLibraries() {
        libraries = (try? libraryRepository.allLibraries()) ?? []
        libraryTableView.reloadData()
        updateLibraryButtons()
    }

    func setLyricDownloadButtonsEnabled(_ isEnabled: Bool) {
        let hasTracks = playerWindowController?.tracks.isEmpty == false
        setCookieButton.isEnabled = isEnabled
        resetCookieButton.isEnabled = isEnabled
        downloadCurrentLyricButton.isEnabled = isEnabled && hasTracks
        fillMissingLyricsButton.isEnabled = isEnabled && hasTracks
    }

    func updateLyricDownloadButtonState(hasTracks: Bool) {
        downloadCurrentLyricButton.isEnabled = hasTracks
        fillMissingLyricsButton.isEnabled = hasTracks
    }

    private static let formLabelWidth: CGFloat = 108
    private static let groupInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

    private func setupContent() {
        guard let contentView = window?.contentView else {
            return
        }

        [
            addLibraryButton,
            removeLibraryButton,
            setCookieButton,
            resetCookieButton,
            downloadCurrentLyricButton,
            fillMissingLyricsButton,
            menuBarCustomWidthButton
        ].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }

        resetCookieButton.bezelStyle = .rounded
        resetCookieButton.contentTintColor = .secondaryLabelColor

        lyricProviderPopup.addItems(withTitles: LyricProvider.allCases.map(\.displayName))
        lyricProviderPopup.selectItem(at: 0)

        menuBarWidthPopup.addItems(withTitles: MenuBarLyricsMaxWidthOption.allCases.map { "\($0.title) pt" })

        let libraryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        libraryColumn.title = "文件夹路径"
        libraryColumn.resizingMask = .autoresizingMask
        libraryTableView.addTableColumn(libraryColumn)
        libraryTableView.headerView = nil
        libraryTableView.rowHeight = 28
        libraryTableView.usesAlternatingRowBackgroundColors = true
        libraryTableView.dataSource = self
        libraryTableView.delegate = self
        libraryTableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let libraryScrollView = NSScrollView()
        libraryScrollView.documentView = libraryTableView
        libraryScrollView.hasVerticalScroller = true
        libraryScrollView.borderType = .bezelBorder
        libraryScrollView.translatesAutoresizingMaskIntoConstraints = false
        libraryScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let libraryButtons = NSStackView(views: [addLibraryButton, removeLibraryButton])
        libraryButtons.orientation = .horizontal
        libraryButtons.spacing = 8
        libraryButtons.distribution = .fillEqually

        let librarySection = makeSection(
            title: "音乐库",
            footer: "移除文件夹只会从总播放列表删除索引，不会删除磁盘上的音乐文件。",
            panel: makeGroupedPanel(rows: [libraryScrollView, libraryButtons])
        )

        lyricProviderPopup.controlSize = .regular
        lyricProviderPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let lyricsPanel = makeGroupedPanel(rows: [
            makeFormRow(label: "Cookie 来源", control: lyricProviderPopup),
            makePanelDivider(),
            makeIndentedBlock(rows: [
                makeSubsectionLabel("账号"),
                makeEqualWidthButtonRow([setCookieButton, resetCookieButton])
            ]),
            makePanelDivider(),
            makeIndentedBlock(rows: [
                makeSubsectionLabel("下载"),
                makeEqualWidthButtonRow([downloadCurrentLyricButton, fillMissingLyricsButton])
            ])
        ])

        let lyricsSection = makeSection(
            title: "歌词",
            footer: "登录音乐平台后，从浏览器复制 Cookie 并粘贴保存，用于在线搜索与下载歌词。",
            panel: lyricsPanel
        )

        menuBarWidthPopup.controlSize = .regular
        menuBarWidthPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let menuBarPanel = makeGroupedPanel(rows: [
            menuBarLyricsEnabledButton,
            makeFormRow(label: "显示宽度", control: menuBarWidthPopup),
            makeFormRow(label: "自定义", control: menuBarCustomWidthButton),
            makePanelDivider(),
            menuBarShowIconButton
        ])

        let menuBarSection = makeSection(
            title: "菜单栏歌词",
            panel: menuBarPanel
        )

        let root = NSStackView(views: [librarySection, lyricsSection, menuBarSection])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 24
        root.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = root

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            librarySection.widthAnchor.constraint(equalTo: root.widthAnchor),
            lyricsSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            menuBarSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func makeSection(title: String, footer: String? = nil, panel: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        var views: [NSView] = [titleLabel, panel]
        if let footer {
            views.append(makeMutedFooter(footer))
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        panel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeMutedFooter(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 440
        return label
    }

    private func makeSubsectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func makeGroupedPanel(rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = Self.groupInsets
        stack.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.titlePosition = .noTitle
        box.boxType = .custom
        box.borderType = .noBorder
        box.cornerRadius = 10
        box.fillColor = NSColor.controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])

        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -(Self.groupInsets.left + Self.groupInsets.right)
            ).isActive = true
        }

        return box
    }

    private func makeFormRow(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13)
        labelView.alignment = .right
        labelView.textColor = .secondaryLabelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.setContentHuggingPriority(.required, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labelView)
        row.addSubview(control)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelView.widthAnchor.constraint(equalToConstant: Self.formLabelWidth),
            labelView.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            control.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])
        return row
    }

    private func makeIndentedBlock(rows: [NSView]) -> NSStackView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: Self.formLabelWidth + 12, bottom: 0, right: 0)
        if let buttonRow = rows.last {
            buttonRow.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -(Self.formLabelWidth + 12)
            ).isActive = true
        }
        return stack
    }

    private func makeEqualWidthButtonRow(_ buttons: [NSButton]) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        return stack
    }

    private func makePanelDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
    }

    private func bindActions() {
        addLibraryButton.target = self
        addLibraryButton.action = #selector(addLibrary)
        removeLibraryButton.target = self
        removeLibraryButton.action = #selector(removeSelectedLibrary)

        lyricProviderPopup.target = self
        lyricProviderPopup.action = #selector(lyricProviderChanged)

        setCookieButton.target = playerWindowController
        setCookieButton.action = #selector(PlayerWindowController.setLyricCookie)
        resetCookieButton.target = playerWindowController
        resetCookieButton.action = #selector(PlayerWindowController.resetLyricCookie)
        downloadCurrentLyricButton.target = playerWindowController
        downloadCurrentLyricButton.action = #selector(PlayerWindowController.downloadCurrentLyric)
        fillMissingLyricsButton.target = playerWindowController
        fillMissingLyricsButton.action = #selector(PlayerWindowController.fillMissingLyrics)

        menuBarLyricsEnabledButton.target = self
        menuBarLyricsEnabledButton.action = #selector(toggleMenuBarLyricsEnabled)
        menuBarWidthPopup.target = self
        menuBarWidthPopup.action = #selector(menuBarWidthChanged)
        menuBarCustomWidthButton.target = self
        menuBarCustomWidthButton.action = #selector(promptCustomMenuBarWidth)
        menuBarShowIconButton.target = self
        menuBarShowIconButton.action = #selector(toggleMenuBarShowIcon)
    }

    private func updateLibraryButtons() {
        let selectedRow = libraryTableView.selectedRow
        removeLibraryButton.isEnabled = selectedRow >= 0 && libraries.indices.contains(selectedRow)
    }

    private func updateCookieButtonTitle() {
        let provider = selectedLyricProvider
        setCookieButton.title = "设置\(provider.displayName) Cookie"
    }

    private func refreshMenuBarControls() {
        let settings = menuBarLyricsController?.currentSettingsSnapshot()
            ?? (try? appSettingsRepository.settings())
            ?? .defaults

        menuBarLyricsEnabledButton.state = settings.menuBarLyricsEnabled ? .on : .off
        menuBarShowIconButton.state = settings.menuBarLyricsShowIcon ? .on : .off

        let width = MenuBarLyricsMaxWidth.clamp(settings.menuBarLyricsMaxWidth)
        if let presetIndex = MenuBarLyricsMaxWidthOption.allCases.firstIndex(where: { abs($0.rawValue - width) < 0.5 }) {
            menuBarWidthPopup.selectItem(at: presetIndex)
        }
        if MenuBarLyricsMaxWidth.isPreset(width) {
            menuBarCustomWidthButton.title = "自定义宽度…"
        } else {
            menuBarCustomWidthButton.title = "自定义（\(Int(width.rounded())) pt）"
        }
    }

    @objc private func addLibrary() {
        playerWindowController?.chooseFolder()
        reloadLibraries()
    }

    @objc private func removeSelectedLibrary() {
        let row = libraryTableView.selectedRow
        guard libraries.indices.contains(row) else {
            return
        }

        let library = libraries[row]
        let alert = NSAlert()
        alert.messageText = "移除音乐文件夹？"
        alert.informativeText = """
        将从总播放列表移除「\(library.displayName ?? library.path)」下的曲目索引。
        若某首歌仅存在于该文件夹，将一并从列表移除。
        不会删除磁盘上的音乐文件。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try libraryRepository.deleteLibrary(id: library.id)
            reloadLibraries()
            playerWindowController?.handleLibraryRemoved()
        } catch {
            presentError("移除文件夹失败：\(error.localizedDescription)")
        }
    }

    @objc private func lyricProviderChanged() {
        updateCookieButtonTitle()
    }

    @objc private func toggleMenuBarLyricsEnabled(_ sender: NSButton) {
        do {
            try appSettingsRepository.updateMenuBarLyrics(enabled: sender.state == .on)
            menuBarLyricsController?.reloadSettingsFromDatabase()
            playerWindowController?.syncMenuBarLyrics()
            refreshMenuBarControls()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func menuBarWidthChanged() {
        let index = menuBarWidthPopup.indexOfSelectedItem
        guard MenuBarLyricsMaxWidthOption.allCases.indices.contains(index) else {
            return
        }
        let width = MenuBarLyricsMaxWidthOption.allCases[index].rawValue
        do {
            try appSettingsRepository.updateMenuBarLyrics(maxWidth: width)
            menuBarLyricsController?.reloadSettingsFromDatabase()
            playerWindowController?.syncMenuBarLyrics()
            refreshMenuBarControls()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func promptCustomMenuBarWidth() {
        menuBarLyricsController?.promptCustomMenuBarLyricsMaxWidth(self)
        refreshMenuBarControls()
    }

    @objc private func toggleMenuBarShowIcon(_ sender: NSButton) {
        do {
            try appSettingsRepository.updateMenuBarLyrics(showIcon: sender.state == .on)
            menuBarLyricsController?.reloadSettingsFromDatabase()
            playerWindowController?.syncMenuBarLyrics()
            refreshMenuBarControls()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        libraries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard libraries.indices.contains(row) else {
            return nil
        }

        let library = libraries[row]
        let text = library.path
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = text
        cell.toolTip = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateLibraryButtons()
    }
}
