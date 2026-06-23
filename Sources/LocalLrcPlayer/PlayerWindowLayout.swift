import AppKit

final class PlayerWindowLayout {
    let searchField = NSSearchField()
    let statusLabel = NSTextField(labelWithString: "请选择一个音乐文件夹")
    let tableView = TrackTableView()
    let lyricsView = LyricsView()
    let playButton = NSButton(title: "", target: nil, action: nil)
    let previousButton = NSButton(title: "", target: nil, action: nil)
    let nextButton = NSButton(title: "", target: nil, action: nil)
    let playbackModeButton = NSButton(title: "", target: nil, action: nil)
    let locatePlayingButton = NSButton(title: "", target: nil, action: nil)
    let progressSlider = SeekSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")

    private let trackListEmptyState = EmptyStateView()
    private let listContainer = NSView()
    private let listHeaderBar = NSStackView()
    private let listTitleLabel = NSTextField(labelWithString: "歌曲")
    private let listNavigationStack = NSStackView()
    private let tableScrollView = NSScrollView()

    init(contentView: NSView) {
        setup(in: contentView)
    }

    static func installBackground(in contentView: NSView) {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effect.topAnchor.constraint(equalTo: contentView.topAnchor),
            effect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func refreshEmptyStates(hasLibraries: Bool, trackCount: Int, searchKeyword: String) {
        if !hasLibraries {
            trackListEmptyState.configure(
                symbolName: "folder.badge.plus",
                title: "请添加音乐文件夹",
                subtitle: "⌘, 打开设置"
            )
            trackListEmptyState.isHidden = false
            listHeaderBar.isHidden = true
            return
        }

        if trackCount == 0 {
            if searchKeyword.isEmpty {
                trackListEmptyState.configure(
                    symbolName: "music.note.list",
                    title: "未找到音乐文件",
                    subtitle: "支持 MP3、FLAC、M4A 等常见格式"
                )
            } else {
                trackListEmptyState.configure(
                    symbolName: "magnifyingglass",
                    title: "无匹配结果",
                    subtitle: "试试其他关键词"
                )
            }
            trackListEmptyState.isHidden = false
            listHeaderBar.isHidden = true
            return
        }

        trackListEmptyState.isHidden = true
        listHeaderBar.isHidden = false
    }

    func updateListHeader(trackCount: Int) {
        if trackCount > 0 {
            listTitleLabel.stringValue = "歌曲 · \(trackCount)"
        } else {
            listTitleLabel.stringValue = "歌曲"
        }
    }

    private func setup(in contentView: NSView) {
        configureTransportButtons()

        searchField.placeholderString = "搜索歌曲、歌手或专辑"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 12)
        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        setupTrackTable()
        configureListContainer()

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(listContainer)
        splitView.addArrangedSubview(lyricsView)

        listContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        listContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let controls = NSStackView(views: [previousButton, playButton, nextButton, playbackModeButton, progressSlider, timeLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12

        progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        playButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 36),
            playButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        let root = NSStackView(views: [splitView, statusLabel, controls])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        let layoutGuide = contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: layoutGuide.topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            splitView.widthAnchor.constraint(equalTo: root.widthAnchor),
            splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            controls.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func configureListContainer() {
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.borderType = .noBorder
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false

        listTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        listTitleLabel.textColor = .secondaryLabelColor

        listNavigationStack.orientation = .horizontal
        listNavigationStack.alignment = .centerY
        listNavigationStack.spacing = 4
        listNavigationStack.addArrangedSubview(locatePlayingButton)

        listHeaderBar.orientation = .horizontal
        listHeaderBar.alignment = .centerY
        listHeaderBar.spacing = 8
        listHeaderBar.translatesAutoresizingMaskIntoConstraints = false
        listHeaderBar.addArrangedSubview(listTitleLabel)
        listHeaderBar.addArrangedSubview(NSView()) // spacer
        listHeaderBar.addArrangedSubview(listNavigationStack)
        if let spacer = listHeaderBar.arrangedSubviews[1] as? NSView {
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        trackListEmptyState.isHidden = true
        listHeaderBar.isHidden = true
        listContainer.addSubview(listHeaderBar)
        listContainer.addSubview(tableScrollView)
        listContainer.addSubview(trackListEmptyState)

        NSLayoutConstraint.activate([
            listHeaderBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listHeaderBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listHeaderBar.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listHeaderBar.heightAnchor.constraint(equalToConstant: 28),

            tableScrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: listHeaderBar.bottomAnchor, constant: 4),
            tableScrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            trackListEmptyState.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            trackListEmptyState.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            trackListEmptyState.topAnchor.constraint(equalTo: listContainer.topAnchor),
            trackListEmptyState.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor)
        ])
    }

    private func setupTrackTable() {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        tableColumn.title = "歌曲"
        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
    }

    func setPlayButtonShowsPause(_ showsPause: Bool) {
        playButton.image = Self.symbolImage(
            showsPause ? "pause.fill" : "play.fill",
            pointSize: 17,
            weight: .semibold
        )
        playButton.toolTip = showsPause ? "暂停" : "播放"
    }

    private func configureTransportButtons() {
        previousButton.image = Self.symbolImage("backward.fill", pointSize: 15, weight: .semibold)
        previousButton.imagePosition = .imageOnly
        previousButton.isBordered = false
        previousButton.bezelStyle = .regularSquare
        previousButton.contentTintColor = .labelColor
        previousButton.toolTip = "上一首"
        previousButton.setContentHuggingPriority(.required, for: .horizontal)

        playButton.bezelStyle = .circular
        playButton.controlSize = .large
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = .white
        setPlayButtonShowsPause(false)
        playButton.setContentHuggingPriority(.required, for: .horizontal)

        nextButton.image = Self.symbolImage("forward.fill", pointSize: 15, weight: .semibold)
        nextButton.imagePosition = .imageOnly
        nextButton.isBordered = false
        nextButton.bezelStyle = .regularSquare
        nextButton.contentTintColor = .labelColor
        nextButton.toolTip = "下一首"
        nextButton.setContentHuggingPriority(.required, for: .horizontal)

        playbackModeButton.imagePosition = .imageOnly
        playbackModeButton.isBordered = false
        playbackModeButton.bezelStyle = .regularSquare
        playbackModeButton.setContentHuggingPriority(.required, for: .horizontal)
        setPlaybackMode(.sequential)

        locatePlayingButton.image = Self.symbolImage("scope", pointSize: 14, weight: .semibold)
        locatePlayingButton.imagePosition = .imageOnly
        locatePlayingButton.isBordered = false
        locatePlayingButton.bezelStyle = .regularSquare
        locatePlayingButton.contentTintColor = .secondaryLabelColor
        locatePlayingButton.toolTip = "定位正在播放的歌曲"
        locatePlayingButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackModeButton.image = Self.symbolImage(mode.symbolName, pointSize: 14, weight: .semibold)
        playbackModeButton.toolTip = mode.title
        playbackModeButton.contentTintColor = .controlAccentColor
    }

    private static func symbolImage(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        UIChrome.symbolImage(name, pointSize: pointSize, weight: weight)
    }
}
