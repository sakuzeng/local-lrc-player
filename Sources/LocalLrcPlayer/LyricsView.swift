import AppKit
import QuartzCore

/// 歌词排版档位。日常模式居中中号字；沉浸模式左对齐放大，行高必须同步放大，
/// 否则大字被固定行框裁掉。
struct LyricsDisplayProfile {
    let activeFontSize: CGFloat
    let baseFontSize: CGFloat
    let lineHeight: CGFloat
    let paragraphSpacing: CGFloat
    let alignment: NSTextAlignment
    let horizontalInset: CGFloat

    static let standard = LyricsDisplayProfile(
        activeFontSize: 26,
        baseFontSize: 18,
        lineHeight: 40,
        paragraphSpacing: 14,
        alignment: .center,
        horizontalInset: 28
    )

    static let immersive = LyricsDisplayProfile(
        activeFontSize: 34,
        baseFontSize: 22,
        lineHeight: 56,
        paragraphSpacing: 16,
        alignment: .left,
        horizontalInset: 8
    )
}

final class LyricsView: NSScrollView {
    private struct LyricLineAppearance {
        let fontSize: CGFloat
        let weight: NSFont.Weight
        let color: NSColor

        func lerped(to other: LyricLineAppearance, progress: CGFloat) -> LyricLineAppearance {
            let blendedColor = color.blended(withFraction: progress, of: other.color) ?? other.color
            let weight: NSFont.Weight = progress >= 0.85 ? other.weight : self.weight
            return LyricLineAppearance(
                fontSize: fontSize + (other.fontSize - fontSize) * progress,
                weight: weight,
                color: blendedColor
            )
        }
    }

    private let textView = NSTextView()
    private let emptyStateView = EmptyStateView()
    private var lines: [LrcLine] = []
    private var lineRanges: [NSRange] = []
    private var activeLineIndex: Int?
    private var styleAnimationTimer: Timer?
    private var lastScrollPadding: CGFloat = 32
    private let styleAnimationDuration: TimeInterval = 0.28
    private let focusCenterRatio: CGFloat = 0.5
    private var profile: LyricsDisplayProfile = .standard

