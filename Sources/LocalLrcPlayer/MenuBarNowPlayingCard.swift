import AppKit

/// 菜单栏卡片要展示的播放态快照。由 PlayerWindowController 组装，
/// 因为封面只经 layout 进了私有 NSImageView，控制器侧另存一份副本。
struct NowPlayingSnapshot {
    let title: String
    let artist: String?
    let artwork: NSImage?
    let lyricLine: String?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let mode: PlaybackMode
    let volume: Double
}

// 卡片弹出时 App 通常处于后台。默认第一次点击只会激活 App、事件被吞掉，
// 所以卡片自己的控件要接受 first mouse；主窗口那套控件不受影响。
private class CardButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class CardSeekSlider: SeekSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// 圆形强调色播放键，和主窗口传输区的圆键呼应。
private final class CardPlayButton: CardButton {
    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        super.draw(dirtyRect)
    }
}

/// 悬停卡片：封面 + 歌名/歌手 + 当前歌词 + 可拖动进度 + 传输控制 + 模式 + 音量。
/// 控件全是新实例，不与主窗口共用（主窗口那套被 bindActions 绑死且散布在控制器各处）。
final class MenuBarNowPlayingCardView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onNext: (() -> Void)?
    var onCycleMode: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onVolume: ((Double) -> Void)?

    private let artView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let lyricLabel = NSTextField(labelWithString: "")
    private let progressSlider = CardSeekSlider(frame: .zero)
    private let elapsedLabel = NSTextField(labelWithString: "00:00")
    private let durationLabel = NSTextField(labelWithString: "00:00")
    private let previousButton = CardButton()
    private let playButton = CardPlayButton()
    private let nextButton = CardButton()
    private let modeButton = CardButton()
    private let volumeIcon = NSImageView()
    private let volumeSlider = CardSeekSlider(frame: .zero)

    private var trackingArea: NSTrackingArea?
    private var currentDuration: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    /// 传 nil 表示当前没有正在播放的曲目，展示占位并禁用控制。
    func apply(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot else {
            currentDuration = 0
            titleLabel.stringValue = "未在播放"
            artistLabel.stringValue = ""
            artistLabel.isHidden = true
            lyricLabel.stringValue = ""
            lyricLabel.isHidden = true
            setArtwork(nil)
            if !progressSlider.isTrackingMouse {
                progressSlider.doubleValue = 0
            }
            elapsedLabel.stringValue = "00:00"
            durationLabel.stringValue = "00:00"
            playButton.image = Self.playSymbol(isPlaying: false)
            playButton.setAccessibilityLabel("播放")
            setTransportEnabled(false)
            return
        }

        setTransportEnabled(true)
        currentDuration = snapshot.duration

        // ID3 常缺歌手，标题多是「歌手 - 歌名」；拆开显示，与曲目列表一致。
        let rawArtist = snapshot.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawArtist.isEmpty, let parsed = MusicTrack.parseArtistTitle(snapshot.title) {
            titleLabel.stringValue = parsed.title
            artistLabel.stringValue = parsed.artist
        } else {
            titleLabel.stringValue = snapshot.title
            artistLabel.stringValue = rawArtist
        }
        artistLabel.isHidden = artistLabel.stringValue.isEmpty

        let lyric = snapshot.lyricLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lyricLabel.stringValue = lyric
        lyricLabel.isHidden = lyric.isEmpty

        setArtwork(snapshot.artwork)

        // 拖动中不回写，否则 0.2s 刷新会把圆点拽回播放头。
        if !progressSlider.isTrackingMouse {
            progressSlider.doubleValue = snapshot.duration > 0
                ? min(max(snapshot.currentTime / snapshot.duration, 0), 1)
                : 0
        }
        elapsedLabel.stringValue = Self.formatTime(snapshot.currentTime)
        durationLabel.stringValue = Self.formatTime(snapshot.duration)

        playButton.image = Self.playSymbol(isPlaying: snapshot.isPlaying)
        playButton.setAccessibilityLabel(snapshot.isPlaying ? "暂停" : "播放")
        modeButton.image = UIChrome.symbolImage(snapshot.mode.symbolName, pointSize: 11, weight: .medium)
        modeButton.toolTip = snapshot.mode.title
        modeButton.setAccessibilityLabel("播放模式：\(snapshot.mode.title)")
        progressSlider.setAccessibilityValueDescription("\(elapsedLabel.stringValue) / \(durationLabel.stringValue)")

        if !volumeSlider.isTrackingMouse {
            volumeSlider.doubleValue = snapshot.volume
        }
    }

    private func setArtwork(_ artwork: NSImage?) {
        if let artwork {
            artView.imageScaling = .scaleProportionallyUpOrDown
            artView.image = artwork
        } else {
            artView.imageScaling = .scaleNone
            artView.image = UIChrome.symbolImage("music.note", pointSize: 18, weight: .medium)
        }
    }

    private func setTransportEnabled(_ enabled: Bool) {
        for button in [previousButton, playButton, nextButton, modeButton] {
            button.isEnabled = enabled
        }
        progressSlider.isEnabled = enabled
        playButton.needsDisplay = true
    }

    private static func playSymbol(isPlaying: Bool) -> NSImage? {
        UIChrome.symbolImage(isPlaying ? "pause.fill" : "play.fill", pointSize: 11, weight: .bold)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // 封面和音量小喇叭是装饰，不让 VoiceOver 停在上面。
        artView.setAccessibilityElement(false)
        artView.wantsLayer = true
        artView.layer?.cornerRadius = 8
        artView.layer?.cornerCurve = .continuous
        artView.layer?.masksToBounds = true
        artView.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        artView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        artistLabel.font = .systemFont(ofSize: 11)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        // 当前歌词单独成行、整卡居中：跟歌名歌手错开层级，也呼应主窗口的居中歌词排版。
        lyricLabel.font = .systemFont(ofSize: 12)
        lyricLabel.textColor = .labelColor
        lyricLabel.alignment = .center
        lyricLabel.lineBreakMode = .byTruncatingTail
        for label in [titleLabel, artistLabel, lyricLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let textStack = NSStackView(views: [titleLabel, artistLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // 封面 + 文字块用显式约束对齐，不用横向 NSStackView 的 centerY：
        // 歌手行显隐切换改变文字块高度后，stack 的 centerY 对齐不会重新居中，
        // 文字块会贴到封面顶端（无歌手时歌名甚至顶出卡片）。
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(artView)
        header.addSubview(textStack)

        // 用 stack 承载，歌词为空时自动收起不留空行。
        let topStack = NSStackView(views: [header, lyricLabel])
        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.spacing = 9
        topStack.translatesAutoresizingMaskIntoConstraints = false

        progressSlider.setAccessibilityLabel("播放进度")
        progressSlider.minValue = 0
        progressSlider.maxValue = 1
        progressSlider.target = self
        progressSlider.action = #selector(progressChanged)
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.onTrackingEnded = { [weak self] in
            guard let self else {
                return
            }
            onSeek?(progressSlider.doubleValue)
        }

        for label in [elapsedLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        configureIconButton(previousButton, symbol: "backward.fill", pointSize: 12, label: "上一首", action: #selector(previousClicked))
        configureIconButton(nextButton, symbol: "forward.fill", pointSize: 12, label: "下一首", action: #selector(nextClicked))
        configureIconButton(modeButton, symbol: "arrow.right.to.line.compact", pointSize: 11, label: "播放模式", action: #selector(modeClicked))
        modeButton.contentTintColor = .secondaryLabelColor

        configureIconButton(playButton, symbol: "play.fill", pointSize: 11, label: "播放", action: #selector(playClicked))
        playButton.contentTintColor = .white
        playButton.wantsLayer = true

        previousButton.toolTip = "上一首"
        playButton.toolTip = "播放/暂停"
        nextButton.toolTip = "下一首"

        volumeIcon.setAccessibilityElement(false)
        volumeIcon.image = UIChrome.symbolImage("speaker.wave.2.fill", pointSize: 10, weight: .regular)
        volumeIcon.contentTintColor = .tertiaryLabelColor
        volumeIcon.translatesAutoresizingMaskIntoConstraints = false

        volumeSlider.setAccessibilityLabel("音量")
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.doubleValue = 1
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false

        // 传输键真正居中：左右两侧宽度不等（模式 vs 音量），
        // 所以用 centerX 约束而不是塞进同一个 stack 靠 spacer 撑。
        let transportStack = NSStackView(views: [previousButton, playButton, nextButton])
        transportStack.orientation = .horizontal
        transportStack.alignment = .centerY
        transportStack.spacing = 10
        transportStack.translatesAutoresizingMaskIntoConstraints = false

        let controlsRow = NSView()
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.addSubview(modeButton)
        controlsRow.addSubview(transportStack)
        controlsRow.addSubview(volumeIcon)
        controlsRow.addSubview(volumeSlider)

        addSubview(topStack)
        addSubview(progressSlider)
        addSubview(elapsedLabel)
        addSubview(durationLabel)
        addSubview(controlsRow)

        let inset: CGFloat = 14
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),

            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            topStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            header.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            lyricLabel.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            artView.widthAnchor.constraint(equalToConstant: 48),
            artView.heightAnchor.constraint(equalToConstant: 48),
            artView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            artView.topAnchor.constraint(equalTo: header.topAnchor),
            artView.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            textStack.leadingAnchor.constraint(equalTo: artView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            textStack.centerYAnchor.constraint(equalTo: artView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),

            progressSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            progressSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            progressSlider.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 11),

            elapsedLabel.leadingAnchor.constraint(equalTo: progressSlider.leadingAnchor, constant: 1),
            elapsedLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 1),
            durationLabel.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor, constant: -1),
            durationLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),

            controlsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            controlsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            controlsRow.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 7),
            controlsRow.heightAnchor.constraint(equalToConstant: 28),
            controlsRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),

            modeButton.leadingAnchor.constraint(equalTo: controlsRow.leadingAnchor),
            modeButton.centerYAnchor.constraint(equalTo: controlsRow.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 22),
            modeButton.heightAnchor.constraint(equalToConstant: 22),

            transportStack.centerXAnchor.constraint(equalTo: controlsRow.centerXAnchor),
            transportStack.centerYAnchor.constraint(equalTo: controlsRow.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 24),
            previousButton.heightAnchor.constraint(equalToConstant: 24),
            nextButton.widthAnchor.constraint(equalToConstant: 24),
            nextButton.heightAnchor.constraint(equalToConstant: 24),
            playButton.widthAnchor.constraint(equalToConstant: 28),
            playButton.heightAnchor.constraint(equalToConstant: 28),

            volumeSlider.trailingAnchor.constraint(equalTo: controlsRow.trailingAnchor),
            volumeSlider.centerYAnchor.constraint(equalTo: controlsRow.centerYAnchor),
            volumeSlider.widthAnchor.constraint(equalToConstant: 56),
            volumeIcon.trailingAnchor.constraint(equalTo: volumeSlider.leadingAnchor, constant: -4),
            volumeIcon.centerYAnchor.constraint(equalTo: controlsRow.centerYAnchor),
            volumeIcon.widthAnchor.constraint(equalToConstant: 12)
        ])
    }

    private func configureIconButton(
        _ button: NSButton,
        symbol: String,
        pointSize: CGFloat,
        label: String,
        action: Selector
    ) {
        button.setAccessibilityLabel(label)
        button.image = UIChrome.symbolImage(symbol, pointSize: pointSize, weight: .medium)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc private func progressChanged() {
        // 拖动过程中只更新时间标签；真正 seek 在 onTrackingEnded。
        guard currentDuration > 0 else {
            return
        }
        elapsedLabel.stringValue = Self.formatTime(currentDuration * progressSlider.doubleValue)
    }

    @objc private func volumeChanged() {
        onVolume?(volumeSlider.doubleValue)
    }

    @objc private func previousClicked() {
        onPrevious?()
    }

    @objc private func playClicked() {
        onTogglePlayback?()
    }

    @objc private func nextClicked() {
        onNext?()
    }

    @objc private func modeClicked() {
        onCycleMode?()
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "00:00"
        }
        let totalSeconds = Int(time.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// 卡片的显隐状态机：悬停菜单栏歌词 0.3s 弹出，指针离开 button 与卡片 0.25s 后收起。
/// 宽限期是为了让指针能从 button 穿过几像素空档移进卡片。
///
/// 卡片是无箭头的 borderless 面板而不是 NSPopover：状态项宽度随歌词变化，popover 的箭头
/// 只能指向一个点，要么跟着中心漂、要么偏在一角；照系统控制中心下拉的做法，面板右缘
/// 对齐状态项右缘挂在菜单栏下方。NSPopover 没有公开 API 能去掉箭头。
final class MenuBarNowPlayingCardController: NSResponder {
    private static let openDelay: TimeInterval = 0.3
    private static let closeGrace: TimeInterval = 0.25
    /// 面板顶边与菜单栏底边的留白。
    private static let menuBarGap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let cornerRadius: CGFloat = 14

    private weak var playerWindowController: PlayerWindowController?
    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let cardView = MenuBarNowPlayingCardView()

    private weak var attachedButton: NSStatusBarButton?
    private var trackingArea: NSTrackingArea?
    private var openTimer: Timer?
    private var closeTimer: Timer?
    private var insideButton = false
    private var insideCard = false
    private var offscreenTicks = 0
    private var isMenuOpen = false

    var isShown: Bool {
        panel.isVisible
    }

    init(playerWindowController: PlayerWindowController?) {
        self.playerWindowController = playerWindowController
        super.init()
        configurePanel()

        cardView.onEnter = { [weak self] in
            self?.insideCard = true
            self?.cancelCloseTimer()
        }
        cardView.onExit = { [weak self] in
            self?.insideCard = false
            self?.scheduleClose()
        }
        cardView.onPrevious = { [weak self] in
            self?.playerWindowController?.playPreviousFromMenu()
        }
        cardView.onTogglePlayback = { [weak self] in
            self?.playerWindowController?.togglePlaybackFromMenu()
        }
        cardView.onNext = { [weak self] in
            self?.playerWindowController?.playNextFromMenu()
        }
        cardView.onCycleMode = { [weak self] in
            self?.playerWindowController?.cyclePlaybackMode()
        }
        cardView.onSeek = { [weak self] fraction in
            self?.playerWindowController?.seekFromRemote(toFraction: fraction)
        }
        cardView.onVolume = { [weak self] value in
            self?.playerWindowController?.setVolumeFromRemote(value)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        openTimer?.invalidate()
        closeTimer?.invalidate()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 与状态项弹出的 popover 同层，压在其它 App 窗口之上；全屏 Space 里菜单栏滑出时也能显示。
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        // 显隐完全由悬停状态机决定：NSPanel 默认 App 失活就自动隐藏，这里关掉。
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow

        // 毛玻璃底 + 圆角遮罩；窗口透明，阴影跟着圆角走。
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = Self.cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: root.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        panel.contentView = root
    }

    /// statusItem 会被反复销毁重建，所以每次配置成功都要调；按 button 身份幂等。
    func attach(to button: NSStatusBarButton) {
        guard attachedButton !== button else {
            return
        }
        detach()
        attachedButton = button
        // item.length 随歌词滚动频繁变化，用 inVisibleRect 让区域自己跟着 bounds 走。
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(area)
        trackingArea = area
    }

    func detach() {
        closeImmediately()
        if let trackingArea, let attachedButton, attachedButton.trackingAreas.contains(trackingArea) {
            attachedButton.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        attachedButton = nil
        insideButton = false
        insideCard = false
    }

    /// 原生菜单打开期间抑制卡片，避免两层浮层叠在一起。
    func setMenuOpen(_ open: Bool) {
        isMenuOpen = open
        if open {
            closeImmediately()
        }
    }

    func refreshIfVisible() {
        guard panel.isVisible else {
            return
        }
        cardView.apply(playerWindowController?.currentNowPlayingSnapshot())
        // 歌词换行会改 item.length（右缘不动、左缘伸缩），歌词行显隐会改卡片高度，
        // 借这条刷新链把面板重新贴回右缘；frame 没变就不动。
        if let button = attachedButton {
            layoutPanel(under: button)
        }
        verifyPointerStillInside()
    }

    func closeImmediately() {
        cancelOpenTimer()
        cancelCloseTimer()
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        insideButton = true
        cancelCloseTimer()
        scheduleOpen()
    }

    override func mouseExited(with event: NSEvent) {
        insideButton = false
        cancelOpenTimer()
        scheduleClose()
    }

    private func scheduleOpen() {
        guard !isMenuOpen, !panel.isVisible, openTimer == nil else {
            return
        }
        openTimer = Timer.scheduledTimer(withTimeInterval: Self.openDelay, repeats: false) { [weak self] _ in
            self?.openTimer = nil
            self?.showCard()
        }
        if let openTimer {
            RunLoop.main.add(openTimer, forMode: .common)
        }
    }

    private func scheduleClose() {
        guard panel.isVisible, closeTimer == nil else {
            return
        }
        closeTimer = Timer.scheduledTimer(withTimeInterval: Self.closeGrace, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            closeTimer = nil
            guard !insideButton, !insideCard else {
                return
            }
            closeImmediately()
        }
        if let closeTimer {
            RunLoop.main.add(closeTimer, forMode: .common)
        }
    }

    private func cancelOpenTimer() {
        openTimer?.invalidate()
        openTimer = nil
    }

    private func cancelCloseTimer() {
        closeTimer?.invalidate()
        closeTimer = nil
    }

    private func showCard() {
        guard !isMenuOpen, insideButton, !panel.isVisible else {
            return
        }
        guard let button = attachedButton, button.window != nil else {
            return
        }

        cardView.apply(playerWindowController?.currentNowPlayingSnapshot())
        offscreenTicks = 0
        layoutPanel(under: button)
        // App 多半在后台，普通 orderFront 可能不生效。
        panel.orderFrontRegardless()
    }

    /// 面板右缘对齐状态项右缘、顶边贴菜单栏下方。菜单栏状态项从右往左排，
    /// item.length 随歌词变化时右缘不动、左缘伸缩，所以对齐右缘卡片就不会漂。
    /// 右侧超出屏幕时整体左移。
    private func layoutPanel(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let content = panel.contentView else {
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = content.fittingSize
        var origin = NSPoint(
            x: buttonRect.maxX - size.width,
            y: buttonRect.minY - Self.menuBarGap - size.height
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let limit = screen.visibleFrame
            origin.x = min(origin.x, limit.maxX - size.width - Self.screenMargin)
            origin.x = max(origin.x, limit.minX + Self.screenMargin)
        }
        let frame = NSRect(origin: origin, size: size)
        guard panel.frame != frame else {
            return
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// tracking 事件偶尔会漏（菜单栏位图 30fps 重绘、跨屏移动），
    /// 借 0.2s 刷新链核对指针是否真的还在 button 或卡片上，连续两次不在就强制收起。
    /// 两边各外扩 4pt，合起来盖住 button 与面板之间 6pt 的留白。
    private func verifyPointerStillInside() {
        let pointer = NSEvent.mouseLocation
        var inside = false
        if let frame = attachedButton?.window?.frame, frame.insetBy(dx: -4, dy: -4).contains(pointer) {
            inside = true
        }
        if panel.isVisible, panel.frame.insetBy(dx: -4, dy: -4).contains(pointer) {
            inside = true
        }

        if inside {
            offscreenTicks = 0
            return
        }
        offscreenTicks += 1
        if offscreenTicks >= 2 {
            insideButton = false
            insideCard = false
            closeImmediately()
        }
    }
}
