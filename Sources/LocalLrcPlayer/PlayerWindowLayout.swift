import AppKit

final class PlayerWindowLayout {
    /// 与 `LyricsView` 的 `textContainerInset.width` 保持一致，便于进度条与歌词文本对齐。
    private static let lyricsHorizontalInset: CGFloat = 28
    private static let playbackBarHeight: CGFloat = 52

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
    let volumeSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let volumeButton = NSButton(title: "", target: nil, action: nil)

    private let nowPlayingArtView = NSImageView()
    private let nowPlayingTitleLabel = NSTextField(labelWithString: "")
    private let nowPlayingArtistLabel = NSTextField(labelWithString: "")
    private let nowPlayingInfoStack = NSStackView()
    private let nowPlayingBar = NSView()
    private var nowPlayingBarHeightConstraint: NSLayoutConstraint!
    private let ambientBackgroundView = AmbientBackgroundView()
    private let volumePopover = NSPopover()
    private let seekPreviewLabel = NSTextField(labelWithString: "")

    private let trackListEmptyState = EmptyStateView()
    private let listContainer = NSView()
    private let lyricsContainer = NSView()
    private let listHeaderBar = NSStackView()
    private let listTitleLabel = NSTextField(labelWithString: "歌曲")
    private let listNavigationStack = NSStackView()
    private let tableScrollView = NSScrollView()
    private let transportBar = NSView()
    private let progressBar = NSView()

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
        configurePlaybackBars()

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
        configureLyricsContainer()

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(listContainer)
        splitView.addArrangedSubview(lyricsContainer)

        listContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        listContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let root = NSStackView(views: [splitView, statusLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        // 氛围背景在毛玻璃之上、内容之下。
        ambientBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(ambientBackgroundView)

        contentView.addSubview(root)
        let layoutGuide = contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            ambientBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            ambientBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ambientBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            ambientBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            root.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: layoutGuide.topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            splitView.widthAnchor.constraint(equalTo: root.widthAnchor),
            splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func configurePlaybackBars() {
        progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.heightAnchor.constraint(equalToConstant: 24).isActive = true

        playButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 32),
            playButton.heightAnchor.constraint(equalToConstant: 32),
            previousButton.widthAnchor.constraint(equalToConstant: 32),
            previousButton.heightAnchor.constraint(equalToConstant: 32),
            nextButton.widthAnchor.constraint(equalToConstant: 32),
            nextButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        let transportCluster = NSStackView(views: [previousButton, playButton, nextButton])
        transportCluster.orientation = .horizontal
        transportCluster.alignment = .centerY
        transportCluster.spacing = 6
        transportCluster.translatesAutoresizingMaskIntoConstraints = false

        let clusterBackground = NSView()
        clusterBackground.wantsLayer = true
        clusterBackground.layer?.cornerRadius = 22
        clusterBackground.layer?.cornerCurve = .continuous
        clusterBackground.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        clusterBackground.translatesAutoresizingMaskIntoConstraints = false
        clusterBackground.addSubview(transportCluster)

        NSLayoutConstraint.activate([
            transportCluster.leadingAnchor.constraint(equalTo: clusterBackground.leadingAnchor, constant: 6),
            transportCluster.trailingAnchor.constraint(equalTo: clusterBackground.trailingAnchor, constant: -6),
            transportCluster.topAnchor.constraint(equalTo: clusterBackground.topAnchor, constant: 4),
            transportCluster.bottomAnchor.constraint(equalTo: clusterBackground.bottomAnchor, constant: -4)
        ])

        let modePill = NSView()
        modePill.wantsLayer = true
        modePill.layer?.cornerRadius = 22
        modePill.layer?.cornerCurve = .continuous
        modePill.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        modePill.translatesAutoresizingMaskIntoConstraints = false
        modePill.addSubview(playbackModeButton)

        playbackModeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modePill.widthAnchor.constraint(equalToConstant: 40),
            modePill.heightAnchor.constraint(equalToConstant: 40),
            playbackModeButton.centerXAnchor.constraint(equalTo: modePill.centerXAnchor),
            playbackModeButton.centerYAnchor.constraint(equalTo: modePill.centerYAnchor),
            playbackModeButton.widthAnchor.constraint(equalToConstant: 32),
            playbackModeButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        let transportRow = NSStackView(views: [clusterBackground, modePill])
        transportRow.orientation = .horizontal
        transportRow.alignment = .centerY
        transportRow.spacing = 20
        transportRow.translatesAutoresizingMaskIntoConstraints = false

        transportBar.translatesAutoresizingMaskIntoConstraints = false
        transportBar.addSubview(transportRow)

        configureNowPlayingInfo()
        configureVolumeControls()

        let progressRow = NSStackView(views: [progressSlider, timeLabel, volumeButton])
        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 12
        progressRow.setCustomSpacing(8, after: timeLabel)
        progressRow.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(progressRow)

        // 进度条悬停时间气泡：frame 手动摆（跟随指针），不进 Auto Layout。
        seekPreviewLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        seekPreviewLabel.textColor = .secondaryLabelColor
        seekPreviewLabel.alignment = .center
        seekPreviewLabel.wantsLayer = true
        seekPreviewLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        seekPreviewLabel.layer?.cornerRadius = 7
        seekPreviewLabel.layer?.cornerCurve = .continuous
        seekPreviewLabel.isHidden = true
        progressBar.addSubview(seekPreviewLabel)

        NSLayoutConstraint.activate([
            transportBar.heightAnchor.constraint(equalToConstant: Self.playbackBarHeight),
            transportRow.centerXAnchor.constraint(equalTo: transportBar.centerXAnchor),
            transportRow.centerYAnchor.constraint(equalTo: transportBar.centerYAnchor),

            progressBar.heightAnchor.constraint(equalToConstant: Self.playbackBarHeight),
            progressRow.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor, constant: Self.lyricsHorizontalInset),
            progressRow.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: -Self.lyricsHorizontalInset),
            progressRow.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor)
        ])
    }

    private func configureNowPlayingInfo() {
        nowPlayingArtView.wantsLayer = true
        nowPlayingArtView.layer?.cornerRadius = 6
        nowPlayingArtView.layer?.cornerCurve = .continuous
        nowPlayingArtView.layer?.masksToBounds = true
        nowPlayingArtView.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        nowPlayingArtView.imageScaling = .scaleProportionallyUpOrDown
        nowPlayingArtView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nowPlayingArtView.widthAnchor.constraint(equalToConstant: 36),
            nowPlayingArtView.heightAnchor.constraint(equalToConstant: 36)
        ])

        nowPlayingTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nowPlayingTitleLabel.lineBreakMode = .byTruncatingTail
        nowPlayingArtistLabel.font = .systemFont(ofSize: 11)
        nowPlayingArtistLabel.textColor = .secondaryLabelColor
        nowPlayingArtistLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [nowPlayingTitleLabel, nowPlayingArtistLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        nowPlayingInfoStack.orientation = .horizontal
        nowPlayingInfoStack.alignment = .centerY
        nowPlayingInfoStack.spacing = 8
        nowPlayingInfoStack.addArrangedSubview(nowPlayingArtView)
        nowPlayingInfoStack.addArrangedSubview(textStack)
        nowPlayingInfoStack.isHidden = true

        // 文本可截断，列宽（240–380pt）内不撑破布局。
        nowPlayingTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nowPlayingArtistLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureVolumeControls() {
        volumeButton.image = Self.symbolImage("speaker.wave.2.fill", pointSize: 13, weight: .medium)
        volumeButton.imagePosition = .imageOnly
        volumeButton.isBordered = false
        volumeButton.bezelStyle = .regularSquare
        volumeButton.contentTintColor = .secondaryLabelColor
        volumeButton.toolTip = "音量"
        volumeButton.setContentHuggingPriority(.required, for: .horizontal)

        // 竖向滑杆装在 transient popover 里（下小上大）；必须显式 isVertical，仅靠约束不可靠。
        volumeSlider.isVertical = true
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(volumeSlider)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 40),
            content.heightAnchor.constraint(equalToConstant: 124),
            volumeSlider.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            volumeSlider.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            volumeSlider.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            volumeSlider.widthAnchor.constraint(equalToConstant: 21)
        ])

        let contentController = NSViewController()
        contentController.view = content
        volumePopover.contentViewController = contentController
        volumePopover.behavior = .transient
    }

    func showSeekPreview(text: String, fraction: Double) {
        seekPreviewLabel.stringValue = text
        seekPreviewLabel.sizeToFit()

        let bubbleSize = NSSize(
            width: seekPreviewLabel.frame.width + 10,
            height: seekPreviewLabel.frame.height + 2
        )
        let sliderFrame = progressSlider.convert(progressSlider.bounds, to: progressBar)
        let knobSize: CGFloat = 14
        let knobX = sliderFrame.minX + knobSize / 2 + (sliderFrame.width - knobSize) * CGFloat(fraction)
        let x = min(
            max(knobX - bubbleSize.width / 2, sliderFrame.minX),
            sliderFrame.maxX - bubbleSize.width
        )
        seekPreviewLabel.frame = NSRect(
            x: x,
            y: sliderFrame.maxY + 1,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        seekPreviewLabel.isHidden = false
    }

    func hideSeekPreview() {
        seekPreviewLabel.isHidden = true
    }

    func toggleVolumePopover() {
        if volumePopover.isShown {
            volumePopover.performClose(nil)
        } else {
            volumePopover.show(relativeTo: volumeButton.bounds, of: volumeButton, preferredEdge: .maxY)
        }
    }

    /// 歌词顶栏信息块：无标题时整栏折叠；封面为空时显示占位音符。
    /// 封面同时驱动氛围背景：有图取主色淡入，无图淡出回纯毛玻璃。
    func updateNowPlaying(title: String?, artist: String?, artwork: NSImage?) {
        guard let title, !title.isEmpty else {
            nowPlayingInfoStack.isHidden = true
            nowPlayingBar.isHidden = true
            nowPlayingBarHeightConstraint.constant = 0
            nowPlayingArtView.image = nil
            ambientBackgroundView.apply(artwork: nil)
            return
        }

        nowPlayingInfoStack.isHidden = false
        nowPlayingBar.isHidden = false
        nowPlayingBarHeightConstraint.constant = 48
        nowPlayingTitleLabel.stringValue = title
        let artistText = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        nowPlayingArtistLabel.stringValue = artistText
        nowPlayingArtistLabel.isHidden = artistText.isEmpty

        if let artwork {
            nowPlayingArtView.imageScaling = .scaleProportionallyUpOrDown
            nowPlayingArtView.image = artwork
        } else {
            nowPlayingArtView.imageScaling = .scaleNone
            nowPlayingArtView.image = UIChrome.symbolImage("music.note", pointSize: 14, weight: .medium)
        }
        ambientBackgroundView.apply(artwork: artwork)
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
        listContainer.addSubview(transportBar)
        listContainer.addSubview(trackListEmptyState)

        NSLayoutConstraint.activate([
            listHeaderBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listHeaderBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listHeaderBar.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listHeaderBar.heightAnchor.constraint(equalToConstant: 28),

            tableScrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: listHeaderBar.bottomAnchor, constant: 4),
            tableScrollView.bottomAnchor.constraint(equalTo: transportBar.topAnchor),

            transportBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            transportBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            transportBar.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            trackListEmptyState.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            trackListEmptyState.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            trackListEmptyState.topAnchor.constraint(equalTo: listContainer.topAnchor),
            trackListEmptyState.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor)
        ])
    }

    private func configureLyricsContainer() {
        lyricsContainer.translatesAutoresizingMaskIntoConstraints = false
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        nowPlayingBar.translatesAutoresizingMaskIntoConstraints = false
        nowPlayingInfoStack.translatesAutoresizingMaskIntoConstraints = false

        // 歌词顶栏：正在播放信息，水平居中呼应歌词居中排版；两侧至少留 28pt。
        // 无曲目时高度收到 0，不占歌词空间。
        nowPlayingBar.addSubview(nowPlayingInfoStack)
        nowPlayingBar.isHidden = true
        nowPlayingBarHeightConstraint = nowPlayingBar.heightAnchor.constraint(equalToConstant: 0)
        nowPlayingBarHeightConstraint.isActive = true
        lyricsContainer.addSubview(nowPlayingBar)
        lyricsContainer.addSubview(lyricsView)
        lyricsContainer.addSubview(progressBar)

        NSLayoutConstraint.activate([
            nowPlayingBar.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            nowPlayingBar.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            nowPlayingBar.topAnchor.constraint(equalTo: lyricsContainer.topAnchor),

            nowPlayingInfoStack.centerXAnchor.constraint(equalTo: nowPlayingBar.centerXAnchor),
            nowPlayingInfoStack.leadingAnchor.constraint(greaterThanOrEqualTo: nowPlayingBar.leadingAnchor, constant: Self.lyricsHorizontalInset),
            nowPlayingInfoStack.trailingAnchor.constraint(lessThanOrEqualTo: nowPlayingBar.trailingAnchor, constant: -Self.lyricsHorizontalInset),
            nowPlayingInfoStack.centerYAnchor.constraint(equalTo: nowPlayingBar.centerYAnchor),

            lyricsView.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: nowPlayingBar.bottomAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: progressBar.topAnchor),

            progressBar.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor)
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

        playButton.bezelStyle = .regularSquare
        playButton.isBordered = false
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = .labelColor
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
        playbackModeButton.image = Self.modeSymbolImage(for: mode)
        playbackModeButton.toolTip = mode.title
    }

    private static func modeSymbolImage(for mode: PlaybackMode) -> NSImage? {
        let pointSize: CGFloat = 15
        let weight: NSFont.Weight = .medium
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor))
        return NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title)?
            .withSymbolConfiguration(config)
    }

    private static func symbolImage(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        UIChrome.symbolImage(name, pointSize: pointSize, weight: weight)
    }
}
