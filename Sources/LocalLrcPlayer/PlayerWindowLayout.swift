import AppKit

final class PlayerWindowLayout {
    let searchField = NSSearchField()
    let statusLabel = NSTextField(labelWithString: "请选择一个音乐文件夹")
    let tableView = NSTableView()
    let lyricsView = LyricsView()
    let playButton = NSButton(title: "", target: nil, action: nil)
    let previousButton = NSButton(title: "", target: nil, action: nil)
    let nextButton = NSButton(title: "", target: nil, action: nil)
    let progressSlider = SeekSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")

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

    private func setup(in contentView: NSView) {
        configureTransportButtons()

        searchField.placeholderString = "搜索歌曲、歌手或专辑"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        setupTrackTable()
        let tableScrollView = makeBorderlessScrollView(documentView: tableView)

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

    private func makeBorderlessScrollView(documentView: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    private func setupTrackTable() {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        tableColumn.title = "歌曲"
        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 34
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
    }

    private static func symbolImage(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