    /// 切换排版档位：重排全文并把当前行重新滚回视口中心。
    func applyProfile(_ profile: LyricsDisplayProfile) {
        guard profile.activeFontSize != self.profile.activeFontSize
            || profile.alignment != self.profile.alignment else {
            return
        }
        self.profile = profile
        cancelStyleAnimation()
        // 横向 inset 立即写死：applyScrollPadding 在 bounds 尚未稳定（高度为 0）时会提前返回，
        // 只靠它会让新档位的 inset 拖到下次窗口尺寸变化才生效。
        let verticalPadding = max(lastScrollPadding, 32)
        lastScrollPadding = verticalPadding
        textView.textContainerInset = NSSize(width: profile.horizontalInset, height: verticalPadding)
        applyScrollPadding(repositionActiveLine: false)

        guard !lines.isEmpty else {
            return
        }
        rebuildLyricText()
        if let index = activeLineIndex, lineRanges.indices.contains(index) {
            applyLineStyles(activeIndex: index)
            scrollLyricRangeToFocus(lineRanges[index], animated: false)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        cancelStyleAnimation()
    }

    func showPlaceholder(_ text: String) {
        cancelStyleAnimation()
        lines = []
        lineRanges = []
        activeLineIndex = nil
        applyScrollPadding(repositionActiveLine: false)

        let content = Self.placeholderContent(for: text)
        emptyStateView.configure(symbolName: content.symbol, title: text, subtitle: content.subtitle)
        emptyStateView.isHidden = false
        hasVerticalScroller = false
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    func render(_ lines: [LrcLine], scrollToTop: Bool = true) {
        cancelStyleAnimation()
        self.lines = lines
        lineRanges = []
        activeLineIndex = nil
        emptyStateView.isHidden = true
        hasVerticalScroller = true
        applyScrollPadding(repositionActiveLine: false)

        rebuildLyricText()

        if scrollToTop {
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    /// 按当前档位重排全文。切换排版档位时复用，避免和 render 各写一份拼装逻辑。
    private func rebuildLyricText() {
        lineRanges = []
        let text = NSMutableString()
        for line in lines {
            if text.length > 0 {
                text.append("\n")
            }

            let start = text.length
            text.append(line.text)
            lineRanges.append(NSRange(location: start, length: (line.text as NSString).length))
        }

        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text as String,
            attributes: normalLyricAttributes(paragraphStyle: makeParagraphStyle())
        ))
    }

    /// 文本布局在 `render` 后常需下一帧才稳定；启动恢复或重新加载歌词时用此方法确保滚动到位。
    func updateWhenReady(for time: TimeInterval, forceScroll: Bool) {
        applyUpdate(for: time, forceScroll: forceScroll, animateStyles: !forceScroll)
        textView.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.textView.layoutSubtreeIfNeeded()
            self.applyUpdate(for: time, forceScroll: forceScroll, animateStyles: !forceScroll)
        }
    }

    func update(for time: TimeInterval, forceScroll: Bool) {
        applyUpdate(for: time, forceScroll: forceScroll, animateStyles: !forceScroll)
    }

    private func applyUpdate(for time: TimeInterval, forceScroll: Bool, animateStyles: Bool) {
        guard
            let index = LrcParser.activeLineIndex(for: time, in: lines),
            lineRanges.indices.contains(index)
        else {
            return
        }

        applyScrollPadding(repositionActiveLine: false)
        textView.layoutSubtreeIfNeeded()

        if activeLineIndex == index {
            if forceScroll {
                scrollLyricRangeToFocus(lineRanges[index], animated: false)
            }
            return
        }

        let oldIndex = activeLineIndex
        activeLineIndex = index

        if animateStyles, let oldIndex {
            animateStyleTransition(from: oldIndex, to: index)
            scrollLyricRangeToFocus(lineRanges[index], animated: !forceScroll)
        } else {
            cancelStyleAnimation()
            applyLineStyles(activeIndex: index)
            scrollLyricRangeToFocus(lineRanges[index], animated: !forceScroll)
        }
    }

    private func setup() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: profile.horizontalInset, height: 32)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleLyricClick(_:)))
        textView.addGestureRecognizer(click)

        documentView = textView
        hasVerticalScroller = true
        borderType = .noBorder
        drawsBackground = false
        backgroundColor = .clear

        emptyStateView.isHidden = true
        addSubview(emptyStateView)
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        super.layout()
        applyScrollPadding(repositionActiveLine: true)
        emptyStateView.frame = bounds
    }

    private static func placeholderContent(for text: String) -> (symbol: String, subtitle: String?) {
        switch text {
        case "请选择歌曲":
            return ("text.quote", nil)
        case "双击左侧歌曲开始播放":
            return ("music.note", "从列表选择一首开始")
        case "请添加音乐文件夹":
            return ("folder.badge.plus", "⌘, 打开设置")
        case "未找到音乐文件":
            return ("music.note.list", nil)
        case "未找到同名 LRC 歌词":
            return ("doc.text", "可尝试在设置中下载歌词")
        case "歌词读取失败":
            return ("exclamationmark.triangle", nil)
        case "歌词文件为空或格式无法识别":
            return ("doc.text", nil)
        case "读取目录失败":
            return ("exclamationmark.triangle", nil)
        default:
            return ("text.quote", nil)
        }
    }

    var onMouseDown: (() -> Void)?

    /// 点击某行歌词时回调该行时间戳（用于 seek）。
    var onLineClicked: ((TimeInterval) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    @objc private func handleLyricClick(_ gesture: NSClickGestureRecognizer) {
        onMouseDown?()
        guard !lines.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let point = gesture.location(in: textView)
        layoutManager.ensureLayout(for: textContainer)

        // 按行高命中，X 不限制，行两侧空白也可点。
        for (index, range) in lineRanges.enumerated() {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.x += textView.textContainerOrigin.x
            lineRect.origin.y += textView.textContainerOrigin.y
            if point.y >= lineRect.minY - 6, point.y <= lineRect.maxY + 6 {
                onLineClicked?(lines[index].time)
                return
            }
        }
    }

    /// 上下留白约为半屏高，使首尾歌词也能滚到视口正中，而不是贴底。
    private func applyScrollPadding(repositionActiveLine: Bool) {
        let visibleHeight = contentView.bounds.height > 0 ? contentView.bounds.height : bounds.height
        guard visibleHeight > 0 else {
            return
        }

        let verticalPadding = max(32, visibleHeight * focusCenterRatio)
        guard abs(verticalPadding - lastScrollPadding) > 0.5 else {
            return
        }

        lastScrollPadding = verticalPadding
        textView.textContainerInset = NSSize(width: profile.horizontalInset, height: verticalPadding)
        textView.layoutSubtreeIfNeeded()

        guard repositionActiveLine,
              let index = activeLineIndex,
              lineRanges.indices.contains(index)
        else {
            return
        }

        scrollLyricRangeToFocus(lineRanges[index], animated: false)
    }

    private func scrollLyricRangeToFocus(_ range: NSRange, animated: Bool) {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += textView.textContainerOrigin.x
        lineRect.origin.y += textView.textContainerOrigin.y

        let clipView = contentView
        let visibleHeight = clipView.bounds.height
        guard visibleHeight > 0 else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let documentHeight = max(textView.bounds.height, textView.fittingSize.height)
        let maxY = max(0, documentHeight - visibleHeight)
        let focusY = lineRect.midY - visibleHeight * focusCenterRatio
        let targetOrigin = NSPoint(x: clipView.bounds.origin.x, y: min(max(focusY, 0), maxY))

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                // 控制点带轻微过冲，模拟 spring 回弹落位。
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.12, 0.35, 1.0)
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: {
                self.reflectScrolledClipView(clipView)
            }
        } else {
            clipView.setBoundsOrigin(targetOrigin)
            reflectScrolledClipView(clipView)
        }
    }

    /// 固定行高：字号插值动画只放大字形、不改变行框，避免整段 reflow 抖动。
    private var fixedLineHeight: CGFloat {
        profile.lineHeight
    }

    private func makeParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = profile.alignment
        paragraphStyle.minimumLineHeight = fixedLineHeight
        paragraphStyle.maximumLineHeight = fixedLineHeight
        paragraphStyle.paragraphSpacing = profile.paragraphSpacing
        return paragraphStyle
    }

    private func distantLineAppearance() -> LyricLineAppearance {
        targetAppearance(forLineIndex: 0, activeIndex: 4)
    }

    private func normalLyricAttributes(paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        attributes(for: distantLineAppearance(), paragraphStyle: paragraphStyle)
    }

    private func targetAppearance(forLineIndex index: Int, activeIndex: Int) -> LyricLineAppearance {
        let distance = abs(index - activeIndex)
        if distance == 0 {
            return LyricLineAppearance(
                fontSize: profile.activeFontSize,
                weight: .bold,
                color: .controlAccentColor
            )
        }

        let falloff = min(distance, 4)
        let alpha = max(0.2, 1.0 - CGFloat(falloff) * 0.22)
        let base = profile.baseFontSize
        let fontSize = max(base - 2, base - CGFloat(min(falloff, 3)) * 0.75)
        let color: NSColor
        switch falloff {
        case 1:
            color = NSColor.labelColor.withAlphaComponent(alpha)
        case 2:
            color = NSColor.secondaryLabelColor.withAlphaComponent(min(1, alpha + 0.08))
        default:
            color = NSColor.tertiaryLabelColor.withAlphaComponent(min(1, alpha + 0.12))
        }
        return LyricLineAppearance(fontSize: fontSize, weight: .regular, color: color)
    }

    private func attributes(
        for appearance: LyricLineAppearance,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        let font = NSFont.systemFont(ofSize: appearance.fontSize, weight: appearance.weight)
        // 固定行高下小字号会沉底，用 baselineOffset 垂直居中。
        let baselineOffset = (fixedLineHeight - (font.ascender - font.descender)) / 2
        return [
            .font: font,
            .foregroundColor: appearance.color,
            .paragraphStyle: paragraphStyle,
            .baselineOffset: baselineOffset
        ]
    }

    private func applyLineStyles(activeIndex: Int) {
        let paragraphStyle = makeParagraphStyle()
        for index in lineRanges.indices {
            let appearance = targetAppearance(forLineIndex: index, activeIndex: activeIndex)
            textView.textStorage?.setAttributes(
                attributes(for: appearance, paragraphStyle: paragraphStyle),
                range: lineRanges[index]
            )
        }
    }

    private func animateStyleTransition(from oldIndex: Int, to newIndex: Int) {
        cancelStyleAnimation()
        let fromAppearances = lineRanges.indices.map {
            targetAppearance(forLineIndex: $0, activeIndex: oldIndex)
        }
        let toAppearances = lineRanges.indices.map {
            targetAppearance(forLineIndex: $0, activeIndex: newIndex)
        }
        let start = CACurrentMediaTime()

        styleAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - start
            let raw = min(1, elapsed / self.styleAnimationDuration)
            let progress = self.easeInOut(CGFloat(raw))
            let paragraphStyle = self.makeParagraphStyle()

            for index in self.lineRanges.indices {
                let appearance = fromAppearances[index].lerped(to: toAppearances[index], progress: progress)
                self.textView.textStorage?.setAttributes(
                    self.attributes(for: appearance, paragraphStyle: paragraphStyle),
                    range: self.lineRanges[index]
                )
            }

            if raw >= 1 {
                timer.invalidate()
                self.styleAnimationTimer = nil
            }
        }
    }

    private func cancelStyleAnimation() {
        styleAnimationTimer?.invalidate()
        styleAnimationTimer = nil
    }

    private func easeInOut(_ value: CGFloat) -> CGFloat {
        if value < 0.5 {
            return 2 * value * value
        }
        return 1 - pow(-2 * value + 2, 2) / 2
    }
}
