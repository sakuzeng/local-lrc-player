import AppKit

final class PlayerWindowLayout {
    let chooseButton = NSButton(title: "选择文件夹", target: nil, action: nil)
    let folderLabel = NSTextField(labelWithString: "未选择音乐目录")
    let statusLabel = NSTextField(labelWithString: "请选择一个音乐文件夹")
    let tableView = NSTableView()
    let lyricsView = LyricsView()
    let lyricProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let setNetEaseCookieButton = NSButton(title: "设置 Cookie", target: nil, action: nil)
    let resetNetEaseCookieButton = NSButton(title: "重置 Cookie", target: nil, action: nil)
    let downloadCurrentLyricButton = NSButton(title: "下载当前歌词", target: nil, action: nil)
    let fillMissingLyricsButton = NSButton(title: "补全缺失歌词", target: nil, action: nil)
    let playButton = NSButton(title: "播放", target: nil, action: nil)
    let previousButton = NSButton(title: "上一首", target: nil, action: nil)
    let nextButton = NSButton(title: "下一首", target: nil, action: nil)
    let progressSlider = SeekSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")

    init(contentView: NSView) {
        setup(in: contentView)
    }

    private func setup(in contentView: NSView) {
        [
            chooseButton,
            setNetEaseCookieButton,
            resetNetEaseCookieButton,
            downloadCurrentLyricButton,
            fillMissingLyricsButton,
            previousButton,
            playButton,
            nextButton
        ].forEach {
            $0.bezelStyle = .rounded
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        lyricProviderPopup.addItems(withTitles: LyricProvider.allCases.map(\.displayName))
        lyricProviderPopup.selectItem(at: 0)
        lyricProviderPopup.setContentHuggingPriority(.required, for: .horizontal)

        folderLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let topBar = NSStackView(views: [chooseButton, folderLabel])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 12

        let cookieSourceLabel = NSTextField(labelWithString: "Cookie 来源")
        cookieSourceLabel.textColor = .secondaryLabelColor

        let lyricTools = NSStackView(views: [
            cookieSourceLabel,
            lyricProviderPopup,
            setNetEaseCookieButton,
            resetNetEaseCookieButton,
            downloadCurrentLyricButton,
            fillMissingLyricsButton
        ])
        lyricTools.orientation = .horizontal
        lyricTools.alignment = .centerY
        lyricTools.spacing = 10

        setupTrackTable()
        let tableScrollView = NSScrollView()
        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.borderType = .lineBorder

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(tableScrollView)
        splitView.addArrangedSubview(lyricsView)

        tableScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        tableScrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let controls = NSStackView(views: [previousButton, playButton, nextButton, progressSlider, timeLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10

        let root = NSStackView(views: [topBar, lyricTools, splitView, statusLabel, controls])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            topBar.widthAnchor.constraint(equalTo: root.widthAnchor),
            lyricTools.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
            splitView.widthAnchor.constraint(equalTo: root.widthAnchor),
            splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            controls.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func setupTrackTable() {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        tableColumn.title = "歌曲"
        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
    }
}
