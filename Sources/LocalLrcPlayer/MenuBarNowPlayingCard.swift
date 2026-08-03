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
        modeButton.image = UIChrome.symbolImage(snapshot.mode.symbolName, pointSize: 11, weight: .medium)
        modeButton.toolTip = snapshot.mode.title

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
        lyricLabel.font = .systemFont(ofSize: 11)
        lyricLabel.textColor = .tertiaryLabelColor
        lyricLabel.lineBreakMode = .byTruncatingTail
        for label in [titleLabel, artistLabel, lyricLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let textStack = NSStackView(views: [titleLabel, artistLabel, lyricLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let headerStack = NSStackView(views: [artView, textStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 10
        headerStack.translatesAutoresizingMaskIntoConstraints = false

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

        configureIconButton(previousButton, symbol: "backward.fill", pointSize: 12, action: #selector(previousClicked))
        configureIconButton(nextButton, symbol: "forward.fill", pointSize: 12, action: #selector(nextClicked))
        configureIconButton(modeButton, symbol: "arrow.right.to.line.compact", pointSize: 11, action: #selector(modeClicked))
        modeButton.contentTintColor = .secondaryLabelColor

        configureIconButton(playButton, symbol: "play.fill", pointSize: 11, action: #selector(playClicked))
        playButton.contentTintColor = .white
        playButton.wantsLayer = true

        previousButton.toolTip = "上一首"
        playButton.toolTip = "播放/暂停"
        nextButton.toolTip = "下一首"

        volumeIcon.image = UIChrome.symbolImage("speaker.wave.2.fill", pointSize: 10, weight: .regular)
        volumeIcon.contentTintColor = .tertiaryLabelColor
        volumeIcon.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(headerStack)
        addSubview(progressSlider)
        addSubview(elapsedLabel)
        addSubview(durationLabel)
        addSubview(controlsRow)

        let inset: CGFloat = 14
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),

            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            artView.widthAnchor.constraint(equalToConstant: 48),
            artView.heightAnchor.constraint(equalToConstant: 48),

            progressSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            progressSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            progressSlider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 11),

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
        action: Selector
    ) {
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
final class MenuBarNowPlayingCardController: NSResponder {
    private static let openDelay: TimeInterval = 0.3
    private static let closeGrace: TimeInterval = 0.25

    private weak var playerWindowController: PlayerWindowController?
    private let popover = NSPopover()
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
        popover.isShown
    }

    init(playerWindowController: PlayerWindowController?) {
        self.playerWindowController = playerWindowController
        super.init()

        let contentController = NSViewController()
        contentController.view = cardView
        popover.contentViewController = contentController
        // hover 语义下显隐完全由下面的状态机决定，不要让 AppKit 自作主张收起。
        popover.behavior = .applicationDefined

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
        guard popover.isShown else {
            return
        }
        cardView.apply(playerWindowController?.currentNowPlayingSnapshot())
        verifyPointerStillInside()
    }

    func closeImmediately() {
        cancelOpenTimer()
        cancelCloseTimer()
        if popover.isShown {
            popover.performClose(nil)
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
        guard !isMenuOpen, !popover.isShown, openTimer == nil else {
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
        guard popover.isShown, closeTimer == nil else {
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
        guard !isMenuOpen, insideButton, !popover.isShown else {
            return
        }
        guard let button = attachedButton, button.window != nil else {
            return
        }

        cardView.apply(playerWindowController?.currentNowPlayingSnapshot())
        offscreenTicks = 0
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// tracking 事件偶尔会漏（菜单栏位图 30fps 重绘、跨屏移动），
    /// 借 0.2s 刷新链核对指针是否真的还在 button 或卡片上，连续两次不在就强制收起。
    private func verifyPointerStillInside() {
        let pointer = NSEvent.mouseLocation
        var inside = false
        if let frame = attachedButton?.window?.frame, frame.insetBy(dx: -4, dy: -4).contains(pointer) {
            inside = true
        }
        if let frame = popover.contentViewController?.view.window?.frame,
           frame.insetBy(dx: -4, dy: -4).contains(pointer) {
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
