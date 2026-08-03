import AppKit
import QuartzCore

/// 庆祝面板要展示的内容。里程碑和「往年今日」共用同一个面板，只是各自组装不同文案。
struct CelebrationContent {
    /// 「不再提醒」要关掉的是哪一类提醒。
    enum Kind {
        case milestone
        case memory
    }

    let kind: Kind
    /// 大字主体：里程碑是次数，往年今日是「1 个月前」这类时间跨度。
    let headline: String
    /// 大字下方的小字说明。
    let caption: String
    let title: String
    let artist: String?
    let artwork: NSImage?
    let footnote: String
    /// headline 是否从 0 滚动上去 —— 只有数字才滚，文字滚起来是乱码。
    let countsUpTo: Int?
}

enum MilestoneCelebration {
    /// 稀疏节点，不是每 10 次一弹 —— 弹太勤会从惊喜变成打扰。
    static let thresholds = [10, 50, 100, 300, 500, 1000]

    static func threshold(reachedBy count: Int) -> Int? {
        thresholds.first { $0 == count }
    }

    static func content(
        count: Int,
        title: String,
        artist: String?,
        artwork: NSImage?,
        firstPlayedAt: Date
    ) -> CelebrationContent {
        // ID3 常缺歌手，标题多是「歌手 - 歌名」；拆开显示，与曲目列表、菜单栏卡片一致。
        let rawArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = rawArtist.isEmpty ? MusicTrack.parseArtistTitle(title) : nil
        return CelebrationContent(
            kind: .milestone,
            headline: "\(count)",
            caption: "次播放",
            title: parsed?.title ?? title,
            artist: parsed?.artist ?? (rawArtist.isEmpty ? nil : rawArtist),
            artwork: artwork,
            footnote: milestoneFootnote(count: count, firstPlayedAt: firstPlayedAt),
            countsUpTo: count
        )
    }

    private static func milestoneFootnote(count: Int, firstPlayedAt: Date) -> String {
        let calendar = Calendar.current
        let days = max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: firstPlayedAt),
                to: calendar.startOfDay(for: Date())
            ).day ?? 0,
            0
        )
        if days <= 0 {
            return "今天第一次听到它，就单曲循环到了 \(count) 次"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return "从 \(formatter.string(from: firstPlayedAt)) 第一次听起，它已经陪了你 \(days) 天"
    }
}

/// 庆祝弹窗。无标题栏圆角面板，底色取自这首歌的封面主色 ——
/// 比通用彩带更贴合「这首歌对你有意义」，且复用了氛围背景那套取色。
final class CelebrationPanelController: NSWindowController {
    private let content: CelebrationContent
    private let onMute: () -> Void

    private let headlineLabel = NSTextField(labelWithString: "")
    private var countUpTimer: Timer?
    private var countUpStartedAt: TimeInterval = 0

    init(content: CelebrationContent, onMute: @escaping () -> Void) {
        self.content = content
        self.onMute = onMute

        let panel = CelebrationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 452),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        super.init(window: panel)

        panel.contentView = makeContentView()
        panel.onCancel = { [weak self] in
            self?.dismiss()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        countUpTimer?.invalidate()
    }

    func present(over parent: NSWindow?) {
        guard let window else {
            return
        }

        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }

