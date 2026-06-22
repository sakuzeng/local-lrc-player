import AppKit

final class MenuBarLyricsView: NSView {
    private static let viewHeight: CGFloat = 22
    private static let iconSize: CGFloat = 14
    private static let horizontalPadding: CGFloat = 6
    private static let iconSpacing: CGFloat = 4
    private static let scrollSpeed: CGFloat = 0.7
    private static let startPauseTicks: Int = 30

    var text: String = "" {
        didSet {
            guard oldValue != text else {
                return
            }
            resetScroll()
            toolTip = text.isEmpty ? nil : text
            needsLayout = true
        }
    }

    var maxWidth: CGFloat = 240 {
        didSet {
            guard oldValue != maxWidth else {
                return
            }
            resetScroll()
            needsLayout = true
        }
    }

    var showIcon: Bool = true {
        didSet {
            guard oldValue != showIcon else {
                return
            }
            resetScroll()
            needsLayout = true
        }
    }

    var isScrollingEnabled: Bool = true {
        didSet {
            guard oldValue != isScrollingEnabled else {
                return
            }
            updateScrollTimer()
        }
    }

    private var offsetX: CGFloat = 0
    private var scrollTimer: Timer?
    private var textSize = NSSize.zero
    private var needsScroll = false
    private var startPauseRemaining = 0
    private var reachedEnd = false

    override var isFlipped: Bool {
        true
    }

    deinit {
        stopScrollTimer()
    }

    override func removeFromSuperview() {
        stopScrollTimer()
        super.removeFromSuperview()
    }

    /// 状态栏宽度始终固定为配置的最大宽度，避免长歌词挤压系统图标。
    func preferredWidth() -> CGFloat {
        max(maxWidth, 28)
    }

    func configure(maxWidth: CGFloat, showIcon: Bool) {
        self.maxWidth = maxWidth
        self.showIcon = showIcon
    }

    override func layout() {
        super.layout()
        updateScrollState()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawText(in: textDrawingRect())

        if showIcon {
            drawTrailingIcon()
        }
    }

    private func drawText(in textRect: NSRect) {
        guard !text.isEmpty else {
            return
        }

        let attributes = textAttributes()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()

        if needsScroll {
            let point = NSPoint(x: textRect.minX + offsetX, y: centeredTextY(in: textRect))
            (text as NSString).draw(at: point, withAttributes: attributes)
        } else {
            let centeredX = textRect.minX + max((textRect.width - textSize.width) / 2, 0)
            let point = NSPoint(x: centeredX, y: centeredTextY(in: textRect))
            (text as NSString).draw(at: point, withAttributes: attributes)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTrailingIcon() {
        guard let icon = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Local LRC Player") else {
            return
        }

        let iconRect = trailingIconRect()
        icon.isTemplate = true
        NSColor.labelColor.set()
        icon.draw(in: iconRect)
    }

    private func textDrawingRect() -> NSRect {
        let trailing = trailingIconBlockWidth()
        let width = max(bounds.width - Self.horizontalPadding - trailing, 0)
        return NSRect(x: Self.horizontalPadding, y: 0, width: width, height: bounds.height)
    }

    private func trailingIconRect() -> NSRect {
        let x = bounds.width - Self.horizontalPadding - Self.iconSize
        let y = (bounds.height - Self.iconSize) / 2
        return NSRect(x: x, y: y, width: Self.iconSize, height: Self.iconSize)
    }

    private func trailingIconBlockWidth() -> CGFloat {
        guard showIcon else {
            return 0
        }
        return Self.iconSize + Self.iconSpacing
    }

    private func centeredTextY(in rect: NSRect) -> CGFloat {
        rect.minY + max((rect.height - textSize.height) / 2, 0)
    }

    private func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func measuredTextSize() -> NSSize {
        guard !text.isEmpty else {
            return .zero
        }
        return (text as NSString).size(withAttributes: textAttributes())
    }

    private func resetScroll() {
        offsetX = 0
        startPauseRemaining = Self.startPauseTicks
        reachedEnd = false
        textSize = measuredTextSize()
        updateScrollState()
    }

    private func updateScrollState() {
        let textRect = textDrawingRect()
        needsScroll = textSize.width > textRect.width + 0.5
        if !needsScroll {
            offsetX = 0
            reachedEnd = true
        }
        updateScrollTimer()
        needsDisplay = true
    }

    private func updateScrollTimer() {
        if needsScroll, isScrollingEnabled, !reachedEnd {
            startScrollTimerIfNeeded()
        } else {
            stopScrollTimer()
        }
    }

    private func startScrollTimerIfNeeded() {
        guard scrollTimer == nil else {
            return
        }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.advanceScroll()
        }
        if let scrollTimer {
            RunLoop.main.add(scrollTimer, forMode: .common)
        }
    }

    private func stopScrollTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func advanceScroll() {
        guard needsScroll, !reachedEnd else {
            stopScrollTimer()
            return
        }

        let textRect = textDrawingRect()
        let minOffset = textRect.width - textSize.width

        if startPauseRemaining > 0 {
            startPauseRemaining -= 1
            needsDisplay = true
            return
        }

        offsetX -= Self.scrollSpeed
        if offsetX <= minOffset {
            offsetX = minOffset
            reachedEnd = true
            stopScrollTimer()
        }
        needsDisplay = true
    }

    static func makeFrame(width: CGFloat) -> NSRect {
        NSRect(x: 0, y: 0, width: width, height: viewHeight)
    }

    static var preferredHeight: CGFloat {
        viewHeight
    }
}
