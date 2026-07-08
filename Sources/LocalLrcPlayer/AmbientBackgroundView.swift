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
        guard let artwork, let base = Self.dominantColor(of: artwork) else {
            fade(topLeadingBlob, to: nil, alpha: 0)
            fade(bottomTrailingBlob, to: nil, alpha: 0)
            return
        }
        fade(topLeadingBlob, to: Self.shiftedHue(base, by: 0.04), alpha: 0.5)
        fade(bottomTrailingBlob, to: Self.shiftedHue(base, by: -0.06), alpha: 0.4)
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

    /// 1x1 下采样取平均色；平均色常发灰，拉一把饱和度、把亮度压进中间段再用。
    private static func dominantColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: 1, height: 1,
                  bitsPerComponent: 8, bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else {
            return nil
        }

        let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation * 1.6, 0.3), 0.85),
            brightness: min(max(brightness, 0.45), 0.8),
            alpha: 1
        )
    }

    private static func shiftedHue(_ color: NSColor, by delta: CGFloat) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return color
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shifted = (hue + delta).truncatingRemainder(dividingBy: 1)
        return NSColor(
            hue: shifted < 0 ? shifted + 1 : shifted,
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
    }
}
