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
    let immersiveEnterButton = NSButton(title: "", target: nil, action: nil)
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

    // 沉浸模式：与 splitView 平级、互斥显隐的独立容器。
    // lyricsView / transportRow / progressRow 在两套容器间搬家（不造第二套控件，
    // 主窗口那套被 bindActions 绑死且散布在控制器各处，镜像同步必然出状态漂移）。
    let immersiveExitButton = NSButton(title: "", target: nil, action: nil)
    private let splitView = NSSplitView()
    private let immersiveContainer = NSView()
    private let immersiveContentArea = NSView()
    private let immersiveCoverView = NSImageView()
    private let immersiveTitleLabel = NSTextField(labelWithString: "")
    private let immersiveArtistLabel = NSTextField(labelWithString: "")
    // 只作定位容器，不画背景：控制区直接浮在氛围背景上（参考图的做法）。
    // 想要回毛玻璃底就把它换成 NSVisualEffectView（.popover + .withinWindow + 圆角）。
    private let immersiveControlBar = NSView()
    // transportRow 内部这两块底色在日常模式下贴着窗口背景看是对的，
    // 但叠在沉浸模式的毛玻璃控制条上会变成双层灰块，切换时按模式开关。
    private var transportClusterBackground: NSView!
    private var transportModePill: NSView!
    private var transportRow: NSStackView!
    private var progressRow: NSStackView!
    private var listModeConstraints: [NSLayoutConstraint] = []
    private var immersiveModeConstraints: [NSLayoutConstraint] = []
    private var seekPreviewHost: NSView!
    private(set) var isImmersive = false

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
        configureImmersiveContainer()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(listContainer)
        splitView.addArrangedSubview(lyricsContainer)

        listContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        listContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let root = NSStackView(views: [splitView, immersiveContainer, statusLabel])
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
            immersiveContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            immersiveContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        NSLayoutConstraint.activate(listModeConstraints)
    }

    /// 沉浸模式容器：左侧大封面、右侧歌名/歌手 + 歌词、底部一整条悬浮控制条。
    /// 约束全部落在容器内部，不与 splitView 列宽发生关系（见 doc/ui.md 的列宽约束告诫）。
    private func configureImmersiveContainer() {
        immersiveContainer.translatesAutoresizingMaskIntoConstraints = false
        immersiveContainer.isHidden = true

        immersiveCoverView.wantsLayer = true
        immersiveCoverView.layer?.cornerRadius = 14
        immersiveCoverView.layer?.cornerCurve = .continuous
        immersiveCoverView.layer?.masksToBounds = true
        immersiveCoverView.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        immersiveCoverView.imageScaling = .scaleProportionallyUpOrDown
        immersiveCoverView.translatesAutoresizingMaskIntoConstraints = false

        immersiveTitleLabel.font = .systemFont(ofSize: 27, weight: .bold)
        immersiveTitleLabel.lineBreakMode = .byTruncatingTail
        immersiveArtistLabel.font = .systemFont(ofSize: 15)
        immersiveArtistLabel.textColor = .secondaryLabelColor
        immersiveArtistLabel.lineBreakMode = .byTruncatingTail
        for label in [immersiveTitleLabel, immersiveArtistLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        immersiveExitButton.image = Self.symbolImage("arrow.down.right.and.arrow.up.left", pointSize: 13, weight: .medium)
        immersiveExitButton.imagePosition = .imageOnly
        immersiveExitButton.isBordered = false
        immersiveExitButton.bezelStyle = .regularSquare
        immersiveExitButton.contentTintColor = .secondaryLabelColor
        immersiveExitButton.toolTip = "退出沉浸模式（Esc）"
        immersiveExitButton.translatesAutoresizingMaskIntoConstraints = false

        immersiveControlBar.translatesAutoresizingMaskIntoConstraints = false

        immersiveContentArea.translatesAutoresizingMaskIntoConstraints = false

        immersiveContainer.addSubview(immersiveContentArea)
        immersiveContainer.addSubview(immersiveControlBar)
        immersiveContainer.addSubview(immersiveExitButton)
        immersiveContentArea.addSubview(immersiveCoverView)
        immersiveContentArea.addSubview(immersiveTitleLabel)
        immersiveContentArea.addSubview(immersiveArtistLabel)

        // 封面按内容区宽度取比例，但同时受高度与上限压制，窄窗/矮窗都不会顶穿控制条。
        let coverProportional = immersiveCoverView.widthAnchor.constraint(
            equalTo: immersiveContentArea.widthAnchor,
            multiplier: 0.40
        )
        coverProportional.priority = .defaultHigh

        NSLayoutConstraint.activate([
            immersiveContentArea.leadingAnchor.constraint(equalTo: immersiveContainer.leadingAnchor, constant: 40),
            immersiveContentArea.trailingAnchor.constraint(equalTo: immersiveContainer.trailingAnchor, constant: -40),
            immersiveContentArea.topAnchor.constraint(equalTo: immersiveContainer.topAnchor, constant: 24),
            immersiveContentArea.bottomAnchor.constraint(equalTo: immersiveControlBar.topAnchor, constant: -18),

            immersiveCoverView.leadingAnchor.constraint(equalTo: immersiveContentArea.leadingAnchor),
            immersiveCoverView.centerYAnchor.constraint(equalTo: immersiveContentArea.centerYAnchor),
            immersiveCoverView.heightAnchor.constraint(equalTo: immersiveCoverView.widthAnchor),
            immersiveCoverView.heightAnchor.constraint(lessThanOrEqualTo: immersiveContentArea.heightAnchor),
            immersiveCoverView.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            coverProportional,

            immersiveTitleLabel.leadingAnchor.constraint(equalTo: immersiveCoverView.trailingAnchor, constant: 36),
            immersiveTitleLabel.trailingAnchor.constraint(equalTo: immersiveContentArea.trailingAnchor),
            immersiveTitleLabel.topAnchor.constraint(equalTo: immersiveContentArea.topAnchor, constant: 8),

            immersiveArtistLabel.leadingAnchor.constraint(equalTo: immersiveTitleLabel.leadingAnchor),
            immersiveArtistLabel.trailingAnchor.constraint(equalTo: immersiveTitleLabel.trailingAnchor),
            immersiveArtistLabel.topAnchor.constraint(equalTo: immersiveTitleLabel.bottomAnchor, constant: 4),

            immersiveControlBar.leadingAnchor.constraint(equalTo: immersiveContainer.leadingAnchor, constant: 40),
            immersiveControlBar.trailingAnchor.constraint(equalTo: immersiveContainer.trailingAnchor, constant: -40),
            immersiveControlBar.bottomAnchor.constraint(equalTo: immersiveContainer.bottomAnchor, constant: -14),
            immersiveControlBar.heightAnchor.constraint(equalToConstant: 56),

            immersiveExitButton.trailingAnchor.constraint(equalTo: immersiveContainer.trailingAnchor, constant: -8),
            immersiveExitButton.topAnchor.constraint(equalTo: immersiveContainer.topAnchor),
            immersiveExitButton.widthAnchor.constraint(equalToConstant: 24),
            immersiveExitButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        // 沉浸组：搬家后才 activate。
        immersiveModeConstraints = [
            lyricsView.leadingAnchor.constraint(equalTo: immersiveTitleLabel.leadingAnchor, constant: -8),
            lyricsView.trailingAnchor.constraint(equalTo: immersiveContentArea.trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: immersiveArtistLabel.bottomAnchor, constant: 14),
            lyricsView.bottomAnchor.constraint(equalTo: immersiveContentArea.bottomAnchor),

            // 无背景容器时按内容对齐：传输键左缘对齐封面左缘，进度条右缘对齐歌词右缘。
            transportRow.leadingAnchor.constraint(equalTo: immersiveControlBar.leadingAnchor),
            transportRow.centerYAnchor.constraint(equalTo: immersiveControlBar.centerYAnchor),

            progressRow.leadingAnchor.constraint(equalTo: transportRow.trailingAnchor, constant: 28),
            progressRow.trailingAnchor.constraint(equalTo: immersiveControlBar.trailingAnchor),
            progressRow.centerYAnchor.constraint(equalTo: immersiveControlBar.centerYAnchor)
        ]
    }

    /// 日常 ⇄ 沉浸切换。顺序固定：先卸当前组约束，再搬视图，最后装目标组。
    func setImmersiveMode(_ enabled: Bool) {
        guard enabled != isImmersive else {
            return
        }
        isImmersive = enabled

        NSLayoutConstraint.deactivate(enabled ? listModeConstraints : immersiveModeConstraints)

        move(lyricsView, to: enabled ? immersiveContentArea : lyricsContainer)
        move(transportRow, to: enabled ? immersiveControlBar : transportBar)
        move(progressRow, to: enabled ? immersiveControlBar : progressBar)
        // 时间气泡是手动摆 frame 的，宿主换了要跟着走，否则算出来的坐标落在旧父视图里。
        seekPreviewHost = enabled ? immersiveControlBar : progressBar
        move(seekPreviewLabel, to: seekPreviewHost)
        seekPreviewLabel.isHidden = true

        NSLayoutConstraint.activate(enabled ? immersiveModeConstraints : listModeConstraints)

        // 沉浸控制条本身已是一层毛玻璃，内层 pill 底色再叠上去会糊成双层灰块。
        let pillFill = enabled ? nil : NSColor.quaternarySystemFill.cgColor
        transportClusterBackground.layer?.backgroundColor = pillFill
        transportModePill.layer?.backgroundColor = pillFill

        splitView.isHidden = enabled
        immersiveContainer.isHidden = !enabled
        lyricsView.applyProfile(enabled ? .immersive : .standard)
    }

    private func move(_ view: NSView, to parent: NSView) {
        guard view.superview !== parent else {
            return
        }
        view.removeFromSuperview()
        parent.addSubview(view)
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
        transportClusterBackground = clusterBackground
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
        transportModePill = modePill
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

        transportRow = NSStackView(views: [clusterBackground, modePill])
        transportRow.orientation = .horizontal
        transportRow.alignment = .centerY
        transportRow.spacing = 20
        transportRow.translatesAutoresizingMaskIntoConstraints = false

        transportBar.translatesAutoresizingMaskIntoConstraints = false
        transportBar.addSubview(transportRow)

        configureNowPlayingInfo()
        configureVolumeControls()

        progressRow = NSStackView(views: [progressSlider, timeLabel, volumeButton])
        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 12
        progressRow.setCustomSpacing(8, after: timeLabel)
        progressRow.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(progressRow)
        seekPreviewHost = progressBar

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
            progressBar.heightAnchor.constraint(equalToConstant: Self.playbackBarHeight)
        ])

        // 两条 row 会在沉浸模式里搬到别的宿主，跨视图约束必须成组管理：
        // 切换时先 deactivate 当前组、再搬家、最后 activate 目标组。顺序错会崩在
        // "constraint with anchors of different hierarchies"。
        listModeConstraints += [
            transportRow.centerXAnchor.constraint(equalTo: transportBar.centerXAnchor),
            transportRow.centerYAnchor.constraint(equalTo: transportBar.centerYAnchor),

            progressRow.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor, constant: Self.lyricsHorizontalInset),
            progressRow.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: -Self.lyricsHorizontalInset),
            progressRow.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor)
        ]
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
        let sliderFrame = progressSlider.convert(progressSlider.bounds, to: seekPreviewHost)
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
        updateImmersiveNowPlaying(title: title, artist: artist, artwork: artwork)

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

    /// 沉浸模式的大封面与大字标题：与顶栏共用同一条封面来源链，不另外取图。
    private func updateImmersiveNowPlaying(title: String?, artist: String?, artwork: NSImage?) {
        guard let title, !title.isEmpty else {
            immersiveTitleLabel.stringValue = "未在播放"
            immersiveArtistLabel.stringValue = ""
            immersiveArtistLabel.isHidden = true
            immersiveCoverView.imageScaling = .scaleNone
            immersiveCoverView.image = UIChrome.symbolImage("music.note", pointSize: 64, weight: .light)
            return
        }

        // ID3 常缺歌手，标题多是「歌手 - 歌名」；拆开显示，与曲目列表、菜单栏卡片一致。
        let rawArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawArtist.isEmpty, let parsed = MusicTrack.parseArtistTitle(title) {
            immersiveTitleLabel.stringValue = parsed.title
            immersiveArtistLabel.stringValue = parsed.artist
        } else {
            immersiveTitleLabel.stringValue = title
            immersiveArtistLabel.stringValue = rawArtist
        }
        immersiveArtistLabel.isHidden = immersiveArtistLabel.stringValue.isEmpty

        if let artwork {
            immersiveCoverView.imageScaling = .scaleProportionallyUpOrDown
            immersiveCoverView.image = artwork
        } else {
            immersiveCoverView.imageScaling = .scaleNone
            immersiveCoverView.image = UIChrome.symbolImage("music.note", pointSize: 64, weight: .light)
        }
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
        listNavigationStack.addArrangedSubview(immersiveEnterButton)

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

            progressBar.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor)
        ])

        // lyricsView 同样会搬去沉浸容器，归入 list 组。
        listModeConstraints += [
            lyricsView.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: nowPlayingBar.bottomAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: progressBar.topAnchor)
        ]
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

        immersiveEnterButton.image = Self.symbolImage("arrow.up.left.and.arrow.down.right", pointSize: 13, weight: .semibold)
        immersiveEnterButton.imagePosition = .imageOnly
        immersiveEnterButton.isBordered = false
        immersiveEnterButton.bezelStyle = .regularSquare
        immersiveEnterButton.contentTintColor = .secondaryLabelColor
        immersiveEnterButton.toolTip = "沉浸模式（⌘⇧F）"
        immersiveEnterButton.setContentHuggingPriority(.required, for: .horizontal)
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