        window.alphaValue = 0
        window.contentView?.layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = CATransform3DMakeScale(0.94, 0.94, 1)
        grow.toValue = CATransform3DIdentity
        grow.duration = 0.34
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.1, 0.35, 1)
        window.contentView?.layer?.transform = CATransform3DIdentity
        window.contentView?.layer?.add(grow, forKey: "grow")

        startCountUp()
    }

    @objc private func dismiss() {
        countUpTimer?.invalidate()
        guard let window else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.close()
        }
    }

    @objc private func muteAndDismiss() {
        onMute()
        dismiss()
    }

    /// 数字滚动到目标值：仪式感的主要来源，成本却只有一个 timer。
    /// headline 不是数字时（例如「1 个月前」）直接静态显示。
    private func startCountUp() {
        guard let target = content.countsUpTo else {
            headlineLabel.stringValue = content.headline
            return
        }

        let duration: TimeInterval = 0.9
        countUpStartedAt = Date().timeIntervalSince1970
        countUpTimer?.invalidate()
        countUpTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince1970 - countUpStartedAt
            let progress = min(max(elapsed / duration, 0), 1)
            // easeOutCubic：开头快、末尾稳稳停在目标值上。
            let eased = 1 - pow(1 - progress, 3)
            headlineLabel.stringValue = "\(Int((Double(target) * eased).rounded()))"
            if progress >= 1 {
                headlineLabel.stringValue = content.headline
                timer.invalidate()
                countUpTimer = nil
            }
        }
        if let countUpTimer {
            RunLoop.main.add(countUpTimer, forMode: .common)
        }
    }

    private func makeContentView() -> NSView {
        let accent = content.artwork
            .flatMap(ArtworkColor.dominant(of:))
            .map(ArtworkColor.readable) ?? .controlAccentColor

        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        // 复用氛围背景：弹窗底色就是这首歌封面的主色。
        let ambient = AmbientBackgroundView()
        ambient.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(ambient)
        ambient.apply(artwork: content.artwork)

        let coverView = NSImageView()
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 16
        coverView.layer?.cornerCurve = .continuous
        coverView.layer?.masksToBounds = true
        coverView.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        coverView.translatesAutoresizingMaskIntoConstraints = false
        if let artwork = content.artwork {
            coverView.imageScaling = .scaleProportionallyUpOrDown
            coverView.image = artwork
        } else {
            coverView.imageScaling = .scaleNone
            coverView.image = UIChrome.symbolImage("music.note", pointSize: 44, weight: .light)
        }

        // headline 可能是「1 个月前」这种较长的文字，按长度降一档字号免得撑破。
        headlineLabel.stringValue = content.countsUpTo == nil ? content.headline : "0"
        headlineLabel.font = .systemFont(ofSize: content.headline.count > 4 ? 40 : 62, weight: .bold)
        headlineLabel.textColor = accent
        headlineLabel.alignment = .center

        let captionLabel = NSTextField(labelWithString: content.caption)
        captionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center

        let titleLabel = NSTextField(labelWithString: content.title)
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        let artistText = content.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artistLabel = NSTextField(labelWithString: artistText)
        artistLabel.font = .systemFont(ofSize: 13)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.alignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.isHidden = artistText.isEmpty

        let footnoteLabel = NSTextField(wrappingLabelWithString: content.footnote)
        footnoteLabel.font = .systemFont(ofSize: 12)
        footnoteLabel.textColor = .tertiaryLabelColor
        footnoteLabel.alignment = .center
        footnoteLabel.maximumNumberOfLines = 2

        let muteButton = NSButton(title: "不再提醒", target: self, action: #selector(muteAndDismiss))
        muteButton.bezelStyle = .inline
        muteButton.isBordered = false
        muteButton.contentTintColor = .secondaryLabelColor
        muteButton.font = .systemFont(ofSize: 12)

        let confirmButton = NSButton(title: "知道了", target: self, action: #selector(dismiss))
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.controlSize = .large

        for view in [coverView, headlineLabel, captionLabel, titleLabel, artistLabel, footnoteLabel, muteButton, confirmButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            ambient.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            ambient.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ambient.topAnchor.constraint(equalTo: root.topAnchor),
            ambient.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            coverView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            coverView.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            coverView.widthAnchor.constraint(equalToConstant: 132),
            coverView.heightAnchor.constraint(equalToConstant: 132),

            headlineLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            headlineLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            headlineLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            headlineLabel.topAnchor.constraint(equalTo: coverView.bottomAnchor, constant: 18),

            captionLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            captionLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: -2),

            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            titleLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 18),

            artistLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            artistLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28),
            artistLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),

            footnoteLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            footnoteLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            footnoteLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 14),

            confirmButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -44),
            confirmButton.widthAnchor.constraint(equalToConstant: 130),

            muteButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            muteButton.topAnchor.constraint(equalTo: confirmButton.bottomAnchor, constant: 8)
        ])

        return root
    }
}

/// borderless 面板默认不能成为 key window，按钮和 Esc 都会失灵。
private final class CelebrationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
