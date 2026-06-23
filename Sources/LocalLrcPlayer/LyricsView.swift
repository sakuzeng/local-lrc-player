import AppKit
import QuartzCore

final class LyricsView: NSScrollView {
    private let textView = NSTextView()
    private var lines: [LrcLine] = []
    private var lineRanges: [NSRange] = []
    private var activeLineIndex: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showPlaceholder(_ text: String) {
        lines = []
        lineRanges = []
        activeLineIndex = nil

        let paragraphStyle = makeParagraphStyle()
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        ))
    }

    func render(_ lines: [LrcLine], scrollToTop: Bool = true) {
        self.lines = lines
        lineRanges = []
        activeLineIndex = nil

        let text = NSMutableString()
        for line in lines {
            if text.length > 0 {
                text.append("\n\n")
            }

            let start = text.length
            text.append(line.text)
            lineRanges.append(NSRange(location: start, length: (line.text as NSString).length))
        }

        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text as String,
            attributes: normalLyricAttributes(paragraphStyle: makeParagraphStyle())
        ))
        if scrollToTop {
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    /// 文本布局在 `render` 后常需下一帧才稳定；启动恢复或重新加载歌词时用此方法确保滚动到位。
    func updateWhenReady(for time: TimeInterval, forceScroll: Bool) {
        applyUpdate(for: time, forceScroll: forceScroll)
        textView.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.textView.layoutSubtreeIfNeeded()
            self.applyUpdate(for: time, forceScroll: forceScroll)
        }
    }

    func update(for time: TimeInterval, forceScroll: Bool) {
        applyUpdate(for: time, forceScroll: forceScroll)
    }

    private func applyUpdate(for time: TimeInterval, forceScroll: Bool) {
        guard
            let index = LrcParser.activeLineIndex(for: time, in: lines),
            lineRanges.indices.contains(index)
        else {
            return
        }

        if activeLineIndex == index, !forceScroll {
            return
        }

        let paragraphStyle = makeParagraphStyle()
        if let oldIndex = activeLineIndex, lineRanges.indices.contains(oldIndex) {
            textView.textStorage?.setAttributes(
                normalLyricAttributes(paragraphStyle: paragraphStyle),
                range: lineRanges[oldIndex]
            )
        }

        let activeRange = lineRanges[index]
        textView.textStorage?.setAttributes([
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
            .paragraphStyle: paragraphStyle
        ], range: activeRange)

        activeLineIndex = index
        scrollLyricRangeToFocus(activeRange, animated: !forceScroll)
    }

    private func setup() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        documentView = textView
        hasVerticalScroller = true
        borderType = .noBorder
        drawsBackground = false
        backgroundColor = .clear
    }

    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
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
        let focusY = lineRect.midY - visibleHeight * 0.48
        let targetOrigin = NSPoint(x: clipView.bounds.origin.x, y: min(max(focusY, 0), maxY))

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: {
                self.reflectScrolledClipView(clipView)
            }
        } else {
            clipView.setBoundsOrigin(targetOrigin)
            reflectScrolledClipView(clipView)
        }
    }

    private func makeParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 10
        return paragraphStyle
    }

    private func normalLyricAttributes(paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}
