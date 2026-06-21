import AppKit

final class SeekSlider: NSSlider {
    var onTrackingBegan: (() -> Void)?
    var onTrackingEnded: (() -> Void)?

    private(set) var isTrackingMouse = false

    override func mouseDown(with event: NSEvent) {
        isTrackingMouse = true
        onTrackingBegan?()
        super.mouseDown(with: event)
        isTrackingMouse = false
        onTrackingEnded?()
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        onTrackingEnded?()
    }
}
