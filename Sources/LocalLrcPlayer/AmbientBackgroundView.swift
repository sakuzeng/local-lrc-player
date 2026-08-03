import AppKit
import QuartzCore

/// 封面主色氛围背景：毛玻璃上叠两团大半径柔和色斑（左上/右下，色相微错开），
/// 切歌时颜色交叉淡入淡出；无封面时淡出回纯毛玻璃。
final class AmbientBackgroundView: NSView {
    private let topLeadingBlob = CAGradientLayer()
    private let bottomTrailingBlob = CAGradientLayer()
    private let fadeDuration: CFTimeInterval = 1.2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for blob in [topLeadingBlob, bottomTrailingBlob] {
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            blob.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
            layer?.addSublayer(blob)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // 色斑直径约为窗口长边的 0.9，圆心分别压出左上/右下角外侧。
        let size = max(bounds.width, bounds.height) * 0.9
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topLeadingBlob.frame = CGRect(
            x: -size * 0.35, y: bounds.height - size * 0.65, width: size, height: size
        )
        bottomTrailingBlob.frame = CGRect(
            x: bounds.width - size * 0.65, y: -size * 0.35, width: size, height: size
        )
        CATransaction.commit()
    }

    func apply(artwork: NSImage?) {
        guard let artwork, let base = ArtworkColor.dominant(of: artwork) else {
            fade(topLeadingBlob, to: nil, alpha: 0)
            fade(bottomTrailingBlob, to: nil, alpha: 0)
            return
        }
        fade(topLeadingBlob, to: ArtworkColor.shiftedHue(base, by: 0.04), alpha: 0.5)
        fade(bottomTrailingBlob, to: ArtworkColor.shiftedHue(base, by: -0.06), alpha: 0.4)
    }

    private func fade(_ blob: CAGradientLayer, to color: NSColor?, alpha: CGFloat) {
        let baseColor = color ?? .clear
        let target: [CGColor] = [
            baseColor.withAlphaComponent(alpha).cgColor,
            baseColor.withAlphaComponent(0).cgColor
        ]

        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = blob.presentation()?.colors ?? blob.colors
        animation.toValue = target
        animation.duration = fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        blob.colors = target
        blob.add(animation, forKey: "colors")
    }
}
