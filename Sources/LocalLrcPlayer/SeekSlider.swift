import AppKit

final class SeekSlider: NSSlider {
    var onTrackingBegan: (() -> Void)?
    var onTrackingEnded: (() -> Void)?

    private(set) var isTrackingMouse = false
    private var isHovering = false

    convenience init(value: Double, minValue: Double, maxValue: Double, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.minValue = minValue
        self.maxValue = maxValue
        self.doubleValue = value
        self.target = target
        self.action = action
        cell = SeekSliderCell()
        sliderType = .linear
        isContinuous = true
        controlSize = .small
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = SeekSliderCell()
        sliderType = .linear
        isContinuous = true
        controlSize = .small
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 拖动时整控件重绘，避免透明背景下圆点残影（一串蓝点）
        super.draw(isTrackingMouse ? bounds : dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        setKnobExpanded(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isTrackingMouse {
            setKnobExpanded(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isTrackingMouse = true
        setKnobExpanded(true)
        onTrackingBegan?()
        super.mouseDown(with: event)
        onTrackingEnded?()
        isTrackingMouse = false
        setKnobExpanded(isHovering)
        redrawFully()
    }

    override func keyDown(with event: NSEvent) {
        isTrackingMouse = true
        onTrackingBegan?()
        super.keyDown(with: event)
        onTrackingEnded?()
        isTrackingMouse = false
        redrawFully()
    }

    func redrawFully() {
        setNeedsDisplay(bounds)
    }

    private func setKnobExpanded(_ expanded: Bool) {
        (cell as? SeekSliderCell)?.knobExpanded = expanded
        redrawFully()
    }
}

private final class SeekSliderCell: NSSliderCell {
    var knobExpanded = false

    private let trackHeight: CGFloat = 4
    private let knobSizeNormal: CGFloat = 11
    private let knobSizeExpanded: CGFloat = 14

    private func visualBarRect(in trackRect: NSRect) -> NSRect {
        NSRect(
            x: trackRect.minX,
            y: trackRect.midY - trackHeight / 2,
            width: trackRect.width,
            height: trackHeight
        )
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let size = knobExpanded ? knobSizeExpanded : knobSizeNormal
        let track = super.trackRect
        let bar = visualBarRect(in: track)
        let defaultKnob = super.knobRect(flipped: flipped)
        return NSRect(
            x: defaultKnob.midX - size / 2,
            y: bar.midY - size / 2,
            width: size,
            height: size
        )
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let barRect = visualBarRect(in: super.trackRect)
        let radius = trackHeight / 2

        NSColor.separatorColor.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()

        let knob = knobRect(flipped: flipped)
        let filledWidth = knob.midX - barRect.minX
        guard filledWidth > 0.5 else {
            return
        }

        let filledRect = NSRect(
            x: barRect.minX,
            y: barRect.minY,
            width: min(filledWidth, barRect.width),
            height: barRect.height
        )
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filledRect, xRadius: radius, yRadius: radius).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let size = knobExpanded ? knobSizeExpanded : knobSizeNormal
        let bar = visualBarRect(in: super.trackRect)
        let knob = NSRect(
            x: knobRect.midX - size / 2,
            y: bar.midY - size / 2,
            width: size,
            height: size
        )

        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: knob).fill()

        NSColor.controlBackgroundColor.withAlphaComponent(0.35).setStroke()
        let stroke = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
        stroke.lineWidth = 1
        stroke.stroke()
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let tracking = super.startTracking(at: startPoint, in: controlView)
        (controlView as? SeekSlider)?.redrawFully()
        return tracking
    }

    override func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool {
        let tracking = super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)
        (controlView as? SeekSlider)?.redrawFully()
        return tracking
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        (controlView as? SeekSlider)?.redrawFully()
    }

    private func normalizedProgress() -> Double {
        let span = maxValue - minValue
        guard span > 0 else {
            return 0
        }
        return min(max((doubleValue - minValue) / span, 0), 1)
    }
}
